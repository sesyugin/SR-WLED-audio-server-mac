import SwiftUI

/// Сцена в центре венца: подиум, колонки и группа музыкантов изо льда.
///
/// Фигуры собраны из объёмных тел — сфер, капсул и коробок, заданных в трёхмерных
/// координатах. Прежняя версия рисовала плоские силуэты, и никакая отделка не могла
/// сделать их объёмными: у плоского контура нет нормали, а значит нечему ловить свет.
/// Здесь у каждого тела своя светотень, а все тела сортируются по глубине общим
/// списком, поэтому рука заходит за корпус, а корпус за колонку.
///
/// Лёд намеренно холодный независимо от гаммы сцены: тёплые лампы вокруг и холодные
/// фигуры в центре дают контраст, на котором держится картинка.
struct GlassStage {
    let palette: Palette
    /// Общая громкость: от неё зависит накал льда.
    let energy: Double
    /// Бас: от него дышат колонки и бочка.
    let bass: Double
    /// Верхние частоты: от них вспыхивают блики.
    let air: Double
    let beat: Double

    private func ice(glow: Double) -> Solid3D.Material {
        Solid3D.Material(hue: 0.545, saturation: 0.62, glow: min(1, glow), opacity: 0.46)
    }

    func draw(_ context: inout GraphicsContext,
              project: @escaping Solid3D.Projection,
              radius: Double,
              maxHeight: Double,
              base: Double)
    {
        let line = max(0.4, base * 0.0009)
        drawPodium(&context, project: project, radius: radius, base: base)

        // Рост фигур задан в долях высоты венца, положение — в долях его радиуса.
        // Знак z: положительный уходит от зрителя.
        let stand = maxHeight * 1.05
        var pieces: [Solid3D.Piece] = []

        // Положения заданы в долях радиуса венца и переводятся в мировые единицы.
        // Без перевода вся группа схлопывается в точку посреди сцены.
        func place(_ x: Double, _ z: Double) -> (Double, Double) {
            (x * radius, z * radius)
        }

        pieces += drummer(at: place(0.00, 0.42), height: stand * 0.34,
                          project: project, line: line)
        pieces += speaker(at: place(-0.66, 0.18), height: stand * 0.40,
                          project: project, line: line)
        pieces += speaker(at: place( 0.66, 0.18), height: stand * 0.40,
                          project: project, line: line)
        pieces += guitarist(at: place(-0.30, -0.04), height: stand * 0.44,
                            project: project, line: line)
        pieces += keyboardist(at: place(0.30, -0.02), height: stand * 0.42,
                              project: project, line: line)
        pieces += vocalist(at: place(0.00, -0.32), height: stand * 0.50,
                           project: project, line: line)

        // Общая сортировка: без неё тела накладываются в порядке создания
        // и объём рассыпается.
        pieces.sort { $0.depth > $1.depth }
        for piece in pieces {
            piece.render(&context)
        }
    }

    // MARK: - Подиум

    private func drawPodium(_ context: inout GraphicsContext,
                            project: Solid3D.Projection,
                            radius: Double,
                            base: Double)
    {
        let podiumRadius = radius * 0.72
        var disc = Path()
        for step in 0...120 {
            let theta = Double(step) / 120 * 2 * .pi
            let point = project(cos(theta) * podiumRadius, 0, sin(theta) * podiumRadius).0
            if step == 0 { disc.move(to: point) } else { disc.addLine(to: point) }
        }
        disc.closeSubpath()

        let bounds = disc.boundingRect
        context.fill(disc,
                     with: .linearGradient(
                         Gradient(colors: [
                             Color(hue: 0.545, saturation: 0.25, brightness: 1)
                                 .opacity(0.020 + 0.026 * energy),
                             Color(hue: 0.545, saturation: 0.5, brightness: 1).opacity(0.005),
                         ]),
                         startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                         endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))

        context.blendMode = .plusLighter
        context.stroke(disc,
                       with: .color(Color(hue: 0.545, saturation: 0.22, brightness: 1)
                           .opacity(0.16 + 0.22 * energy)),
                       style: StrokeStyle(lineWidth: max(0.5, base * 0.0010)))
        context.blendMode = .normal
    }

    // MARK: - Общая анатомия
    //
    // Все фигуры собраны по одной схеме и отличаются позой и реквизитом.
    // Размеры заданы в долях роста, поэтому пропорции не плывут при любом масштабе.

