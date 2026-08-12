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

        // План 3: полярная измерительная сетка на плоскости — она отвечает
        // столбикам по смыслу. Топографические разводы, стоявшие здесь раньше,
        // были просто узором и со шкалой прибора не связаны никак.
        drawPolarGrid(&context, size: size, time: time)

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

    /// Полярная сетка на плоскости: концентрические круги и лучи по границам полос.
    /// Уходит за пределы венца, поэтому у сцены появляется пол, а не пустота.
    private func drawPolarGrid(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        let hues = palette.hues

        let spin = time * 0.10
        let tilt = 0.92
        let focal = base * 2.0
        let distance = base * 2.1
        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)

        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            let ty = y * cosTilt - rz * sinTilt
            let tz = y * sinTilt + rz * cosTilt
            let scale = focal / max(tz + distance, 1)
            return CGPoint(x: centre.x + rx * scale, y: centre.y + ty * scale)
        }

        let unit = base * 0.325

        // Концентрические круги: внутри венца и далеко за ним.
        for ring in 1...7 {
            let r = unit * (0.28 + Double(ring) * 0.30)
            var path = Path()
            for step in 0...120 {
                let theta = Double(step) / 120 * 2 * .pi
                let point = project(cos(theta) * r, 0, sin(theta) * r)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let fade = 1 - Double(ring) / 8
            context.stroke(path,
                           with: .color(.white.opacity(0.020 + 0.030 * fade)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0006)))
        }

        // Лучи по границам шестнадцати полос, уходящие наружу.
        for band in 0..<32 {
            let theta = Double(band) / 32 * 2 * .pi
            var path = Path()
            path.move(to: project(cos(theta) * unit * 0.30, 0, sin(theta) * unit * 0.30))
            path.addLine(to: project(cos(theta) * unit * 2.35, 0, sin(theta) * unit * 2.35))
            context.stroke(path,
                           with: .color(Color(hue: hues.deep,
                                              saturation: palette.saturation * 0.5,
                                              brightness: 1).opacity(band % 4 == 0 ? 0.045 : 0.022)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0006)))
        }
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

    /// То же, что spectrum, но по пиковым значениям.
    private func peakSpectrum(at position: Double) -> Double {
        let folded = position < 0.5 ? position * 2 : (1 - position) * 2
        let scaled = folded * 15
        let lower = min(15, Int(scaled))
        let upper = min(15, lower + 1)
        let blend = scaled - Double(lower)
        guard smoother.peaks.count == 16 else { return 0 }
        return smoother.peaks[lower] * (1 - blend) + smoother.peaks[upper] * blend
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

        struct Lamp {
            var stem: Path
            var glass: Path
            var filament: Path
            var tip: CGPoint
            var tipSize: Double
            var peak: Path?
            var depth: Double
            var nearness: Double
            var value: Double
        }

        var lamps: [Lamp] = []
        lamps.reserveCapacity(Self.columns)

        let step = 2 * Double.pi / Double(Self.columns)
        let halfWidth = radius * step * 0.30

        // Колба всегда одного размера — меняется только высота стойки под ней.
        // Раньше растягивалась сама колба вместе с нитью, и лампа переставала
        // читаться лампой: у настоящей меняется накал, а не размер стекла.
        let bulbHeight = maxHeight * 0.115
        let stemRange = maxHeight - bulbHeight

        for index in 0..<Self.columns {
            let position = Double(index) / Double(Self.columns)
            let theta = position * 2 * .pi
            let value = spectrum(at: position)
            let peakValue = peakSpectrum(at: position)

            let stemTop = stemRange * (0.04 + 0.96 * value)
            let bulbBottom = stemTop
            let bulbTop = stemTop + bulbHeight

            let tangentX = -sin(theta), tangentZ = cos(theta)
            let cx = cos(theta) * radius, cz = sin(theta) * radius
            let leftX = cx - tangentX * halfWidth, leftZ = cz - tangentZ * halfWidth
            let rightX = cx + tangentX * halfWidth, rightZ = cz + tangentZ * halfWidth

            // Стойка — тонкая линия от плоскости до колбы.
            let footPoint = project(cx, 0, cz)
            let stemTopPoint = project(cx, -bulbBottom, cz)
            var stem = Path()
            stem.move(to: footPoint.0)
            stem.addLine(to: stemTopPoint.0)

            // Стекло колбы.
            let glassBaseLeft = project(leftX, -bulbBottom, leftZ)
            let glassBaseRight = project(rightX, -bulbBottom, rightZ)
            let shoulderLeft = project(leftX, -(bulbBottom + bulbHeight * 0.72), leftZ)
            let shoulderRight = project(rightX, -(bulbBottom + bulbHeight * 0.72), rightZ)
            let crown = project(cx, -bulbTop, cz)

            var glass = Path()
            glass.move(to: glassBaseLeft.0)
            glass.addLine(to: shoulderLeft.0)
            glass.addQuadCurve(to: crown.0,
                               control: CGPoint(x: shoulderLeft.0.x,
                                                y: crown.0.y + (shoulderLeft.0.y - crown.0.y) * 0.2))
            glass.addQuadCurve(to: shoulderRight.0,
                               control: CGPoint(x: shoulderRight.0.x,
                                                y: crown.0.y + (shoulderRight.0.y - crown.0.y) * 0.2))
            glass.addLine(to: glassBaseRight.0)
            glass.closeSubpath()

            // Нить внутри колбы — та же длина у всех, меняется только накал.
            var filament = Path()
            filament.move(to: project(cx, -(bulbBottom + bulbHeight * 0.18), cz).0)
            filament.addLine(to: project(cx, -(bulbBottom + bulbHeight * 0.76), cz).0)

            var peak: Path?
            if peakValue > value + 0.04 {
                let peakY = stemRange * (0.04 + 0.96 * peakValue) + bulbHeight * 0.5
                let markLeft = project(leftX * 1.25, -peakY, leftZ * 1.25)
                let markRight = project(rightX * 1.25, -peakY, rightZ * 1.25)
                var mark = Path()
                mark.move(to: markLeft.0)
                mark.addLine(to: markRight.0)
                peak = mark
            }

            lamps.append(Lamp(stem: stem, glass: glass, filament: filament,
                              tip: crown.0,
                              tipSize: halfWidth * crown.1 * 0.45,
                              peak: peak,
                              depth: footPoint.2,
                              nearness: footPoint.1 / referenceScale,
                              value: value))
        }

        lamps.sort { $0.depth > $1.depth }

        for lamp in lamps {
            let depthFade = max(0, min(1, (lamp.nearness - 0.72) / 0.55))
            let intensity = (0.10 + 0.90 * lamp.value) * (0.30 + 0.70 * depthFade)

            let hue = hues.deep + (hues.hot - hues.deep) * lamp.value
            let tint = Color(hue: hue,
                             saturation: palette.saturation * (0.92 - 0.45 * lamp.value),
                             brightness: 1)

            // Стойка: тонкая и тёмная, она не должна спорить с колбой.
            context.stroke(lamp.stem,
                           with: .color(tint.opacity(0.12 + 0.20 * depthFade)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0009)))

            // Стекло: почти невидимое.
            context.fill(lamp.glass, with: .color(tint.opacity(0.05 + 0.09 * intensity)))
            context.stroke(lamp.glass,
                           with: .color(tint.opacity(0.12 + 0.22 * intensity)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008), lineJoin: .round))

            // Нить — единственное яркое место.
            context.blendMode = .plusLighter
            context.stroke(lamp.filament,
                           with: .color(tint.opacity(0.08 + 0.32 * intensity)),
                           style: StrokeStyle(lineWidth: max(1.4, base * 0.0040), lineCap: .round))
            context.stroke(lamp.filament,
                           with: .color(Color(hue: hue,
                                              saturation: palette.saturation * (0.5 - 0.45 * lamp.value),
                                              brightness: 1).opacity(0.30 + 0.65 * intensity)),
                           style: StrokeStyle(lineWidth: max(0.7, base * 0.0013), lineCap: .round))

            let tipSize = max(0.6, lamp.tipSize)
            context.fill(
                Path(ellipseIn: CGRect(x: lamp.tip.x - tipSize, y: lamp.tip.y - tipSize * 0.7,
                                       width: tipSize * 2, height: tipSize * 1.4)),
                with: .color(.white.opacity(0.08 + 0.40 * intensity)))
            context.blendMode = .normal

            if let peak = lamp.peak {
                context.stroke(peak,
                               with: .color(.white.opacity(0.12 + 0.24 * depthFade)),
                               style: StrokeStyle(lineWidth: max(0.5, base * 0.0009), lineCap: .round))
            }
        }

        drawLevelScale(&context, project: project, radius: radius,
                       maxHeight: maxHeight, base: base)
        drawBaseRing(&context, project: project, radius: radius, base: base, hues: hues)
    }

    /// Шкала уровня по высоте: тонкие кольца на характерных отметках в децибелах
    /// и подписи к ним. Раньше высота колонок была величиной без единиц измерения —
    /// теперь по ней можно читать уровень, а не только сравнивать столбики между собой.
    private func drawLevelScale(_ context: inout GraphicsContext,
                                project: (Double, Double, Double) -> (CGPoint, Double, Double),
                                radius: Double,
                                maxHeight: Double,
                                base: Double)
    {
        // Отметки выбраны по децибелам, а не по долям: -12 дБ это ровно четверть
        // амплитуды, и глазу привычнее видеть шкалу прибора.
        let marks: [(level: Double, text: String)] = [
            (0.251, "−12"), (0.501, "−6"), (0.708, "−3"), (1.0, "0 dB"),
        ]

        for mark in marks {
            let height = maxHeight * mark.level
            var ring = Path()
            for step in 0...120 {
                let theta = Double(step) / 120 * 2 * .pi
                let point = project(cos(theta) * radius * 1.02, -height, sin(theta) * radius * 1.02).0
                if step == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
            }
            context.stroke(ring,
                           with: .color(.white.opacity(mark.level == 1.0 ? 0.10 : 0.055)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0006),
                                              dash: [base * 0.004, base * 0.010]))

            // Подпись ставится на ближней к зрителю стороне кольца.
            var nearest = CGPoint.zero
            var nearestDepth = Double.infinity
            for step in 0..<48 {
                let theta = Double(step) / 48 * 2 * .pi
                let projected = project(cos(theta) * radius * 1.30, -height, sin(theta) * radius * 1.30)
                if projected.2 < nearestDepth {
                    nearestDepth = projected.2
                    nearest = projected.0
                }
            }
            var text = context.resolve(
                Text(mark.text)
                    .font(.system(size: base * 0.015, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(0.24))
            context.draw(text, at: nearest, anchor: .center)
        }
    }

    /// Кольцо-основание с засечками на настоящих границах полос WLED и подписями
    /// частот. Мелкая деталь, но осмысленная: видно, где какая полоса стоит.
    private func drawBaseRing(_ context: inout GraphicsContext,
                              project: (Double, Double, Double) -> (CGPoint, Double, Double),
                              radius: Double,
                              base: Double,
                              hues: (deep: Double, hot: Double))
    {
        var ring = Path()
        for step in 0...144 {
            let theta = Double(step) / 144 * 2 * .pi
            let point = project(cos(theta) * radius * 1.055, 0, sin(theta) * radius * 1.055).0
            if step == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
        }
        context.stroke(ring,
                       with: .color(Color(hue: hues.deep, saturation: palette.saturation * 0.6,
                                          brightness: 1).opacity(0.14)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))

        // Засечки по границам шестнадцати полос.
        for band in 0...15 {
            let position = Double(band) / 15 * 0.5
            let theta = position * 2 * .pi
            let inner = project(cos(theta) * radius * 1.055, 0, sin(theta) * radius * 1.055).0
            let outer = project(cos(theta) * radius * 1.105, 0, sin(theta) * radius * 1.105).0
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            context.stroke(tick,
                           with: .color(.white.opacity(band % 5 == 0 ? 0.20 : 0.08)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))
        }

        // Подписи на характерных частотах — по таблице полос прошивки.
        // Подписи по границам полос из таблицы прошивки — через одну, чтобы
        // разметка была частой, но ещё читалась.
        let edges = [43, 86, 129, 216, 301, 430, 560, 818, 1120,
                     1421, 1895, 2412, 3015, 3704, 4479, 9259]
        let labels: [(band: Int, text: String)] = stride(from: 0, through: 15, by: 2).map { band in
            let hz = edges[band]
            let text = hz >= 1000
                ? String(format: "%.1fk", Double(hz) / 1000)
                : "\(hz)"
            return (band, text)
        }
        for label in labels {
            // Полоса встречается на круге дважды из-за зеркальной симметрии.
            // Берём ту сторону, что ближе к зрителю.
            let first = Double(label.band) / 15 * 0.5
            let second = 1 - first
            let candidates = [first, second].map { position -> (CGPoint, Double) in
                let theta = position * 2 * .pi
                let projected = project(cos(theta) * radius * 1.16, 0, sin(theta) * radius * 1.16)
                return (projected.0, projected.2)
            }
            let chosen = candidates[0].1 < candidates[1].1 ? candidates[0] : candidates[1]

            // Круг вращается, поэтому подпись уезжает то ближе, то дальше.
            // Гасим её на дальней половине и плавно проявляем на ближней —
            // так надписи не пляшут поверх колонн и не мельтешат.
            let front = max(0, min(1, (radius * 0.55 - chosen.1) / (radius * 0.85)))
            let alpha = 0.30 * front * front
            guard alpha > 0.02 else { continue }

            var text = context.resolve(
                Text(label.text)
                    .font(.system(size: base * 0.015, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(alpha))
            context.draw(text, at: chosen.0, anchor: .center)
        }
    }
}
