import SwiftUI

/// Маленький рендер объёмных тел: сфера, капсула и параллелепипед.
///
/// Плоские силуэты объёма не дают никогда, сколько ни добавляй бликов. Здесь
/// тела заданы в трёхмерных координатах и закрашиваются по нормали к источнику
/// света: у сферы заливка радиальная со смещением к свету, у капсулы —
/// поперечная, как у цилиндра, у коробки каждая грань закрашивается отдельно
/// по своему наклону. Отсюда и берётся форма.
///
/// Все тела складываются в общий список и рисуются от дальних к ближним,
/// поэтому руки заходят за корпус, а корпус за колонку — без этого объём
/// рассыпается на наложенные друг на друга пятна.
struct Solid3D {

    typealias Projection = (Double, Double, Double) -> (CGPoint, Double, Double)

    /// Отложенная отрисовка одного тела вместе с его глубиной.
    struct Piece {
        var depth: Double
        var render: (inout GraphicsContext) -> Void
    }

    /// Материал: тёмно-коричневое золотое стекло.
    ///
    /// Тон меняется вместе с освещённостью, а не только яркость: в тени тело
    /// уходит в глубокий коричневый, на свету разгорается до золота. Один тон
    /// на всю поверхность давал бы плоскую крашеную деталь — именно перепад
    /// от коричневого к золотому и читается как толща стекла.
    struct Material {
        /// Тон в глубокой тени.
        var deepHue: Double = 0.055
        /// Тон на свету.
        var liteHue: Double = 0.115
        var saturation: Double = 0.85
        /// Насколько тело раскалено изнутри: от этого зависит и свечение, и блик.
        var glow: Double = 0.3
        /// Общая непрозрачность тела.
        var opacity: Double = 0.62
        /// Насколько тело темнее эталонного золота. Единица — как есть.
        ///
        /// Нужно бэклайну: у глухого тела заливка граней доходит до полной, и
        /// верхняя грань кабинета выходила самым светлым пятном кадра. Два
        /// стека портала перетягивали на себя весь взгляд, а музыканты — то,
        /// ради чего сцена и собрана, — оказывались тусклее своей аппаратуры.
        /// Тон при этом остаётся тем же: темнее делается яркость, а не цвет.
        var shade: Double = 1

        func colour(_ brightness: Double, _ alpha: Double) -> Color {
            let level = max(0, min(1, brightness))
            return Color(hue: deepHue + (liteHue - deepHue) * level,
                         // К свету насыщенность падает мягко: золото светлеет,
                         // но не выцветает в белый — белым остаётся только блик.
                         saturation: saturation * (1 - level * 0.42),
                         brightness: (0.16 + 0.84 * pow(level, 0.85)) * shade)
                .opacity(alpha * opacity)
        }

        // Три слоя ниже кладутся поверх основной заливки сложением цвета.
        // Они и отличают толщу стекла от крашеной поверхности: сама заливка
        // говорит только о том, как тело повёрнуто к свету, а сквозь тело
        // при этом ничего не идёт.

        /// Общая непрозрачность у накладных слоёв ограничена единицей:
        /// у инструментов она заведена выше единицы ради плотности заливки,
        /// но складываемый слой от этого просто выжигался бы в белое.
        private var addedOpacity: Double { min(1, opacity) }

        /// Кромка на просвет. У края тела луч идёт по касательной и проходит
        /// сквозь толщу в несколько раз бОльшую, чем в середине, поэтому край
        /// у прозрачного тела всегда светлее середины — по этому признаку глаз
        /// и отличает стекло от крашеного бока.
        func rim(_ alpha: Double) -> Color {
            Color(hue: liteHue, saturation: saturation * 0.52, brightness: 0.88)
                .opacity(alpha * addedOpacity * (0.62 + 0.38 * glow))
        }

        /// Второй блик — отражение окружающего света с противоположной от
        /// источника стороны. Без него тело матовое: одного блика хватает
        /// пластмассе, но не стеклу, которому есть что отражать по всему кругу.
        func sheen(_ alpha: Double) -> Color {
            Color(hue: liteHue - 0.010, saturation: saturation * 0.30, brightness: 1)
                .opacity(alpha * addedOpacity)
        }

