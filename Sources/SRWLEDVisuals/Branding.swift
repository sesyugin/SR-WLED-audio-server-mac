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
            let midY = size.height / 2
            let left = size.width * 0.5 - side * 0.40
            let right = size.width * 0.5 + side * 0.40
            let span = right - left
            let amplitude = side * 0.20
            let thickness = side * 0.085

            /// Одна волна на всю ширину знака. Слева она сплошная, справа рассыпается
            /// на отдельные светодиоды — это и есть суть программы: звук становится светом.
            func wave(_ t: Double) -> CGPoint {
                let x = left + span * t
                // Затухание к концу: волна «успокаивается» в ровную линию светодиодов.
                // Без него хвост уходил по диагонали в угол и знак заваливался.
                let damping = 1.0 - 0.88 * t * t
                let y = midY - sin(t * .pi * 2.6) * amplitude * damping
                return CGPoint(x: x, y: y)
            }

            // Сплошная часть волны — левые три пятых.
            var line = Path()
            for step in 0...60 {
                let t = Double(step) / 60 * 0.56
                let point = wave(t)
                if step == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }

            if !monochrome {
                context.blendMode = .plusLighter
                for width in stride(from: 5.0, through: 1.5, by: -0.5) {
                    context.stroke(line,
                                   with: .color(Brand.accent.opacity(0.02 * lit)),
                                   style: StrokeStyle(lineWidth: thickness * width, lineCap: .round))
                }
                context.blendMode = .normal
            }

            context.stroke(line,
                           with: monochrome
                               ? .color(.black)
                               : .linearGradient(
                                   Gradient(colors: [Brand.accentDeep, Brand.accent]),
                                   startPoint: CGPoint(x: left, y: midY),
                                   endPoint: CGPoint(x: left + span * 0.56, y: midY)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

            // Правая часть: отдельные светодиоды по той же кривой, разгорающиеся к концу.
            let pixels = 5
            for index in 0..<pixels {
                let t = 0.62 + Double(index) / Double(pixels - 1) * 0.38
                let point = wave(t)
                let progress = Double(index) / Double(pixels - 1)
                let dot = thickness * (0.58 + 0.30 * progress)

                if !monochrome {
                    context.blendMode = .plusLighter
                    let halo = dot * 3.6
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo,
                                               width: halo * 2, height: halo * 2)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Brand.accent.opacity((0.20 + 0.55 * progress) * lit),
                                      location: 0),
                                .init(color: Brand.accent.opacity(0), location: 1),
                            ]),
                            center: point, startRadius: 0, endRadius: halo))
                    context.blendMode = .normal
                }

                let tint: Color = monochrome
                    ? .black
                    : Color(hue: 0.075, saturation: 0.85 - 0.85 * progress, brightness: 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot,
                                           width: dot * 2, height: dot * 2)),
                    with: .color(tint))
            }
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
