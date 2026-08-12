import SwiftUI

/// Гамма сцены. Одна тональность на всю картинку: глубина читается яркостью
/// и затуханием, а разноцветье её только разрушает.
public enum Palette: String, CaseIterable, Identifiable, Sendable {
    case amber, ice, violet, mono

    public var id: String { rawValue }

    /// Тон в глубине и тон у зрителя.
    public var hues: (deep: Double, hot: Double) {
        switch self {
        case .amber:  return (0.030, 0.105)
        case .ice:    return (0.600, 0.505)
        case .violet: return (0.755, 0.870)
        case .mono:   return (0.000, 0.000)
        }
    }

    public var saturation: Double { self == .mono ? 0 : 1 }

    public var title: String {
        switch self {
        case .amber: return "Amber"
        case .ice: return "Ice"
        case .violet: return "Violet"
        case .mono: return "Mono"
        }
    }
}

/// Плоская полоса спектра для строки меню.
public struct SpectrumStrip: View, @MainActor Animatable {
    public let bands: [Float]
    public var barCount: Int

    /// Ход разгорания от 0 до 1. Полосы поднимаются не разом, а слева направо:
    /// бас первым, верх последним — ровно так гряда и отзывается на первый такт.
    ///
    /// Значение анимируемое: `animatableData` заставляет SwiftUI пересчитывать
    /// холст на промежуточных долях, иначе разгорание было бы скачком из 0 в 1.
    public var ignition: Double

    public init(bands: [Float], barCount: Int = 16, ignition: Double = 1) {
        self.bands = bands
        self.barCount = barCount
        self.ignition = ignition
    }

    public var animatableData: Double {
        get { ignition }
        set { ignition = newValue }
    }

    public var body: some View {
        Canvas { context, size in
            guard barCount > 0 else { return }
            let gap: CGFloat = 1
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            guard barWidth > 0 else { return }

            for index in 0..<barCount {
                let gate = Motion.bandGate(ignition, index: index, count: barCount)
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                // Гасим не прозрачностью, а высотой: полоса не проявляется
                // призраком, а вырастает со дна, как на самой ленте. Погашенная
                // гряда при этом не исчезает — остаётся шестнадцать тёмных нитей,
                // и видно, что зажигать есть что.
                let height = max(1, value * size.height * CGFloat(gate))
                let rect = CGRect(x: CGFloat(index) * (barWidth + gap),
                                  y: size.height - height,
                                  width: barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 3),
                             with: .color(.primary.opacity(0.12 + 0.88 * gate)))
            }
        }
    }
}


/// Оформление сцены.
public enum SceneStyle: String, CaseIterable, Identifiable, Sendable {
    /// Венец из объёмных колонн спектра по кругу.
    case crown
    /// Неоновое кольцо со знаком слева.
    case neon
    /// Круговой спектр вокруг диска.
    case ring
    /// Проволочная сфера, деформируемая спектром.
    case sphere

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .crown: return "Crown"
        case .neon: return "Neon"
        case .ring: return "Ring"
        case .sphere: return "Sphere"
        }
    }
}
