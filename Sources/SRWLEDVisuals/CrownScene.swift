import SwiftUI

/// Венец из колонн спектра, стоящих по кругу на наклонённой плоскости.
///
/// Объём здесь настоящий: круг колонн лежит в трёхмерном пространстве, наклонён
/// к зрителю и проецируется с делением на глубину. Отсюда всё сразу — ближние
/// колонны крупнее и ярче, дальние мельче и тонут; при вращении видно, как они
/// обходят друг друга. Каждая колонна рисуется не линией, а гранью с более светлой
/// вершиной, поэтому читается как тело, а не как штрих.
///
/// Композиция строго по центру своего блока: сцена ничего не знает про окно
/// и всегда стоит посередине того места, которое ей отдали.
public struct CrownScene: View {
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

    /// Колонн в венце. Много и тонких — так спектр читается подробно и аккуратно.
    private static let columns = 128

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                beat.step(time: time, bass: smoother.values.prefix(3).max() ?? 0)
                drawBackdrop(&context, size: size, time: time)
                draw(&context, size: size, time: time)
                drawVignette(&context, size: size)
            }
        }
        .background(
            LinearGradient(colors: [Color(red: 0.036, green: 0.032, blue: 0.062),
                                    Color(red: 0.016, green: 0.014, blue: 0.028)],
                           startPoint: .top, endPoint: .bottom))
    }

    /// Значение спектра по углу: зеркальная симметрия, чтобы венец читался
    /// как единая форма, а не как случайный частокол.
    private func spectrum(at position: Double) -> Double {
        let folded = position < 0.5 ? position * 2 : (1 - position) * 2
        let scaled = folded * 15
        let lower = min(15, Int(scaled))
        let upper = min(15, lower + 1)
        let blend = scaled - Double(lower)
        guard smoother.values.count == 16 else { return 0 }
        return smoother.values[lower] * (1 - blend) + smoother.values[upper] * blend
    }

    // MARK: - Фон
    //
    // Глубина фона берётся из планов, идущих с разной скоростью: дальняя дымка
    // почти стоит, средние контуры плывут еле заметно, ближние заметнее. Один
    // градиент, каким фон был раньше, глубины дать не может в принципе — глазу
    // не за что зацепиться.

    private func drawBackdrop(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let base = min(size.width, size.height)
        let hues = palette.hues
        let energy = smoother.energy
        let horizon = size.height * 0.72

        // План 1: дальняя дымка у горизонта, широкая и мягкая.
        context.blendMode = .plusLighter
        for layer in 0..<3 {
            let spread = base * (0.85 + Double(layer) * 0.55)
            let centre = CGPoint(x: size.width * (0.5 + 0.04 * sin(time * 0.02 + Double(layer))),
                                 y: horizon)
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - spread, y: centre.y - spread * 0.45,
                                       width: spread * 2, height: spread * 0.9)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hue: layer == 0 ? hues.hot : hues.deep,
                                           saturation: palette.saturation * 0.75,
                                           brightness: 1)
                            .opacity((0.055 - Double(layer) * 0.012) * (0.5 + 0.5 * energy)),
                              location: 0),
                        .init(color: .clear, location: 1),
                    ]),
                    center: centre, startRadius: 0, endRadius: spread))
        }

        // План 2: звёздная пыль. Дальние точки почти стоят, ближние сдвигаются —
        // этот параллакс и создаёт ощущение расстояния.
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(UInt32(truncatingIfNeeded: seed >> 33)) / Double(UInt32.max)
        }
        for _ in 0..<150 {
            let rx = random(), ry = random(), depth = 0.2 + 0.8 * random()
            let drift = (time * 0.004 * depth).truncatingRemainder(dividingBy: 1)
            let x = ((rx + drift).truncatingRemainder(dividingBy: 1)) * Double(size.width)
            let y = ry * Double(horizon)
            let dot = base * 0.0011 * depth
            context.fill(
                Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                with: .color(.white.opacity(0.06 + 0.30 * depth * depth)))
        }
        context.blendMode = .normal

        // Планы 3 и 4: топографические контуры на двух разных глубинах.
        // Дальний набор тоньше, бледнее и плывёт медленнее ближнего.
        let sets: [(origin: CGPoint, count: Int, scale: Double, alpha: Double,
                    width: Double, speed: Double)] = [
            (CGPoint(x: size.width * 0.16, y: size.height * 0.34), 8, 0.085, 0.030, 0.0011, 0.05),
            (CGPoint(x: size.width * 0.84, y: size.height * 0.66), 6, 0.105, 0.045, 0.0017, 0.09),
        ]

        for set in sets {
            for ring in 0..<set.count {
                let radius = base * (set.scale + Double(ring) * set.scale * 1.15)
                var path = Path()
                for step in 0...84 {
                    let theta = Double(step) / 84 * 2 * .pi
                    let wobble = 1
                        + 0.17 * sin(theta * 2 + time * set.speed + Double(ring) * 0.8)
                        + 0.10 * sin(theta * 3 - time * set.speed * 0.7 + Double(ring) * 1.5)
                    let r = radius * wobble
                    let point = CGPoint(x: set.origin.x + cos(theta) * r,
                                        y: set.origin.y + sin(theta) * r * 0.84)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                let fade = 1 - Double(ring) / Double(set.count)
                context.stroke(path,
                               with: .color(.white.opacity(set.alpha * (0.45 + 0.55 * fade))),
                               style: StrokeStyle(lineWidth: base * set.width))
            }
        }

        // План 5: линия горизонта — она отделяет «даль» от «пола» и без неё
        // все предыдущие планы сливаются.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: horizon))
        line.addLine(to: CGPoint(x: size.width, y: horizon))
        context.stroke(line,
                       with: .linearGradient(
                           Gradient(colors: [.clear,
                                             Color(hue: hues.hot,
                                                   saturation: palette.saturation * 0.45,
                                                   brightness: 1).opacity(0.18 + 0.14 * energy),
                                             .clear]),
                           startPoint: CGPoint(x: 0, y: horizon),
                           endPoint: CGPoint(x: size.width, y: horizon)),
                       style: StrokeStyle(lineWidth: base * 0.0013))
    }

    /// Затемнение по краям прижимает внимание к центру и добавляет глубины.
    private func drawVignette(_ context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.34),
                    .init(color: .black.opacity(0.30), location: 0.78),
                    .init(color: .black.opacity(0.70), location: 1.0),
                ]),
                center: centre, startRadius: 0,
                endRadius: max(size.width, size.height) * 0.78))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Центр — строго середина отданного блока.
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        let energy = smoother.energy
        let flash = beat.intensity
        let hues = palette.hues

        let radius = base * 0.325
        let maxHeight = base * 0.30
        let spin = time * 0.10
        let tilt = 0.92
        let focal = base * 2.0
        let distance = base * 2.1

        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)
        let referenceScale = focal / distance

        /// Проекция точки: экранные координаты, масштаб и глубина.
        func project(_ x: Double, _ y: Double, _ z: Double) -> (CGPoint, Double, Double) {
            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            let ty = y * cosTilt - rz * sinTilt
            let tz = y * sinTilt + rz * cosTilt
            let scale = focal / max(tz + distance, 1)
            return (CGPoint(x: centre.x + rx * scale, y: centre.y + ty * scale), scale, tz)
        }

        // Свечение под венцом — только чтобы он не висел в пустоте.
        let glowRadius = radius * (1.5 + 0.25 * energy)
        context.blendMode = .plusLighter
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glowRadius, y: centre.y - glowRadius * 0.5,
                                   width: glowRadius * 2, height: glowRadius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.8,
                                       brightness: 1).opacity(0.07 + 0.12 * energy + 0.05 * flash),
                          location: 0),
                    .init(color: .clear, location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: glowRadius))
        context.blendMode = .normal

        struct Column {
            var face: Path
            var cap: Path
            var reflection: Path
            var depth: Double
            var nearness: Double
            var value: Double
        }

        var columns: [Column] = []
        columns.reserveCapacity(Self.columns)

        // Ширина колонны в мире: чуть меньше шага между ними, чтобы остался просвет.
        let step = 2 * Double.pi / Double(Self.columns)
        let halfWidth = radius * step * 0.34

        for index in 0..<Self.columns {
            let position = Double(index) / Double(Self.columns)
            let theta = position * 2 * .pi
            let value = spectrum(at: position)
            let height = maxHeight * (0.035 + 0.965 * value)

            // Точки основания: колонна имеет ширину, поэтому берём два края.
            let tangentX = -sin(theta), tangentZ = cos(theta)
            let cx = cos(theta) * radius, cz = sin(theta) * radius

            let leftX = cx - tangentX * halfWidth, leftZ = cz - tangentZ * halfWidth
            let rightX = cx + tangentX * halfWidth, rightZ = cz + tangentZ * halfWidth

            let baseLeft = project(leftX, 0, leftZ)
            let baseRight = project(rightX, 0, rightZ)
            let topLeft = project(leftX, -height, leftZ)
            let topRight = project(rightX, -height, rightZ)

            // Передняя грань колонны.
            var face = Path()
            face.move(to: baseLeft.0)
            face.addLine(to: baseRight.0)
            face.addLine(to: topRight.0)
            face.addLine(to: topLeft.0)
            face.closeSubpath()

            // Светлая вершина — она и делает колонну телом, а не штрихом.
            let capDepth = halfWidth * 0.9
            let capBackLeft = project(leftX - cos(theta) * capDepth, -height, leftZ - sin(theta) * capDepth)
            let capBackRight = project(rightX - cos(theta) * capDepth, -height, rightZ - sin(theta) * capDepth)
            var cap = Path()
            cap.move(to: topLeft.0)
            cap.addLine(to: topRight.0)
            cap.addLine(to: capBackRight.0)
            cap.addLine(to: capBackLeft.0)
            cap.closeSubpath()

            // Отражение под плоскостью — даёт сцене пол и глубину.
            let reflectionHeight = height * 0.42
            let mirrorLeft = project(leftX, reflectionHeight, leftZ)
            let mirrorRight = project(rightX, reflectionHeight, rightZ)
            var reflection = Path()
            reflection.move(to: baseLeft.0)
            reflection.addLine(to: baseRight.0)
            reflection.addLine(to: mirrorRight.0)
            reflection.addLine(to: mirrorLeft.0)
            reflection.closeSubpath()

            columns.append(Column(face: face, cap: cap, reflection: reflection,
                                  depth: (baseLeft.2 + baseRight.2) / 2,
                                  nearness: baseLeft.1 / referenceScale,
                                  value: value))
        }

        // Дальние колонны рисуются первыми — они и должны уходить за ближние.
        columns.sort { $0.depth > $1.depth }

        for column in columns {
            // Глубина читается яркостью: дальние тонут, ближние выходят вперёд.
            let depthFade = max(0, min(1, (column.nearness - 0.72) / 0.55))
            let intensity = (0.16 + 0.84 * column.value) * (0.32 + 0.68 * depthFade)

            let hue = hues.deep + (hues.hot - hues.deep) * column.value
            let tint = Color(hue: hue,
                             saturation: palette.saturation * (0.90 - 0.40 * column.value),
                             brightness: 1)

            context.fill(column.reflection,
                         with: .linearGradient(
                             Gradient(colors: [tint.opacity(0.16 * intensity), .clear]),
                             startPoint: CGPoint(x: 0, y: centre.y),
                             endPoint: CGPoint(x: 0, y: centre.y + maxHeight * 0.5)))

            context.fill(column.face, with: .color(tint.opacity(0.30 + 0.55 * intensity)))
            context.fill(column.cap, with: .color(tint.opacity(0.55 + 0.45 * intensity)))
        }
    }
}
