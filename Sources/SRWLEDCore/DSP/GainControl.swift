import Foundation

/// Автоматическая (или ручная) регулировка усиления по полосам.
///
/// В оригинале опора догоняла текущий максимум на 75% за кадр. Отсюда «приседание»:
/// удар бочки мгновенно поднимал опору, все остальные полосы делились на возросшее
/// число и лента гасла ровно в момент удара — визуально это читается как провал,
/// а не как акцент.
///
/// Здесь опора идёт медленно (сотни миллисекунд вверх, секунды вниз), а превышение
/// снимает отдельный ограничитель — он зажимает выход, но не двигает опору. Плюс
/// нижний предел: без него в паузе усиление раскручивается до упора и фоновый шум
/// выходит на полную яркость.
public final class GainControl {
    public private(set) var offset: Float = 0
    public private(set) var span: Float = 0

    private var isFirstFrame = true

    private let mode: GainMode
    private let manual: Bool
    private let manualSpanReference: Float
    private let floor: Float
    private let attackAlpha: Float
    private let releaseAlpha: Float

    /// - Parameters:
    ///   - framesPerSecond: нужен, чтобы постоянные времени не зависели от шага анализа.
    public init(mode: GainMode = .stable,
                manual: Bool = false,
                manualSpanReference: Float = 50,
                floor: Float = 0.02,
                attackSeconds: Float = 1.0,
                releaseSeconds: Float = 2.0,
                framesPerSecond: Float = 47)
    {
        self.mode = mode
        self.manual = manual
        self.manualSpanReference = manualSpanReference
        self.floor = floor
        self.attackAlpha = Self.alpha(seconds: attackSeconds, framesPerSecond: framesPerSecond)
        self.releaseAlpha = Self.alpha(seconds: releaseSeconds, framesPerSecond: framesPerSecond)
    }

    private static func alpha(seconds: Float, framesPerSecond: Float) -> Float {
        guard seconds > 0, framesPerSecond > 0 else { return 1 }
        return 1 - exp(-1 / (seconds * framesPerSecond))
    }

    public func process(buckets: [Bucketizer.Bucket]) {
        let bucketMax = buckets.map(\.value).max() ?? 0
        offset = 0

        if manual {
            span = 1 - log10(manualSpanReference + 1) / log10(101)
            return
        }

        if isFirstFrame {
            isFirstFrame = false
            span = max(bucketMax, floor)
            return
        }

        switch mode {
        case .original:
            if span < bucketMax {
                span = (span * 25 + bucketMax * 75) / 100   // быстрое схождение на громком
            } else {
                span = (span * 90 + bucketMax * 10) / 100   // медленное — на тихом
            }

        case .stable:
            let alpha = bucketMax > span ? attackAlpha : releaseAlpha
            span += alpha * (bucketMax - span)
            span = max(span, floor)
        }
    }
}
