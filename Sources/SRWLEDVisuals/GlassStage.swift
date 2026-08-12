import SwiftUI

/// Стеклянная сцена в центре: подиум, колонки и фигуры музыкантов.
///
/// Всё рисуется в стиле светящегося жидкого стекла — полупрозрачная заливка
/// с холодной сердцевиной и тёплым низом, тонкий яркий контур и блик вдоль
/// освещённой стороны. Ни одна фигура не залита плотно: стекло читается именно
/// через контур и блик, а не через цвет тела.
///
/// Фигуры стоят на той же плоскости, что и лампы, и берут у неё перспективу:
/// точка опоры считается проекцией, от неё же берётся масштаб. Сами силуэты
/// рисуются лицом к зрителю — так делают в сценической графике, иначе на мелком
/// размере фигура превращается в неразборчивое пятно.
struct GlassStage {

    struct Placement {
        /// Положение на плоскости в мировых координатах.
        var x: Double
        var z: Double
        /// Высота фигуры в долях от высоты венца.
        var height: Double
    }

    let palette: Palette
    /// Общая громкость: от неё зависит накал стекла.
    let energy: Double
    /// Бас: от него дышат колонки.
    let bass: Double
    /// Верхние частоты: от них вспыхивают блики.
    let air: Double
    let beat: Double

    private var hues: (deep: Double, hot: Double) { palette.hues }

    private func glass(_ hue: Double, _ alpha: Double, saturation: Double = 0.7) -> Color {
        Color(hue: hue, saturation: palette.saturation * saturation, brightness: 1).opacity(alpha)
    }

    /// Лёд намеренно холодный независимо от гаммы сцены: тёплые лампы вокруг
    /// и холодные фигуры в центре дают контраст, на котором и держится картинка.
    /// Одинаковый тон слил бы фигуры с венцом в одно пятно.
    private func ice(_ alpha: Double, saturation: Double = 0.35) -> Color {
        Color(hue: 0.545, saturation: palette.saturation * saturation, brightness: 1).opacity(alpha)
    }

    /// Рисует всю сцену. `project` — та же проекция, что у ламп.
    func draw(_ context: inout GraphicsContext,
              project: (Double, Double, Double) -> (CGPoint, Double, Double),
              radius: Double,
              maxHeight: Double,
              base: Double)
    {
        drawPodium(&context, project: project, radius: radius, base: base)

        // Порядок отрисовки — от дальних к ближним, иначе барабанщик окажется
        // впереди вокалиста.
        let items: [(Placement, (inout GraphicsContext, CGPoint, Double, Double) -> Void)] = [
            // Знак z: при наклоне камеры положительный уходит ОТ зрителя.
            // Барабанщик стоит позади всех, вокалист — впереди, колонки по краям.
            (Placement(x:  0.00, z:  0.34, height: 0.22), drawDrummer),
            (Placement(x: -0.54, z:  0.12, height: 0.26), drawSpeaker),
            (Placement(x:  0.54, z:  0.12, height: 0.26), drawSpeaker),
            (Placement(x: -0.24, z: -0.02, height: 0.27), drawGuitarist),
            (Placement(x:  0.24, z:  0.00, height: 0.25), drawKeyboardist),
            (Placement(x:  0.00, z: -0.26, height: 0.31), drawVocalist),
        ]

        let placed = items.map { item -> (Placement, CGPoint, Double, Double,
                                          (inout GraphicsContext, CGPoint, Double, Double) -> Void) in
            let projected = project(item.0.x * radius, 0, item.0.z * radius)
            return (item.0, projected.0, projected.1, projected.2, item.1)
        }
        .sorted { $0.3 > $1.3 }

        for (placement, point, scale, _, drawFigure) in placed {
            let height = maxHeight * placement.height * scale * 1.30
            drawFigure(&context, point, height, base)
        }
    }

    // MARK: - Подиум

