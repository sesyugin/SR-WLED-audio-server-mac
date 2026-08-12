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

        func colour(_ brightness: Double, _ alpha: Double) -> Color {
            let level = max(0, min(1, brightness))
            return Color(hue: deepHue + (liteHue - deepHue) * level,
                         // К свету насыщенность падает мягко: золото светлеет,
                         // но не выцветает в белый — белым остаётся только блик.
                         saturation: saturation * (1 - level * 0.42),
                         brightness: 0.16 + 0.84 * pow(level, 0.85))
                .opacity(alpha * opacity)
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

            // Контровая кромка: у прозрачного тела край всегда светлее середины,
            // потому что взгляд идёт по касательной сквозь толщу.
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: lineWidth * 0.4, dy: lineWidth * 0.4)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.72),
                        .init(color: material.colour(1.0, 0.55 + 0.30 * material.glow), location: 1.0),
                    ]),
                    center: point, startRadius: 0, endRadius: screenRadius),
                style: StrokeStyle(lineWidth: lineWidth))

            // Блик: маленький и смещённый к свету.
            let specular = screenRadius * 0.24
            context.blendMode = .plusLighter
            context.fill(
                Path(ellipseIn: CGRect(x: lit.x - specular, y: lit.y - specular * 0.8,
                                       width: specular * 2, height: specular * 1.6)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.55 + 0.30 * material.glow), .clear]),
                    center: lit, startRadius: 0, endRadius: specular * 1.6))
            context.blendMode = .normal
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
                        clockwise: false)
            path.addLine(to: CGPoint(x: a.0.x - nx * screenRadius, y: a.0.y - ny * screenRadius))
            path.addArc(center: a.0, radius: screenRadius,
                        startAngle: .radians(atan2(-ny, -nx)),
                        endAngle: .radians(atan2(ny, nx)),
                        clockwise: false)
            path.closeSubpath()

            // Насколько ось цилиндра развёрнута к свету — от этого зависит,
            // куда сместится светлая полоса вдоль тела.
            let towardsLight = nx * lightScreen.dx + ny * lightScreen.dy
            let shift = CGFloat(max(-1, min(1, towardsLight)))

            let litPoint = CGPoint(x: (a.0.x + b.0.x) / 2 + nx * screenRadius * shift * 0.75,
                                   y: (a.0.y + b.0.y) / 2 + ny * screenRadius * shift * 0.75)
            let darkPoint = CGPoint(x: (a.0.x + b.0.x) / 2 - nx * screenRadius * 1.15,
                                    y: (a.0.y + b.0.y) / 2 - ny * screenRadius * 1.15)

            context.fill(path,
                         with: .linearGradient(
                             Gradient(stops: [
                                 .init(color: material.colour(1.0, 0.52 + 0.32 * material.glow),
                                       location: 0.0),
                                 .init(color: material.colour(0.66, 0.40), location: 0.45),
                                 .init(color: material.colour(0.26, 0.28), location: 1.0),
                             ]),
                             startPoint: litPoint, endPoint: darkPoint))

            // Кромка вдоль освещённой стороны — тонкая и яркая.
            context.stroke(path,
                           with: .linearGradient(
                               Gradient(colors: [
                                   material.colour(1.0, 0.60 + 0.30 * material.glow),
                                   material.colour(0.35, 0.22),
                               ]),
                               startPoint: litPoint, endPoint: darkPoint),
                           style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
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
                                 .init(color: material.colour(0.95, 0.55 + 0.30 * material.glow),
                                       location: 0.0),
                                 .init(color: material.colour(0.45, 0.40), location: 0.55),
                                 .init(color: material.colour(0.18, 0.34), location: 1.0),
                             ]),
                             center: lit, startRadius: 0, endRadius: screenRadius * 1.3))

            context.stroke(Path(ellipseIn: rect),
                           with: .color(material.colour(0.90, 0.50 + 0.25 * material.glow)),
                           style: StrokeStyle(lineWidth: lineWidth))

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
                                 .init(color: material.colour(1.0, 0.50 + 0.30 * material.glow),
                                       location: 0.0),
                                 .init(color: material.colour(0.60, 0.38), location: 0.5),
                                 .init(color: material.colour(0.24, 0.28), location: 1.0),
                             ]),
                             startPoint: lit, endPoint: dark))
            context.stroke(side,
                           with: .color(material.colour(0.85, 0.42 + 0.20 * material.glow)),
                           style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

            // Крышка: она и выдаёт цилиндр.
            let cap = CGRect(x: top.0.x - screenRadius, y: top.0.y - capHeight,
                             width: screenRadius * 2, height: capHeight * 2)
            context.fill(Path(ellipseIn: cap),
                         with: .radialGradient(
                             Gradient(colors: [
                                 material.colour(1.0, 0.55 + 0.30 * material.glow),
                                 material.colour(0.55, 0.34),
                             ]),
                             center: CGPoint(x: cap.midX + lightScreen.dx * screenRadius * 0.4,
                                             y: cap.midY),
                             startRadius: 0, endRadius: screenRadius))
            context.stroke(Path(ellipseIn: cap),
                           with: .color(material.colour(1.0, 0.50 + 0.25 * material.glow)),
                           style: StrokeStyle(lineWidth: lineWidth))
        }
    }

    // MARK: - Параллелепипед

    /// Коробка с честными гранями: каждая закрашивается по своему наклону
    /// к свету, невидимые отбрасываются по знаку площади проекции.
    static func box(centre: (Double, Double, Double),
                    size: (Double, Double, Double),
                    material: Material,
                    project: Projection,
                    lineWidth: Double) -> Piece
    {
        let hx = size.0 / 2, hy = size.1 / 2, hz = size.2 / 2
        let corners: [(Double, Double, Double)] = [
            (-hx, -hy, -hz), ( hx, -hy, -hz), ( hx, -hy,  hz), (-hx, -hy,  hz),
            (-hx,  hy, -hz), ( hx,  hy, -hz), ( hx,  hy,  hz), (-hx,  hy,  hz),
        ].map { (centre.0 + $0.0, centre.1 + $0.1, centre.2 + $0.2) }

        let projected = corners.map { project($0.0, $0.1, $0.2) }
        let depth = projected.map(\.2).reduce(0, +) / Double(projected.count)

        // Грани: индексы вершин и относительная освещённость.
        let faces: [(indices: [Int], brightness: Double)] = [
            ([0, 1, 2, 3], 1.00),   // верх — ловит свет сильнее всего
            ([4, 5, 6, 7], 0.16),   // низ
            ([3, 2, 6, 7], 0.62),   // перед
            ([0, 1, 5, 4], 0.30),   // зад
            ([0, 3, 7, 4], 0.78),   // левая, к свету
            ([1, 2, 6, 5], 0.38),   // правая
        ]

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

                let bounds = path.boundingRect
                context.fill(path,
                             with: .linearGradient(
                                 Gradient(colors: [
                                     material.colour(face.brightness, 0.46 + 0.26 * material.glow),
                                     material.colour(face.brightness * 0.55, 0.34),
                                 ]),
                                 startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                 endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))

                context.stroke(path,
                               with: .color(material.colour(min(1, face.brightness + 0.35),
                                                            0.40 + 0.22 * material.glow)),
                               style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            }
        }
    }

    // MARK: - Контактная тень

    /// Мягкая тень на плоскости под телом. Без неё фигура висит в воздухе,
    /// сколько бы объёма ни было в ней самой.
    static func contactShadow(at position: (Double, Double),
                              radius: Double,
                              strength: Double,
                              project: Projection) -> Piece
    {
        let projected = project(position.0, 0, position.1)
        let screenRadius = radius * projected.1

        return Piece(depth: projected.2 + 0.001) { context in
            context.blendMode = .multiply
            context.fill(
                Path(ellipseIn: CGRect(x: projected.0.x - screenRadius,
                                       y: projected.0.y - screenRadius * 0.34,
                                       width: screenRadius * 2, height: screenRadius * 0.68)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .black.opacity(0.55 * strength), location: 0.0),
                        .init(color: .black.opacity(0.22 * strength), location: 0.55),
                        .init(color: .clear, location: 1.0),
                    ]),
                    center: projected.0, startRadius: 0, endRadius: screenRadius))
            context.blendMode = .normal
        }
    }
}
