import Foundation
import SRWLEDCore

/// Транспорт-заглушка: запоминает отправленное и никогда не трогает сеть.
/// Тесты принципиально не шлют на 255.255.255.255 и 239.0.0.1, чтобы не задеть живые ленты.
final class RecordingTransport: PacketTransport, @unchecked Sendable {
    struct Sent {
        let bytes: [UInt8]
        let endpoint: Endpoint
    }

    private let lock = NSLock()
    private var storage = [Sent]()

    var sent: [Sent] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func send(_ bytes: [UInt8], to endpoint: Endpoint) throws {
        lock.lock(); defer { lock.unlock() }
        storage.append(Sent(bytes: bytes, endpoint: endpoint))
    }
}

/// Управляемое время — чтобы проверять keep-alive и ограничитель частоты без ожиданий.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1000

    var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value += seconds
    }
}

private func makeSender(_ configure: (inout Settings) -> Void = { _ in })
    -> (PacketSender, RecordingTransport, VirtualClock)
{
    var settings = Settings()
    settings.sendMode = .targetIPList
    settings.targetIPList = ["10.0.0.5"]
    configure(&settings)

    let transport = RecordingTransport()
    let clock = VirtualClock()
    let sender = PacketSender(settings: settings, transport: transport, now: { clock.now })
    return (sender, transport, clock)
}

