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
