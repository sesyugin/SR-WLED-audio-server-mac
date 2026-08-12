import SwiftUI

/// Сцена в духе больших концертных экранов.
///
/// Плоскость прошлой версии бралась из того, что вся картинка жила в одном слое
/// на одной глубине. Здесь пространство построено по-настоящему: есть уходящий
/// к горизонту пол, сквозь который летит туннель колец, есть герой в центре
/// и есть звёздное поле с параллаксом. Всё это движется на зрителя со скоростью,
/// привязанной к громкости, а на ударах сцену заливает вспышка.
///
/// Приёмы взяты из сценического визуала электронной музыки: перспективная сетка,
/// туннель, послесвечение, засветка по биту, развёртка строк. Каждый из них
/// решает свою задачу — сетка даёт масштаб, туннель скорость, вспышка ритм.
public struct StageScene: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette
    private let packetsPerSecond: Int

    @State private var smoother = SpectrumSmoother()
    @State private var motes = MoteField()
    @State private var beat = BeatFlash()
    @State private var travel = TravelClock()

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

    private static let pixelCount = 132
    private static let turns = 2.4

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                travel.step(time: time, energy: smoother.energy)
                beat.step(time: time, bass: smoother.values.prefix(3).max() ?? 0)
                motes.step(time: time, energy: smoother.energy,
                           rate: Double(packetsPerSecond), running: isRunning)

                let scene = Scene(size: size, time: time,
                                  palette: palette,
                                  energy: smoother.energy,
                                  bands: smoother.values,
                                  travel: travel.distance,
                                  flash: beat.intensity)

                scene.drawSky(&context)
                scene.drawStars(&context)
                scene.drawFloor(&context)
                scene.drawTunnel(&context)
                scene.drawHelix(&context, pixels: Self.pixelCount, turns: Self.turns)
                scene.drawMotes(&context, motes: motes.items)
                scene.drawFlash(&context)
                scene.drawScanlines(&context)
                scene.drawVignette(&context)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Сцена

private struct Scene {
    let size: CGSize
    let time: TimeInterval
    let palette: Palette
    let energy: Double
    let bands: [Double]
    let travel: Double
    let flash: Double

    /// Горизонт стоит выше середины: под ним пол, над ним небо и туннель.
    var horizon: CGFloat { size.height * 0.46 }
    var centreX: CGFloat { size.width / 2 }
    var base: Double { min(size.width, size.height) }

    private var hues: (deep: Double, hot: Double) { palette.hues }

    private func colour(_ hue: Double, _ saturation: Double = 1) -> Color {
        Color(hue: hue, saturation: palette.saturation * saturation, brightness: 1)
    }

    private func band(_ index: Int) -> Double {
        index >= 0 && index < bands.count ? bands[index] : 0
    }

    // MARK: Небо

