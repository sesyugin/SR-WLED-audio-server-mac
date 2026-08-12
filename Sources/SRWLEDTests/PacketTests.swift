import Foundation
import SRWLEDCore

func runPacketTests(_ t: TestRunner) {
    t.suite("Пакет audiosync v2") { t in

        t.test("Ровно 44 байта — WLED отбрасывает любой другой размер молча") { t in
            t.expectEqual(AudioSyncPacket().encoded().count, 44, "размер пакета")
            t.expectEqual(AudioSyncPacket.byteCount, 44, "константа размера")
        }

        t.test("Заголовок 00002 с нулевым байтом-терминатором") { t in
            let bytes = AudioSyncPacket().encoded()
            t.expectEqual(Array(bytes[0..<6]), [0x30, 0x30, 0x30, 0x30, 0x32, 0x00], "заголовок")
        }

        t.test("Каждое поле лежит по своему смещению") { t in
            var packet = AudioSyncPacket()
            packet.sampleRaw = 1.0            // 0x3F800000
            packet.sampleSmth = 2.0           // 0x40000000
            packet.samplePeak = 0xAA
            packet.frameCounter = 0xBB
            packet.fftBins = (0..<16).map { UInt8($0 * 16) }
            packet.zeroCrossingCount = 0x1234
            packet.fftMagnitude = 4.0         // 0x40800000
            packet.fftMajorPeak = 8.0         // 0x41000000

            let bytes = packet.encoded()

            t.expectEqual(Array(bytes[8..<12]), [0x00, 0x00, 0x80, 0x3F], "sampleRaw @8")
            t.expectEqual(Array(bytes[12..<16]), [0x00, 0x00, 0x00, 0x40], "sampleSmth @12")
            t.expectEqual(bytes[16], 0xAA, "samplePeak @16")
            t.expectEqual(bytes[17], 0xBB, "frameCounter @17")
            t.expectEqual(Array(bytes[18..<34]), (0..<16).map { UInt8($0 * 16) }, "полосы @18")
            t.expectEqual(bytes[34], 0x34, "zeroCrossing младший @34")
            t.expectEqual(bytes[35], 0x12, "zeroCrossing старший @35")
            t.expectEqual(Array(bytes[36..<40]), [0x00, 0x00, 0x80, 0x40], "magnitude @36")
            t.expectEqual(Array(bytes[40..<44]), [0x00, 0x00, 0x00, 0x41], "majorPeak @40")
        }

        t.test("Давление кодируется фиксированной точкой 8.8") { t in
            var packet = AudioSyncPacket()

            packet.pressure = 0
            t.expectEqual(Array(packet.encoded()[6..<8]), [0, 0], "ноль")

            packet.pressure = 1.0
            t.expectEqual(Array(packet.encoded()[6..<8]), [1, 0], "единица")

            packet.pressure = 1.5
            t.expectEqual(Array(packet.encoded()[6..<8]), [1, 128], "полтора")

            packet.pressure = 300
            t.expectEqual(Array(packet.encoded()[6..<8]), [255, 0], "зажим сверху")

            packet.pressure = -5
            t.expectEqual(Array(packet.encoded()[6..<8]), [0, 0], "зажим снизу")
        }

        // Ловит реальный дефект: конверсия NaN в UInt8 роняет процесс по SIGTRAP.
        t.test("Мусор в полях не роняет процесс") { t in
            let garbage: [Float] = [.nan, .infinity, -.infinity, -1, 1e30, .signalingNaN]
            for value in garbage {
                var packet = AudioSyncPacket()
                packet.pressure = value
                packet.sampleRaw = value
                packet.sampleSmth = value
                packet.fftMagnitude = value
                packet.fftMajorPeak = value
                t.expectEqual(packet.encoded().count, 44, "пакет с \(value)")
            }
        }

        t.test("Затухание доводит все поля до нуля и не уходит в минус") { t in
            var packet = AudioSyncPacket()
            packet.sampleRaw = 200
            packet.sampleSmth = 200
            packet.fftMagnitude = 3000
            packet.pressure = 100
            packet.fftBins = [UInt8](repeating: 255, count: 16)

            // Видимая часть — полосы. Именно их гашение человек замечает глазом,
            // и оно должно укладываться примерно в секунду при 47 кадрах в секунду.
            var framesUntilDark = 0
            var frames = 0
            while frames < 200 {
                packet.decay(rate: 0.85)
                frames += 1
                if framesUntilDark == 0 && packet.fftBins.allSatisfy({ $0 == 0 }) {
                    framesUntilDark = frames
                }
                if framesUntilDark > 0 && packet.sampleRaw == 0 { break }
            }

            t.expect(framesUntilDark <= 40,
                     "полосы гасли \(framesUntilDark) кадров (~\(String(format: "%.1f", Double(framesUntilDark) / 47))" +
                     " с), ожидалось не больше 40")
            t.expect(frames <= 70, "полное затухание заняло \(frames) кадров, ожидалось не больше 70")
            t.expect(packet.fftBins.allSatisfy { $0 == 0 }, "полосы должны обнулиться")
            t.expectEqual(packet.sampleRaw, 0, "уровень")
            t.expect(packet.pressure >= 0, "давление не должно уходить в минус")
        }
    }
}

