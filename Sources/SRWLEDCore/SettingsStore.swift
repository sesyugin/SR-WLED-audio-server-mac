import Foundation

/// Хранилище настроек в файле, с версией схемы и миграциями.
///
/// У оригинала настройки терялись между версиями — известный его дефект.
/// Здесь схема пронумерована, чтение старой версии поднимается миграциями,
/// а запись атомарна: оборванная запись не оставит битый файл.
public struct SettingsStore: Sendable {

    /// Текущая версия схемы. Увеличивать при любой несовместимой правке формата.
    public static let currentVersion = 1

    public enum StoreError: Error, CustomStringConvertible {
        case unreadable(String)
        case futureVersion(Int)

        public var description: String {
            switch self {
            case .unreadable(let detail): return "не удалось прочитать настройки: \(detail)"
            case .futureVersion(let version):
                return "файл настроек версии \(version) новее, чем понимает программа "
                     + "(\(SettingsStore.currentVersion)) — обнови приложение"
            }
        }
    }

    public let url: URL

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.url = base
                .appendingPathComponent("SR-WLED", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
    }

    // MARK: - Формат файла

    /// Плоское представление: словарь, чтобы миграции могли дописывать и удалять ключи,
    /// не ломая разбор старых файлов.
    struct Document: Codable {
        var version: Int
        var values: [String: Value]

        enum Value: Codable, Equatable {
            case string(String)
            case number(Double)
            case boolean(Bool)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
                if let value = try? container.decode(Double.self) { self = .number(value); return }
                self = .string(try container.decode(String.self))
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let value): try container.encode(value)
                case .number(let value): try container.encode(value)
                case .boolean(let value): try container.encode(value)
                }
            }
        }
    }

    // MARK: - Чтение и запись

    public func load() throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Settings()          // первый запуск — заводские значения
        }

        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw StoreError.unreadable("\(error.localizedDescription)") }

        var document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw StoreError.unreadable("повреждён формат") }

        guard document.version <= Self.currentVersion else {
            throw StoreError.futureVersion(document.version)
        }

        document = Self.migrate(document)
        return Self.decode(document.values)
    }

    public func save(_ settings: Settings) throws {
        let document = Document(version: Self.currentVersion, values: Self.encode(settings))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Атомарная запись: при обрыве останется прежний файл, а не половина нового.
        try data.write(to: url, options: .atomic)
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Миграции

    /// Поднимает документ до текущей версии. Каждая ступень — отдельная и независимая.
    static func migrate(_ document: Document) -> Document {
        var document = document

        // Пример ступени на будущее: значения, появившиеся в версии 2, дописываются здесь.
        // while document.version < currentVersion { ... document.version += 1 }

        document.version = currentVersion
        return document
    }

    // MARK: - Преобразование

    static func encode(_ settings: Settings) -> [String: Document.Value] {
        [
            "port": .number(Double(settings.port)),
            "sendMode": .string(settings.sendMode.rawValue),
            "targetIPList": .string(settings.targetIPList.joined(separator: ",")),
            "broadcastIPList": .string(settings.broadcastIPList.joined(separator: ",")),
            "bandLayout": .string(settings.bandLayout.rawValue),
            "window": .string(settings.window.rawValue),
            "normalization": .string(settings.normalization.rawValue),
            "aggregation": .string(settings.aggregation.rawValue),
            "loudness": .string(settings.loudness.rawValue),
            "gainMode": .string(settings.gainMode.rawValue),
            "frameSlide": .number(Double(settings.frameSlide)),
            "fftLow": .number(Double(settings.fftLow)),
            "fftHigh": .number(Double(settings.fftHigh)),
            "fftFreqLogScale": .boolean(settings.fftFreqLogScale),
            "fftValueScale": .string(settings.fftValueScale.rawValue),
            "bandSmoothing": .boolean(settings.bandSmoothing),
            "attackSeconds": .number(Double(settings.attackSeconds)),
            "releaseSeconds": .number(Double(settings.releaseSeconds)),
            "gainAttackSeconds": .number(Double(settings.gainAttackSeconds)),
            "gainReleaseSeconds": .number(Double(settings.gainReleaseSeconds)),
            "gainFloor": .number(Double(settings.gainFloor)),
            "removeDCOffset": .boolean(settings.removeDCOffset),
            "beatLatch": .boolean(settings.beatLatch),
            "manualGain": .boolean(settings.manualGain),
            "manualGainReference": .number(Double(settings.manualGainReference)),
            "squelch": .number(Double(settings.squelch)),
        ]
    }

    static func decode(_ values: [String: Document.Value]) -> Settings {
        var settings = Settings()

        func string(_ key: String) -> String? {
            if case .string(let value) = values[key] { return value }
            return nil
        }
        func number(_ key: String) -> Double? {
            if case .number(let value) = values[key] { return value }
            return nil
        }
        func boolean(_ key: String) -> Bool? {
            if case .boolean(let value) = values[key] { return value }
            return nil
        }
        func list(_ key: String) -> [String]? {
            guard let text = string(key) else { return nil }
            return text.isEmpty ? [] : [text]
        }

        if let value = number("port") { settings.port = UInt16(max(1, min(value, 65535))) }
        if let value = string("sendMode"), let mode = Settings.SendMode(rawValue: value) {
            settings.sendMode = mode
        }
        if let value = list("targetIPList") { settings.targetIPList = value }
        if let value = list("broadcastIPList") { settings.broadcastIPList = value }
        if let value = string("bandLayout"), let layout = BandLayout(rawValue: value) {
            settings.bandLayout = layout
        }
        if let value = string("window"), let kind = WindowKind(rawValue: value) {
            settings.window = kind
        }
        if let value = string("normalization"), let mode = Normalization(rawValue: value) {
            settings.normalization = mode
        }
        if let value = string("aggregation"), let mode = BandAggregation(rawValue: value) {
            settings.aggregation = mode
        }
        if let value = string("loudness"), let mode = LoudnessMode(rawValue: value) {
            settings.loudness = mode
        }
        if let value = string("gainMode"), let mode = GainMode(rawValue: value) {
            settings.gainMode = mode
        }
        if let value = string("fftValueScale"), let scale = Bucketizer.Scale(rawValue: value) {
            settings.fftValueScale = scale
        }
        if let value = number("frameSlide") { settings.frameSlide = Int(value) }
        if let value = number("fftLow") { settings.fftLow = Int(value) }
        if let value = number("fftHigh") { settings.fftHigh = Int(value) }
        if let value = boolean("fftFreqLogScale") { settings.fftFreqLogScale = value }
        if let value = boolean("bandSmoothing") { settings.bandSmoothing = value }
        if let value = number("attackSeconds") { settings.attackSeconds = Float(value) }
        if let value = number("releaseSeconds") { settings.releaseSeconds = Float(value) }
        if let value = number("gainAttackSeconds") { settings.gainAttackSeconds = Float(value) }
        if let value = number("gainReleaseSeconds") { settings.gainReleaseSeconds = Float(value) }
        if let value = number("gainFloor") { settings.gainFloor = Float(value) }
        if let value = boolean("removeDCOffset") { settings.removeDCOffset = value }
        if let value = boolean("beatLatch") { settings.beatLatch = value }
        if let value = boolean("manualGain") { settings.manualGain = value }
        if let value = number("manualGainReference") {
            settings.manualGainReference = Float(value)
        }
        if let value = number("squelch") { settings.squelch = Float(value) }

        return settings
    }
}
