import Foundation

/// Детектор бита по низким частотам: удар засчитывается, когда текущая энергия
/// в полосе превышает среднюю за окно истории. Порт `BeatDetector.cs`.
public final class BeatDetector {
    private static let maxHistory = 50
    private static let thresholdMultiplier: Float = 1.20

    private let freqLow: Float
    private let freqHigh: Float
    private var history = [Float]()

    public private(set) var detected = false

    public init(freqLow: Float = 100, freqHigh: Float = 500) {
        self.freqLow = freqLow
        self.freqHigh = freqHigh
        history.reserveCapacity(Self.maxHistory)
    }

    public func process(_ fft: FFTProcessor) {
        let range = fft.indexes(freqLow: freqLow, freqHigh: freqHigh)
        var current: Float = 0
        for i in range {
            current = max(current, fft.magnitudes[i])
        }

        if history.count == Self.maxHistory {
            let average = history.reduce(0, +) / Float(Self.maxHistory)
            detected = current > average * Self.thresholdMultiplier
        }

        history.append(current)
        if history.count > Self.maxHistory {
            history.removeFirst()
        }
    }
}