func runPacketSenderTests(_ t: TestRunner) {
    t.suite("Отправка пакетов") { t in

        // MARK: Счётчик кадров

        t.test("Счётчик растёт на каждой отправке и не сбрасывается на тишине") { t in
            let (sender, transport, clock) = makeSender()

            // Чередуем звук и тишину — счётчик обязан расти сквозь паузы.
            for step in 0..<20 {
                var packet = AudioSyncPacket()
                if step % 2 == 0 {
                    packet.fftBins = [UInt8](repeating: 100, count: 16)
                }
                sender.send(packet)
                clock.advance(0.025)
            }

            let counters = transport.sent.map { $0.bytes[17] }
            t.expectEqual(counters.count, 20, "число отправок")
            t.expectEqual(counters, (1...20).map { UInt8($0) }, "последовательность счётчика")
        }

        t.test("Счётчик корректно переходит 255 → 0 и продолжает расти") { t in
            let (sender, transport, clock) = makeSender()

            for _ in 0..<260 {
                sender.send(AudioSyncPacket())
                clock.advance(0.025)
            }

            let counters = transport.sent.map { $0.bytes[17] }
            t.expectEqual(counters.count, 260, "число отправок")
            t.expectEqual(counters[254], 255, "последний перед переходом")
            t.expectEqual(counters[255], 0, "переход через границу")
            t.expectEqual(counters[256], 1, "после перехода")
            for i in 1..<counters.count where counters[i] != counters[i - 1] &+ 1 {
                t.expect(false, "разрыв счётчика на позиции \(i): \(counters[i-1]) → \(counters[i])")
                break
            }
        }

        // MARK: Ограничитель частоты

        t.test("Быстрее 50 пакетов в секунду не отправляем — предел прошивки WLED-MM") { t in
            let (sender, transport, clock) = makeSender()

            // Пытаемся слать каждые 5 мс в течение секунды — вчетверо чаще предела.
            for _ in 0..<200 {
                sender.send(AudioSyncPacket())
                clock.advance(0.005)
            }

            let count = transport.sent.count
            t.expect(count <= 50, "за секунду ушло \(count) пакетов, предел прошивки — 50")
        }

        t.test("Нормальный поток анализа проходит без потерь") { t in
            // Обработка выдаёт кадр каждые 1024 отсчёта при 48 кГц — это 21.33 мс.
            // Ограничитель обязан пропускать такой поток целиком, иначе мы сами себе
            // режем кадры и лента дёргается.
            // С дрожанием таймера ±1 мс — именно оно на живом прогоне сбрасывало
            // каждый второй кадр, когда порог ограничителя стоял слишком близко к шагу.
            let (sender, transport, clock) = makeSender()
            let hopSeconds = 1024.0 / 48000.0
            let jitter: [Double] = [-0.001, 0.0005, -0.0008, 0.001, -0.0003, 0.0007]

            var attempts = 0
            while Double(attempts) * hopSeconds < 1.0 {
                sender.send(AudioSyncPacket())
                clock.advance(hopSeconds + jitter[attempts % jitter.count])
                attempts += 1
            }

            t.expectEqual(transport.sent.count, attempts,
                          "ни один кадр нормального потока не должен быть отброшен")
            t.expect(attempts >= 46 && attempts <= 47,
                     "ожидалось около 47 кадров в секунду, вышло \(attempts)")
        }

        t.test("Пропущенный по ограничителю пакет не тратит номер кадра") { t in
            let (sender, _, clock) = makeSender()

            t.expect(sender.send(AudioSyncPacket()) == true, "первый пакет должен уйти")
            clock.advance(0.001)
            t.expect(sender.send(AudioSyncPacket()) == false, "второй должен быть пропущен")
            t.expectEqual(sender.currentFrameCounter, 1, "счётчик после пропуска")

            clock.advance(0.05)
            t.expect(sender.send(AudioSyncPacket()) == true, "третий должен уйти")
            t.expectEqual(sender.currentFrameCounter, 2, "счётчик после паузы")
        }

        // MARK: Keep-alive

        t.test("Без звука разрыв между пакетами никогда не превышает 500 мс") { t in
            let (sender, transport, clock) = makeSender()

            sender.send(AudioSyncPacket())
            var timestamps: [TimeInterval] = [clock.now]

            // Шестьдесят секунд полной тишины: ни одного аудиокадра, только тики таймера.
            for _ in 0..<600 {
                clock.advance(0.1)
                let before = transport.sent.count
                sender.sendKeepAliveIfNeeded()
                if transport.sent.count > before { timestamps.append(clock.now) }
            }

            var maxGap: TimeInterval = 0
            for i in 1..<timestamps.count {
                maxGap = max(maxGap, timestamps[i] - timestamps[i - 1])
            }

            t.expect(maxGap <= 0.61,
                     "максимальный разрыв \(String(format: "%.2f", maxGap)) с при пороге потери 2.5 с")
            t.expect(timestamps.count > 100, "за 60 с ожидалось около 120 повторов, вышло \(timestamps.count)")
        }

        t.test("Keep-alive молчит, пока звук идёт") { t in
            let (sender, transport, clock) = makeSender()

            for _ in 0..<20 {
                sender.send(AudioSyncPacket())
                clock.advance(0.025)
                sender.sendKeepAliveIfNeeded()
            }

            t.expectEqual(transport.sent.count, 20, "лишних повторов быть не должно")
        }

        // MARK: Гашение при выходе

        t.test("При выходе лента гасится, а не застывает") { t in
            let (sender, transport, _) = makeSender()

            var loud = AudioSyncPacket()
            loud.fftBins = [UInt8](repeating: 254, count: 16)
            loud.sampleRaw = 200
            sender.send(loud)

            sender.fadeOut(pause: { _ in })

            let last = transport.sent.last!
            t.expect(Array(last.bytes[18..<34]).allSatisfy { $0 == 0 },
                     "последний кадр обязан быть нулевым")
            t.expect(transport.sent.count >= 11, "ожидалась серия гашения")

            // Счётчик растёт и во время гашения — иначе MM отбросит эти кадры.
            let counters = transport.sent.map { $0.bytes[17] }
            for i in 1..<counters.count where counters[i] != counters[i - 1] &+ 1 {
                t.expect(false, "счётчик сбился во время гашения на позиции \(i)")
                break
            }
        }

        // MARK: Режимы отправки

        t.test("Каждый режим даёт свой список адресатов") { t in
            var settings = Settings()

            settings.sendMode = .broadcastLAN
            t.expectEqual(PacketSender.resolveEndpoints(settings: settings),
                          [Endpoint(host: "255.255.255.255", port: 11988)], "broadcast LAN")

            settings.sendMode = .multicast
            t.expectEqual(PacketSender.resolveEndpoints(settings: settings),
                          [Endpoint(host: "239.0.0.1", port: 11988)], "multicast")

            settings.sendMode = .targetIPList
            settings.targetIPList = ["192.168.1.50, 192.168.1.51; 192.168.1.52\n192.168.1.53"]
            let resolved = PacketSender.resolveEndpoints(settings: settings)
            t.expectEqual(resolved.count, 4, "число адресатов")
            t.expectEqual(resolved.first, Endpoint(host: "192.168.1.50", port: 11988), "первый")
            t.expectEqual(resolved.last, Endpoint(host: "192.168.1.53", port: 11988), "последний")
        }

        t.test("Широковещательный сокет включается только там, где нужен") { t in
            t.expect(PacketSender.needsBroadcast(.broadcastLAN), "broadcastLAN требует SO_BROADCAST")
            t.expect(PacketSender.needsBroadcast(.broadcastSubnet), "broadcastSubnet требует SO_BROADCAST")
            t.expect(!PacketSender.needsBroadcast(.multicast), "multicast не требует")
            t.expect(!PacketSender.needsBroadcast(.targetIPList), "точечная отправка не требует")
        }

        t.test("Разбор списка адресов терпит любые разделители и отбрасывает мусор") { t in
            let parsed = PacketSender.parseIPList([
                "192.168.0.1, 192.168.0.2",
                "10.0.0.1;10.0.0.2 10.0.0.3",
                "не адрес",
                "999.1.1.1",
                "1.2.3",
                "172.16.0.1",
            ])
            t.expectEqual(parsed,
                          ["192.168.0.1", "192.168.0.2", "10.0.0.1", "10.0.0.2", "10.0.0.3", "172.16.0.1"],
                          "разобранные адреса")
        }

        t.test("Один кадр уходит на все ленты группы") { t in
            let (sender, transport, _) = makeSender {
                $0.targetIPList = ["10.0.0.5, 10.0.0.6, 10.0.0.7"]
            }

            sender.send(AudioSyncPacket())

            t.expectEqual(transport.sent.count, 3, "число отправок")
            t.expectEqual(Set(transport.sent.map { $0.endpoint.host }),
                          ["10.0.0.5", "10.0.0.6", "10.0.0.7"], "адресаты")
            t.expectEqual(Set(transport.sent.map { $0.bytes[17] }).count, 1,
                          "всем лентам должен уйти один и тот же номер кадра")
        }
    }
}
