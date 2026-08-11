import Foundation

/// Пакет WLED audiosync версии 2 — ровно 44 байта, little-endian, без выравнивания.
///
/// Раскладка (совпадает с `audioSyncPacket` в WLED и с `AudioSyncPacket.cs` оригинала):
///
///     offset  0  char     header[6]          "00002\0"
///     offset  6  uint8    pressure[2]        фикс. точка 8.8
///     offset  8  float    sampleRaw
///     offset 12  float    sampleSmth
///     offset 16  uint8    samplePeak         0 — нет бита, >=1 — есть
///     offset 17  uint8    frameCounter       счётчик для отсева дублей
///     offset 18  uint8    fftResult[16]      16 каналов эквалайзера
///     offset 34  uint16   zeroCrossingCount
///     offset 36  float    FFT_Magnitude
///     offset 40  float    FFT_MajorPeak      Гц
public struct AudioSyncPacket: Sendable {
    public static let byteCount = 44
    public static let header: [UInt8] = [0x30, 0x30, 0x30, 0x30, 0x32, 0x00]  // "00002\0"

    public var sampleRaw: Float = 0
    public var sampleSmth: Float = 0
    public var samplePeak: UInt8 = 0
    public var frameCounter: UInt8 = 0
    public var fftBins = [UInt8](repeating: 0, count: 16)
    public var zeroCrossingCount: UInt16 = 0
    public var fftMagnitude: Float = 0
    public var fftMajorPeak: Float = 0

    /// Звуковое давление. Хранится как есть, в байты переводится в фиксированную точку 8.8.
    public var pressure: Float = 0

    public init() {}

    /// Сериализация в 44 байта проводного формата.
    public func encoded() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.byteCount)

        bytes.append(contentsOf: Self.header)

        // Фиксированная точка 8.8: старший байт — целая часть, младший — дробная.
        // Проверка на конечность обязательна: max(NaN, 0) в Swift возвращает NaN,
        // а Int(NaN) роняет процесс. Пришло бы из деления на ноль в АРУ.
        let safePressure = pressure.isFinite ? min(max(pressure, 0), 255) : 0
        let clamped = Int(safePressure * 256.0)
        bytes.append(UInt8(clamped / 256))
        bytes.append(UInt8(clamped % 256))

        bytes.append(contentsOf: littleEndianBytes(sampleRaw))
        bytes.append(contentsOf: littleEndianBytes(sampleSmth))
        bytes.append(samplePeak)
        bytes.append(frameCounter)
        bytes.append(contentsOf: fftBins.prefix(16))
        bytes.append(UInt8(zeroCrossingCount & 0xFF))
        bytes.append(UInt8((zeroCrossingCount >> 8) & 0xFF))
        bytes.append(contentsOf: littleEndianBytes(fftMagnitude))
        bytes.append(contentsOf: littleEndianBytes(fftMajorPeak))

        assert(bytes.count == Self.byteCount, "Пакет должен быть ровно \(Self.byteCount) байт")
        return bytes
    }

    private func littleEndianBytes(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    /// Затухание вместо резкого обнуления — иначе лента гаснет рывком.
    /// Порт `AudioSyncPacketExtensions.DecayValues` из оригинала.
    public mutating func decay(rate: Float) {
        sampleRaw = decayToZero(sampleRaw, rate)
        sampleSmth = decayToZero(sampleSmth, rate)
        for i in fftBins.indices {
            fftBins[i] = UInt8((Float(fftBins[i]) * rate).rounded(.down))
        }
        fftMagnitude = decayToZero(fftMagnitude, rate)
        pressure = decayToZero(pressure, rate)
    }

    private func decayToZero(_ value: Float, _ rate: Float) -> Float {
        value < 0.01 ? 0 : value * rate
    }
}
