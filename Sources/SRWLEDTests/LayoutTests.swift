import AppKit
import Foundation
import SRWLEDCore

/// Переводы против жёстких рамок интерфейса.
///
/// Этот набор появился не из принципа, а по следам дефекта: ряд кнопок в попапе
/// требовал по-немецки 347 точек при 272 доступных, и так в восьми языках из
/// шестнадцати. Глазами это не ловится — надо открыть программу на каждом языке;
/// поэтому ширина меряется тем же, чем её меряет система, и сверяется с числами,
/// которые стоят в коде интерфейса.
///
/// Если правишь рамку в SwiftUI — поправь и число здесь. Разошлись они молча
/// ровно один раз, и хватило.
func runLayoutTests(_ t: TestRunner) {
    t.suite("Переводы помещаются в отведённое им место") { t in

        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            return (text as NSString).size(withAttributes: [.font: font]).width
        }

        /// Ширина попапа в строке меню за вычетом отступов по 14 с каждой стороны.
        let popover: CGFloat = 300 - 28
        /// Панель главного окна при обычной ширине 330 и отступах 18.
        let sidebar: CGFloat = 330 - 36

        /// Подпись в рамке постоянной ширины.
        func fits(_ keys: [S], within limit: CGFloat, size: CGFloat,
                  weight: NSFont.Weight = .regular, uppercase: Bool = false,
                  what: String) {
            for language in Language.allCases {
                for key in keys {
                    var text = L10n.string(key, language)
                    if uppercase { text = text.uppercased() }
                    let measured = width(text, size, weight)
                    t.expect(measured <= limit,
                             "\(what): \(language.rawValue)/\(key.rawValue) — "
                             + "\(Int(measured)) pt при \(Int(limit)) доступных, «\(text)»")
                }
            }
        }

        /// Несколько кнопок в один ряд. У кнопки, меняющей надпись на ходу,
        /// берётся самый широкий вариант — помещаться обязаны оба.
        func rowFits(_ groups: [[S]], within limit: CGFloat, size: CGFloat,
                     chrome: CGFloat, spacing: CGFloat, what: String) {
            for language in Language.allCases {
                var total = spacing * CGFloat(groups.count - 1)
                var parts: [String] = []
                for group in groups {
                    let widest = group.map { L10n.string($0, language) }
                        .max(by: { width($0, size) < width($1, size) }) ?? ""
                    parts.append(widest)
                    total += width(widest, size) + chrome
                }
                t.expect(total <= limit,
                         "\(what): \(language.rawValue) — \(Int(total)) pt при "
                         + "\(Int(limit)) доступных, \(parts.joined(separator: " | "))")
            }
        }

        t.test("Подписи строк в попапе не обрезаются") { t in
            fits([.source, .destination, .totalPackets, .processing],
                 within: 92, size: 11, what: "MenuContent.detailRow")
        }

        t.test("Подписи строк в окне «О программе» не обрезаются") { t in
            fits([.aboutVersion, .aboutPlatform],
                 within: 90, size: 11, what: "AboutWindow.row")
        }

        t.test("Ряд пуска в попапе помещается") { t in
            rowFits([[.start, .stop], [.quit]],
                    within: popover, size: 13, chrome: 24, spacing: 8,
                    what: "MenuContent — ряд пуска")
        }

        t.test("Раскрывашки в попапе помещаются в один ряд") { t in
            // Обвязка больше: к отступам кнопки добавляется стрелка и зазор.
            rowFits([[.settings], [.diagnostics]],
                    within: popover, size: 11, chrome: 26, spacing: 8,
                    what: "MenuContent — ряд раскрывашек")
        }

        t.test("Кнопки настроек в попапе помещаются") { t in
            rowFits([[.applyRestart]], within: popover, size: 11, chrome: 24, spacing: 0,
                    what: "MenuContent — применить и перезапустить")
            rowFits([[.copyDiagnostics]], within: popover - 18, size: 11, chrome: 24, spacing: 0,
                    what: "MenuContent — скопировать диагностику")
        }

        t.test("Подписи переключателей помещаются рядом с самим переключателем") { t in
            // Переключатель занимает около 38 точек плюс зазор до подписи.
            fits([.spectrumInMenuBar, .launchAtLogin, .originalBehaviour],
                 within: popover - 44, size: 11, what: "MenuContent — переключатели")
        }

        t.test("Названия режимов отправки помещаются в раскрывающийся список") { t in
            fits([.modeTargetList, .modeBroadcastLAN, .modeBroadcastSubnet, .modeMulticast],
                 within: popover - 70, size: 13, what: "MenuContent — режимы")
        }

        t.test("Заголовки разделов панели помещаются в её ширину") { t in
            // Заголовки набраны капителью — она заметно шире строчных.
            fits([.whereToSend, .tabLook, .diagnostics, .settings,
                  .devices, .behaviour, .processing],
                 within: sidebar, size: 10, weight: .semibold, uppercase: true,
                 what: "MainWindow — заголовки разделов")
        }
    }
}
