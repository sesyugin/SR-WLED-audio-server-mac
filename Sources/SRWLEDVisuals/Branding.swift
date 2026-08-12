import SwiftUI

/// Фирменный стиль.
public enum Brand {
    /// Имя приложения — то, что видно в Dock, в строке меню и в списках системы.
    ///
    /// Одно слово, а не «SR-WLED-Server-Auralis-macos»: то длинное имя опознаёт
    /// файл на странице релизов, а в Dock оно обрезается многоточием на середине
    /// и не читается вовсе. Длинное имя живёт теперь только на архиве релиза.
    public static let name = "Auralis"
    public static let tagline = "Sound into light"

    /// Страница проекта. Одно место на всю программу: этот же адрес идёт в окно
    /// «О программе» и в README.
    ///
    /// Здесь стояла заглушка `https://github.com/`, и её едва не увезли в релиз —
    /// на вид рабочая ссылка, ведущая в никуда. Теперь за ней следит проверка
    /// `Ссылка на репозиторий никуда не делась`.
    public static let repository = "https://github.com/sesyugin/SR-WLED-audio-server-mac"

    /// Фирменные цвета. Один тёплый акцент и глубокий фон — та же логика,
    /// что и в визуализации: цвет один, работает яркость.
    public static let accent = Color(hue: 0.075, saturation: 0.88, brightness: 1.0)
    public static let accentDeep = Color(hue: 0.035, saturation: 0.95, brightness: 0.85)
    public static let ink = Color(red: 0.043, green: 0.035, blue: 0.055)
}

/// Знак: буква A, сложенная из светящихся полос.
///
/// A — от Auralis, а полосы — кадр эквалайзера: у знака та же природа, что
/// у всего, что программа делает. Прежний знак был волной, рассыпающейся
/// в пиксели; на шестнадцати точках в строке меню от него оставалась
/// невнятная закорючка, потому что рассыпание — эффект, а не форма.
///
/// Буква собрана из горизонтальных полос разной длины и яркости: две
/// наклонные стойки и перекладина. Полосы — не украшение: именно по ним
/// знак читается и в 16 точек, и в 1024, потому что у горизонтальной
/// полосы силуэт не портится ни при каком уменьшении.
///
/// Рисуется кодом, а не картинкой: тогда он одинаково чёткий на любом
/// размере и его не надо хранить в ресурсах.
public struct BrandMark: View {
    public var lit: Double
    public var monochrome: Bool

    public init(lit: Double = 1.0, monochrome: Bool = false) {
        self.lit = lit
        self.monochrome = monochrome
    }

    /// Сколько полос в букве — по размеру знака.
    ///
    /// Оптическое кегельное: на девяти полосах буква хороша в иконке
    /// на 512 точек, а в списке Finder на 32 просветы между ними уходят
    /// в один пиксель, треугольный просвет внутри буквы затягивается,
    /// и A читается пирамидой. Мелкий знак набирается крупнее — тремя
    /// или пятью полосами, — и остаётся буквой.
    private static func rows(for side: Double) -> Int {
        if side < 150 { return 7 }
        return 9
    }

    public var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // Буква занимает не весь квадрат: у знака должны быть поля,
            // иначе в круглой маске macOS он подходит к самой кромке.
            let height = side * 0.76
            let halfWidth = side * 0.34
            let top = centre.y - height / 2
            // Самый мелкий знак набирается не полосами вовсе. На шестнадцати
            // точках полоса — это один пиксель, просвет между ними — тоже один,
            // и любая раскладка превращается в кашу: на пробе трёхполосная
            // буква читалась буквой T на ножках. Здесь A рисуется штрихами,
            // как в шрифте, и остаётся собой.
            guard side >= 72 else {
                let bottom = top + height
                let apexHalf = halfWidth * 0.17
                let weight = side * 0.15
                let ink: Color = monochrome
                    ? .black
                    : Color(hue: 0.062, saturation: 0.80, brightness: 0.98)

                var glyph = Path()
                glyph.move(to: CGPoint(x: centre.x - halfWidth, y: bottom))
                glyph.addLine(to: CGPoint(x: centre.x - apexHalf, y: top))
                glyph.move(to: CGPoint(x: centre.x + halfWidth, y: bottom))
                glyph.addLine(to: CGPoint(x: centre.x + apexHalf, y: top))
                glyph.move(to: CGPoint(x: centre.x - halfWidth * 0.62,
                                       y: bottom - height * 0.30))
                glyph.addLine(to: CGPoint(x: centre.x + halfWidth * 0.62,
                                          y: bottom - height * 0.30))
                context.stroke(glyph, with: .color(ink),
                               style: StrokeStyle(lineWidth: weight,
                                                  lineCap: .round, lineJoin: .round))
                return
            }