        /// Свечение изнутри. Тень у стекла не чёрная: в ней тлеет свет,
        /// прошедший тело насквозь. Накал берётся из glow, а тот идёт от
        /// громкости — тело разгорается изнутри вместе с музыкой.
        func inner(_ alpha: Double) -> Color {
            Color(hue: deepHue + (liteHue - deepHue) * 0.28,
                  saturation: min(1, saturation * 1.06),
                  brightness: 0.20 + 0.34 * glow)
                .opacity(alpha * addedOpacity * (0.22 + 0.78 * glow))
        }
    }

    /// Направление света в экранных координатах: сверху-слева. Камера здесь
    /// неподвижна, поэтому хватает постоянного направления — оно даёт всем телам
    /// согласованную светотень, а это и есть главное условие объёма.
    static let lightScreen = CGVector(dx: -0.42, dy: -0.52)

    // MARK: - Сфера

    static func sphere(centre: (Double, Double, Double),
                       radius: Double,
                       material: Material,
                       project: Projection,
                       lineWidth: Double) -> Piece
    {
        let projected = project(centre.0, centre.1, centre.2)
        let screenRadius = radius * projected.1
        let point = projected.0

        return Piece(depth: projected.2) { context in
            guard screenRadius > 0.4 else { return }
            let rect = CGRect(x: point.x - screenRadius, y: point.y - screenRadius,
                              width: screenRadius * 2, height: screenRadius * 2)

            // Освещённая точка смещена к источнику — это и читается как шар.
            let lit = CGPoint(x: point.x + lightScreen.dx * screenRadius * 0.55,
                              y: point.y + lightScreen.dy * screenRadius * 0.55)

            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: material.colour(1.0, 0.55 + 0.35 * material.glow), location: 0.0),
                        .init(color: material.colour(0.72, 0.42), location: 0.42),
                        .init(color: material.colour(0.30, 0.30), location: 0.88),
                        .init(color: material.colour(0.18, 0.24), location: 1.0),
                    ]),
                    center: lit, startRadius: 0, endRadius: screenRadius * 1.55))

            // Точка на теневой стороне: к ней привязано всё, что идёт не от
            // источника — внутреннее свечение и отражённый блик.
            let shade = CGPoint(x: point.x - lightScreen.dx * screenRadius * 0.62,
                                y: point.y - lightScreen.dy * screenRadius * 0.62)

            context.blendMode = .plusLighter

            // Свечение изнутри: пятно в тени, а не по всему телу — на свету
            // его всё равно не видно за отражённым.
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [material.inner(0.24), .clear]),
                    center: shade, startRadius: 0, endRadius: screenRadius * 1.15))

            // Толща по касательной: свет набирается к самому краю силуэта,
            // независимо от того, где источник. Радиус градиента равен радиусу
            // шара, поэтому единица приходится ровно на контур.
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: material.rim(0.05), location: 0.60),
                        .init(color: material.rim(0.30), location: 0.88),
                        .init(color: material.rim(0.72), location: 1.0),
                    ]),
                    center: point, startRadius: 0, endRadius: screenRadius))

            // Отражённый блик: шире главного и слабее — это не источник, а
            // подсветка от сцены вокруг. Ложится он не в середину тени, а к
            // самому теневому краю: отражение приходит вскользь, и на шаре
            // оно всегда прижато к контуру.
            let ambientAt = CGPoint(x: point.x - lightScreen.dx * screenRadius * 1.12,
                                    y: point.y - lightScreen.dy * screenRadius * 1.12)
            let ambient = screenRadius * 0.62
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [material.sheen(0.20 + 0.12 * material.glow), .clear]),
                    center: ambientAt, startRadius: 0, endRadius: ambient))

            // Блик: маленький и смещённый к свету.
            let specular = screenRadius * 0.24
            context.fill(
                Path(ellipseIn: CGRect(x: lit.x - specular, y: lit.y - specular * 0.8,
                                       width: specular * 2, height: specular * 1.6)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.55 + 0.30 * material.glow), .clear]),
                    center: lit, startRadius: 0, endRadius: specular * 1.6))
            context.blendMode = .normal

            // Контур поверх толщи: он собирает кромку в резкую линию, иначе
            // край размывается и тело теряет силуэт. Толщина растёт вместе с
            // телом — постоянная давала крупным телам ниточку в волос.
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: lineWidth * 0.4, dy: lineWidth * 0.4)),
                with: .color(material.rim(0.50)),
                style: StrokeStyle(lineWidth: max(lineWidth, screenRadius * 0.055)))
        }
    }

    // MARK: - Капсула

    /// Цилиндр со сферическими торцами: из них собираются корпус, руки и ноги.
    static func capsule(from: (Double, Double, Double),
                        to: (Double, Double, Double),
                        radius: Double,
                        material: Material,
                        project: Projection,
                        lineWidth: Double) -> Piece
    {
        let a = project(from.0, from.1, from.2)
        let b = project(to.0, to.1, to.2)
        let scale = (a.1 + b.1) / 2
        let screenRadius = radius * scale

        return Piece(depth: (a.2 + b.2) / 2) { context in
            guard screenRadius > 0.3 else { return }

            let dx = b.0.x - a.0.x, dy = b.0.y - a.0.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.001 else { return }
            // Нормаль к оси в экранных координатах — вдоль неё и идёт заливка.
            let nx = -dy / length, ny = dx / length

            var path = Path()
            path.move(to: CGPoint(x: a.0.x + nx * screenRadius, y: a.0.y + ny * screenRadius))
            path.addLine(to: CGPoint(x: b.0.x + nx * screenRadius, y: b.0.y + ny * screenRadius))
            path.addArc(center: b.0, radius: screenRadius,
                        startAngle: .radians(atan2(ny, nx)),
                        endAngle: .radians(atan2(-ny, -nx)),
                        clockwise: true)
            path.addLine(to: CGPoint(x: a.0.x - nx * screenRadius, y: a.0.y - ny * screenRadius))
            path.addArc(center: a.0, radius: screenRadius,
                        startAngle: .radians(atan2(-ny, -nx)),
                        endAngle: .radians(atan2(ny, nx)),
                        clockwise: true)
            path.closeSubpath()

            // Насколько ось цилиндра развёрнута к свету — от этого зависит,
            // куда сместится светлая полоса вдоль тела.
            let towardsLight = nx * lightScreen.dx + ny * lightScreen.dy
            // Нормаль разворачиваем той стороной, что смотрит на свет. Иначе
            // светотень зависит от того, каким концом задана капсула: тело,
            // выписанное снизу вверх, освещалось с изнанки и читалось тёмной
            // кляксой рядом с правильно освещённым соседом.
            let facing: Double = towardsLight < 0 ? -1 : 1
            let ux = nx * facing, uy = ny * facing
            let shift = CGFloat(min(1, abs(towardsLight)))

            let litPoint = CGPoint(x: (a.0.x + b.0.x) / 2 + ux * screenRadius * shift * 0.75,
                                   y: (a.0.y + b.0.y) / 2 + uy * screenRadius * shift * 0.75)
            let darkPoint = CGPoint(x: (a.0.x + b.0.x) / 2 - ux * screenRadius * 1.15,
                                    y: (a.0.y + b.0.y) / 2 - uy * screenRadius * 1.15)

            context.fill(path,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: material.colour(1.0, 0.52 + 0.32 * material.glow),
                                       location: 0.0),
                                 .init(color: material.colour(0.66, 0.40), location: 0.45),
                                 .init(color: material.colour(0.21, 0.30), location: 1.0),
                             ]),
                             startPoint: litPoint, endPoint: darkPoint))

            // Края силуэта поперёк тела. Раскладка идёт ровно между ними,
            // поэтому ноль и единица градиента приходятся на сам контур, а не
            // на точки где-то за телом, как у заливки выше.
            let mid = CGPoint(x: (a.0.x + b.0.x) / 2, y: (a.0.y + b.0.y) / 2)
            let edgeLit = CGPoint(x: mid.x + ux * screenRadius, y: mid.y + uy * screenRadius)
            let edgeDark = CGPoint(x: mid.x - ux * screenRadius, y: mid.y - uy * screenRadius)

            // Толща за один проход: обе кромки светлее середины, в тени тлеет
            // свечение изнутри, а перед теневой кромкой идёт слабая полоса
            // отражённого света — второй блик капсулы.
            context.blendMode = .plusLighter
            context.fill(path,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: material.rim(0.62), location: 0.0),
                                 .init(color: material.rim(0.14), location: 0.13),
                                 .init(color: .clear, location: 0.30),
                                 .init(color: .clear, location: 0.56),
                                 .init(color: material.inner(0.20), location: 0.78),
                                 .init(color: material.sheen(0.13 + 0.08 * material.glow),
                                       location: 0.88),
                                 .init(color: material.rim(0.40), location: 1.0),
                             ]),
                             startPoint: edgeLit, endPoint: edgeDark))
            context.blendMode = .normal

            // Кромка по контуру: светлая с обеих сторон и притухающая посередине.
            // Прежде теневая сторона обводилась почти чёрным, и тело обрубалось
            // там силуэтом — у стекла же оно с той стороны как раз просвечивает.
            context.stroke(path,
                           with: .linearGradient(
                               Gradient(stops: [
                                   .init(color: material.rim(0.70), location: 0.0),
                                   .init(color: material.colour(0.52, 0.30), location: 0.52),
                                   .init(color: material.rim(0.30), location: 1.0),
                               ]),
                               startPoint: edgeLit, endPoint: edgeDark),
                           style: StrokeStyle(lineWidth: max(lineWidth, screenRadius * 0.10),
                                              lineJoin: .round))
        }
    }

    // MARK: - Диск в вертикальной плоскости

    /// Круг, обращённый к зрителю: динамик колонки, мембрана барабана, корпус гитары.
    /// Раньше вместо него ставились сферы, и динамики выпирали из корпуса шарами.
    static func faceDisc(centre: (Double, Double, Double),
                         radius: Double,
                         material: Material,
                         project: Projection,
                         lineWidth: Double,
                         dish: Double = 0.55,
                         squash: Double = 1.0) -> Piece
    {
        let projected = project(centre.0, centre.1, centre.2)
        let screenRadius = radius * projected.1
        // Глухость — как у ящика и цилиндра: пластик барабана и диффузор
        // динамика показывали сквозь себя заднюю стенку корпуса, на которую
        // они надеты.
        let dense = min(1, max(0, (material.opacity - 1) / 0.3))

        return Piece(depth: projected.2 - 0.0001) { context in
            guard screenRadius > 0.3 else { return }
            let rect = CGRect(x: projected.0.x - screenRadius,
                              y: projected.0.y - screenRadius * squash,
                              width: screenRadius * 2,
                              height: screenRadius * 2 * squash)

            // Вогнутость: свет собирается не в центре, а смещён к источнику,
            // и к краю уходит в тень — так читается воронка динамика.
            let lit = CGPoint(x: projected.0.x + lightScreen.dx * screenRadius * dish,
                              y: projected.0.y + lightScreen.dy * screenRadius * dish * squash)

            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(
                             Gradient(stops: [
                                 .init(color: material.colour(
                                     0.95, (0.55 + 0.30 * material.glow) * (1 - dense) + dense),
                                       location: 0.0),
                                 .init(color: material.colour(0.45, 0.40 * (1 - dense) + dense),
                                       location: 0.55),
                                 .init(color: material.colour(0.18, 0.34 * (1 - dense) + 0.97 * dense),
                                       location: 1.0),
                             ]),
                             center: lit, startRadius: 0, endRadius: screenRadius * 1.3))

            // Теневая сторона воронки: свечение изнутри и отражённый блик
            // напротив главного. Диск бывает сплюснут, поэтому смещение по
            // вертикали берётся с тем же множителем, что и сама фигура.
            let shade = CGPoint(x: projected.0.x - lightScreen.dx * screenRadius * dish,
                                y: projected.0.y - lightScreen.dy * screenRadius * dish * squash)
            context.blendMode = .plusLighter
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(
                             Gradient(colors: [material.inner(0.18), .clear]),
                             center: shade, startRadius: 0, endRadius: screenRadius * 1.1))

            // Отражение окружающего света прижато к теневому краю воронки:
            // в середине тени его перебивает свечение изнутри.
            let ambientAt = CGPoint(x: projected.0.x - lightScreen.dx * screenRadius * 0.92,
                                    y: projected.0.y - lightScreen.dy * screenRadius * 0.92 * squash)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [material.sheen(0.15 + 0.10 * material.glow), .clear]),
                    center: ambientAt, startRadius: 0, endRadius: screenRadius * 0.56))

            // Ободок на просвет. У сплюснутого диска радиальный градиент лёг бы
            // мимо контура, поэтому толща набирается вложенными обводками: чем
            // ближе к краю, тем ярче полоса.
            let wide = screenRadius * 0.24
            context.stroke(Path(ellipseIn: rect.insetBy(dx: wide / 2, dy: wide / 2 * squash)),
                           with: .color(material.rim(0.13)),
                           style: StrokeStyle(lineWidth: wide))
            let narrow = screenRadius * 0.09
            context.stroke(Path(ellipseIn: rect.insetBy(dx: narrow / 2, dy: narrow / 2 * squash)),
                           with: .color(material.rim(0.30)),
                           style: StrokeStyle(lineWidth: narrow))
            context.blendMode = .normal

            context.stroke(Path(ellipseIn: rect),
                           with: .color(material.rim(0.52)),
                           style: StrokeStyle(lineWidth: max(lineWidth, screenRadius * 0.055)))

            // Центральный купол — мелкая деталь, по которой динамик и узнаётся.
            let dome = screenRadius * 0.30
            context.fill(
                Path(ellipseIn: CGRect(x: projected.0.x - dome,
                                       y: projected.0.y - dome * squash,
                                       width: dome * 2, height: dome * 2 * squash)),
                with: .radialGradient(
                    Gradient(colors: [material.colour(1.0, 0.70 + 0.30 * material.glow),
                                      material.colour(0.40, 0.45)]),
                    center: CGPoint(x: projected.0.x + lightScreen.dx * dome * 0.5,
                                    y: projected.0.y + lightScreen.dy * dome * 0.5),
                    startRadius: 0, endRadius: dome * 1.4))
        }
    }

    // MARK: - Цилиндр

    /// Цилиндр с вертикальной осью: боковая поверхность плюс видимая крышка.
    /// Нужен барабанам — коробка вместо них читается ящиком, а сфера мячом.
    static func cylinder(centre: (Double, Double, Double),
                         radius: Double,
                         height: Double,
                         material: Material,
                         project: Projection,
                         lineWidth: Double) -> Piece
    {
        let top = project(centre.0, centre.1 - height / 2, centre.2)
        let bottom = project(centre.0, centre.1 + height / 2, centre.2)
        // Сплюснутость крышки берётся из того, насколько наклонена камера:
        // сравниваем смещение по вертикали для точек, разнесённых по глубине.
        let probe = project(centre.0, centre.1, centre.2 + radius)
        let flatten = abs(probe.0.y - project(centre.0, centre.1, centre.2).0.y)
            / max(radius * top.1, 0.001)

        // Та же мера глухости, что и у ящика: барабанные корпуса просвечивали
        // насквозь и вся установка читалась горстью пузырей, наложенных друг
        // на друга, — у полупрозрачного цилиндра видна разом и его собственная
        // дальняя стенка, и всё, что стоит за ним.
        let dense = min(1, max(0, (material.opacity - 1) / 0.3))

        return Piece(depth: (top.2 + bottom.2) / 2) { context in
            let screenRadius = radius * top.1
            guard screenRadius > 0.4 else { return }
            let capHeight = screenRadius * max(0.12, min(1, flatten))

            // Боковая поверхность.
            var side = Path()
            side.move(to: CGPoint(x: top.0.x - screenRadius, y: top.0.y))
            side.addLine(to: CGPoint(x: bottom.0.x - screenRadius, y: bottom.0.y))
            side.addArc(center: bottom.0, radius: screenRadius,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            side.addLine(to: CGPoint(x: top.0.x + screenRadius, y: top.0.y))
            side.addArc(center: top.0, radius: screenRadius,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            side.closeSubpath()

            let lit = CGPoint(x: top.0.x + lightScreen.dx * screenRadius,
                              y: (top.0.y + bottom.0.y) / 2)
            let dark = CGPoint(x: top.0.x - lightScreen.dx * screenRadius * 1.4,
                               y: (top.0.y + bottom.0.y) / 2)
            context.fill(side,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: material.colour(
                                     1.0, (0.50 + 0.30 * material.glow) * (1 - dense) + dense),
                                       location: 0.0),
                                 .init(color: material.colour(0.60, 0.38 * (1 - dense) + dense),
                                       location: 0.5),
                                 .init(color: material.colour(0.20, 0.30 * (1 - dense) + 0.96 * dense),
                                       location: 1.0),
                             ]),
                             startPoint: lit, endPoint: dark))

            // Толща боковой поверхности. Раскладка идёт между самими кромками
            // силуэта: обе светлее середины, в тени тлеет свечение изнутри,
            // а перед теневой кромкой проходит полоса отражённого света.
            let edgeLit = CGPoint(x: top.0.x - screenRadius, y: (top.0.y + bottom.0.y) / 2)
            let edgeDark = CGPoint(x: top.0.x + screenRadius, y: (top.0.y + bottom.0.y) / 2)
            context.blendMode = .plusLighter
            context.fill(side,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: material.rim(0.58), location: 0.0),
                                 .init(color: material.rim(0.12), location: 0.14),
                                 .init(color: .clear, location: 0.32),
                                 .init(color: .clear, location: 0.58),
                                 .init(color: material.inner(0.19), location: 0.79),
                                 .init(color: material.sheen(0.12 + 0.08 * material.glow),
                                       location: 0.89),
                                 .init(color: material.rim(0.38), location: 1.0),
                             ]),
                             startPoint: edgeLit, endPoint: edgeDark))
            context.blendMode = .normal

            context.stroke(side,
                           with: .color(material.rim(0.34)),
                           style: StrokeStyle(lineWidth: max(lineWidth, screenRadius * 0.08),
                                              lineJoin: .round))

            // Крышка: она и выдаёт цилиндр.
            let cap = CGRect(x: top.0.x - screenRadius, y: top.0.y - capHeight,
                             width: screenRadius * 2, height: capHeight * 2)
            context.fill(Path(ellipseIn: cap),
                         with: .radialGradient(
                             Gradient(colors: [
                                 material.colour(
                                     1.0, (0.55 + 0.30 * material.glow) * (1 - dense) + dense),
                                 material.colour(0.55, 0.34 * (1 - dense) + 0.97 * dense),
                             ]),
                             center: CGPoint(x: cap.midX + lightScreen.dx * screenRadius * 0.4,
                                             y: cap.midY),
                             startRadius: 0, endRadius: screenRadius))
            context.stroke(Path(ellipseIn: cap),
                           with: .color(material.rim(0.58)),
                           style: StrokeStyle(lineWidth: max(lineWidth, screenRadius * 0.07)))
        }
    }

    // MARK: - Параллелепипед

    /// Освещённость боковой грани по её развороту вокруг вертикали: 0 — грань
    /// смотрит на зрителя, четверть оборота — вправо, и так по кругу.
    ///
    /// Четыре опорных значения — те же, что были прописаны граням прямо, но
    /// теперь между ними есть развёртка. Повёрнутому ящику она и нужна: без
    /// неё колонка, поставленная под углом, светилась бы так, будто стоит
    /// анфас, и разворот читался бы ошибкой рисования, а не поворотом тела.
    private static func sideBrightness(_ azimuth: Double) -> Double {
        let stops = [0.62, 0.38, 0.30, 0.78]   // перед, правая, зад, левая
        let turns = azimuth / (.pi / 2)
        let wrapped = turns - (turns / 4).rounded(.down) * 4
        let index = min(3, Int(wrapped))
        let fraction = wrapped - Double(index)
        return stops[index] + (stops[(index + 1) % 4] - stops[index]) * fraction
    }

    /// Коробка с честными гранями: каждая закрашивается по своему наклону
    /// к свету, невидимые отбрасываются по знаку площади проекции.
    ///
    /// `yaw` разворачивает ящик вокруг вертикали через его же центр. Это нужно
    /// колонкам портала: развёрнутый кабинет показывает камере сразу две грани,
    /// а у фронтального ящика видна одна, и он читается плоской карточкой.
    ///
    /// `pitch` заваливает ящик вокруг поперечной оси: положительный уводит верх
    /// от зрителя. Без него на сцене нельзя поставить наклонный предмет — а
    /// напольный монитор только наклоном и отличается от ящика: его узнают
    /// по скошенной панели, развёрнутой вверх и к музыканту.
    static func box(centre: (Double, Double, Double),
                    size: (Double, Double, Double),
                    material: Material,
                    project: Projection,
                    lineWidth: Double,
                    yaw: Double = 0,
                    pitch: Double = 0) -> Piece
    {
        let hx = size.0 / 2, hy = size.1 / 2, hz = size.2 / 2
        let cosYaw = cos(yaw), sinYaw = sin(yaw)
        let cosPitch = cos(pitch), sinPitch = sin(pitch)
        let corners: [(Double, Double, Double)] = [
            (-hx, -hy, -hz), ( hx, -hy, -hz), ( hx, -hy,  hz), (-hx, -hy,  hz),
            (-hx,  hy, -hz), ( hx,  hy, -hz), ( hx,  hy,  hz), (-hx,  hy,  hz),
        ]
        // Сначала завал вокруг поперечной оси, потом разворот вокруг вертикали:
        // в обратном порядке завал шёл бы по мировой оси, а не по собственной
        // оси ящика, и развёрнутый монитор кренился бы вбок вместо наклона назад.
        .map { ($0.0, $0.1 * cosPitch + $0.2 * sinPitch, -$0.1 * sinPitch + $0.2 * cosPitch) }
        .map { (centre.0 + $0.0 * cosYaw + $0.2 * sinYaw,
                centre.1 + $0.1,
                centre.2 - $0.0 * sinYaw + $0.2 * cosYaw) }

        let projected = corners.map { project($0.0, $0.1, $0.2) }
        let depth = projected.map(\.2).reduce(0, +) / Double(projected.count)

        // Грани: индексы вершин и относительная освещённость. У боковых она
        // берётся по мировому развороту грани — собственный разворот грани
        // минус разворот ящика.
        let front = sideBrightness(-yaw)
        let back = sideBrightness(.pi - yaw)
        // Завал перемешивает освещённость верха и торцов: заваленный назад верх
        // отворачивается от света и получает долю переднего торца, а сам торец
        // задирается к небу и получает долю верха. Без этого наклонный ящик
        // светится так, будто стоит ровно, и наклон читается ошибкой рисования.
        let tipped = min(1, abs(sinPitch))
        let up = sinPitch >= 0 ? front : back
        let down = sinPitch >= 0 ? back : front
        let faces: [(indices: [Int], brightness: Double)] = [
            ([0, 1, 2, 3], 1.00 + (up - 1.00) * tipped),   // верх — ловит свет сильнее всего
            ([4, 5, 6, 7], 0.16 + (down - 0.16) * tipped), // низ
            ([3, 2, 6, 7], front + ((sinPitch >= 0 ? 1.00 : 0.16) - front) * tipped),  // перед
            ([0, 1, 5, 4], back + ((sinPitch >= 0 ? 0.16 : 1.00) - back) * tipped),    // зад
            ([0, 3, 7, 4], sideBrightness(1.5 * .pi - yaw)),      // левая, к свету
            ([1, 2, 6, 5], sideBrightness(0.5 * .pi - yaw)),      // правая
        ]

        // Насколько тело глухое. У стекла (opacity около половины) заливка граней
        // остаётся полупрозрачной и толща работает на просвет; у аппаратуры
        // (opacity больше единицы) она догоняется до глухой. Без этого ящик
        // показывал разом все свои задние рёбра: заливка грани доходила от силы
        // до двух третей, и кабинет колонки читался стеклянным каркасом, внутри
        // которого висят динамики, а стопка из двух кабинетов — одним ящиком,
        // сквозь который просвечивает второй.
        let dense = min(1, max(0, (material.opacity - 1) / 0.3))

        return Piece(depth: depth) { context in
            // Грани рисуются от дальних к ближним. Отбраковка по знаку площади
            // зависела от порядка вершин и для части граней срабатывала ложно —
            // у выпуклого тела порядок по глубине даёт верный результат сам собой.
            let ordered = faces.sorted { first, second in
                let firstDepth = first.indices.map { projected[$0].2 }.reduce(0, +)
                let secondDepth = second.indices.map { projected[$0].2 }.reduce(0, +)
                return firstDepth > secondDepth
            }

            for face in ordered {
                let points = face.indices.map { projected[$0].0 }
                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()

                // Дальний край грани уходит глубже прежнего: светящаяся полоса
                // вдоль рёбер читается толщей только против тёмной середины —
                // на ровно залитой грани она выглядит нарисованной рамкой.
                let bounds = path.boundingRect
                let near = (0.46 + 0.26 * material.glow) * (1 - dense) + dense
                let far = 0.32 * (1 - dense) + 0.94 * dense
                context.fill(path,
                             with: .linearGradient(
                                 Gradient(colors: [
                                     material.colour(face.brightness, near),
                                     material.colour(face.brightness * 0.42, far),
                                 ]),
                                 startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                 endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))

                // Свечение изнутри ровное по грани: у плоской грани нет своей
                // кривизны, светится не она, а толща за ней — и тем заметнее,
                // чем меньше грани досталось прямого света.
                let shadowed = max(0, 1 - face.brightness)
                context.blendMode = .plusLighter
                context.fill(path, with: .color(material.inner(0.24 * shadowed)))

                // Отражённый свет приходит с угла, противоположного источнику:
                // светит сверху-слева, значит подъём — к нижнему правому углу.
                // Достаётся он только теневым граням: подними им и освещённые,
                // и ящик потеряет перепад от грани к грани, на котором держится
                // его форма.
                context.fill(path,
                             with: .linearGradient(
                                 Gradient(colors: [
                                     .clear,
                                     material.sheen((0.06 + 0.06 * material.glow) * shadowed),
                                 ]),
                                 startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                 endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))

                // Полоса на просвет вдоль рёбер грани. Обводка вдвое шире
                // нужной кладётся в обрезке по самой грани, поэтому наружу
                // ничего не выходит: у стекла светится толща внутри тела,
                // а не ореол вокруг него.
                let band = min(bounds.width, bounds.height) * 0.055
                var inside = context
                inside.clip(to: path)
                inside.stroke(path, with: .color(material.rim(0.09)),
                              style: StrokeStyle(lineWidth: band * 2, lineJoin: .round))
                context.blendMode = .normal

                context.stroke(path,
                               with: .color(material.rim(0.44)),
                               style: StrokeStyle(lineWidth: max(lineWidth, band * 0.40),
                                                  lineJoin: .round))
            }
        }
    }

    // MARK: - Контактная тень

    /// Мягкая тень на плоскости под телом. Без неё фигура висит в воздухе,
    /// сколько бы объёма ни было в ней самой.
    ///
    /// На чёрном подиуме одного затемнения мало: умножать почти нечего, и тень
    /// пропадает целиком — вместе с ней пропадает и опора, отчего вся сцена
    /// висела в воздухе. Поэтому под телом сначала кладётся тёплое пятно
    /// подсвета вокруг точки опоры, и только в него — тёмное ядро. Читается
    /// контакт именно перепадом: пол рядом с ногой светлее, под самой ногой
    /// темнее. Свет отражённый, поэтому пятно шире тени и много слабее.
    ///
    /// `drift` уводит тень из-под тела в сторону, противоположную свету. Под
    /// ногой это не нужно — нога тоньше своего пятна, и тень видна вокруг неё
    /// сама. А под глухим ящиком нужно: камера смотрит сверху, ящик накрывает
    /// собственное основание целиком, и ровно посаженная тень пропадает под
    /// ним без остатка. Стек портала от этого висел в воздухе, хотя стоял на
    /// полу честно, всеми четырьмя углами.
    static func contactShadow(at position: (Double, Double),
                              radius: Double,
                              strength: Double,
                              project: Projection,
                              drift: Double = 0) -> Piece
    {
        let projected = project(position.0, 0, position.1)
        let screenRadius = radius * projected.1
        let shift = CGPoint(x: projected.0.x - lightScreen.dx * screenRadius * drift,
                            y: projected.0.y - lightScreen.dy * screenRadius * drift)
        // Сплюснутость пятна берётся у самой проекции, а не назначается числом.
        // Круг, лежащий на полу, эта камера показывает почти круглым — она
        // смотрит на сцену сверху. Назначенное вручную блюдце вчетверо площе
        // честного, и вместо пятна под ногами выходила щель за пятками: носки
        // и вынесенная вперёд стопа оставались за его краем, а фигура над ним —
        // подвешенной.
        let flatten = abs(project(position.0, 0, position.1 + radius).0.y - projected.0.y)
            / max(screenRadius, 0.001)

        /// Эллипс пятна: по горизонтали радиус как есть, по вертикали — с той
        /// же сплюснутостью, с какой камера кладёт на пол круг.
        func disc(_ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: shift.x - r, y: shift.y - r * flatten,
                                   width: r * 2, height: r * flatten * 2))
        }

        return Piece(depth: projected.2 + 0.001) { context in
            let pool = screenRadius * 1.7
            context.blendMode = .plusLighter
            context.fill(
                disc(pool),
                with: .radialGradient(
                    // Раскладка гаснет к 0.78, а не к единице: заливка круглая,
                    // а пятно сплюснуто, и на его верхнем и нижнем краю до
                    // конца раскладки дело не доходит — при обрыве на единице
                    // там оставалась бы срезанная поперёк полоса.
                    Gradient(stops: [
                        .init(color: Color(hue: 0.085, saturation: 0.62, brightness: 1)
                            .opacity(0.105 * strength), location: 0.0),
                        .init(color: Color(hue: 0.075, saturation: 0.72, brightness: 1)
                            .opacity(0.047 * strength), location: 0.42),
                        .init(color: .clear, location: 0.78),
                    ]),
                    center: shift, startRadius: 0, endRadius: pool))

            context.blendMode = .multiply
            context.fill(
                disc(screenRadius),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .black.opacity(0.55 * strength), location: 0.0),
                        .init(color: .black.opacity(0.20 * strength), location: 0.44),
                        .init(color: .clear, location: 0.78),
                    ]),
                    center: shift, startRadius: 0, endRadius: screenRadius))
            context.blendMode = .normal
        }
    }
}
