import SwiftUI

/// Подсветка под курсором для кнопок без системного стиля.
///
/// `.buttonStyle(.plain)` снимает с кнопки всё оформление разом — вместе
/// с состоянием под курсором. На маке щёлкаемое обязано откликаться на
/// наведение: без отклика вкладка неотличима от подписи, а строка ссылки —
/// от обычного абзаца, и человек узнаёт о кнопке только случайным щелчком.
///
/// Цвет подсветки задаётся снаружи, а не берётся из `.primary`: сцена тёмная
/// всегда, независимо от того, светлая тема в системе или тёмная, и адаптивный
/// цвет на ней в светлой теме стал бы чёрным пятном.
struct HoverFill: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var opacity: Double

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(tint.opacity(hovering ? opacity : 0),
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            // Появление быстрее исчезновения: под курсором отклик должен быть
            // мгновенным, а уход — не дёргать глаз при проходе мимо.
            .animation(.easeOut(duration: 0.10), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Подсветка на тёмной сцене и в окне «О программе».
    func hoverFillOnDark(cornerRadius: CGFloat, opacity: Double = 0.12) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius, tint: .white, opacity: opacity))
    }

    /// Подсветка в панели, которая следует теме системы.
    func hoverFill(cornerRadius: CGFloat, opacity: Double = 0.08) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius, tint: .primary, opacity: opacity))
    }
}
