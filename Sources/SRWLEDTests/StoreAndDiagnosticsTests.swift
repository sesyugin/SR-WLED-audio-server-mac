import Foundation
import SRWLEDCore

func runStoreTests(_ t: TestRunner) {

    // MARK: - Хранилище настроек

    t.suite("Настройки переживают перезапуск и обновление") { t in

        func temporaryStore() -> SettingsStore {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("srwled-test-\(UInt64.random(in: 0..<UInt64.max))")
                .appendingPathComponent("settings.json")
            return SettingsStore(url: url)
        }

        t.test("Пустое хранилище отдаёт заводские значения") { t in
            let store = temporaryStore()
            do {
                let settings = try store.load()
                t.expectEqual(settings.port, 11988, "порт по умолчанию")
                t.expectEqual(settings.bandLayout, .wled, "сетка полос по умолчанию")
                t.expectEqual(settings.window, .hann, "окно по умолчанию")
            } catch {
                t.expect(false, "чтение пустого хранилища упало: \(error)")
            }
        }

        t.test("Записанное читается обратно без потерь") { t in
            let store = temporaryStore()
            var settings = Settings()
            settings.port = 12345
            settings.sendMode = .targetIPList
            settings.targetIPList = ["192.168.1.50,192.168.1.51"]
            settings.bandLayout = .custom
            settings.window = .flatTop
            settings.aggregation = .maximum
            settings.loudness = .spectralRatio
            settings.gainMode = .original
            settings.frameSlide = 1024
            settings.bandSmoothing = false
            settings.attackSeconds = 0.05
            settings.gainFloor = 0.05
            settings.removeDCOffset = false
            settings.beatLatch = false
            settings.squelch = 0.002

            do {
                try store.save(settings)
                let loaded = try store.load()

                t.expectEqual(loaded.port, 12345, "порт")
                t.expectEqual(loaded.sendMode, .targetIPList, "режим отправки")
                t.expectEqual(loaded.targetIPList, ["192.168.1.50,192.168.1.51"], "адреса")
                t.expectEqual(loaded.bandLayout, .custom, "сетка")
                t.expectEqual(loaded.window, .flatTop, "окно")
                t.expectEqual(loaded.aggregation, .maximum, "агрегация")
                t.expectEqual(loaded.loudness, .spectralRatio, "режим уровня")
                t.expectEqual(loaded.gainMode, .original, "режим АРУ")
                t.expectEqual(loaded.frameSlide, 1024, "шаг анализа")
                t.expectEqual(loaded.bandSmoothing, false, "сглаживание")
                t.expectEqual(loaded.attackSeconds, 0.05, "время нарастания")
                t.expectEqual(loaded.gainFloor, 0.05, "нижний предел АРУ")
                t.expectEqual(loaded.removeDCOffset, false, "снятие смещения")
                t.expectEqual(loaded.beatLatch, false, "импульс удара")
                t.expectEqual(loaded.squelch, 0.002, "порог тишины")

                try? store.reset()
            } catch {
                t.expect(false, "цикл записи и чтения упал: \(error)")
            }
        }

        t.test("Файл от будущей версии не молча портится, а честно отвергается") { t in
            let store = temporaryStore()
            let future = """
            { "version": 999, "values": { "port": 11988 } }
            """
            do {
                try FileManager.default.createDirectory(
                    at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try future.write(to: store.url, atomically: true, encoding: .utf8)

                _ = try store.load()
                t.expect(false, "файл будущей версии обязан вызвать ошибку, а не тихо загрузиться")
            } catch let error as SettingsStore.StoreError {
                if case .futureVersion(let version) = error {
                    t.expectEqual(version, 999, "номер версии в ошибке")
                } else {
                    t.expect(false, "не та ошибка: \(error)")
                }
            } catch {
                t.expect(false, "не та ошибка: \(error)")
            }
            try? store.reset()
        }

        t.test("Битый файл не роняет программу") { t in
            let store = temporaryStore()
            do {
                try FileManager.default.createDirectory(
                    at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "это не json".write(to: store.url, atomically: true, encoding: .utf8)

                _ = try store.load()
                t.expect(false, "битый файл обязан вызвать ошибку")
            } catch is SettingsStore.StoreError {
                t.expect(true, "")
            } catch {
                t.expect(false, "не та ошибка: \(error)")
            }
            try? store.reset()
        }

        t.test("Неизвестные ключи из будущих версий не мешают чтению") { t in
            // Обратная совместимость в другую сторону: файл текущей версии, но с лишними
            // ключами, обязан читаться — иначе откат на прошлую сборку потеряет настройки.
            let store = temporaryStore()
            let document = """
            {
              "version": 1,
              "values": { "port": 4242, "какой-то-будущий-ключ": "значение" }
            }
            """
            do {
                try FileManager.default.createDirectory(
                    at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try document.write(to: store.url, atomically: true, encoding: .utf8)

                let loaded = try store.load()
                t.expectEqual(loaded.port, 4242, "известный ключ прочитан")
            } catch {
                t.expect(false, "чтение с лишними ключами упало: \(error)")
            }
            try? store.reset()
        }
    }

    // MARK: - Диагностика

    t.suite("Диагностика различает причины молчания") { t in

        let endpoint = [Endpoint(host: "192.168.1.50", port: 11988)]

        t.test("Всё хорошо — все строки зелёные") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Колонки", sampleRate: 48000,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: nil, bandsAlive: true)
            t.expectEqual(d.lines.count, 4, "четыре независимых строки")
            t.expectEqual(d.lines[0].verdict, .ok, "звук")
            t.expectEqual(d.lines[1].verdict, .ok, "обработка")
            t.expectEqual(d.lines[2].verdict, .ok, "отправка")
        }

        t.test("Долгая цифровая тишина читается как отказ в разрешении") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 30,
                                     deviceName: "Колонки", sampleRate: 48000,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: nil, bandsAlive: false)
            t.expectEqual(d.lines[0].verdict, .failure, "строка про звук")
            t.expect(d.lines[0].advice.contains("разрешение"),
                     "подсказка обязана назвать разрешение, а не молчать")
        }

        t.test("Не заданы адресаты — виновата отправка, а не звук") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Колонки", sampleRate: 48000,
                                     endpoints: [], packetsPerSecond: 0,
                                     networkError: nil, bandsAlive: true)
            t.expectEqual(d.lines[0].verdict, .ok, "звук в порядке")
            t.expectEqual(d.lines[2].verdict, .failure, "отправка сломана")
            t.expectEqual(d.overall, .failure, "общий вердикт")
        }

        t.test("Ошибка сети видна отдельно от всего остального") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Колонки", sampleRate: 48000,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: "сеть недоступна", bandsAlive: true)
            t.expectEqual(d.lines[0].verdict, .ok, "звук в порядке")
            t.expectEqual(d.lines[2].verdict, .failure, "отправка сломана")
            t.expect(d.lines[2].detail.contains("сеть недоступна"), "текст ошибки виден")
        }

        t.test("Текст для буфера обмена содержит все строки") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Колонки", sampleRate: 48000,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: nil, bandsAlive: true)
            let text = d.asText()
            for line in d.lines {
                t.expect(text.contains(line.title), "в тексте нет строки «\(line.title)»")
            }
        }
    }
}
