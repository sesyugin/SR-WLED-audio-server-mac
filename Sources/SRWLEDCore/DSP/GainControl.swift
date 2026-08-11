import Foundation

/// Автоматическая (или ручная) регулировка усиления по полосам.
/// Порт `BucketGainControl.cs`.
///
/// В авторежиме `span` тянется к текущему максимуму полос: быстро вверх (громкое)
/// и медленно вниз (тихое), чтобы лента не «схлопывалась» на паузах.
public final class GainControl {
    public private(set) var offset: Float = 0
    public private(set) var span: Float = 0

    private var isFirstFrame = true
    private let manual: Bool
    private let manualSpanReference: Float

    public init(manual: Bool = false, manualSpanReference: Float = 50) {
        self.manual = manual
        self.manualSpanReference = manualSpanReference
    }

    public func process(buckets: [Bucketizer.Bucket]) {
        let bucketMax = buckets.map(\.value).max() ?? 0

        offset = 0
        let currentSpan = bucketMax + offset

        if isFirstFrame {
            isFirstFrame = false
            span = currentSpan
            return
        }

        if manual {
            span = 1 - log10(manualSpanReference + 1) / log10(101)
        } else if span < currentSpan {
            span = (span * 25 + currentSpan * 75) / 100   // быстрое схождение на громком
        } else {
            span = (span * 90 + currentSpan * 10) / 100   // медленное — на тихом
        }
    }
}