/// Сверка с самой прошивкой.
///
/// Раскладку и формулы брали из `audio_reactive.h` WLED-MM. Тесты ниже
/// закрепляют именно её числа: если прошивка когда-то поменяет меру, тест
/// упадёт и заставит посмотреть, а не оставит расхождение тихо жить.
func runFirmwareAgreementTests(_ t: TestRunner) {
    t.suite("Согласие с прошивкой") { t in

        t.test("Звуковое давление считается по формуле estimatePressure") { t in
            // constexpr из прошивки: sampleMin 2.3, sampleMax 32767−6144,
            // между ними логарифм, растянутый на 0…255.
            t.expectEqual(AudioPipeline.firmwarePressure(peakAmplitude: 0), 0,
                          "тишина даёт ноль")
            t.expect(AudioPipeline.firmwarePressure(peakAmplitude: 2.0 / 32768) == 0,
                     "пик ниже 2.3 единиц шкалы int16 — ещё ноль")
            t.expectEqual(AudioPipeline.firmwarePressure(peakAmplitude: 1.0), 255,
                          "полная шкала упирается в потолок")

            // Опорная точка: пик в десятую долю шкалы. Считаем ту же формулу
            // здесь, независимо от реализации.
            let sample = 0.1 * 32768.0
            let expected = 256.0 * (log(sample) - log(2.3)) / (log(32767.0 - 6144.0) - log(2.3))
            let got = Double(AudioPipeline.firmwarePressure(peakAmplitude: 0.1))
            t.expect(abs(got - expected) < 0.01,
                     "0.1 полной шкалы: получили \(got), формула даёт \(expected)")
            t.expect(got > 180 && got < 200,
                     "тихая музыка обязана давать заметное давление, а не единицы: \(got)")
        }

        t.test("Пересечения нуля приводятся к пачке прошивки") { t in
            // Прошивка считает по 512 отсчётам и множит на 2/3.
            t.expectEqual(AudioPipeline.firmwareZeroCrossings(300, frameLength: 512), 200,
                          "своё окно того же размера")
            t.expectEqual(AudioPipeline.firmwareZeroCrossings(600, frameLength: 1024), 200,
                          "вдвое большее окно даёт то же число")
            t.expectEqual(AudioPipeline.firmwareZeroCrossings(0, frameLength: 1024), 0,
                          "нет пересечений — ноль")
            t.expectEqual(AudioPipeline.firmwareZeroCrossings(10, frameLength: 0), 0,
                          "пустой кадр не должен ронять деление")
        }

        t.test("Канал эквалайзера доходит до 255, как в прошивке") { t in
            // fftResult[i] = max(min((int)(currentResult+0.5f), 255), 0)
            var packet = AudioSyncPacket()
            packet.fftBins = [UInt8](repeating: 255, count: 16)
            let bytes = packet.encoded()
            for index in 0..<16 {
                t.expectEqual(Int(bytes[18 + index]), 255, "канал \(index)")
            }
        }

        t.test("Счётчик кадров переживает переход через 255") { t in
            // Приёмная сторона: пакет с нулём принимается всегда («legacy value»),
            // а после 248 принимаются значения ниже 12 — это и есть переход.
            let transport = RecordingTransport()
            var settings = Settings()
            settings.sendMode = .targetIPList
            settings.targetIPList = ["192.168.1.50"]
            let clock = VirtualClock()
            let sender = PacketSender(settings: settings, transport: transport,
                                      now: { clock.now })

            var seen = [UInt8]()
            for _ in 0..<300 {
                // Шаг чуть больше минимального: ровно на границе накопленная
                // ошибка сложения долей секунды роняет каждый второй пакет
                // в ограничитель, и проверяется тогда не счётчик, а арифметика.
                clock.advance(PacketSender.minSendInterval + 0.005)
                sender.send(AudioSyncPacket())
                seen.append(transport.sent.last.map { $0.bytes[17] } ?? 0)
            }
            t.expectEqual(seen.count, 300, "все пакеты ушли")
            t.expect(seen.contains(0), "счётчик обязан пройти через ноль")
            for index in 1..<seen.count {
                let previous = Int(seen[index - 1]), current = Int(seen[index])
                let stepped = current == (previous + 1) % 256
                t.expect(stepped, "шаг \(index): \(previous) → \(current)")
                if !stepped { break }
            }
        }
    }
}
