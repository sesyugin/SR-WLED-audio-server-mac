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
        // Ровное почти чёрное поле без градиента: любой градиент здесь читался
        // заливкой и спорил со сценой. Всё освещение даёт сама сцена.
        .background(Color(red: 0.019, green: 0.018, blue: 0.024))
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

        // Единственный источник в фоне — мягкий пул света под сценой.
        // Он даёт объекту опору и отделяет его от пустоты, но сам по себе
        // ничего не изображает: фон должен быть средой, а не картинкой.
        context.blendMode = .plusLighter
        let poolRadius = base * (0.46 + 0.07 * energy)
        let poolCentre = CGPoint(x: size.width / 2, y: size.height * 0.545)
        context.fill(
            // Сильно сплюснутый эллипс: свет лежит НА плоскости, а круглое пятно
            // читалось висящей в воздухе кляксой.
            Path(ellipseIn: CGRect(x: poolCentre.x - poolRadius,
                                   y: poolCentre.y - poolRadius * 0.34,
                                   width: poolRadius * 2, height: poolRadius * 0.68)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.85,
                                       brightness: 1).opacity(0.016 + 0.030 * energy), location: 0),
                    .init(color: Color(hue: hues.deep, saturation: palette.saturation * 0.9,
                                       brightness: 1).opacity(0.005), location: 0.55),
                    .init(color: .clear, location: 1),
                ]),
                center: poolCentre, startRadius: 0, endRadius: poolRadius))
        context.blendMode = .normal

    }

    /// Затемнение по краям прижимает внимание к центру    /// Затемнение по краям прижимает внимание к центру и добавляет глубины.
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

        /// Проекция без вращения: ею пользуются шкалы и сцена в центре.
        /// Группа музыкантов не должна кружиться вместе с венцом — иначе колонки
        /// разъезжаются по диагонали и раскладка теряет смысл.
        func projectStatic(_ x: Double, _ y: Double, _ z: Double)
            -> (CGPoint, Double, Double)
        {
            let ty = y * cosTilt - z * sinTilt
            let tz = y * sinTilt + z * cosTilt
            let scale = focal / max(tz + distance, 1)
            return (CGPoint(x: centre.x + x * scale, y: centre.y + ty * scale), scale, tz)
        }

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

        // Колонна — цельная стеклянная трубка с нитью накаливания во всю длину,
        // как в филаментной лампе. Прошлый вариант делил столбик на стойку и колбу
        // сверху, и в нём нить жила только в верхней части — теперь она проходит
        // весь столбик и закреплена на обоих концах.
        for index in 0..<Self.columns {
            let position = Double(index) / Double(Self.columns)
            let theta = position * 2 * .pi
            let value = spectrum(at: position)
            let peakValue = peakSpectrum(at: position)
            let height = maxHeight * (0.05 + 0.95 * value)

            let tangentX = -sin(theta), tangentZ = cos(theta)
            let cx = cos(theta) * radius, cz = sin(theta) * radius
            let leftX = cx - tangentX * halfWidth, leftZ = cz - tangentZ * halfWidth
            let rightX = cx + tangentX * halfWidth, rightZ = cz + tangentZ * halfWidth

            let baseLeft = project(leftX, 0, leftZ)
            let baseRight = project(rightX, 0, rightZ)
            let topLeft = project(leftX, -height, leftZ)
            let topRight = project(rightX, -height, rightZ)
            let apex = project(cx, -height, cz)
            let foot = project(cx, 0, cz)

            // Стекло: трубка со скруглённой макушкой и скруглённым низом.
            let capRise = (baseLeft.0.y - topLeft.0.y) * 0.0
            _ = capRise
            let width = abs(baseRight.0.x - baseLeft.0.x)
            var glass = Path()
            glass.move(to: baseLeft.0)
            glass.addLine(to: topLeft.0)
            glass.addQuadCurve(to: topRight.0,
                               control: CGPoint(x: apex.0.x, y: apex.0.y - width * 0.85))
            glass.addLine(to: baseRight.0)
            glass.addQuadCurve(to: baseLeft.0,
                               control: CGPoint(x: foot.0.x, y: foot.0.y + width * 0.55))
            glass.closeSubpath()

            // Нить: по всей длине трубки, закреплена на обоих концах.
            var filament = Path()
            filament.move(to: project(cx, -height * 0.035, cz).0)
            filament.addLine(to: project(cx, -height * 0.965, cz).0)

            var peak: Path?
            if peakValue > value + 0.04 {
                let peakY = maxHeight * (0.05 + 0.95 * peakValue)
                let markLeft = project(leftX * 1.22, -peakY, leftZ * 1.22)
                let markRight = project(rightX * 1.22, -peakY, rightZ * 1.22)
                var mark = Path()
                mark.move(to: markLeft.0)
                mark.addLine(to: markRight.0)
                peak = mark
            }

            lamps.append(Lamp(stem: Path(), glass: glass, filament: filament,
                              tip: apex.0,
                              tipSize: halfWidth * apex.1 * 0.55,
                              peak: peak,
                              depth: baseLeft.2,
                              nearness: baseLeft.1 / referenceScale,
                              value: value))
        }

        lamps.sort { $0.depth > $1.depth }

        // Данные для лучей: макушка лампы, её накал и близость к зрителю.
        let beamSources = lamps.map {
            (point: $0.tip, value: $0.value, nearness: max(0.25, min(1, $0.nearness)))
        }

        // Сцена стоит в центре, поэтому дальние лампы рисуются до неё, ближние —
        // после. Иначе передний ряд ламп окажется под фигурами.
        let stage = GlassStage(palette: palette,
                               energy: energy,
                               bass: smoother.values.prefix(3).max() ?? 0,
                               air: smoother.values.suffix(4).max() ?? 0,
                               beat: flash,
                               time: time)
        var stageDrawn = false

        for lamp in lamps {
            if !stageDrawn && lamp.depth <= 0 {
                stage.draw(&context, project: projectStatic, radius: radius,
                           maxHeight: maxHeight, base: base)
                stageDrawn = true
            }

            let depthFade = max(0, min(1, (lamp.nearness - 0.72) / 0.55))
            let intensity = (0.16 + 0.84 * lamp.value) * (0.38 + 0.62 * depthFade)

            let hue = hues.deep + (hues.hot - hues.deep) * lamp.value
            let tint = Color(hue: hue,
                             saturation: palette.saturation * (0.92 - 0.45 * lamp.value),
                             brightness: 1)

            // Стекло: почти невидимое.
            context.fill(lamp.glass, with: .color(tint.opacity(0.05 + 0.09 * intensity)))
            context.stroke(lamp.glass,
                           with: .color(tint.opacity(0.12 + 0.22 * intensity)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008), lineJoin: .round))

            // Нить — единственное яркое место. Три обводки: широкий ореол,
            // тело нити и раскалённая сердцевина.
            context.blendMode = .plusLighter
            context.stroke(lamp.filament,
                           with: .color(tint.opacity(0.06 + 0.26 * intensity)),
                           style: StrokeStyle(lineWidth: max(1.6, base * 0.0046), lineCap: .round))
            context.stroke(lamp.filament,
                           with: .color(tint.opacity(0.20 + 0.48 * intensity)),
                           style: StrokeStyle(lineWidth: max(0.9, base * 0.0018), lineCap: .round))
            context.stroke(lamp.filament,
                           with: .color(Color(hue: hue,
                                              saturation: palette.saturation * (0.35 - 0.30 * lamp.value),
                                              brightness: 1).opacity(0.30 + 0.68 * intensity)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008), lineCap: .round))

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

        if !stageDrawn {
            stage.draw(&context, project: projectStatic, radius: radius,
                       maxHeight: maxHeight, base: base)
        }

        // Лучи рисуются последними и ложатся поверх фигур: свет от ламп должен
        // падать НА сцену, а не находиться где-то рядом с ней.
        GlassStage.beams(&context, from: beamSources,
                         centre: projectStatic(0, -maxHeight * 0.10, 0).0,
                         podiumRadius: radius,
                         palette: palette, energy: energy)

        drawLevelScale(&context, project: projectStatic, radius: radius,
                       maxHeight: maxHeight, base: base)
        // Шкала частот вращается вместе с венцом: она размечает именно его,
        // а не картинку. Нарисованная неподвижной проекцией, она оставалась
        // стоять, пока столбики уезжали мимо, — и подпись «43 Гц» показывала
        // на ту полосу, которая давно ушла в другое место круга.
        drawBaseRing(&context, project: project, radius: radius,
                     base: base, centre: centre, hues: hues)
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

            // Подписи собраны в один столбец слева: у шкалы прибора отметки стоят
            // в ряд, а разбросанные по кругу они сталкивались с частотами.
            let anchorPoint = project(-radius * 1.34, -height, 0).0
            var tick = Path()
            tick.move(to: CGPoint(x: anchorPoint.x + base * 0.010, y: anchorPoint.y))
            tick.addLine(to: CGPoint(x: anchorPoint.x + base * 0.026, y: anchorPoint.y))
            context.stroke(tick,
                           with: .color(.white.opacity(0.22)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0008)))

            var text = context.resolve(
                Text(mark.text)
                    .font(.system(size: base * 0.0145, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(0.30))
            context.draw(text, at: CGPoint(x: anchorPoint.x, y: anchorPoint.y), anchor: .trailing)
        }
    }

    /// Кольцо-основание с засечками на настоящих границах полос WLED и подписями
    /// частот. Мелкая деталь, но осмысленная: видно, где какая полоса стоит.
    private func drawBaseRing(_ context: inout GraphicsContext,
                              project: (Double, Double, Double) -> (CGPoint, Double, Double),
                              radius: Double,
                              base: Double,
                              centre: CGPoint,
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
            let candidates = [first, second].map { position -> (CGPoint, Double, Double) in
                let theta = position * 2 * .pi
                let projected = project(cos(theta) * radius * 1.20, 0, sin(theta) * radius * 1.20)
                return (projected.0, projected.2, theta)
            }
            let picked = candidates[0].1 < candidates[1].1 ? candidates[0] : candidates[1]
            let chosen = (picked.0, picked.1)
            let chosenAngle = picked.2

            // Подписи живут только на передней дуге: на дальней они лезут
            // на колонны и читаются мусором поверх света. Раньше тут стоял
            // жёсткий порог, и при неподвижной шкале этого хватало — теперь
            // она едет, и на пороге подпись просто мигала бы. Гаснет она
            // постепенно, на длине в четверть радиуса.
            let edge = centre.y - radius * 0.10
            let fade = max(0, min(1, (chosen.0.y - edge) / (radius * 0.30)))
            guard fade > 0.02 else { continue }

            // Поводок от кольца к подписи: без него цифра висит в пустоте
            // рядом с венцом, а не подписывает его засечку.
            let leaderStart = project(cos(chosenAngle) * radius * 1.115, 0,
                                      sin(chosenAngle) * radius * 1.115).0
            var leader = Path()
            leader.move(to: leaderStart)
            leader.addLine(to: CGPoint(
                x: leaderStart.x + (chosen.0.x - leaderStart.x) * 0.55,
                y: leaderStart.y + (chosen.0.y - leaderStart.y) * 0.55))
            context.stroke(leader, with: .color(.white.opacity(0.16 * fade)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0006)))

            var text = context.resolve(
                Text(label.text)
                    .font(.system(size: base * 0.0145, weight: .medium, design: .rounded)))
            text.shading = .color(.white.opacity(0.30 * fade))
            context.draw(text, at: chosen.0, anchor: .center)
        }
    }
}