            let rows = Self.rows(for: side)
            let pitch = height / Double(rows)
            // Полоса высокая, просвет тонкий: буква должна читаться сплошной
            // формой, набранной из полос, а не пунктиром. При полосе в половину
            // шага знак рассыпался на отдельные чёрточки — форму приходилось
            // додумывать, а на шестнадцати точках додумывать нечем.
            let bar = pitch * 0.68
            // Толщина штриха буквы. Задана долей ширины, а не полосы: у буквы
            // штрих один и тот же по всей высоте, иначе стойки к низу расплываются.
            let stroke = halfWidth * 0.54

            /// Полуширина буквы на своей высоте: наверху сходится в вершину,
            /// внизу расходится на всю ширину. Вершина срезана — у наборных
            /// шрифтов она такая же, а острая вырождается в точку и пропадает
            /// первой при уменьшении.
            func halfSpan(_ level: Double) -> Double {
                let apex = 0.17
                return halfWidth * (apex + (1 - apex) * level)
            }

            // Перекладина — на трети снизу, как в наборном шрифте. Выше она
            // делает букву похожей на дельту, ниже — на треугольник с юбкой.
            // Перекладина ниже середины: у трёх полос это средняя,
            // у девяти — третья снизу.
            let crossbarRow = rows <= 3 ? 1 : rows - 3

            for row in 0..<rows {
                let level = Double(row) / Double(rows - 1)
                let y = top + pitch * (Double(row) + 0.5)
                let span = halfSpan(level)

                // Яркость растёт книзу: у буквы появляется вес и опора,
                // а знак перестаёт быть плоским набором одинаковых чёрточек.
                // Ровно тем же приёмом набрана и вся визуализация — тон один,
                // работает яркость.
                let heat = 0.30 + 0.70 * level
                let tint: Color = monochrome
                    ? .black
                    : Color(hue: 0.030 + 0.062 * heat,
                            saturation: 0.96 - 0.34 * heat,
                            brightness: 0.52 + 0.48 * heat)

                var segments: [(Double, Double)] = []
                if row == crossbarRow || span * 2 <= stroke * 1.35 {
                    // Перекладина и вершина — одна сплошная полоса.
                    segments = [(-span, span)]
                } else {
                    // Ниже перекладины буква раскрыта: две стойки и просвет.
                    // Ширина стойки постоянная, но у самой вершины её подрезает
                    // сама буква — иначе стойки заходят друг за друга.
                    let width = min(stroke, span * 0.9)
                    segments = [(-span, -span + width), (span - width, span)]
                }

                for segment in segments {
                    let rect = CGRect(x: centre.x + segment.0,
                                      y: y - bar / 2,
                                      width: segment.1 - segment.0,
                                      height: bar)
                    // Скругление по высоте полосы, но не больше четверти её
                    // длины: у короткой стойки полное скругление превращает
                    // полосу в таблетку, и штрих теряет прямые бока.
                    let radius = min(bar / 2, rect.width / 4)

                    // Заливка с перепадом по высоте самой полосы: сверху она
                    // светлее, снизу глуше. Ореола нет намеренно — знак живёт
                    // на прозрачном фоне, а сложение цвета по прозрачности
                    // даёт белёсые пятна вокруг каждой полосы вместо свечения.
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: radius),
                        with: monochrome
                            ? .color(.black)
                            : .linearGradient(
                                Gradient(colors: [
                                    tint,
                                    tint.opacity(0.82),
                                ]),
                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
            }
        }
        .opacity(0.35 + 0.65 * min(1, max(0, lit)))
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

/// Полотно иконки: только знак на прозрачном фоне, без подложки.
public struct AppIconCanvas: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            BrandMark()
                .frame(width: side * 0.92, height: side * 0.92)
                .frame(width: side, height: side)
        }
    }
}
