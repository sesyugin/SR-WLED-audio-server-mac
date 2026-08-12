import SwiftUI

/// Оформление в духе музыкальных релизов: неоновое кольцо справа, знак слева,
/// атмосферный фон с ретро-абстракцией.
///
/// Композиция взята из референсов и держится на трёх вещах. Первое — толстое кольцо
/// с сильным ореолом, смещённое от центра вправо: оно и есть герой кадра, и только
/// оно светится в полную силу. Второе — фон: не чернота, а глубокий градиент
/// с абстрактными топографическими контурами и линией горизонта, дающими воздух.
/// Третье — венец из тонких лучей внутри кольца: много, тонко, аккуратно.
///
/// Кольцо деформируется спектром слабо и плавно. В референсах оно остаётся
/// узнаваемо круглым — сильная деформация превращает знак в кляксу.
public struct NeonScene: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette
    private let showsWordmark: Bool

    @State private var smoother = SpectrumSmoother()
    @State private var beat = BeatFlash()

    public init(sampler: @escaping Sampler,
                isRunning: Bool,
                palette: Palette = .amber,
                showsWordmark: Bool = true)
    {
        self.sampler = sampler
        self.isRunning = isRunning
        self.palette = palette
        self.showsWordmark = showsWordmark
    }

    /// Точек по окружности кольца и лучей в венце.
    private static let ringPoints = 220
    private static let rays = 180

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                beat.step(time: time, bass: smoother.values.prefix(3).max() ?? 0)

                let scene = Layout(size: size, palette: palette)
                drawBackdrop(&context, scene, time: time)
                drawContours(&context, scene, time: time)
                drawHorizon(&context, scene)
                drawRays(&context, scene, time: time)
                drawRing(&context, scene, time: time)
                if showsWordmark { drawWordmark(&context, scene) }
            }
        }
    }

    // MARK: - Раскладка

    private struct Layout {
        let size: CGSize
        let palette: Palette

        var base: Double { min(size.width, size.height) }
        /// Кольцо смещено вправо — как во всех референсах.
        var ringCentre: CGPoint {
            CGPoint(x: size.width * 0.655, y: size.height * 0.50)
        }
        var ringRadius: Double { base * 0.295 }
        var horizon: CGFloat { size.height * 0.74 }

        func colour(_ hue: Double, _ saturation: Double = 1, _ brightness: Double = 1) -> Color {
            Color(hue: hue, saturation: palette.saturation * saturation, brightness: brightness)
        }
    }

    private var energy: Double { smoother.energy }

    /// Значение спектра по углу: плавная выборка с зеркальной симметрией,
    /// чтобы кольцо деформировалось цельно, а не рвано.
    private func spectrum(at angle: Double) -> Double {
        let normalised = (angle / (2 * .pi)).truncatingRemainder(dividingBy: 1)
        let folded = normalised < 0.5 ? normalised * 2 : (1 - normalised) * 2
        let scaled = folded * 15
        let lower = min(15, Int(scaled))
        let upper = min(15, lower + 1)
        let blend = scaled - Double(lower)
        guard smoother.values.count == 16 else { return 0 }
        return smoother.values[lower] * (1 - blend) + smoother.values[upper] * blend
    }

    // MARK: - Фон

    private func drawBackdrop(_ context: inout GraphicsContext, _ layout: Layout, time: TimeInterval) {
        let hues = layout.palette.hues

        // Глубокий градиент вместо черноты: сверху почти ночь, к горизонту теплеет.
        context.fill(
            Path(CGRect(origin: .zero, size: layout.size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.035, green: 0.032, blue: 0.070), location: 0.0),
                    .init(color: Color(red: 0.055, green: 0.040, blue: 0.085), location: 0.45),
                    .init(color: layout.colour(hues.deep, 0.75, 0.30)
                        .opacity(0.55 + 0.25 * energy), location: 0.80),
                    .init(color: Color(red: 0.030, green: 0.024, blue: 0.045), location: 1.0),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: layout.size.height)))

        // Тусклое зарево у горизонта под кольцом.
        context.blendMode = .plusLighter
        let glowRadius = layout.base * (0.62 + 0.14 * energy)
        let glowCentre = CGPoint(x: layout.ringCentre.x, y: layout.horizon)
        context.fill(
            Path(ellipseIn: CGRect(x: glowCentre.x - glowRadius, y: glowCentre.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: layout.colour(hues.hot, 0.7).opacity(0.10 + 0.10 * energy),
                          location: 0),
                    .init(color: .clear, location: 1),
                ]),
                center: glowCentre, startRadius: 0, endRadius: glowRadius))
        context.blendMode = .normal
    }

    /// Абстрактные топографические контуры — ретро-модерн из первого референса.
    /// Тонкие, приглушённые, они дают фактуру и не спорят с кольцом.
    private func drawContours(_ context: inout GraphicsContext, _ layout: Layout, time: TimeInterval) {
        let origin = CGPoint(x: layout.size.width * 0.22, y: layout.size.height * 0.44)
        let rings = 9

        for ring in 0..<rings {
            let scale = 0.10 + Double(ring) * 0.115
            let radius = layout.base * scale
            var path = Path()

            for step in 0...96 {
                let theta = Double(step) / 96 * 2 * .pi
                // Небольшая, медленно плывущая неправильность — контуры «дышат».
                let wobble = 1
                    + 0.16 * sin(theta * 2 + time * 0.10 + Double(ring) * 0.7)
                    + 0.09 * sin(theta * 3 - time * 0.07 + Double(ring) * 1.3)
                let r = radius * wobble
                let point = CGPoint(x: origin.x + cos(theta) * r,
                                    y: origin.y + sin(theta) * r * 0.86)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }

            context.stroke(path,
                           with: .color(.white.opacity(0.045 + 0.025 * (1 - Double(ring) / Double(rings)))),
                           style: StrokeStyle(lineWidth: layout.base * 0.0016))
        }
    }

    /// Линия горизонта с редкой сеткой — тот самый ретро-футуризм, но очень сдержанно.
    private func drawHorizon(_ context: inout GraphicsContext, _ layout: Layout) {
        let hues = layout.palette.hues

        var line = Path()
        line.move(to: CGPoint(x: 0, y: layout.horizon))
        line.addLine(to: CGPoint(x: layout.size.width, y: layout.horizon))
        context.stroke(line,
                       with: .linearGradient(
                           Gradient(colors: [.clear,
                                             layout.colour(hues.hot, 0.5).opacity(0.28 + 0.20 * energy),
                                             .clear]),
                           startPoint: CGPoint(x: 0, y: layout.horizon),
                           endPoint: CGPoint(x: layout.size.width, y: layout.horizon)),
                       style: StrokeStyle(lineWidth: layout.base * 0.0015))

        // Несколько уходящих вдаль поперечин — намёк на сетку, не сама сетка.
        for row in 1...5 {
            let t = Double(row) / 5
            let y = layout.horizon + CGFloat(t * t * Double(layout.size.height - layout.horizon))
            guard y < layout.size.height else { continue }
            var bar = Path()
            bar.move(to: CGPoint(x: 0, y: y))
            bar.addLine(to: CGPoint(x: layout.size.width, y: y))
            context.stroke(bar,
                           with: .color(layout.colour(hues.hot, 0.45).opacity(0.05 * (1 - t) + 0.02)),
                           style: StrokeStyle(lineWidth: layout.base * 0.0012))
        }
    }

    // MARK: - Венец из лучей

    /// Тонкие лучи внутри кольца. Их много и они аккуратные — это то, что должно
    /// читаться как спектр, тогда как кольцо остаётся цельным знаком.
    private func drawRays(_ context: inout GraphicsContext, _ layout: Layout, time: TimeInterval) {
        let hues = layout.palette.hues
        let centre = layout.ringCentre
        let inner = layout.ringRadius * 0.26
        let span = layout.ringRadius * 0.62

        context.blendMode = .plusLighter
        for index in 0..<Self.rays {
            let angle = Double(index) / Double(Self.rays) * 2 * .pi - .pi / 2
            let value = spectrum(at: angle + .pi / 2)
            let length = span * (0.05 + 0.95 * value)

            let from = CGPoint(x: centre.x + cos(angle) * inner,
                               y: centre.y + sin(angle) * inner)
            let to = CGPoint(x: centre.x + cos(angle) * (inner + length),
                             y: centre.y + sin(angle) * (inner + length))

            var ray = Path()
            ray.move(to: from)
            ray.addLine(to: to)
            context.stroke(ray,
                           with: .color(layout.colour(hues.hot, 0.35 - 0.25 * value)
                               .opacity(0.16 + 0.42 * value)),
                           style: StrokeStyle(lineWidth: layout.base * 0.0018, lineCap: .round))
        }
        context.blendMode = .normal
    }

    // MARK: - Кольцо

    private func drawRing(_ context: inout GraphicsContext, _ layout: Layout, time: TimeInterval) {
        let hues = layout.palette.hues
        let centre = layout.ringCentre
        let flash = beat.intensity

        var path = Path()
        for step in 0...Self.ringPoints {
            let theta = Double(step) / Double(Self.ringPoints) * 2 * .pi
            // Деформация намеренно слабая: в референсах кольцо остаётся круглым,
            // сильное искажение превращает знак в кляксу.
            let value = spectrum(at: theta)
            let wobble = 1
                + 0.045 * value
                + 0.012 * sin(theta * 3 + time * 0.9)
                + 0.008 * sin(theta * 5 - time * 1.3)
            let r = layout.ringRadius * wobble * (1 + 0.012 * flash)
            let point = CGPoint(x: centre.x + cos(theta) * r, y: centre.y + sin(theta) * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        let neon = layout.colour(hues.hot, 0.85)
        let width = layout.ringRadius * 0.075

        // Ореол: несколько обводок с падающей непрозрачностью. Единственное место
        // в кадре, где свет работает в полную силу — герой должен быть один.
        context.blendMode = .plusLighter
        for step in stride(from: 5.5, through: 1.4, by: -0.5) {
            context.stroke(path,
                           with: .color(neon.opacity((0.030 + 0.020 * flash))),
                           style: StrokeStyle(lineWidth: width * step, lineCap: .round))
        }

        // Тело кольца и белая сердцевина внутри него.
        context.stroke(path, with: .color(neon.opacity(0.92)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        context.stroke(path, with: .color(.white.opacity(0.55 + 0.25 * flash)),
                       style: StrokeStyle(lineWidth: width * 0.34, lineCap: .round))
        context.blendMode = .normal
    }

    // MARK: - Словесный знак

    private func drawWordmark(_ context: inout GraphicsContext, _ layout: Layout) {
        let x = layout.size.width * 0.215
        let y = layout.size.height * 0.50

        var title = context.resolve(
            Text(Brand.name.uppercased())
                .font(.system(size: layout.base * 0.105, weight: .heavy, design: .rounded))
                .kerning(layout.base * 0.006))
        title.shading = .color(.white.opacity(0.95))
        let titleSize = title.measure(in: layout.size)
        context.draw(title, at: CGPoint(x: x, y: y - titleSize.height * 0.18), anchor: .center)

        // Подпись под чертой — как в блоке знака у референсов.
        let ruleWidth = titleSize.width * 1.02
        var rule = Path()
        rule.addRect(CGRect(x: x - ruleWidth / 2, y: y + titleSize.height * 0.36,
                            width: ruleWidth, height: max(1, layout.base * 0.0035)))
        context.fill(rule, with: .color(.white.opacity(0.9)))

        var caption = context.resolve(
            Text(Brand.tagline.uppercased())
                .font(.system(size: layout.base * 0.024, weight: .semibold))
                .kerning(layout.base * 0.0085))
        caption.shading = .color(.white.opacity(0.85))
        context.draw(caption, at: CGPoint(x: x, y: y + titleSize.height * 0.62), anchor: .center)
    }
}
