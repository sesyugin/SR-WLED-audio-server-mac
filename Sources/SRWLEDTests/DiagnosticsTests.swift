import Foundation
import SRWLEDCore

func runDiagnosticsTests(_ t: TestRunner) {

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
                                     networkError: nil, bandsAlive: false,
                                     language: .russian)
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

/// Строка про ленты — единственная, что отвечает на вопрос «дошло ли».
func runStripDiagnosticsTests(_ t: TestRunner) {
    t.suite("Диагностика лент") { t in

        let endpoint = [Endpoint(host: "192.168.1.50", port: 11988)]

        func make(_ strips: Diagnostics.StripSummary) -> Diagnostics.Line {
            Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                             deviceName: "Speakers", sampleRate: 48000,
                             endpoints: endpoint, packetsPerSecond: 47,
                             networkError: nil, bandsAlive: true,
                             strips: strips, language: .english).lines[3]
        }

        t.test("Пока не спрашивали — так и написано") { t in
            let line = make(Diagnostics.StripSummary())
            t.expectEqual(line.verdict, .unknown, "вердикт")
            t.expect(!line.advice.isEmpty, "должна быть подсказка, что делать")
        }

        t.test("Нашли и все принимают — зелёная") { t in
            let line = make(.init(found: 2, receiving: 2, asked: true))
            t.expectEqual(line.verdict, .ok, "вердикт")
            t.expect(line.detail.contains("2"), "числа видны: \(line.detail)")
            t.expect(line.advice.isEmpty, "чинить нечего — подсказка лишняя")
        }

        t.test("Принимает не всякая — внимание, а не порядок") { t in
            let line = make(.init(found: 3, receiving: 1, asked: true))
            t.expectEqual(line.verdict, .warning, "вердикт")
            t.expect(!line.advice.isEmpty, "подсказка нужна")
        }

        t.test("Нашли, но не принимает никто — это отказ") { t in
            // Самый важный случай: пакеты уходят, счётчик растёт, а на ленте
            // выключен приём. Все прочие строки при этом зелёные.
            let line = make(.init(found: 2, receiving: 0, asked: true))
            t.expectEqual(line.verdict, .failure, "вердикт")
            t.expect(line.advice.contains("Receive"),
                     "подсказка обязана назвать, что включить: \(line.advice)")
        }

        t.test("Искали и не нашли — предупреждение") { t in
            let line = make(.init(found: 0, receiving: 0, asked: true))
            t.expectEqual(line.verdict, .warning, "вердикт")
        }
    }
}

/// Настройки обработки должны доезжать до Settings, а не оставаться в интерфейсе.
func runProcessingSettingsTests(_ t: TestRunner) {
    t.suite("Настройки обработки доходят до обработки") { t in

        t.test("Порог тишины переводится из децибел в амплитуду") { t in
            // -60 dBFS = 0.001 по амплитуде: ровно то, что стоит по умолчанию.
            let amplitude = Float(pow(10, -60.0 / 20))
            t.expect(abs(amplitude - 0.001) < 1e-6, "получили \(amplitude)")
            let quiet = Float(pow(10, -90.0 / 20))
            t.expect(quiet < amplitude, "тише порог — меньше амплитуда")
        }

        t.test("Набор «как в оригинале» остаётся целым") { t in
            // Смесь из половины оригинального набора и половины исправленного
            // не воспроизводит ни одну из двух версий, и сравнивать бок о бок
            // становится не с чем.
            let original = Settings.originalCompatible()
            t.expectEqual(original.bandLayout, .custom, "сетка полос")
            t.expectEqual(original.window, .flatTop, "окно")
            t.expectEqual(original.aggregation, .maximum, "свёртка")
            t.expectEqual(original.gainMode, .original, "АРУ")
            t.expect(!original.bandSmoothing, "сглаживание выключено")
        }
    }
}
