import Foundation

/// Несимметричное сглаживание полос по времени: быстро вверх, медленно вниз.
///
/// Без него значения полос пересчитываются с нуля каждый кадр, и даже на идеально
/// ровном звуке они гуляют на десятки процентов — лента мерцает там, где звук
/// не меняется. Быстрое нарастание нужно, чтобы удар не смазался, медленный спад —
/// чтобы полоса не проваливалась между периодами колебания.
public final class BandSmoother {
    private var values: [Float]
    private let attackAlpha: Float
    private let releaseAlpha: Float

    public init(bandCount: Int,
                attackSeconds: Float,
                releaseSeconds: Float,
                framesPerSecond: Float)
    {
        self.values = [Float](repeating: 0, count: bandCount)
        self.attackAlpha = Self.alpha(seconds: attackSeconds, framesPerSecond: framesPerSecond)
        self.releaseAlpha = Self.alpha(seconds: releaseSeconds, framesPerSecond: framesPerSecond)
    }

    private static func alpha(seconds: Float, framesPerSecond: Float) -> Float {
        guard seconds > 0, framesPerSecond > 0 else { return 1 }
        return 1 - exp(-1 / (seconds * framesPerSecond))
    }

    /// Сглаживает значения на месте.
    public func apply(to buckets: inout [Bucketizer.Bucket]) {
        for i in buckets.indices where i < values.count {
            let target = buckets[i].value
            let alpha = target > values[i] ? attackAlpha : releaseAlpha
            values[i] += alpha * (target - values[i])
            buckets[i].value = values[i]
        }
    }

    public func reset() {
        for i in values.indices { values[i] = 0 }
    }
}
