import SwiftUI

/// Гамма сцены. Одна тональность на всю картинку: глубина читается яркостью
/// и затуханием, а разноцветье её только разрушает.
public enum Palette: String, CaseIterable, Identifiable, Sendable {
    case amber, ice, violet, mono

    public var id: String { rawValue }

    /// Тон в тени и тон в разогретой части.
    public var hues: (deep: Double, hot: Double) {
        switch self {
        case .amber:  return (0.035, 0.115)
        case .ice:    return (0.600, 0.500)
        case .violet: return (0.755, 0.885)
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

/// Объёмная сцена: светящаяся лента, свёрнутая спиралью в пространстве.
///
/// Смысл картинки прямой: в центре — сама светодиодная лента, ради которой всё
/// и затевалось. Её пиксели загораются от полос спектра, вдоль ленты бежит волна,
/// а наружу улетают искры — уходящие в сеть пакеты. Позади висит дымка и медленные
/// кольца, дающие сцене воздух и масштаб.
///
/// Данные берутся замыканием на каждом кадре, а не из наблюдаемого поля: поле
/// обновляется десять раз в секунду, и картинка от него шла ступеньками — именно
/// это читалось как дешёвая дёрганая анимация. Сглаживание живёт в `SpectrumSmoother`
/// и считается от настоящего времени, а не от номера кадра.
public struct VolumetricVisualizer: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette
    private let packetsPerSecond: Int

    @State private var smoother = SpectrumSmoother()
    @State private var motes = MoteField()

    public init(sampler: @escaping Sampler,
                isRunning: Bool,
                palette: Palette = .amber,
                packetsPerSecond: Int = 0)
    {
        self.sampler = sampler
        self.isRunning = isRunning
        self.palette = palette
        self.packetsPerSecond = packetsPerSecond
    }

    /// Пикселей на ленте — как в распространённой ленте 144 диода на метр.
    private static let pixelCount = 144
    private static let turns = 2.6

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                motes.step(time: time, energy: smoother.energy,
                           rate: Double(packetsPerSecond), running: isRunning)

                drawHaze(&context, size: size, time: time)
                drawContextRings(&context, size: size, time: time)
                drawStrip(&context, size: size, time: time)
                drawMotes(&context, size: size)
                drawVignette(&context, size: size)
            }
        }
        .background(
            LinearGradient(colors: [Color(red: 0.032, green: 0.026, blue: 0.040),
                                    Color(red: 0.011, green: 0.009, blue: 0.016)],
                           startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Камера

    private struct Camera {
        let centre: CGPoint
        let base: Double
        let focal: Double
        let distance: Double
        let cosSpin: Double, sinSpin: Double
        let cosTilt: Double, sinTilt: Double

        init(size: CGSize, time: TimeInterval) {
            centre = CGPoint(x: size.width / 2, y: size.height * 0.5)
            base = min(size.width, size.height)
            focal = base * 1.45
            distance = base * 1.55
            // Полный оборот примерно за сорок секунд: движение заметно, но не мельтешит.
            let spin = time * 0.155
            let tilt = 0.92 + sin(time * 0.07) * 0.07
            cosSpin = cos(spin); sinSpin = sin(spin)
            cosTilt = cos(tilt); sinTilt = sin(tilt)
        }

        func project(_ x: Double, _ y: Double, _ z: Double)
            -> (point: CGPoint, scale: Double, depth: Double)
        {
            // Сначала вращение вокруг вертикали, потом наклон камеры. В обратном
            // порядке ось всей формы сама вращается и картинка заваливается.
            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            let ty = y * cosTilt - rz * sinTilt
            let tz = y * sinTilt + rz * cosTilt

            let scale = focal / max(tz + distance, 1)
            return (CGPoint(x: centre.x + rx * scale, y: centre.y + ty * scale), scale, tz)
        }
    }

    // MARK: - Дымка

    private func drawHaze(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let base = min(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let hues = palette.hues
        let energy = smoother.energy
        context.blendMode = .plusLighter

        let clouds: [(scale: Double, alpha: Double, hue: Double, drift: Double, phase: Double)] = [
            (1.30, 0.26, hues.deep, 0.031, 0.0),
            (0.85, 0.22, hues.deep, 0.047, 2.1),
            (0.52, 0.26, hues.hot,  0.062, 4.0),
            (0.30, 0.30, hues.hot,  0.083, 5.4),
        ]

        for cloud in clouds {
            let radius = base * cloud.scale * (0.40 + 0.16 * energy)
            let spot = CGPoint(
                x: centre.x + cos(time * cloud.drift + cloud.phase) * base * 0.07,
                y: centre.y + sin(time * cloud.drift * 1.3 + cloud.phase) * base * 0.05)

            let colour = Color(hue: cloud.hue,
                               saturation: palette.saturation * (0.92 - 0.35 * energy),
                               brightness: 1)
            let alpha = cloud.alpha * (0.28 + 0.72 * energy)

            context.fill(
                Path(ellipseIn: CGRect(x: spot.x - radius, y: spot.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: colour.opacity(alpha), location: 0.0),
                        .init(color: colour.opacity(alpha * 0.38), location: 0.30),
                        .init(color: colour.opacity(alpha * 0.09), location: 0.62),
                        .init(color: colour.opacity(0), location: 1.0),
                    ]),
                    center: spot, startRadius: 0, endRadius: radius))
        }
        context.blendMode = .normal
    }

    // MARK: - Кольца позади

    private func drawContextRings(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let camera = Camera(size: size, time: time)
        let hues = palette.hues
        let energy = smoother.energy
        context.blendMode = .plusLighter

        for ring in 0..<4 {
            let position = Double(ring) / 3.0
            let radius = camera.base * (0.44 + 0.20 * position)
            let y = camera.base * (position - 0.5) * 0.46
            let value = smoother.values[min(smoother.values.count - 1, ring * 5)]

            var path = Path()
            for step in 0...72 {
                let theta = Double(step) / 72 * 2 * .pi
                let r = radius * (1 + 0.05 * sin(theta * 3 + time * 0.5 + position * 4))
                let projected = camera.project(cos(theta) * r, y, sin(theta) * r)
                if step == 0 { path.move(to: projected.point) } else { path.addLine(to: projected.point) }
            }

            let colour = Color(hue: hues.deep, saturation: palette.saturation * 0.9, brightness: 1)
            context.stroke(path,
                           with: .color(colour.opacity((0.05 + 0.11 * value) * (0.35 + 0.65 * energy))),
                           style: StrokeStyle(lineWidth: camera.base * 0.004, lineCap: .round))
        }
        context.blendMode = .normal
    }

    // MARK: - Лента

    private func drawStrip(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let camera = Camera(size: size, time: time)
        let hues = palette.hues
        let energy = smoother.energy

        struct Pixel {
            var point: CGPoint
            var nearness: Double
            var depth: Double
            var intensity: Double
            var hue: Double
        }

        var pixels: [Pixel] = []
        pixels.reserveCapacity(Self.pixelCount)

        let radius = camera.base * 0.30
        let height = camera.base * 0.34
        let referenceScale = camera.focal / camera.distance

        for index in 0..<Self.pixelCount {
            let t = Double(index) / Double(Self.pixelCount - 1)
            let angle = t * Self.turns * 2 * .pi
            let y = (t - 0.5) * height

            // Полоса для этого пикселя. Сдвиг фазы со временем даёт бегущую вдоль
            // ленты волну — ровно так свет идёт по настоящей ленте.
            let bandPosition = (t * 16 + time * 1.1).truncatingRemainder(dividingBy: 16)
            let lower = Int(bandPosition) % 16
            let upper = (lower + 1) % 16
            let blend = bandPosition - Double(lower)
            let value = smoother.values[lower] * (1 - blend) + smoother.values[upper] * blend

            let r = radius * (0.88 + 0.26 * value)
            let projected = camera.project(cos(angle) * r, y, sin(angle) * r)

            pixels.append(Pixel(point: projected.point,
                                nearness: projected.scale / referenceScale,
                                depth: projected.depth,
                                intensity: value,
                                hue: hues.deep + (hues.hot - hues.deep) * t))
        }

        // Нить, связывающая пиксели в единую ленту, — рисуется до них, по порядку следования.
        var thread = Path()
        for (index, pixel) in pixels.enumerated() {
            if index == 0 { thread.move(to: pixel.point) } else { thread.addLine(to: pixel.point) }
        }

        context.blendMode = .plusLighter
        context.stroke(thread,
                       with: .color(Color(hue: hues.hot,
                                          saturation: palette.saturation * 0.55,
                                          brightness: 1).opacity(0.10 + 0.20 * energy)),
                       style: StrokeStyle(lineWidth: camera.base * 0.012, lineCap: .round))

        // Дальние пиксели рисуются первыми.
        pixels.sort { $0.depth > $1.depth }

        for pixel in pixels {
            let dotSize = camera.base * 0.014 * pixel.nearness * (0.50 + 1.05 * pixel.intensity)
            let brightness = 0.12 + 0.88 * pixel.intensity
            let colour = Color(hue: pixel.hue,
                               saturation: palette.saturation * max(0, 0.95 - brightness * 0.7),
                               brightness: 1)

            let halo = dotSize * 3.8
            context.fill(
                Path(ellipseIn: CGRect(x: pixel.point.x - halo, y: pixel.point.y - halo,
                                       width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: colour.opacity(0.52 * brightness), location: 0.0),
                        .init(color: colour.opacity(0.18 * brightness), location: 0.4),
                        .init(color: colour.opacity(0), location: 1.0),
                    ]),
                    center: pixel.point, startRadius: 0, endRadius: halo))

            context.fill(
                Path(ellipseIn: CGRect(x: pixel.point.x - dotSize / 2, y: pixel.point.y - dotSize / 2,
                                       width: dotSize, height: dotSize)),
                with: .color(colour.opacity(0.55 + 0.45 * brightness)))
        }

