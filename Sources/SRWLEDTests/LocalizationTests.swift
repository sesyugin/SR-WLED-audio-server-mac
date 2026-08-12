import Foundation
import SRWLEDCore

func runLocalizationTests(_ t: TestRunner) {
    t.suite("Локализация") { t in

        t.test("Поддерживается 16 языков, и все они разные") { t in
            let languages = Language.allCases
            t.expectEqual(languages.count, 16, "число языков")
            t.expectEqual(Set(languages.map(\.rawValue)).count, languages.count,
                          "коды языков не должны повторяться")
            t.expectEqual(Set(languages.map(\.nativeName)).count, languages.count,
                          "самоназвания не должны повторяться")
        }

        t.test("У каждого языка переведены все строки без исключения") { t in
            // Пропущенный ключ иначе всплывёт только у пользователя — и на чужом языке.
            let allKeys = Set(S.allCases)
            for language in Language.allCases {
                guard let table = L10n.table[language] else {
                    t.expect(false, "нет таблицы для языка \(language.rawValue)")
                    continue
                }
                let missing = allKeys.subtracting(table.keys)
                t.expect(missing.isEmpty,
                         "\(language.rawValue): не переведено \(missing.count) строк — "
                         + missing.map(\.rawValue).sorted().prefix(5).joined(separator: ", "))
            }
        }

        t.test("Нет пустых и подозрительно длинных строк") { t in
            for language in Language.allCases {
                guard let table = L10n.table[language] else { continue }
                for (key, value) in table {
                    t.expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                             "\(language.rawValue)/\(key.rawValue): пустая строка")
                }
            }
        }

        t.test("Строка с подстановкой сохраняет её во всех языках") { t in
            // Если в переводе потерять %@, число просто не покажется.
            for language in Language.allCases {
                let value = L10n.string(.diagAllZeroes, language)
                t.expect(value.contains("%@"),
                         "\(language.rawValue): в diagAllZeroes потеряна подстановка %@")
            }
        }

        t.test("Языки справа налево помечены верно") { t in
            t.expect(Language.arabic.isRightToLeft, "арабский пишется справа налево")
            t.expect(Language.urdu.isRightToLeft, "урду пишется справа налево")
            for language in Language.allCases where language != .arabic && language != .urdu {
                t.expect(!language.isRightToLeft,
                         "\(language.rawValue) помечен как справа налево, хотя это не так")
            }
        }

        t.test("Неизвестный язык системы откатывается на английский") { t in
            // systemDefault читает предпочтения системы; проверяем, что она всегда
            // возвращает поддерживаемый язык, а не падает.
            let resolved = Language.systemDefault
            t.expect(Language.allCases.contains(resolved),
                     "systemDefault вернул неподдерживаемый язык")
        }

        t.test("Английский служит запасным для любого ключа") { t in
            guard let english = L10n.table[.english] else {
                t.expect(false, "нет английской таблицы"); return
            }
            t.expectEqual(Set(english.keys).count, S.allCases.count,
                          "английская таблица обязана быть полной — она опорная")
        }
    }
}

/// Диагностика на чужом языке.
///
/// Отдельный набор: строки диагностики раньше были вписаны в код по-русски
/// в обход таблицы, и ни один тест этого не ловил — на всех шестнадцати языках
/// самый нужный экран оставался русским.
func runDiagnosticsLanguageTests(_ t: TestRunner) {
    t.suite("Диагностика говорит на языке интерфейса") { t in

        let endpoint = [Endpoint(host: "192.168.1.50", port: 11988)]

        t.test("Заголовки строк переводятся") { t in
            for language in [Language.english, .german, .chinese, .swedish] {
                let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                         deviceName: "Speakers", sampleRate: 48000,
                                         endpoints: endpoint, packetsPerSecond: 47,
                                         networkError: nil, bandsAlive: true,
                                         language: language)
                t.expectEqual(d.lines[0].title, L10n.string(.diagSystemAudio, language),
                              "\(language.rawValue): заголовок первой строки")
                t.expectEqual(d.lines[2].title, L10n.string(.diagSending, language),
                              "\(language.rawValue): заголовок строки отправки")
            }
        }

        t.test("Ни одна строка не остаётся русской на английском") { t in
            let d = Diagnostics.make(captureRunning: false, digitalSilenceSeconds: 30,
                                     deviceName: "Speakers", sampleRate: 48000,
                                     endpoints: [], packetsPerSecond: 0,
                                     networkError: nil, bandsAlive: false,
                                     language: .english)
            let cyrillic = CharacterSet(charactersIn: "абвгдежзийклмнопрстуфхцчшщъыьэюя")
            for line in d.lines {
                let all = line.title + line.detail + line.advice
                t.expect(all.lowercased().rangeOfCharacter(from: cyrillic) == nil,
                         "в английской диагностике осталась кириллица: «\(all)»")
            }
        }

        t.test("Подстановки доходят до готовой строки") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Studio Display", sampleRate: 44100,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: nil, bandsAlive: true,
                                     language: .english)
            t.expect(d.lines[0].detail.contains("Studio Display"), "имя устройства")
            t.expect(d.lines[0].detail.contains("44100"), "частота дискретизации")
            t.expect(!d.lines[0].detail.contains("%@"), "подстановка не осталась незаполненной")
            t.expect(d.lines[2].detail.contains("47"), "частота отправки")
        }

        t.test("Отчёт для буфера обмена переведён целиком") { t in
            let d = Diagnostics.make(captureRunning: true, digitalSilenceSeconds: 0,
                                     deviceName: "Speakers", sampleRate: 48000,
                                     endpoints: endpoint, packetsPerSecond: 47,
                                     networkError: nil, bandsAlive: true,
                                     language: .german)
            let text = d.asText(language: .german)
            t.expect(text.contains(L10n.string(.diagTitle, .german)), "заголовок отчёта")
            t.expect(text.contains(L10n.string(.diagOK, .german)), "вердикт переведён")
        }
    }
}
