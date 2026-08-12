import SwiftUI

/// Круговой спектр вокруг центрального диска.
///
/// Оформление в духе музыкальных релизов: по центру круг, вокруг него венец
/// из тонких лучей, глубокий фон и один акцентный цвет. Всё держится на симметрии
/// и на чистоте — лишних слоёв здесь нет намеренно.
///
/// Венец зеркальный: правая половина повторяет левую. Так делают в клипах, и это
/// не украшательство — симметричная форма читается как единый объект, а несимметричная
/// распадается на случайный частокол.
public struct RingScene: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette

    @State private var smoother = SpectrumSmoother()
    @State private var beat = BeatFlash()

    public init(sampler: @escaping Sampler,
                isRunning: Bool,
                palette: Palette = .amber)
    {
        self.sampler = sampler
        self.isRunning = isRunning
        self.palette = palette
    }

    /// Лучей в венце. Половина считается, вторая зеркалится.
    private static let rays = 128

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                beat.step(time: time, bass: smoother.values.prefix(3).max() ?? 0)
                draw(&context, size: size, time: time)
            }
        }
        .background(Color(red: 0.024, green: 0.022, blue: 0.030))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        let energy = smoother.energy
        let flash = beat.intensity
        let hues = palette.hues

        let innerRadius = base * 0.20 * (1 + 0.020 * flash)
        let maxLength = base * 0.17

        // Ореол позади — очень сдержанный, только чтобы диск не был вырезан из фона.
        let glowRadius = innerRadius * (2.5 + 0.5 * energy)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glowRadius, y: centre.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.hot, saturation: palette.saturation * 0.75,
                                       brightness: 1).opacity(0.05 + 0.11 * energy + 0.08 * flash),
                          location: 0.25),
                    .init(color: .clear, location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: glowRadius))

        // Центральный диск.
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - innerRadius, y: centre.y - innerRadius,
                                   width: innerRadius * 2, height: innerRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.55,
                                       brightness: 0.16), location: 0),
                    .init(color: Color(red: 0.035, green: 0.030, blue: 0.042), location: 1),
                ]),
                center: CGPoint(x: centre.x - innerRadius * 0.3, y: centre.y - innerRadius * 0.35),
                startRadius: 0, endRadius: innerRadius * 1.5))

        // Тонкий контур диска.
        context.stroke(
            Path(ellipseIn: CGRect(x: centre.x - innerRadius, y: centre.y - innerRadius,
                                   width: innerRadius * 2, height: innerRadius * 2)),
            with: .color(Color(hue: hues.hot, saturation: palette.saturation * 0.5, brightness: 1)
                .opacity(0.16 + 0.24 * energy)),
            style: StrokeStyle(lineWidth: base * 0.0016))

        // Венец лучей.
        let half = Self.rays / 2
        for index in 0..<Self.rays {
            // Зеркалим: индексы правее середины повторяют левые.
            let mirrored = index < half ? index : Self.rays - 1 - index
            let position = Double(mirrored) / Double(half - 1)

            // Плавная выборка по 16 полосам.
            let scaled = position * 15
            let lower = min(15, Int(scaled))
            let upper = min(15, lower + 1)
            let blend = scaled - Double(lower)
            let value = smoother.values[lower] * (1 - blend) + smoother.values[upper] * blend

            // Луч начинается от контура диска и растёт наружу.
            let angle = Double(index) / Double(Self.rays) * 2 * .pi - .pi / 2
            let length = maxLength * (0.06 + 0.94 * value)

            let from = CGPoint(x: centre.x + cos(angle) * innerRadius * 1.035,
                               y: centre.y + sin(angle) * innerRadius * 1.035)
            let to = CGPoint(x: centre.x + cos(angle) * (innerRadius * 1.035 + length),
                             y: centre.y + sin(angle) * (innerRadius * 1.035 + length))

            var ray = Path()
            ray.move(to: from)
            ray.addLine(to: to)

            let tint = Color(hue: hues.deep + (hues.hot - hues.deep) * value,
                             saturation: palette.saturation * (0.85 - 0.35 * value),
                             brightness: 1)
            context.stroke(ray,
                           with: .color(tint.opacity(0.30 + 0.55 * value)),
                           style: StrokeStyle(lineWidth: base * 0.0026, lineCap: .round))
        }

        // Внешнее кольцо, замыкающее композицию.
        let outer = innerRadius * 1.035 + maxLength * 1.12
        context.stroke(
            Path(ellipseIn: CGRect(x: centre.x - outer, y: centre.y - outer,
                                   width: outer * 2, height: outer * 2)),
            with: .color(Color(hue: hues.hot, saturation: palette.saturation * 0.4, brightness: 1)
                .opacity(0.07 + 0.10 * energy)),
            style: StrokeStyle(lineWidth: base * 0.0012))
    }
}


// MARK: - Вспышка по биту

/// Простой детектор удара по басу: всплеск выше скользящего среднего даёт короткий
/// импульс, который тут же гаснет. Своя реализация, а не из обработки звука, —
/// здесь важна не точность, а совпадение с тем, что видит глаз.
final class BeatFlash {
    private(set) var intensity: Double = 0
    private var average: Double = 0
    private var lastTime: TimeInterval = 0
    private var refractory: Double = 0

    func step(time: TimeInterval, bass: Double) {
        let delta = lastTime == 0 ? 1.0 / 60.0 : min(0.1, max(0.0001, time - lastTime))
        lastTime = time

        average += (bass - average) * (1 - exp(-delta / 0.55))
        refractory = max(0, refractory - delta)

        if bass > average * 1.35 && bass > 0.18 && refractory == 0 {
            intensity = min(1, intensity + 0.85)
            refractory = 0.12
        }

        intensity *= exp(-delta / 0.18)
        if intensity < 0.002 { intensity = 0 }
    }
}