    func drawSky(_ context: inout GraphicsContext) {
        // Свечение у горизонта — источник света всей сцены.
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: colour(hues.deep, 0.9).opacity(0.08 + 0.18 * energy), location: 0.70),
                    .init(color: colour(hues.hot, 0.7).opacity(0.22 + 0.34 * energy), location: 1.0),
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: horizon)))

        // Тугое ядро света ровно на линии горизонта.
        context.blendMode = .plusLighter
        let coreWidth = size.width * (0.35 + 0.30 * energy)
        let coreHeight = base * (0.04 + 0.07 * energy)
        context.fill(
            Path(ellipseIn: CGRect(x: centreX - coreWidth / 2, y: horizon - coreHeight / 2,
                                   width: coreWidth, height: coreHeight)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.22 + 0.30 * energy), location: 0.0),
                    .init(color: colour(hues.hot, 0.8).opacity(0.30 * energy), location: 0.35),
                    .init(color: .clear, location: 1.0),
                ]),
                center: CGPoint(x: centreX, y: horizon),
                startRadius: 0, endRadius: coreWidth / 2))
        context.blendMode = .normal
    }

    // MARK: Звёздное поле

    /// Точки с параллаксом: дальние почти неподвижны, ближние заметно плывут.
    /// Это дешёвый и очень действенный способ показать, что пространство глубокое.
    func drawStars(_ context: inout GraphicsContext) {
        context.blendMode = .plusLighter
        var seed: UInt64 = 0xA24BAED4963EE407

        for _ in 0..<90 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let rx = Double(UInt32(truncatingIfNeeded: seed >> 33)) / Double(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let ry = Double(UInt32(truncatingIfNeeded: seed >> 33)) / Double(UInt32.max)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let depth = 0.25 + 0.75 * Double(UInt32(truncatingIfNeeded: seed >> 33)) / Double(UInt32.max)

            let drift = (travel * depth * 0.04).truncatingRemainder(dividingBy: 1)
            let x = ((rx + drift).truncatingRemainder(dividingBy: 1)) * Double(size.width)
            let y = ry * Double(horizon) * 0.92

            let dot = base * 0.0016 * depth
            let alpha = (0.10 + 0.45 * depth) * (0.4 + 0.6 * energy)
            context.fill(
                Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                with: .color(.white.opacity(alpha)))
        }
        context.blendMode = .normal
    }

    // MARK: Пол

    /// Перспективная сетка, уходящая к горизонту. Линии бегут на зрителя,
    /// и скорость привязана к громкости — отсюда ощущение движения сквозь пространство.
    func drawFloor(_ context: inout GraphicsContext) {
        context.blendMode = .plusLighter
        let depthOfField = size.height - horizon

        // Поперечные линии: сгущаются к горизонту по закону перспективы.
        let rows = 26
        for row in 0..<rows {
            // Смещение делает сетку бегущей.
            let raw = (Double(row) + travel.truncatingRemainder(dividingBy: 1)) / Double(rows)
            guard raw > 0.001 else { continue }
            // Обратная величина даёт перспективное сгущение.
            let t = 1 - 1 / (1 + raw * 7)
            let y = horizon + CGFloat(t) * depthOfField
            guard y < size.height + 2 else { continue }

            let nearness = t
            let alpha = (0.03 + 0.30 * nearness) * (0.35 + 0.65 * energy)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line,
                           with: .color(colour(hues.hot, 0.55).opacity(alpha)),
                           style: StrokeStyle(lineWidth: 0.6 + 1.8 * nearness))
        }

        // Продольные линии сходятся в точку схода. Их яркость берётся у полос спектра —
        // сетка тоже реагирует на музыку, а не просто лежит фоном.
        let columns = 17
        for column in 0...columns {
            let offset = Double(column) / Double(columns) - 0.5
            let x = centreX + CGFloat(offset) * size.width * 2.4
            let value = band(Int(abs(offset) * 30) % 16)

            var line = Path()
            line.move(to: CGPoint(x: centreX + CGFloat(offset) * size.width * 0.06, y: horizon))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line,
                           with: .linearGradient(
                               Gradient(stops: [
                                   .init(color: colour(hues.hot, 0.6).opacity(0), location: 0.0),
                                   .init(color: colour(hues.hot, 0.6)
                                       .opacity((0.10 + 0.35 * value) * (0.3 + 0.7 * energy)),
                                       location: 1.0),
                               ]),
                               startPoint: CGPoint(x: centreX, y: horizon),
                               endPoint: CGPoint(x: x, y: size.height)),
                           style: StrokeStyle(lineWidth: 1.1))
        }
        context.blendMode = .normal
    }

    // MARK: Туннель

    /// Кольца, летящие из глубины на зрителя. Каждое берёт размер у своей полосы,
    /// поэтому туннель «дышит» вместе с музыкой.
    func drawTunnel(_ context: inout GraphicsContext) {
        context.blendMode = .plusLighter
        let ringCount = 14

        for ring in 0..<ringCount {
            // Каждое кольцо непрерывно приближается; дойдя до зрителя, уходит в конец.
            let progress = ((Double(ring) / Double(ringCount)) + travel * 0.08)
                .truncatingRemainder(dividingBy: 1)
            // Перспектива: у горизонта кольцо крошечное, у зрителя огромное.
            let scale = 0.02 + progress * progress * 2.4
            let value = band(ring % 16)

            let radiusX = base * scale * (0.55 + 0.35 * value)
            let radiusY = radiusX * 0.42

            // Кольца уходят чуть выше горизонта — туда, где ядро света.
            let y = horizon - CGFloat(base * 0.02 * (1 - progress))

            let alpha = (1 - progress) * (0.14 + 0.40 * value) * (0.3 + 0.7 * energy)
            guard alpha > 0.004 else { continue }

            let rect = CGRect(x: centreX - radiusX, y: y - radiusY,
                              width: radiusX * 2, height: radiusY * 2)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(colour(hues.deep + (hues.hot - hues.deep) * progress, 0.8)
                               .opacity(alpha)),
                           style: StrokeStyle(lineWidth: 0.8 + 3.2 * progress))
        }
        context.blendMode = .normal
    }

    // MARK: Герой — светодиодная лента

    /// Сама лента, свёрнутая спиралью: 132 пикселя, каждый от своей полосы,
    /// вдоль ленты бежит волна. Это то, ради чего программа существует.
    func drawHelix(_ context: inout GraphicsContext, pixels: Int, turns: Double) {
        let centre = CGPoint(x: centreX, y: horizon + CGFloat(base * 0.045))
        let radius = base * 0.235
        let height = base * 0.24

        let spin = time * 0.30
        let tilt = 1.06
        let focal = base * 1.5
        let distance = base * 1.6
        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)
        let referenceScale = focal / distance

        struct Dot {
            var point: CGPoint
            var nearness: Double
            var depth: Double
            var value: Double
            var hue: Double
        }

        var dots: [Dot] = []
        dots.reserveCapacity(pixels)

        for index in 0..<pixels {
            let t = Double(index) / Double(pixels - 1)
            let angle = t * turns * 2 * .pi
            let y = (t - 0.5) * height

            let position = (t * 16 + time * 1.35).truncatingRemainder(dividingBy: 16)
            let lower = Int(position) % 16
            let upper = (lower + 1) % 16
            let blend = position - Double(lower)
            let value = band(lower) * (1 - blend) + band(upper) * blend

            let r = radius * (0.86 + 0.30 * value)
            var x = cos(angle) * r
            var z = sin(angle) * r

            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            x = rx; z = rz
            let ty = y * cosTilt - z * sinTilt
            let tz = y * sinTilt + z * cosTilt

            let scale = focal / max(tz + distance, 1)
            dots.append(Dot(point: CGPoint(x: centre.x + x * scale, y: centre.y + ty * scale),
                            nearness: scale / referenceScale,
                            depth: tz,
                            value: value,
                            hue: hues.deep + (hues.hot - hues.deep) * t))
        }

        context.blendMode = .plusLighter

        // Нить, связывающая пиксели в ленту.
        var thread = Path()
        for (index, dot) in dots.enumerated() {
            if index == 0 { thread.move(to: dot.point) } else { thread.addLine(to: dot.point) }
        }
        context.stroke(thread,
                       with: .color(colour(hues.hot, 0.5).opacity(0.10 + 0.22 * energy)),
                       style: StrokeStyle(lineWidth: base * 0.011, lineCap: .round))

        dots.sort { $0.depth > $1.depth }

        for dot in dots {
            let dotSize = base * 0.0125 * dot.nearness * (0.5 + 1.0 * dot.value)
            let brightness = 0.14 + 0.86 * dot.value
            let tint = colour(dot.hue, max(0, 0.95 - brightness * 0.7))

            let halo = dotSize * 4.0
            context.fill(
                Path(ellipseIn: CGRect(x: dot.point.x - halo, y: dot.point.y - halo,
                                       width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.50 * brightness), location: 0.0),
                        .init(color: tint.opacity(0.16 * brightness), location: 0.4),
                        .init(color: tint.opacity(0), location: 1.0),
                    ]),
                    center: dot.point, startRadius: 0, endRadius: halo))

            context.fill(
                Path(ellipseIn: CGRect(x: dot.point.x - dotSize / 2, y: dot.point.y - dotSize / 2,
                                       width: dotSize, height: dotSize)),
                with: .color(tint.opacity(0.55 + 0.45 * brightness)))
        }
        context.blendMode = .normal
    }

    // MARK: Искры пакетов

    func drawMotes(_ context: inout GraphicsContext, motes: [MoteField.Mote]) {
        guard !motes.isEmpty else { return }
        context.blendMode = .plusLighter
        let origin = CGPoint(x: centreX, y: horizon + CGFloat(base * 0.045))

        for mote in motes {
            let distance = mote.progress * base * 0.95
            let point = CGPoint(x: origin.x + cos(mote.angle) * distance,
                                y: origin.y + sin(mote.angle) * distance * 0.38)
            let fade = (1 - mote.progress) * (1 - mote.progress)
            let dot = base * 0.0032 * (0.6 + 0.9 * fade)

            // Короткий хвост — искра читается как летящая, а не висящая.
            var tail = Path()
            tail.move(to: point)
            tail.addLine(to: CGPoint(x: origin.x + cos(mote.angle) * (distance - base * 0.03),
                                     y: origin.y + sin(mote.angle) * (distance - base * 0.03) * 0.38))
            context.stroke(tail,
                           with: .color(colour(hues.hot, 0.4).opacity(0.22 * fade)),
                           style: StrokeStyle(lineWidth: dot, lineCap: .round))

            context.fill(
                Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot,
                                       width: dot * 2, height: dot * 2)),
                with: .color(.white.opacity(0.55 * fade)))
        }
        context.blendMode = .normal
    }

    // MARK: Вспышка по биту

    /// Засветка всей сцены на ударе. Именно она даёт картинке ритм —
    /// без неё визуал не «попадает» в музыку, как бы точно ни двигались полосы.
    func drawFlash(_ context: inout GraphicsContext) {
        guard flash > 0.004 else { return }
        context.blendMode = .plusLighter
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: colour(hues.hot, 0.35).opacity(0.30 * flash), location: 0.0),
                    .init(color: colour(hues.deep, 0.6).opacity(0.12 * flash), location: 0.55),
                    .init(color: .clear, location: 1.0),
                ]),
                center: CGPoint(x: centreX, y: horizon),
                startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
        context.blendMode = .normal
    }

    // MARK: Развёртка и виньетка

    /// Горизонтальные строки, как на светодиодном экране сцены. Очень тонкий приём:
    /// он не заметен глазом отдельно, но вся картинка начинает читаться как экран.
    func drawScanlines(_ context: inout GraphicsContext) {
        context.blendMode = .multiply
        let spacing: CGFloat = 4
        var y: CGFloat = 0
        var lines = Path()
        while y < size.height {
            lines.move(to: CGPoint(x: 0, y: y))
            lines.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(lines, with: .color(.black.opacity(0.05)), style: StrokeStyle(lineWidth: 1))
        context.blendMode = .normal
    }

    func drawVignette(_ context: inout GraphicsContext) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.30),
                    .init(color: .black.opacity(0.38), location: 0.74),
                    .init(color: .black.opacity(0.82), location: 1.0),
                ]),
                center: CGPoint(x: centreX, y: horizon),
                startRadius: 0, endRadius: max(size.width, size.height) * 0.78))
    }
}

// MARK: - Движение вперёд

/// Пройденное «расстояние». Скорость зависит от громкости, поэтому на громком
/// сцена летит вперёд, а в тишине почти останавливается.
final class TravelClock {
    private(set) var distance: Double = 0
    private var lastTime: TimeInterval = 0

    func step(time: TimeInterval, energy: Double) {
        let delta = lastTime == 0 ? 1.0 / 60.0 : min(0.1, max(0.0001, time - lastTime))
        lastTime = time
        distance += delta * (0.22 + 1.5 * energy)
    }
}

// MARK: - Вспышка по биту

/// Простой детектор удара по басу: всплеск выше скользящего среднего зажигает
/// вспышку, которая затем быстро гаснет. Свой, а не из обработки звука, — здесь
/// важна не точность, а совпадение с тем, что видно глазом.
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

        intensity *= exp(-delta / 0.16)
        if intensity < 0.002 { intensity = 0 }
    }
}
