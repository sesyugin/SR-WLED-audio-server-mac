import Foundation

/// Сворачивает спектр в 16 полос эквалайзера WLED.
/// Порт `Bucketizer.cs`, включая подобранные автором константы нормировки.
public final class Bucketizer {
    public enum Scale: String, CaseIterable, Sendable {
        case linear = "Linear"
        case logarithmic = "Logarithmic"
        case squareRoot = "SquareRoot"
    }

    public struct Bucket: Sendable {
        public var freqLow: Float = 0
        public var freqHigh: Float = 0
        public var value: Float = 0
        public var dataCount: Int = 0
        /// Полоса уже полученных интерполяцией соседей — в неё не попал ни один бин БПФ.
        public var interpolated: Bool = false
    }

    /// Границы 16 полос, зашитые в прошивку WLED (`audio_reactive.cpp`, `fftCalc[0..15]`).
    /// Эффекты GEQ, DJ Light, Blurz и Akemi авторы настраивали именно под эту таблицу:
    /// каждый канал светит своим цветом в своей точке ленты.
    public static let wledBandEdges: [Float] = [
        43, 86, 129, 216, 301, 430, 560, 818, 1120,
        1421, 1895, 2412, 3015, 3704, 4479, 7106, 9259,
    ]

    // «Самые громкие сигналы, измеренные на моей системе» — комментарий автора оригинала.
    // Числа привязаны к его звуковой карте и к размеру БПФ: при смене размера они молча ломаются.
    private static let normScaleLinearMax: Float = 0.001769422435994416
    private static let normScaleLogarithmicMax: Float = 7.4804198503512
    private static let normScaleSquareRootMax: Float = 0.04193937709831769

    public private(set) var buckets: [Bucket]
    public private(set) var peakValue: Float = 0
    public private(set) var peakFrequency: Float = 0

    private let freqPoints: [Float]
    private let scale: Scale
    private let normalization: Normalization
    /// Множитель аналитической нормировки: пик синуса полной шкалы даёт ровно 1.0.
    private let analyticScale: Float

    /// Полосы по произвольным границам: `edges` содержит на один элемент больше, чем полос.
    public init(edges: [Float],
                valueScale: Scale,
                normalization: Normalization,
                fftSize: Int)
    {
        precondition(edges.count >= 2, "нужно минимум две границы полос")

        self.scale = valueScale
        self.normalization = normalization
        self.freqPoints = edges

        // Для окна, нормированного по сумме, пик синуса амплитуды A равен A/N.
        // Значит домножение на N приводит полную шкалу ровно к единице —
        // без констант, подобранных под конкретную звуковую карту.
        self.analyticScale = Float(fftSize)

        self.buckets = (0..<(edges.count - 1)).map { i in
            var bucket = Bucket()
            bucket.freqLow = edges[i]
            bucket.freqHigh = edges[i + 1]
            return bucket
        }
    }

    /// Полосы логарифмическим или линейным делением диапазона — как в Windows-версии.
    public convenience init(bucketCount: Int = 16,
                            freqMin: Int,
                            freqMax: Int,
                            logFreqScale: Bool,
                            valueScale: Scale,
                            normalization: Normalization = .originalConstants,
                            fftSize: Int = 2048)
    {
        self.init(edges: Self.freqBands(freqMin: freqMin,
                                        freqMax: freqMax,
                                        logScale: logFreqScale,
                                        count: bucketCount),
                  valueScale: valueScale,
                  normalization: normalization,
                  fftSize: fftSize)
    }

    private static func freqBands(freqMin: Int, freqMax: Int, logScale: Bool, count: Int) -> [Float] {
        let low = Double(freqMin), high = Double(freqMax)
        return (0...count).map { i in
            if logScale {
                return Float(low * pow(high / low, Double(i) / Double(count)))
            } else {
                return Float(low + (high - low) / Double(count) * Double(i))
            }
        }
    }

    /// Приводит амплитуду бина к диапазону примерно 0…1.
    private func scaled(_ value: Float) -> Float {
        switch normalization {
        case .analytic:
            return scaledAnalytically(value)
        case .originalConstants:
            return scaledByOriginalConstants(value)
        }
    }

    /// Нормировка от размера окна: пик синуса полной шкалы = 1.0 при любом N и любой частоте.
    private func scaledAnalytically(_ value: Float) -> Float {
        let unit = abs(value) * analyticScale        // 0…1 для полной шкалы
        switch scale {
        case .linear:
            return unit
        case .squareRoot:
            return unit.squareRoot()
        case .logarithmic:
            // Равномерная шкала в децибелах: -60 dBFS даёт 0, полная шкала — 1.
            guard unit > 0 else { return 0 }
            let dB = 20 * log10(unit)
            return max(0, min(1, (dB + 60) / 60))
        }
    }

    private func scaledByOriginalConstants(_ value: Float) -> Float {
        switch scale {
        case .linear:
            return abs(value) / Self.normScaleLinearMax
        case .squareRoot:
            return abs(value).squareRoot() / Self.normScaleSquareRootMax
        case .logarithmic:
            guard value != 0 else { return 0 }
            return max(0, log(abs(value) * 1_000_000)) / Self.normScaleLogarithmicMax
        }
    }

    public func process(_ fft: FFTProcessor) {
        let fullRange = fft.indexes(freqLow: freqPoints[0], freqHigh: freqPoints[freqPoints.count - 1])

        // Пик по всему рабочему диапазону — он уходит в FFT_Magnitude / FFT_MajorPeak.
        var peakIndex = fullRange.lowerBound
        var peakMagnitude: Float = -1
        for i in fullRange where fft.magnitudes[i] > peakMagnitude {
            peakMagnitude = fft.magnitudes[i]
            peakIndex = i
        }
        if peakMagnitude >= 0 {
            peakValue = scaled(fft.magnitudes[peakIndex])
            peakFrequency = fft.frequencies[peakIndex]
        } else {
            peakValue = 0
            peakFrequency = 0
        }

        for i in buckets.indices {
            let range = fft.indexes(freqLow: freqPoints[i], freqHigh: freqPoints[i + 1])
            if range.isEmpty {
                // Внизу шкалы полосы уже шага БПФ — бинов может не оказаться вовсе.
                buckets[i].interpolated = true
                buckets[i].dataCount = 0
            } else {
                var maxValue: Float = 0
                for idx in range {
                    maxValue = max(maxValue, scaled(fft.magnitudes[idx]))
                }
                buckets[i].interpolated = false
                buckets[i].value = maxValue
                buckets[i].dataCount = range.count
            }
        }

        // Пустые полосы получают среднее соседей (края не трогаем — как в оригинале).
        for i in 1..<(buckets.count - 1) where buckets[i].interpolated {
            buckets[i].value = (buckets[i - 1].value + buckets[i + 1].value) / 2
        }
    }
}