        context.blendMode = .normal
    }

    // MARK: - Искры пакетов

    private func drawMotes(_ context: inout GraphicsContext, size: CGSize) {
        guard !motes.items.isEmpty else { return }
        let base = min(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let hues = palette.hues
        context.blendMode = .plusLighter

        for mote in motes.items {
            let distance = mote.progress * base * 0.86
            let point = CGPoint(x: centre.x + cos(mote.angle) * distance,
                                y: centre.y + sin(mote.angle) * distance * 0.42)
            // Искра гаснет к краю — как пакет, ушедший в сеть.
            let fade = (1 - mote.progress) * (1 - mote.progress)
            let dot = base * 0.0035 * (0.6 + 0.8 * fade)

            let colour = Color(hue: hues.hot, saturation: palette.saturation * 0.35, brightness: 1)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot,
                                       width: dot * 2, height: dot * 2)),
                with: .color(colour.opacity(0.55 * fade)))
        }
        context.blendMode = .normal
    }

    private func drawVignette(_ context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let radius = max(size.width, size.height) * 0.80
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.32),
                    .init(color: .black.opacity(0.34), location: 0.76),
                    .init(color: .black.opacity(0.76), location: 1.0),
                ]),
                center: centre, startRadius: 0, endRadius: radius))
    }
}

