import Foundation

/// Детектор удара.
///
/// Оригинал брал максимум в полосе 100–500 Гц и сравнивал со средним за окно истории.
/// Две беды: один сильный удар входит в это же среднее и поднимает порог почти на 3 дБ,
/// после чего следующие удары теряются; и никакого запрета на повторное срабатывание —
/// один кик давал несколько сработок подряд.
///
/// Здесь считается спектральный поток — сумма прироста энергии по бинам относительно
/// предыдущего кадра. Он реагирует на атаку, а не на громкость, поэтому ровный громкий
/// бас ударом не считается. Порог берётся от медианы истории (одиночный всплеск её
/// почти не двигает), плюс рефрактерный период.
public final class BeatDetector {
    public enum Mode: String, CaseIterable, Sendable {
        /// Спектральный поток, медиана, рефрактерный период.
        case spectralFlux
        /// Максимум в полосе против среднего — как в оригинале.
        case originalAverage
    }

    private static let historyLength = 50
    private static let fluxThresholdMultiplier: Float = 1.6
    private static let averageThresholdMultiplier: Float = 1.20

    private let mode: Mode
    private let freqLow: Float
    private let freqHigh: Float
    private let refractoryFrames: Int

    private var history = [Float]()
    private var previousMagnitudes = [Float]()
    private var framesSinceBeat = Int.max

    public private(set) var detected = false

    public init(mode: Mode = .spectralFlux,
                freqLow: Float = 100,
                freqHigh: Float = 500,
                refractorySeconds: Float = 0.1,
                framesPerSecond: Float = 47)
    {
        self.mode = mode
        self.freqLow = freqLow
        self.freqHigh = freqHigh
        self.refractoryFrames = max(1, Int((refractorySeconds * framesPerSecond).rounded()))
        history.reserveCapacity(Self.historyLength)
    }

    public func process(_ fft: FFTProcessor) {
        let range = fft.indexes(freqLow: freqLow, freqHigh: freqHigh)

        let current: Float
        switch mode {
        case .originalAverage:
            var maximum: Float = 0
            for i in range { maximum = max(maximum, fft.magnitudes[i]) }
            current = maximum

        case .spectralFlux:
            if previousMagnitudes.count != fft.magnitudes.count {
                previousMagnitudes = fft.magnitudes
                current = 0
            } else {
                var flux: Float = 0
                for i in range {
                    let rise = fft.magnitudes[i] - previousMagnitudes[i]
                    if rise > 0 { flux += rise }        // только прирост — это и есть атака
                }
                for i in fft.magnitudes.indices { previousMagnitudes[i] = fft.magnitudes[i] }
                current = flux
            }
        }

        framesSinceBeat = framesSinceBeat == Int.max ? Int.max : framesSinceBeat + 1
        detected = false

        if history.count == Self.historyLength {
            let threshold: Float
            switch mode {
            case .spectralFlux:
                // Медиана вместо среднего: одиночный сильный удар её почти не двигает.
                threshold = median(history) * Self.fluxThresholdMultiplier
            case .originalAverage:
                threshold = history.reduce(0, +) / Float(Self.historyLength)
                             * Self.averageThresholdMultiplier
            }

            let loudEnough = current > threshold && current > 0
            let outOfRefractory = mode == .originalAverage || framesSinceBeat >= refractoryFrames
            if loudEnough && outOfRefractory {
                detected = true
                framesSinceBeat = 0
            }
        }

        history.append(current)
        if history.count > Self.historyLength { history.removeFirst() }
    }

    private func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
