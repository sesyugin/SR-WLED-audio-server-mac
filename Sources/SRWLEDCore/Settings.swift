import Foundation

/// Окно взвешивания перед БПФ.
public enum WindowKind: String, CaseIterable, Sendable {
    /// Узкий главный лепесток (2 бина) — тон не размазывается по соседним полосам.
    case hann
    /// Плоская вершина ради точности амплитуды, но лепесток шириной 4.58 бина.
    /// Так делал оригинал: один басовый тон зажигал сразу четыре нижние полосы.
    case flatTop
}

/// Раскладка 16 полос эквалайзера.
public enum BandLayout: String, CaseIterable, Sendable {
    /// Таблица, зашитая в саму прошивку WLED. Эффекты рисовались под неё.
    case wled
    /// Логарифмическое деление произвольного диапазона — как в Windows-версии.
    case custom
}

/// Чем заполнять поля уровня в пакете.
public enum LoudnessMode: String, CaseIterable, Sendable {
    /// Действительная громкость кадра в дБ. Эффекты WLED ждут именно её.
    case rms
    /// Отношение средней полосы к максимальной — то, что клал оригинал.
    /// Это мера «плоскости» спектра, а не громкость: изменение сигнала на 60 дБ
    /// двигает значение на единицы процентов.
    case spectralRatio
}

/// Как приводить амплитуду спектра к диапазону 0…1.
public enum Normalization: String, CaseIterable, Sendable {
    /// Аналитически: пик синуса полной шкалы равен 1.0 при любом размере окна
    /// и любой частоте дискретизации.
    case analytic
    /// Три константы, подобранные автором оригинала на своей звуковой карте.
    case originalConstants
}

/// Настройки сервера.
///
/// Значения по умолчанию — исправленное поведение. Чтобы получить в точности
/// поведение Windows-версии, возьми `Settings.originalCompatible()`.
public struct Settings: Sendable {
    public enum SendMode: String, CaseIterable, Sendable {
        case broadcastLAN       // 255.255.255.255 — по умолчанию
        case broadcastSubnet    // широковещательные адреса подсетей из списка
        case multicast          // 239.0.0.1, требует IGMP snooping на роутере
        case targetIPList       // точечно по списку адресов
    }

    // MARK: Сеть

    public var port: UInt16 = 11988
    public var sendMode: SendMode = .broadcastLAN
    public var broadcastIPList: [String] = []
    public var targetIPList: [String] = []
    public var localIPToBind: String? = nil

    // MARK: Спектр

    public var bandLayout: BandLayout = .wled
    public var window: WindowKind = .hann
    public var normalization: Normalization = .analytic

    /// Границы для `BandLayout.custom`. Значения по умолчанию — как в оригинале.
    public var fftLow: Int = 40
    public var fftHigh: Int = 10000
    public var fftFreqLogScale: Bool = true
    public var fftValueScale: Bucketizer.Scale = .squareRoot

    // MARK: Уровень и динамика

    public var loudness: LoudnessMode = .rms

    /// Убирать постоянную составляющую перед анализом. Без этого смещение входа
    /// зажигает нижнюю полосу и перебивает музыку.
    public var removeDCOffset: Bool = true

    /// Отправлять признак удара одиночным импульсом. WLED сбрасывает его сам через
    /// max(50 мс, длительность кадра); если держать флаг поднятым, эффекты вроде
    /// Puddlepeak срабатывают непрерывно вместо реальных ударов.
    public var beatLatch: Bool = true

    public var manualGain: Bool = false
    public var manualGainReference: Float = 50

    /// Порог тишины. -60 dBFS: ниже него кадр считается пустым и пакет затухает.
    /// В оригинале стояло 0.00001, то есть -100 dBFS — ниже разрешения 16-битного звука.
    public var squelch: Float = 0.001

    public init() {}

    /// Поведение в точности как у Windows-версии — для сравнения бок о бок.
    public static func originalCompatible() -> Settings {
        var settings = Settings()
        settings.bandLayout = .custom
        settings.window = .flatTop
        settings.normalization = .originalConstants
        settings.loudness = .spectralRatio
        settings.removeDCOffset = false
        settings.beatLatch = false
        settings.squelch = 0.00001
        return settings
    }
}