    private func body(at foot: (Double, Double),
                      height h: Double,
                      glow: Double,
                      project: @escaping Solid3D.Projection,
                      line: Double,
                      lean: Double = 0) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let material = ice(glow: glow)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.26,
                                            strength: 0.55, project: project))

        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.capsule(
                from: (x + side * h * 0.075, 0, z),
                to: (x + side * h * 0.055, -h * 0.46, z + lean * h * 0.04),
                radius: h * 0.042, material: material, project: project, lineWidth: line))
        }

        // Корпус двумя капсулами: нижняя шире, верхняя уже — так читаются плечи.
        pieces.append(Solid3D.capsule(
            from: (x, -h * 0.42, z + lean * h * 0.03),
            to: (x, -h * 0.63, z + lean * h * 0.05),
            radius: h * 0.076, material: material, project: project, lineWidth: line))
        pieces.append(Solid3D.capsule(
            from: (x, -h * 0.60, z + lean * h * 0.05),
            to: (x, -h * 0.76, z + lean * h * 0.06),
            radius: h * 0.068, material: material, project: project, lineWidth: line))

        pieces.append(Solid3D.capsule(
            from: (x, -h * 0.76, z + lean * h * 0.06),
            to: (x, -h * 0.83, z + lean * h * 0.06),
            radius: h * 0.028, material: material, project: project, lineWidth: line))
        pieces.append(Solid3D.sphere(
            centre: (x, -h * 0.90, z + lean * h * 0.06),
            radius: h * 0.066, material: material, project: project, lineWidth: line))

        return pieces
    }

    private func arm(shoulder: (Double, Double, Double),
                     elbow: (Double, Double, Double),
                     hand: (Double, Double, Double),
                     thickness: Double,
                     glow: Double,
                     project: @escaping Solid3D.Projection,
                     line: Double) -> [Solid3D.Piece]
    {
        let material = ice(glow: glow)
        return [
            Solid3D.capsule(from: shoulder, to: elbow, radius: thickness,
                            material: material, project: project, lineWidth: line),
            Solid3D.capsule(from: elbow, to: hand, radius: thickness * 0.85,
                            material: material, project: project, lineWidth: line),
        ]
    }

    // MARK: - Фигуры

    private func vocalist(at foot: (Double, Double), height h: Double,
                          project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let glow = 0.35 + 0.65 * energy
        var pieces = body(at: foot, height: h, glow: glow, project: project, line: line)

        // Рука вскинута вверх; на ударе поднимается ещё выше.
        let lift = h * (0.02 + 0.05 * beat)
        pieces += arm(shoulder: (x - h * 0.085, -h * 0.72, z),
                      elbow: (x - h * 0.20, -h * 0.86, z - h * 0.02),
                      hand: (x - h * 0.24, -h * 1.06 - lift, z - h * 0.03),
                      thickness: h * 0.040, glow: glow, project: project, line: line)

        pieces += arm(shoulder: (x + h * 0.085, -h * 0.72, z),
                      elbow: (x + h * 0.17, -h * 0.60, z - h * 0.04),
                      hand: (x + h * 0.07, -h * 0.80, z - h * 0.07),
                      thickness: h * 0.038, glow: glow, project: project, line: line)

        pieces.append(Solid3D.capsule(
            from: (x + h * 0.07, -h * 0.80, z - h * 0.07),
            to: (x + h * 0.05, -h * 0.88, z - h * 0.08),
            radius: h * 0.020,
            material: Solid3D.Material(hue: 0.545, saturation: 0.10,
                                       glow: 0.6 + 0.4 * energy, opacity: 0.60),
            project: project, lineWidth: line))

        return pieces
    }

    private func guitarist(at foot: (Double, Double), height h: Double,
                           project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let glow = 0.28 + 0.55 * energy
        var pieces = body(at: foot, height: h, glow: glow, project: project, line: line)

        pieces += arm(shoulder: (x - h * 0.085, -h * 0.70, z),
                      elbow: (x - h * 0.15, -h * 0.56, z - h * 0.06),
                      hand: (x - h * 0.02, -h * 0.50, z - h * 0.10),
                      thickness: h * 0.036, glow: glow, project: project, line: line)
        pieces += arm(shoulder: (x + h * 0.085, -h * 0.70, z),
                      elbow: (x + h * 0.16, -h * 0.58, z - h * 0.05),
                      hand: (x + h * 0.20, -h * 0.42, z - h * 0.10),
                      thickness: h * 0.036, glow: glow, project: project, line: line)

        let guitar = Solid3D.Material(hue: 0.545, saturation: 0.16,
                                      glow: 0.5 + 0.5 * air, opacity: 0.55)
        pieces.append(Solid3D.box(
            centre: (x - h * 0.04, -h * 0.46, z - h * 0.12),
            size: (h * 0.24, h * 0.20, h * 0.05),
            material: guitar, project: project, lineWidth: line))
        pieces.append(Solid3D.capsule(
            from: (x + h * 0.06, -h * 0.47, z - h * 0.12),
            to: (x + h * 0.34, -h * 0.38, z - h * 0.12),
            radius: h * 0.017, material: guitar, project: project, lineWidth: line))

        return pieces
    }

    private func keyboardist(at foot: (Double, Double), height h: Double,
                             project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let glow = 0.26 + 0.5 * energy
        var pieces = body(at: foot, height: h, glow: glow, project: project, line: line)

        for side in [-1.0, 1.0] {
            pieces += arm(shoulder: (x + side * h * 0.085, -h * 0.70, z),
                          elbow: (x + side * h * 0.15, -h * 0.56, z - h * 0.05),
                          hand: (x + side * h * 0.13, -h * 0.44, z - h * 0.16),
                          thickness: h * 0.036, glow: glow, project: project, line: line)
        }

        pieces.append(Solid3D.box(
            centre: (x, -h * 0.40, z - h * 0.20),
            size: (h * 0.46, h * 0.035, h * 0.14),
            material: Solid3D.Material(hue: 0.545, saturation: 0.14,
                                       glow: 0.45 + 0.55 * air, opacity: 0.55),
            project: project, lineWidth: line))
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.capsule(
                from: (x + side * h * 0.18, 0, z - h * 0.20),
                to: (x + side * h * 0.18, -h * 0.39, z - h * 0.20),
                radius: h * 0.012, material: ice(glow: 0.2),
                project: project, lineWidth: line))
        }

        return pieces
    }

    private func drummer(at foot: (Double, Double), height h: Double,
                         project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let glow = 0.30 + 0.6 * energy
        // Барабанщик сидит, поэтому корпус ниже и наклонён вперёд.
        var pieces = body(at: foot, height: h * 0.82, glow: glow,
                          project: project, line: line, lean: -0.4)

        let drum = Solid3D.Material(hue: 0.545, saturation: 0.18,
                                    glow: 0.4 + 0.6 * bass, opacity: 0.52)

        pieces.append(Solid3D.box(
            centre: (x, -h * 0.20, z - h * 0.30),
            size: (h * 0.40, h * 0.40, h * 0.26),
            material: drum, project: project, lineWidth: line))
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.sphere(
                centre: (x + side * h * 0.38, -h * 0.34, z - h * 0.18),
                radius: h * 0.12, material: drum, project: project, lineWidth: line))
        }

        let raise = h * (0.06 + 0.12 * beat)
        for side in [-1.0, 1.0] {
            pieces.append(Solid3D.capsule(
                from: (x + side * h * 0.14, -h * 0.56, z - h * 0.14),
                to: (x + side * h * 0.34, -h * 0.66 - raise, z - h * 0.22),
                radius: h * 0.013,
                material: Solid3D.Material(hue: 0.545, saturation: 0.06,
                                           glow: 0.5 + 0.5 * beat, opacity: 0.65),
                project: project, lineWidth: line))
        }

        return pieces
    }

    private func speaker(at foot: (Double, Double), height h: Double,
                         project: @escaping Solid3D.Projection, line: Double) -> [Solid3D.Piece]
    {
        let (x, z) = foot
        let material = Solid3D.Material(hue: 0.545, saturation: 0.20,
                                        glow: 0.30 + 0.65 * bass, opacity: 0.50)
        var pieces: [Solid3D.Piece] = []

        pieces.append(Solid3D.contactShadow(at: (x, z), radius: h * 0.34,
                                            strength: 0.6, project: project))
        pieces.append(Solid3D.box(
            centre: (x, -h * 0.50, z),
            size: (h * 0.44, h, h * 0.34),
            material: material, project: project, lineWidth: line))

        // Динамики выходят вперёд на басу.
        let push = h * 0.010 * bass
        pieces.append(Solid3D.sphere(
            centre: (x, -h * 0.30, z - h * 0.17 - push),
            radius: h * 0.13,
            material: Solid3D.Material(hue: 0.545, saturation: 0.10,
                                       glow: 0.45 + 0.55 * bass, opacity: 0.60),
            project: project, lineWidth: line))
        pieces.append(Solid3D.sphere(
            centre: (x, -h * 0.72, z - h * 0.17 - push * 0.5),
            radius: h * 0.075,
            material: Solid3D.Material(hue: 0.545, saturation: 0.10,
                                       glow: 0.40 + 0.50 * air, opacity: 0.60),
            project: project, lineWidth: line))

        return pieces
    }
}
