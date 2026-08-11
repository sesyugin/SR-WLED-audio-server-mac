import Foundation

/// Настройки сервера. Значения по умолчанию совпадают с Windows-версией
/// (`Properties/Settings.settings` оригинала), чтобы лента вела себя так же.
public struct Settings: Sendable {
    public enum SendMode: String, CaseIterable, Sendable {
        case broadcastLAN       // 255.255.255.255 — по умолчанию
        case broadcastSubnet    // широковещательные адреса подсетей из списка
        case multicast          // 239.0.0.1, требует IGMP snooping на роутере
        case targetIPList       // точечно по списку адресов
    }

    // Сеть
    public var port: UInt16 = 11988
    public var sendMode: SendMode = .broadcastLAN
    public var broadcastIPList: [String] = []
    public var targetIPList: [String] = []
    public var localIPToBind: String? = nil

    // Спектр
    public var fftLow: Int = 40
    public var fftHigh: Int = 10000
    public var fftFreqLogScale: Bool = true
    public var fftValueScale: Bucketizer.Scale = .squareRoot

    // Усиление
    public var manualGain: Bool = false
    public var manualGainReference: Float = 50

    /// Порог тишины: ниже него кадр считается пустым и пакет затухает.
    public var squelch: Float = 0.00001

    public init() {}
}
