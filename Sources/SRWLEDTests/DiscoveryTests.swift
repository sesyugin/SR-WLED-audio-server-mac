import Foundation
import SRWLEDCore

// Разбор ответа /json/info проверяется на записанных ответах прошивки:
// ленты для этого не нужны, сеть не трогается.

func runDiscoveryTests(_ t: TestRunner) {
    t.suite("Опрос состояния ленты") { t in

        func parse(_ json: String) -> DeviceStatus? {
            DeviceDiscovery.parseInfo(Data(json.utf8))
        }

        t.test("Лента принимает наш поток по протоколу v2") { t in
            // Суффикс v2 прошивка выставляет, только если пакет прошёл обе её проверки:
            // размер ровно 44 байта и верный заголовок. Одна эта строка доказывает формат.
            let status = parse("""
            {
              "ver": "0.14.7-mm",
              "u": { "UDP Sound Sync": ["v2", " - receiving"] }
            }
            """)
            t.expect(status != nil, "ответ должен разобраться")
            t.expectEqual(status?.syncState, .receivingV2, "состояние")
            t.expectEqual(status?.isReceivingFromUs, true, "приём от нас")
            t.expectEqual(status?.version, "0.14.7-mm", "версия прошивки")
        }

        t.test("Лента ждёт сигнала — значит наши пакеты не доходят") { t in
            let status = parse("""
            { "ver": "0.14.7-mm", "u": { "UDP Sound Sync": ["", " - idle"] } }
            """)
            t.expectEqual(status?.syncState, .idle, "состояние")
            t.expectEqual(status?.isReceivingFromUs, false, "приёма нет")
        }

        t.test("Лента сама передаёт — она в режиме источника, а не приёмника") { t in
            let status = parse("""
            { "ver": "0.14.7-mm", "u": { "UDP Sound Sync": ["sending"] } }
            """)
            t.expectEqual(status?.syncState, .sending, "состояние")
        }

        t.test("Звуковой модуль вообще не собран в прошивке") { t in
            let status = parse("""
            { "ver": "0.14.0", "u": { "Battery": ["87 %"] } }
            """)
            t.expectEqual(status?.syncState, .noUsermod, "состояние")
        }

        t.test("Мусор вместо ответа не роняет разбор") { t in
            t.expect(parse("не json") == nil, "мусор обязан дать nil")
            t.expect(parse("{}") != nil, "пустой объект разбирается")
            t.expect(parse("[]") == nil, "массив вместо объекта даёт nil")
        }

        t.test("Ключ модуля может называться иначе") { t in
            // У разных сборок ключ отличается, поэтому ищем по подстроке, а не точным именем.
            let status = parse("""
            { "ver": "0.15.0", "u": { "Audio Source": ["UDP", " v2 - receiving"] } }
            """)
            t.expectEqual(status?.syncState, .receivingV2, "состояние по другому ключу")
        }
    }

    t.suite("Список найденных устройств") { t in

        t.test("Устройство, введённое вручную, попадает в список") { t in
            let discovery = DeviceDiscovery()
            discovery.addManual(host: "192.168.1.50", name: "Гостиная")

            let devices = discovery.devices
            t.expectEqual(devices.count, 1, "число устройств")
            t.expectEqual(devices.first?.host, "192.168.1.50", "адрес")
            t.expectEqual(devices.first?.name, "Гостиная", "имя")
        }

        t.test("Повторное добавление того же адреса не плодит дубликаты") { t in
            let discovery = DeviceDiscovery()
            discovery.addManual(host: "192.168.1.50")
            discovery.addManual(host: "192.168.1.50")
            discovery.addManual(host: "192.168.1.51")

            t.expectEqual(discovery.devices.count, 2, "дубликаты должны отсеиваться")
        }
    }
}
