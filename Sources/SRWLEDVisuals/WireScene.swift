import SwiftUI

/// Проволочная сфера, которую деформирует спектр.
///
/// Здесь сознательно один объект и ничего больше. Прошлая версия набирала эффекты —
/// сетку, туннель, звёзды, развёртку, вспышки — и они спорили друг с другом,
/// превращая кадр в свалку. Чистая форма читается лучше любого набора приёмов.
///
/// Объём держится на затухании: дальняя сторона сферы гаснет и истончается, ближняя
/// плотнее и ярче. Это честный признак глубины, и он не требует свечения — поэтому
/// в кадре нет ни одного пересвета, только тонкие линии на глубоком фоне.
public struct WireScene: View {
    public typealias Sampler = () -> [Float]

    private let sampler: Sampler
    private let isRunning: Bool
    private let palette: Palette
    /// Свой тон вместо палитрового. Столбики — единственное, что человек
    /// правит на глаз прямо во время музыки, и ползунок тона под сценой
    /// обязан доходить до них, не проходя через набор готовых гамм.
    /// `nil` — брать тон из палитры.
    private let tint: Double?

    /// Тона сцены: свой, если задан. Свой тон разводится в вилку той же
    /// ширины, что и у палитры, — на одном тоне столбики теряют перепад
    /// между тихой и громкой полосой, на котором держится вся картинка.
    private var hues: (deep: Double, hot: Double) {
        guard let tint else { return palette.hues }
        return (tint - 0.037, tint + 0.038)
    }


    @State private var smoother = SpectrumSmoother()

    public init(sampler: @escaping Sampler,
                isRunning: Bool,
                palette: Palette = .amber,
                tint: Double? = nil)
    {
        self.sampler = sampler
        self.isRunning = isRunning
        self.palette = palette
        self.tint = tint
    }

    /// Параллелей и точек на каждой. Меридианы берутся из тех же точек,
    /// поэтому сетка получается связной без второго прохода.
    private static let latitudes = 26
    private static let segments = 84
    private static let meridianStep = 7

    /// Глубина разбивается на слои: линии одного слоя рисуются одной обводкой.
    /// Так на кадр приходится полтора десятка вызовов вместо двух тысяч.
    private static let depthLayers = 14

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas(rendersAsynchronously: true) { context, size in
                smoother.step(target: sampler(), time: time)
                draw(&context, size: size, time: time)
            }
        }
        .background(Color(red: 0.026, green: 0.024, blue: 0.032))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        let energy = smoother.energy
        let hues = self.hues

        // Очень сдержанное свечение позади — только чтобы сфера не висела в пустоте.
        let glowRadius = base * (0.34 + 0.10 * energy)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glowRadius, y: centre.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hue: hues.deep,
                                       saturation: palette.saturation * 0.8,
                                       brightness: 1).opacity(0.07 + 0.13 * energy),
                          location: 0),
                    .init(color: .clear, location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: glowRadius))

        let radius = base * 0.37
        let spin = time * 0.13
        let tilt = 0.36
        let focal = base * 2.2
        let distance = base * 2.3

        let cosSpin = cos(spin), sinSpin = sin(spin)
        let cosTilt = cos(tilt), sinTilt = sin(tilt)

        /// Радиус в точке сферы. Каждая параллель слушает свою полосу, а бегущая
        /// по долготе волна не даёт форме застыть.
        func displaced(_ latitude: Int, _ theta: Double) -> Double {
            let phi = Double.pi * (Double(latitude) + 0.5) / Double(Self.latitudes)
            let bandIndex = min(15, latitude * 16 / Self.latitudes)
            let value = bandIndex < smoother.values.count ? smoother.values[bandIndex] : 0
            let wave = sin(theta * 2 - time * 1.15 + Double(latitude) * 0.28) * 0.5 + 0.5

            // У полюсов деформацию гасим: там сходятся все меридианы, и любое
            // смещение сминает их в узел — ровно та неопрятность, которой быть не должно.
            let taper = pow(sin(phi), 1.4)
            return radius * (0.78 + 0.46 * value * (0.40 + 0.60 * wave) * taper)
        }

        /// Точка сферы: экранные координаты и глубина от нуля (дальше) до единицы (ближе).
        func point(_ latitude: Int, _ theta: Double) -> (CGPoint, Double) {
            let phi = Double.pi * (Double(latitude) + 0.5) / Double(Self.latitudes)
            let r = displaced(latitude, theta)

            let sinPhi = sin(phi)
            var x = sinPhi * cos(theta) * r
            let y0 = cos(phi) * r
            var z = sinPhi * sin(theta) * r

            let rx = x * cosSpin + z * sinSpin
            let rz = -x * sinSpin + z * cosSpin
            x = rx; z = rz

            let ty = y0 * cosTilt - z * sinTilt
            let tz = y0 * sinTilt + z * cosTilt

            let scale = focal / max(tz + distance, 1)
            let nearness = 1 - (tz / radius + 1) / 2      // 1 у зрителя, 0 в глубине
            return (CGPoint(x: centre.x + x * scale, y: centre.y + ty * scale),
                    min(1, max(0, nearness)))
        }

        // Собираем отрезки в слои по глубине.
        var layers = [Path](repeating: Path(), count: Self.depthLayers)

        func addSegment(_ from: CGPoint, _ to: CGPoint, depth: Double) {
            let layer = min(Self.depthLayers - 1, max(0, Int(depth * Double(Self.depthLayers))))
            layers[layer].move(to: from)
            layers[layer].addLine(to: to)
        }

        // Параллели.
        for latitude in 0..<Self.latitudes {
            var previous = point(latitude, 0)
            for step in 1...Self.segments {
                let theta = Double(step) / Double(Self.segments) * 2 * .pi
                let current = point(latitude, theta)
                addSegment(previous.0, current.0, depth: (previous.1 + current.1) / 2)
                previous = current
            }
        }

        // Меридианы — реже параллелей, иначе сетка становится глухой.
        for step in stride(from: 0, to: Self.segments, by: Self.meridianStep) {
            let theta = Double(step) / Double(Self.segments) * 2 * .pi
            var previous = point(0, theta)
            for latitude in 1..<Self.latitudes {
                let current = point(latitude, theta)
                addSegment(previous.0, current.0, depth: (previous.1 + current.1) / 2)
                previous = current
            }
        }

        // Рисуем от дальних слоёв к ближним.
        for (index, path) in layers.enumerated() {
            let depth = Double(index) / Double(Self.depthLayers - 1)

            // Дальние линии тоньше и почти прозрачны, ближние плотнее.
            // Верхний предел непрозрачности намеренно ниже единицы: белых пересветов быть не должно.
            let alpha = (0.10 + 0.78 * pow(depth, 1.6)) * (0.50 + 0.50 * energy)
            let width = base * (0.0008 + 0.0020 * depth)

            let hue = hues.deep + (hues.hot - hues.deep) * depth
            context.stroke(path,
                           with: .color(Color(hue: hue,
                                              saturation: palette.saturation * (0.75 - 0.30 * depth),
                                              brightness: 0.92 + 0.08 * depth).opacity(alpha)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }
}