    private func drawPodium(_ context: inout GraphicsContext,
                            project: (Double, Double, Double) -> (CGPoint, Double, Double),
                            radius: Double,
                            base: Double)
    {
        // Круглый подиум под фигурами: стеклянный диск с подсвеченным краем.
        let podiumRadius = radius * 0.68
        var disc = Path()
        for step in 0...120 {
            let theta = Double(step) / 120 * 2 * .pi
            let point = project(cos(theta) * podiumRadius, 0, sin(theta) * podiumRadius).0
            if step == 0 { disc.move(to: point) } else { disc.addLine(to: point) }
        }
        disc.closeSubpath()

        let bounds = disc.boundingRect
        // Заливка подиума намеренно почти нулевая: сплошной диск давал мутное
        // пятно под фигурами и съедал контраст со льдом.
        context.fill(disc,
                     with: .linearGradient(
                         Gradient(stops: [
                             .init(color: ice(0.020 + 0.028 * energy, saturation: 0.30), location: 0),
                             .init(color: ice(0.006, saturation: 0.5), location: 1),
                         ]),
                         startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                         endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))

        context.blendMode = .plusLighter
        context.stroke(disc,
                       with: .color(ice(0.18 + 0.24 * energy, saturation: 0.28)),
                       style: StrokeStyle(lineWidth: max(0.6, base * 0.0011)))
        context.blendMode = .normal
    }

    // MARK: - Общая отделка стекла

