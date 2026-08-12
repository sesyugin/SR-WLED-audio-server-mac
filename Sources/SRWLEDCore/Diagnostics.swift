import Foundation

/// Диагностика по четырём независимым признакам.
///
/// Причин, по которым лента молчит, минимум четыре, и для человека они неразличимы:
/// нет разрешения на звук, нет доступа в сеть, устройство не в режиме приёма,
/// обработка выдаёт нули. Один общий индикатор «не работает» тут бесполезен —
/// нужен ответ, что именно чинить.
public struct Diagnostics: Sendable, Equatable {

    public enum Verdict: String, Sendable {
        case ok, warning, failure, unknown

        /// Ключ перевода. Вердикт печатается в отчёте, который человек копирует
        /// и кому-то отправляет, — печататься он обязан на языке интерфейса.
        public var key: S {
            switch self {
            case .ok: return .diagOK
            case .warning: return .diagWarning
            case .failure: return .diagFailure
            case .unknown: return .diagUnknown
            }
        }
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

    /// Что известно про ленты в сети. Собирается автопоиском и опросом
    /// `/json/info`; пока не спрашивали — `asked` ложно, и строка честно
    /// говорит, что проверки не было, вместо того чтобы гадать.
    public struct StripSummary: Sendable, Equatable {
        public var found: Int
        public var receiving: Int
        public var asked: Bool

        public init(found: Int = 0, receiving: Int = 0, asked: Bool = false) {
            self.found = found
            self.receiving = receiving
            self.asked = asked
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
    /// Язык передаётся снаружи, а не берётся из глобального состояния: сборка
    /// идёт не на главном потоке, а `L10n.current` живёт на нём. Раньше строки
    /// были вписаны сюда по-русски прямо в коде, и диагностика оставалась
    /// русской на всех шестнадцати языках — самое нужное место в приложении
    /// становилось нечитаемым ровно тогда, когда оно понадобилось.
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
    ///   - language: язык интерфейса
    public static func make(captureRunning: Bool,
                            digitalSilenceSeconds: Double,
                            deviceName: String,
                            sampleRate: Double,
                            endpoints: [Endpoint],
                            packetsPerSecond: Int,
                            networkError: String?,
                            bandsAlive: Bool,
                            strips: StripSummary = StripSummary(),
                            language: Language = .english) -> Diagnostics
    {
        func text(_ key: S, _ values: [String] = []) -> String {
            L10n.string(key, language, values)
        }

        var lines = [Line]()

        // 1. Системный звук
        if !captureRunning {
            lines.append(Line(title: text(.diagSystemAudio),
                              verdict: .unknown,
                              detail: text(.diagNotRunning)))
        } else if digitalSilenceSeconds > 10 {
            // macOS при отказе в разрешении не отдаёт ни ошибки, ни события —
            // просто кладёт в буфер нули, и всё выглядит работающим.
            lines.append(Line(title: text(.diagSystemAudio),
                              verdict: .failure,
                              detail: text(.diagAllZeroes, ["\(Int(digitalSilenceSeconds))"]),
                              advice: text(.diagPermissionAdvice)))
        } else {
            lines.append(Line(title: text(.diagSystemAudio),
                              verdict: .ok,
                              detail: text(.diagSource, [deviceName, "\(Int(sampleRate))"])))
        }

        // 2. Обработка
        if !captureRunning {
            lines.append(Line(title: text(.diagProcessing),
                              verdict: .unknown,
                              detail: text(.diagNotRunning)))
        } else if bandsAlive {
            lines.append(Line(title: text(.diagProcessing),
                              verdict: .ok,
                              detail: text(.diagBandsFlowing)))
        } else {
            lines.append(Line(title: text(.diagProcessing),
                              verdict: .warning,
                              detail: text(.diagBandsEmpty),
                              advice: text(.diagBandsEmptyAdvice)))
        }

        // 3. Отправка
        if endpoints.isEmpty {
            lines.append(Line(title: text(.diagSending),
                              verdict: .failure,
                              detail: text(.diagNoTargets),
                              advice: text(.diagNoTargetsAdvice)))
        } else if let networkError {
            lines.append(Line(title: text(.diagSending),
                              verdict: .failure,
                              detail: networkError,
                              advice: text(.diagNetworkAdvice)))
        } else if !captureRunning {
            lines.append(Line(title: text(.diagSending),
                              verdict: .unknown,
                              detail: endpoints.map(\.description).joined(separator: ", ")))
        } else if packetsPerSecond == 0 {
            lines.append(Line(title: text(.diagSending),
                              verdict: .failure,
                              detail: text(.diagNotSending)))
        } else {
            lines.append(Line(title: text(.diagSending),
                              verdict: .ok,
                              detail: text(.diagSendingRate,
                                           ["\(packetsPerSecond)", "\(endpoints.count)"])))
        }

        // 4. Ленты. Это единственная строка, которая отвечает на вопрос
        // «дошло ли», а не «ушло ли»: прошивка выставляет в /json/info суффикс
        // версии, только когда действительно принимает наш поток. Пока строка
        // говорила «не проверялось» при уже работающем автопоиске, самый
        // ценный ответ диагностики оставался незаданным.
        if !strips.asked {
            lines.append(Line(title: text(.diagDevices),
                              verdict: .unknown,
                              detail: text(.diagDevicesUnchecked),
                              advice: text(.diagDevicesAdvice)))
        } else if strips.found == 0 {
            lines.append(Line(title: text(.diagDevices),
                              verdict: .warning,
                              detail: text(.noDevicesFound),
                              advice: text(.diagDevicesAdvice)))
        } else if strips.receiving > 0 {
            lines.append(Line(title: text(.diagDevices),
                              verdict: strips.receiving == strips.found ? .ok : .warning,
                              detail: text(.stripsReceiving,
                                           ["\(strips.receiving)", "\(strips.found)"]),
                              advice: strips.receiving == strips.found
                                  ? "" : text(.stripsAdvice)))
        } else {
            lines.append(Line(title: text(.diagDevices),
                              verdict: .failure,
                              detail: text(.stripsNoneReceiving, ["\(strips.found)"]),
                              advice: text(.stripsAdvice)))
        }

        return Diagnostics(lines: lines)
    }

    /// Текст для кнопки «скопировать диагностику».
    ///
    /// Отчёт человек копирует, чтобы кому-то показать, поэтому и заголовок,
    /// и вердикты печатаются на языке интерфейса, а не на языке разработчика.
    public func asText(language: Language = .english) -> String {
        var text = L10n.string(.diagTitle, language) + "\n"
        text += String(repeating: "-", count: 40) + "\n"
        for line in lines {
            let verdict = L10n.string(line.verdict.key, language)
            text += "\(line.title): \(verdict) — \(line.detail)\n"
            if !line.advice.isEmpty {
                text += "    \(line.advice)\n"
            }
        }
        return text
    }
}