// MARK: - Искры

/// Частицы, изображающие уходящие в сеть пакеты. Появляются тем чаще,
/// чем выше настоящая частота отправки.
public final class MoteField {
    public struct Mote {
        public var angle: Double
        public var progress: Double
        public var speed: Double
    }

    public private(set) var items: [Mote] = []
    private var lastTime: TimeInterval = 0
    private var spawnAccumulator: Double = 0
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    private func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(UInt32(truncatingIfNeeded: seed >> 33)) / Double(UInt32.max)
    }

    public init() {}

    public func step(time: TimeInterval, energy: Double, rate: Double, running: Bool) {
        let delta = lastTime == 0 ? 1.0 / 60.0 : min(0.1, max(0.0001, time - lastTime))
        lastTime = time

        for index in items.indices {
            items[index].progress += items[index].speed * delta
        }
        items.removeAll { $0.progress >= 1 }

        guard running else { return }

        // Одна искра примерно на каждые четыре пакета — иначе их слишком много.
        let perSecond = max(2.0, min(24.0, rate / 4)) * (0.35 + 0.65 * energy)
        spawnAccumulator += perSecond * delta

        while spawnAccumulator >= 1, items.count < 90 {
            spawnAccumulator -= 1
            items.append(Mote(angle: random() * 2 * .pi,
                              progress: 0.12 + random() * 0.06,
                              speed: 0.22 + random() * 0.28))
        }
    }
}

// MARK: - Плоская полоса для строки меню

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
