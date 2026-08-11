import SwiftUI

/// Фирменный стиль.
public enum Brand {
    public static let name = "Auralis"
    public static let tagline = "Sound into light"
    /// Полное имя для окна «О программе» и системных списков.
    public static let fullName = "Auralis · WLED audio server"

    /// Фирменные цвета. Один тёплый акцент и глубокий фон — та же логика,
    /// что и в визуализации: цвет один, работает яркость.
    public static let accent = Color(hue: 0.075, saturation: 0.88, brightness: 1.0)
    public static let accentDeep = Color(hue: 0.035, saturation: 0.95, brightness: 0.85)
    public static let ink = Color(red: 0.043, green: 0.035, blue: 0.055)
}

/// Знак: светодиодная лента, свёрнутая в кольцо с разрывом, и яркий пиксель на конце.
///
/// Рисуется кодом, а не картинкой: тогда он одинаково чёткий и в строке меню
/// на 16 точках, и в иконке на 1024, и его не надо хранить в ресурсах.
public struct BrandMark: View {
    public var lit: Double
    public var monochrome: Bool

    public init(lit: Double = 1.0, monochrome: Bool = false) {
        self.lit = lit
        self.monochrome = monochrome
    }

    public var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.30
            let thickness = side * 0.105

            // Разрыв справа, а не внизу: снизу он читался подковой. Так виден
            // конец ленты с ярким первым диодом.
            let start = Angle(degrees: 42)
            let end = Angle(degrees: -18)

            var arc = Path()
            arc.addArc(center: centre, radius: radius,
                       startAngle: start, endAngle: end, clockwise: false)

            // Ореол: несколько обводок с падающей прозрачностью вместо одной толстой.
            // Одна давала плотное кольцо, читавшееся вторым контуром, а не свечением.
            if !monochrome {
                context.blendMode = .plusLighter
                for step in stride(from: 6.0, through: 1.2, by: -0.4) {
                    context.stroke(arc,
                                   with: .color(Brand.accent.opacity(0.016 * lit)),
                                   style: StrokeStyle(lineWidth: thickness * step, lineCap: .round))
                }
                context.blendMode = .normal
            }

            // Тело ленты: градиент от тёплой тени к раскалённому концу.
            context.stroke(arc,
                           with: monochrome
                               ? .color(.black)
                               : .linearGradient(
                                   Gradient(colors: [Brand.accentDeep, Brand.accent, .white]),
                                   startPoint: CGPoint(x: centre.x - radius, y: centre.y + radius),
                                   endPoint: CGPoint(x: centre.x + radius, y: centre.y - radius)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

            // Яркий пиксель на конце ленты — тот самый «первый диод».
            let tip = CGPoint(x: centre.x + cos(end.radians) * radius,
                              y: centre.y - sin(end.radians) * radius)
            let dot = thickness * 0.62
            if !monochrome {
                context.blendMode = .plusLighter
                let halo = dot * 3.4
                context.fill(
                    Path(ellipseIn: CGRect(x: tip.x - halo, y: tip.y - halo,
                                           width: halo * 2, height: halo * 2)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Brand.accent.opacity(0.75 * lit), location: 0),
                            .init(color: Brand.accent.opacity(0), location: 1),
                        ]),
                        center: tip, startRadius: 0, endRadius: halo))
                context.blendMode = .normal
            }
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - dot, y: tip.y - dot,
                                       width: dot * 2, height: dot * 2)),
                with: .color(monochrome ? .black : .white))
        }
    }
}

/// Знак вместе с названием — для шапки окна и страницы «О программе».
public struct BrandLockup: View {
    public var showTagline: Bool

    public init(showTagline: Bool = true) {
        self.showTagline = showTagline
    }

    public var body: some View {
        HStack(spacing: 10) {
            BrandMark()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(.white)
                if showTagline {
                    Text(Brand.tagline)
                        .font(.system(size: 9, weight: .medium))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

/// Полотно иконки приложения: знак на фирменном тёмном фоне со свечением.
public struct AppIconCanvas: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                // Подложка со скруглением как у системных иконок, с полями по краю.
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(RadialGradient(
                        colors: [Color(hue: 0.065, saturation: 0.60, brightness: 0.26),
                                 Brand.ink],
                        center: UnitPoint(x: 0.62, y: 0.34),
                        startRadius: 0, endRadius: side * 0.85))

                BrandMark()
                    .frame(width: side * 0.78, height: side * 0.78)
            }
            .frame(width: side, height: side)
            .padding(side * 0.055)
        }
    }
}
