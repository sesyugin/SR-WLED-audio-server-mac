import SwiftUI

/// Гамма визуализации. Одна тональность на всю сцену: глубина читается яркостью
/// и затуханием, а разноцветье её только разрушает.
public enum Palette: String, CaseIterable, Identifiable, Sendable {
    case amber, ice, violet, mono

    public var id: String { rawValue }

    /// Тон у основания (низ, бас) и тон в разогретой части (верх).
    public var hues: (deep: Double, hot: Double) {
        switch self {
        case .amber:  return (0.055, 0.115)
        case .ice:    return (0.585, 0.505)
        case .violet: return (0.760, 0.860)
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

/// Объёмная визуализация: шестнадцать светящихся колец в трёхмерном пространстве,
/// по одному на полосу спектра.
///
/// Объём здесь настоящий и берётся из двух вещей. Первая — честная перспектива:
/// кольца считаются в трёх координатах, вращаются, проецируются с делением на глубину,
/// поэтому дальняя сторона кольца уже и тусклее ближней, а при вращении виден параллакс.
/// Вторая — сложение света: нити рисуются в режиме `plusLighter` дважды, широким мягким
/// ореолом и узкой яркой сердцевиной, и в местах пересечения свет накапливается и белеет,
/// как настоящее свечение в дымке. Матовой закраски поверхностей здесь нет намеренно —
/// освещённое тело выглядит предметом, а нужен объём света.
public struct VolumetricVisualizer: View {
    public let bands: [Float]
    public let peaks: [Float]
    public let isRunning: Bool
    public var palette: Palette

    public init(bands: [Float], peaks: [Float], isRunning: Bool, palette: Palette = .amber) {
        self.bands = bands
        self.peaks = peaks
        self.isRunning = isRunning
        self.palette = palette
    }

    private static let ringCount = 16
    private static let pointsPerRing = 96

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let energy = overallEnergy

            Canvas(rendersAsynchronously: true) { context, size in
                drawGlow(&context, size: size, energy: energy, time: time)
                drawRings(&context, size: size, energy: energy, time: time)
                drawVignette(&context, size: size)
            }
        }
        .background(Color(red: 0.020, green: 0.017, blue: 0.026))
    }

    private var overallEnergy: Double {
        guard !bands.isEmpty else { return 0 }
        return min(1, Double(bands.reduce(0, +)) / Double(bands.count))
    }

    private func band(_ index: Int) -> Double {
        index < bands.count ? min(1, Double(bands[index])) : 0
    }

    // MARK: - Зарево в глубине

    /// Свет из-за объекта. Кольца полупрозрачны, поэтому зарево просвечивает сквозь них —
    /// именно так появляется ощущение дымки, в которой всё это висит.
    private func drawGlow(_ context: inout GraphicsContext, size: CGSize,
                          energy: Double, time: TimeInterval)
    {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.48)
        let base = min(size.width, size.height)
        let hues = palette.hues
        context.blendMode = .plusLighter

        let layers: [(scale: Double, alpha: Double, hue: Double, drift: Double)] = [
            (1.15, 0.34, hues.deep, 0.05),
            (0.70, 0.30, hues.deep, 0.09),
            (0.36, 0.34, hues.hot,  0.13),
        ]

        for layer in layers {
            let breathe = 0.55 + 0.45 * energy
            let radius = base * layer.scale * (0.42 + 0.22 * breathe)
            let wobbleX = cos(time * layer.drift) * base * 0.03
            let wobbleY = sin(time * layer.drift * 1.4) * base * 0.02
            let spot = CGPoint(x: centre.x + wobbleX, y: centre.y + wobbleY)

            let colour = Color(hue: layer.hue,
                               saturation: palette.saturation * (0.9 - 0.4 * energy),
                               brightness: 1)
            let alpha = layer.alpha * (0.30 + 0.70 * energy)

            context.fill(
                Path(ellipseIn: CGRect(x: spot.x - radius, y: spot.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: colour.opacity(alpha), location: 0.0),
                        .init(color: colour.opacity(alpha * 0.40), location: 0.32),
                        .init(color: colour.opacity(alpha * 0.10), location: 0.64),
                        .init(color: colour.opacity(0), location: 1.0),
                    ]),
                    center: spot, startRadius: 0, endRadius: radius))
        }
        context.blendMode = .normal
    }

    // MARK: - Кольца

    private func drawRings(_ context: inout GraphicsContext, size: CGSize,
                           energy: Double, time: TimeInterval)
    {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.48)
        let base = min(size.width, size.height)
        let hues = palette.hues

        let spin = time * 0.20
        let tilt = 1.02 + sin(time * 0.11) * 0.05     // кольца видны эллипсами, не с ребра
        let focal = base * 1.35
        let cameraDistance = base * 1.5

        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)

        struct Ring {
            var path: Path
            var depth: Double
            var value: Double
            var index: Int
            var nearness: Double
        }

        var rings: [Ring] = []
        rings.reserveCapacity(Self.ringCount)

        for index in 0..<Self.ringCount {
            let value = band(index)
            let peak = index < peaks.count ? min(1, Double(peaks[index])) : value

            // Кольца расставлены по высоте: бас внизу, верх сверху.
            let position = Double(index) / Double(Self.ringCount - 1)
            let y = (position - 0.5) * base * 0.30

            // Радиус: широкое основание, сужение кверху, плюс дыхание своей полосы.
            let profile = 0.46 + 0.54 * sin(position * .pi)
            let radius = base * 0.32 * profile * (0.62 + 0.52 * value)

            var path = Path()
            var depthSum = 0.0
            var nearest = -Double.infinity

            for step in 0...Self.pointsPerRing {
                let theta = Double(step) / Double(Self.pointsPerRing) * 2 * .pi

                // Рябь по окружности — кольцо не идеальный круг, иначе картинка мертвеет.
                let ripple = 1 + 0.045 * sin(theta * 3 + time * 1.7 + position * 6)
                               + 0.022 * sin(theta * 7 - time * 1.1)
                let r = radius * ripple * (1 + 0.07 * peak * sin(theta * 2 - time * 2.3))

                var x = cos(theta) * r
                var z = sin(theta) * r
                var yy = y

                // Порядок важен: сперва вращение вокруг вертикали, и только потом наклон
                // камеры. Если наклонить раньше, ось стопки колец сама начинает вращаться,
                // и вся форма заваливается по диагонали.
                let rx = x * cosSpin + z * sinSpin
                let rz = -x * sinSpin + z * cosSpin
                x = rx; z = rz

                let ty = yy * cosTilt - z * sinTilt
                let tz = yy * sinTilt + z * cosTilt
                yy = ty; z = tz

                depthSum += z
                nearest = max(nearest, -z)

                let scale = focal / max(z + cameraDistance, 1)
                let point = CGPoint(x: centre.x + x * scale, y: centre.y + yy * scale)

                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }

            rings.append(Ring(path: path,
                              depth: depthSum / Double(Self.pointsPerRing + 1),
                              value: value,
                              index: index,
                              nearness: nearest / base))
        }

        // Дальние кольца рисуются первыми, ближние ложатся поверх.
        rings.sort { $0.depth > $1.depth }

        context.blendMode = .plusLighter

        for ring in rings {
            let position = Double(ring.index) / Double(Self.ringCount - 1)
            let hue = hues.deep + (hues.hot - hues.deep) * position

            // Ближние кольца ярче и толще — это и есть считываемая глазом глубина.
            let depthFade = 0.45 + 0.55 * max(0, min(1, (ring.nearness + 0.35) / 0.7))
            let intensity = (0.10 + 0.90 * ring.value) * depthFade

            let colour = Color(hue: hue,
                               saturation: palette.saturation * max(0, 0.95 - intensity * 0.75),
                               brightness: 1)

            // Мягкий ореол: широкая полупрозрачная линия.
            context.stroke(ring.path,
                           with: .color(colour.opacity(0.10 + 0.22 * intensity)),
                           style: StrokeStyle(lineWidth: base * (0.010 + 0.022 * intensity),
                                              lineCap: .round, lineJoin: .round))

            // Сердцевина: тонкая яркая нить.
            context.stroke(ring.path,
                           with: .color(colour.opacity(0.35 + 0.60 * intensity)),
                           style: StrokeStyle(lineWidth: base * (0.0013 + 0.0030 * intensity),
                                              lineCap: .round, lineJoin: .round))
        }

        context.blendMode = .normal
    }

    private func drawVignette(_ context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.48)
        let radius = max(size.width, size.height) * 0.78
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.30),
                    .init(color: .black.opacity(0.40), location: 0.78),
                    .init(color: .black.opacity(0.80), location: 1.0),
                ]),
                center: centre, startRadius: 0, endRadius: radius))
    }
}

// MARK: - Плоская полоса для строки меню и компактных мест

public struct SpectrumStrip: View {
    public let bands: [Float]
    public var barCount: Int

    public init(bands: [Float], barCount: Int = 16) {
        self.bands = bands
        self.barCount = barCount
    }

    public var body: some View {
        Canvas { context, size in
            guard barCount > 0 else { return }
            let gap: CGFloat = 1
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            guard barWidth > 0 else { return }

            for index in 0..<barCount {
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = max(1, value * size.height)
                let rect = CGRect(x: CGFloat(index) * (barWidth + gap),
                                  y: size.height - height,
                                  width: barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 3),
                             with: .color(.primary))
            }
        }
    }
}
