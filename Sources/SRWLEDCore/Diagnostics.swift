import Foundation

/// Диагностика по четырём независимым признакам.
///
/// Причин, по которым лента молчит, минимум четыре, и для человека они неразличимы:
/// нет разрешения на звук, нет доступа в сеть, устройство не в режиме приёма,
/// обработка выдаёт нули. Один общий индикатор «не работает» тут бесполезен —
/// нужен ответ, что именно чинить.
public struct Diagnostics: Sendable, Equatable {

    public enum Verdict: String, Sendable {
        case ok = "в порядке"
        case warning = "внимание"
        case failure = "не работает"
        case unknown = "неизвестно"
    }

    public struct Line: Sendable, Equatable {
        public let title: String
        public let verdict: Verdict
        public let detail: String
        /// Что делать человеку. Пустая строка — делать нечего.
        public let advice: String

        public init(title: String, verdict: Verdict, detail: String, advice: String = "") {
            self.title = title
            self.verdict = verdict
            self.detail = detail
            self.advice = advice
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public var overall: Verdict {
        if lines.contains(where: { $0.verdict == .failure }) { return .failure }
        if lines.contains(where: { $0.verdict == .warning }) { return .warning }
        if lines.allSatisfy({ $0.verdict == .ok }) { return .ok }
        return .unknown
    }

    /// Собирает диагностику из наблюдаемых фактов.
    ///
    /// - Parameters:
    ///   - captureRunning: захват запущен и tap создан
    ///   - digitalSilenceSeconds: сколько длится идеальная цифровая тишина при работающем захвате
    ///   - deviceName: имя устройства вывода
    ///   - sampleRate: частота захвата
    ///   - endpoints: адресаты отправки
    ///   - packetsPerSecond: фактическая частота отправки
    ///   - networkError: последняя ошибка отправки, если была
    ///   - bandsAlive: хоть одна полоса ненулевая
    public static func make(captureRunning: Bool,
                            digitalSilenceSeconds: Double,
                            deviceName: String,
                            sampleRate: Double,
                            endpoints: [Endpoint],
                            packetsPerSecond: Int,
                            networkError: String?,
                            bandsAlive: Bool) -> Diagnostics
    {
        var lines = [Line]()

        // 1. Системный звук
        if !captureRunning {
            lines.append(Line(title: "Системный звук",
                              verdict: .unknown,
                              detail: "захват не запущен"))
        } else if digitalSilenceSeconds > 10 {
            // macOS при отказе в разрешении не отдаёт ни ошибки, ни события —
            // просто кладёт в буфер нули, и всё выглядит работающим.
            lines.append(Line(title: "Системный звук",
                              verdict: .failure,
                              detail: "в буфере \(Int(digitalSilenceSeconds)) с одних нулей",
                              advice: "Скорее всего не выдано разрешение на запись системного звука"))
        } else {
            lines.append(Line(title: "Системный звук",
                              verdict: .ok,
                              detail: "\(deviceName), \(Int(sampleRate)) Гц"))
        }

        // 2. Обработка
        if !captureRunning {
            lines.append(Line(title: "Обработка",
                              verdict: .unknown,
                              detail: "не запущена"))
        } else if bandsAlive {
            lines.append(Line(title: "Обработка", verdict: .ok, detail: "полосы заполняются"))
        } else {
            lines.append(Line(title: "Обработка",
                              verdict: .warning,
                              detail: "все полосы нулевые",
                              advice: "Либо сейчас тишина, либо сигнал не доходит до анализа"))
        }

        // 3. Отправка
        if endpoints.isEmpty {
            lines.append(Line(title: "Отправка",
                              verdict: .failure,
                              detail: "адресаты не заданы",
                              advice: "Укажи адреса лент или выбери широковещательный режим"))
        } else if let networkError {
            lines.append(Line(title: "Отправка",
                              verdict: .failure,
                              detail: networkError,
                              advice: "Проверь, что мак в той же сети, что и ленты"))
        } else if !captureRunning {
            lines.append(Line(title: "Отправка",
                              verdict: .unknown,
                              detail: endpoints.map(\.description).joined(separator: ", ")))
        } else if packetsPerSecond == 0 {
            lines.append(Line(title: "Отправка",
                              verdict: .failure,
                              detail: "пакеты не уходят"))
        } else {
            lines.append(Line(title: "Отправка",
                              verdict: .ok,
                              detail: "\(packetsPerSecond) пак/с на "
                                    + "\(endpoints.count) \(endpoints.count == 1 ? "адрес" : "адреса")"))
        }

        // 4. Ленты — заполняется опросом устройств, пока их не спрашивали
        lines.append(Line(title: "Ленты",
                          verdict: .unknown,
                          detail: "состояние не проверялось",
                          advice: "Проверка появится вместе с автопоиском устройств"))

        return Diagnostics(lines: lines)
    }

    /// Текст для кнопки «скопировать диагностику».
    public func asText() -> String {
        var text = "SR-WLED — диагностика\n"
        text += String(repeating: "-", count: 40) + "\n"
        for line in lines {
            text += "\(line.title): \(line.verdict.rawValue) — \(line.detail)\n"
            if !line.advice.isEmpty {
                text += "    \(line.advice)\n"
            }
        }
        return text
    }
}
