import SwiftUI

/// Ползунок выбора тона: полоса всех тонов и бегунок по ней.
///
/// Своя реализация, а не системный `Slider`, по одной причине: цвет выбирают
/// глазом, а не числом. У системного ползунка дорожка серая, и человек тянет
/// бегунок вслепую, пока не совпадёт. Здесь дорожка — сам спектр, и выбор
/// делается до отпускания кнопки.
///
/// Значение `nil` означает «взять тон из палитры»: ползунок обязан уметь
/// уступать выбор готовой гамме, иначе набор палитр рядом с ним превращается
/// в кнопки без действия.
struct HueSlider: View {
    @Binding var hue: Double?
    /// Тон, который показывать, пока свой не выбран.
    let fallback: Double
    var height: CGFloat = 12

    private var shown: Double { hue ?? fallback }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let knobX = width * shown

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        // Шаг по тону мелкий: у крупного между опорами
                        // проступают полосы, и дорожка читается не спектром,
                        // а набором подкрашенных секций.
                        colors: (0...24).map {
                            Color(hue: Double($0) / 24, saturation: 0.85, brightness: 1)
                        },
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: height)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))

                // Бегунок белый с заливкой выбранного тона: на пёстрой дорожке
                // одноцветный бегунок теряется ровно на своём же тоне.
                Circle()
                    .fill(Color(hue: shown, saturation: 0.85, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .frame(width: height + 8, height: height + 8)
                    .opacity(hue == nil ? 0.45 : 1)
                    .offset(x: min(max(0, knobX - (height + 8) / 2), width - height - 8))
            }
            .frame(height: height + 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(1, max(0, value.location.x / width))
                    })
        }
        .frame(height: height + 8)
    }
}