    /// Заливает силуэт как стекло: холодная сердцевина, тёплый низ, яркий контур
    /// и блик вдоль левой грани.
    private func fillGlass(_ context: inout GraphicsContext,
                           _ path: Path,
                           base: Double,
                           glow: Double,
                           facets: Bool = true)
    {
        let bounds = path.boundingRect
        guard bounds.height > 0.5, bounds.width > 0.2 else { return }

        // Свет изнутри: пятно у сердцевины, гаснущее к краям. Именно оно делает
        // лёд светящимся, а не подсвеченным снаружи.
        context.blendMode = .plusLighter
        context.fill(path,
                     with: .radialGradient(
                         Gradient(stops: [
                             .init(color: ice(0.16 + 0.34 * glow, saturation: 0.20), location: 0.0),
                             .init(color: ice(0.06 + 0.16 * glow, saturation: 0.40), location: 0.55),
                             .init(color: ice(0.0), location: 1.0),
                         ]),
                         center: CGPoint(x: bounds.midX, y: bounds.midY + bounds.height * 0.18),
                         startRadius: 0,
                         endRadius: max(bounds.width, bounds.height) * 0.75))
        context.blendMode = .normal

        // Тело: холодная полупрозрачная масса, книзу плотнее.
        context.fill(path,
                     with: .linearGradient(
                         Gradient(stops: [
                             .init(color: ice(0.05 + 0.08 * glow, saturation: 0.15), location: 0.0),
                             .init(color: ice(0.09 + 0.10 * glow, saturation: 0.45), location: 1.0),
                         ]),
                         startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                         endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))

        // Огранка: пара прямых сколов внутри силуэта. Лёд отличается от стекла
        // именно гранями, а не гладкостью.
        if facets, bounds.height > base * 0.012 {
            // Обрезка ведётся в КОПИИ контекста: GraphicsContext.clip меняет
            // состояние навсегда, и вызов на общем контексте обрезал бы всё,
            // что рисуется дальше, силуэтом этой фигуры.
            var faceted = context
            faceted.clip(to: path)
            faceted.blendMode = .plusLighter
            for facet in 0..<2 {
                let offset = bounds.width * (facet == 0 ? 0.22 : 0.62)
                var line = Path()
                line.move(to: CGPoint(x: bounds.minX + offset, y: bounds.minY))
                line.addLine(to: CGPoint(x: bounds.minX + offset - bounds.width * 0.30,
                                         y: bounds.maxY))
                faceted.stroke(line,
                               with: .color(ice(0.14 + 0.20 * glow, saturation: 0.10)),
                               style: StrokeStyle(lineWidth: max(0.4, base * 0.0009)))
            }
        }

        // Кромка: сверху яркая, книзу гаснет — так лёд ловит верхний свет.
        context.stroke(path,
                       with: .linearGradient(
                           Gradient(colors: [.white.opacity(0.55 + 0.35 * glow),
                                             ice(0.34 + 0.30 * glow, saturation: 0.25),
                                             ice(0.10, saturation: 0.55)]),
                           startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                           endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)),
                       style: StrokeStyle(lineWidth: max(0.6, base * 0.0012), lineJoin: .round))
    }

    // MARK: - Фигуры
    //
    // Каждая строится от точки опоры вверх, все размеры — в долях высоты,
    // поэтому фигура одинаково собрана на любом масштабе.

    private func drawSpeaker(_ context: inout GraphicsContext,
                             at foot: CGPoint, height: Double, base: Double)
    {
        let width = height * 0.42
        let body = CGRect(x: foot.x - width / 2, y: foot.y - height, width: width, height: height)

        var path = Path(roundedRect: body, cornerRadius: width * 0.10)
        fillGlass(&context, path, base: base, glow: bass)

        // Динамики: два круга, нижний крупнее. Дышат вместе с басом.
        context.blendMode = .plusLighter
        let pulse = 1 + 0.06 * bass
        let lower = CGRect(x: body.midX - width * 0.30 * pulse,
                           y: body.maxY - height * 0.36 - width * 0.30 * pulse,
                           width: width * 0.60 * pulse, height: width * 0.60 * pulse)
        let upper = CGRect(x: body.midX - width * 0.17,
                           y: body.minY + height * 0.14,
                           width: width * 0.34, height: width * 0.34)
        for circle in [lower, upper] {
            context.stroke(Path(ellipseIn: circle),
                           with: .color(ice(0.32 + 0.45 * bass, saturation: 0.25)),
                           style: StrokeStyle(lineWidth: max(0.5, base * 0.0009)))
            context.fill(Path(ellipseIn: circle.insetBy(dx: circle.width * 0.34,
                                                        dy: circle.height * 0.34)),
                         with: .color(.white.opacity(0.18 + 0.42 * bass)))
        }
        context.blendMode = .normal
        _ = path
    }

    private func drawVocalist(_ context: inout GraphicsContext,
                              at foot: CGPoint, height: Double, base: Double)
    {
        let unit = height
        var path = Path()

        // Ноги и корпус одной сплошной линией — силуэт, а не анатомия.
        path.move(to: CGPoint(x: foot.x - unit * 0.10, y: foot.y))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.07, y: foot.y - unit * 0.42))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.14, y: foot.y - unit * 0.70))
        // Рука поднята вверх — жест на сцене.
        path.addLine(to: CGPoint(x: foot.x - unit * 0.30, y: foot.y - unit * 0.96))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.24, y: foot.y - unit * 0.99))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.09, y: foot.y - unit * 0.78))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.09, y: foot.y - unit * 0.78))
        // Вторая рука опущена к микрофону.
        path.addLine(to: CGPoint(x: foot.x + unit * 0.20, y: foot.y - unit * 0.52))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.14, y: foot.y - unit * 0.50))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.07, y: foot.y - unit * 0.70))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.10, y: foot.y - unit * 0.42))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.10, y: foot.y))
        path.closeSubpath()
        fillGlass(&context, path, base: base, glow: energy)

        // Голова.
        let headRadius = unit * 0.11
        let head = CGRect(x: foot.x - headRadius, y: foot.y - unit * 0.98 + headRadius * 0.2,
                          width: headRadius * 2, height: headRadius * 2)
        fillGlass(&context, Path(ellipseIn: head), base: base, glow: energy)

        // Микрофонная стойка.
        var stand = Path()
        stand.move(to: CGPoint(x: foot.x + unit * 0.26, y: foot.y))
        stand.addLine(to: CGPoint(x: foot.x + unit * 0.24, y: foot.y - unit * 0.56))
        context.blendMode = .plusLighter
        context.stroke(stand,
                       with: .color(ice(0.30 + 0.32 * energy, saturation: 0.22)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0009), lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: foot.x + unit * 0.20, y: foot.y - unit * 0.60,
                                   width: unit * 0.08, height: unit * 0.08)),
            with: .color(.white.opacity(0.30 + 0.45 * energy)))
        context.blendMode = .normal
    }

    private func drawGuitarist(_ context: inout GraphicsContext,
                               at foot: CGPoint, height: Double, base: Double)
    {
        let unit = height
        var path = Path()
        path.move(to: CGPoint(x: foot.x - unit * 0.11, y: foot.y))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.08, y: foot.y - unit * 0.44))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.15, y: foot.y - unit * 0.72))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.06, y: foot.y - unit * 0.76))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.08, y: foot.y - unit * 0.74))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.11, y: foot.y - unit * 0.44))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.11, y: foot.y))
        path.closeSubpath()
        fillGlass(&context, path, base: base, glow: energy)

        let headRadius = unit * 0.105
        fillGlass(&context,
                  Path(ellipseIn: CGRect(x: foot.x - headRadius * 0.4,
                                         y: foot.y - unit * 0.96,
                                         width: headRadius * 2, height: headRadius * 2)),
                  base: base, glow: energy)

        // Гитара: наклонённый корпус и гриф.
        var guitar = Path()
        let bodyCentre = CGPoint(x: foot.x - unit * 0.02, y: foot.y - unit * 0.46)
        guitar.addEllipse(in: CGRect(x: bodyCentre.x - unit * 0.15, y: bodyCentre.y - unit * 0.10,
                                     width: unit * 0.30, height: unit * 0.20))
        context.blendMode = .plusLighter
        context.stroke(guitar,
                       with: .color(ice(0.34 + 0.36 * energy, saturation: 0.22)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0010)))
        var neck = Path()
        neck.move(to: CGPoint(x: bodyCentre.x + unit * 0.12, y: bodyCentre.y - unit * 0.02))
        neck.addLine(to: CGPoint(x: bodyCentre.x + unit * 0.44, y: bodyCentre.y - unit * 0.20))
        context.stroke(neck,
                       with: .color(ice(0.32 + 0.34 * energy, saturation: 0.20)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0009), lineCap: .round))
        context.blendMode = .normal
    }

    private func drawKeyboardist(_ context: inout GraphicsContext,
                                 at foot: CGPoint, height: Double, base: Double)
    {
        let unit = height
        var path = Path()
        path.move(to: CGPoint(x: foot.x - unit * 0.10, y: foot.y))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.08, y: foot.y - unit * 0.46))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.13, y: foot.y - unit * 0.74))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.13, y: foot.y - unit * 0.74))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.08, y: foot.y - unit * 0.46))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.10, y: foot.y))
        path.closeSubpath()
        fillGlass(&context, path, base: base, glow: energy)

        let headRadius = unit * 0.10
        fillGlass(&context,
                  Path(ellipseIn: CGRect(x: foot.x - headRadius, y: foot.y - unit * 0.95,
                                         width: headRadius * 2, height: headRadius * 2)),
                  base: base, glow: energy)

        // Клавиши перед фигурой — узкая пластина со светящейся кромкой.
        let deck = CGRect(x: foot.x - unit * 0.30, y: foot.y - unit * 0.44,
                          width: unit * 0.60, height: unit * 0.07)
        fillGlass(&context, Path(roundedRect: deck, cornerRadius: deck.height * 0.4),
                  base: base, glow: air)
    }

    private func drawDrummer(_ context: inout GraphicsContext,
                             at foot: CGPoint, height: Double, base: Double)
    {
        let unit = height

        // Установка: большой барабан и два тома, все со светящейся кромкой.
        let kick = CGRect(x: foot.x - unit * 0.34, y: foot.y - unit * 0.52,
                          width: unit * 0.68, height: unit * 0.52)
        fillGlass(&context, Path(ellipseIn: kick), base: base, glow: bass)

        for offset in [-0.42, 0.42] {
            let tom = CGRect(x: foot.x + unit * offset - unit * 0.15,
                             y: foot.y - unit * 0.66,
                             width: unit * 0.30, height: unit * 0.24)
            fillGlass(&context, Path(ellipseIn: tom), base: base, glow: bass * 0.7)
        }

        // Фигура за установкой — видна только верхняя часть.
        var path = Path()
        path.move(to: CGPoint(x: foot.x - unit * 0.12, y: foot.y - unit * 0.52))
        path.addLine(to: CGPoint(x: foot.x - unit * 0.14, y: foot.y - unit * 0.78))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.14, y: foot.y - unit * 0.78))
        path.addLine(to: CGPoint(x: foot.x + unit * 0.12, y: foot.y - unit * 0.52))
        path.closeSubpath()
        fillGlass(&context, path, base: base, glow: energy)

        let headRadius = unit * 0.10
        fillGlass(&context,
                  Path(ellipseIn: CGRect(x: foot.x - headRadius, y: foot.y - unit * 0.99,
                                         width: headRadius * 2, height: headRadius * 2)),
                  base: base, glow: energy)

        // Палочки, поднятые вверх.
        context.blendMode = .plusLighter
        for direction in [-1.0, 1.0] {
            var stick = Path()
            stick.move(to: CGPoint(x: foot.x + unit * 0.12 * direction, y: foot.y - unit * 0.72))
            stick.addLine(to: CGPoint(x: foot.x + unit * 0.34 * direction,
                                      y: foot.y - unit * (0.88 + 0.10 * beat)))
            context.stroke(stick,
                           with: .color(.white.opacity(0.22 + 0.40 * beat)),
                           style: StrokeStyle(lineWidth: max(0.4, base * 0.0008), lineCap: .round))
        }
        context.blendMode = .normal
    }
}
