import SwiftUI

/// Объёмная визуализация звука.
///
/// Свет собирается слоями со сложением (`plusLighter`), как настоящее свечение:
/// перекрывающиеся пятна становятся ярче и белее к центру, а не просто накладываются.
/// Всё рисуется в `Canvas` мягкими радиальными градиентами — это дешевле, чем размывать
/// настоящие вью фильтром, и держит 60 кадров в секунду без нагрева.
struct VolumetricVisualizer: View {
    let bands: [Float]
    let peaks: [Float]
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.black

                AuroraField(bands: bands, time: time)
                    .blendMode(.plusLighter)

                SpectrumRing(bands: bands, peaks: peaks, time: time)

                // Виньетка прижимает свет к центру и добавляет глубины.
                RadialGradient(colors: [.clear, .black.opacity(0.75)],
                               center: .center,
                               startRadius: 120,
                               endRadius: 520)
                    .allowsHitTesting(false)
            }
            .drawingGroup()          // всё сводится за один проход на видеокарте
        }
    }
}

// MARK: - Поле света

/// Медленно плывущие пятна света, каждое привязано к своей части спектра.
private struct AuroraField: View {
    let bands: [Float]
    let time: TimeInterval

    /// Семь пятен: бас — крупные и тёплые внизу, верх — мелкие и холодные.
    private static let blobs: [(bandRange: Range<Int>, hue: Double, drift: Double, phase: Double)] = [
        (0..<2,   0.03, 0.07, 0.0),
        (2..<4,   0.08, 0.11, 1.3),
        (4..<6,   0.12, 0.09, 2.4),
        (6..<8,   0.45, 0.13, 3.1),
        (8..<11,  0.55, 0.10, 4.2),
        (11..<14, 0.62, 0.15, 5.0),
        (14..<16, 0.72, 0.12, 5.9),
    ]

    var body: some View {
        Canvas { context, size in
            context.blendMode = .plusLighter
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height)

            for blob in Self.blobs {
                let energy = averageEnergy(in: blob.bandRange)

                // Пятно живёт даже в тишине — еле заметно, чтобы кадр не был пустым.
                let intensity = 0.06 + 0.94 * energy

                // Дрейф по эллипсу: два разных периода дают неповторяющееся движение.
                let drift = time * blob.drift
                let offsetX = cos(drift + blob.phase) * base * 0.20
                let offsetY = sin(drift * 1.37 + blob.phase) * base * 0.14

                // Радиус дышит вместе с энергией полосы.
                let radius = base * (0.16 + 0.30 * intensity)

                let colour = Color(hue: blob.hue,
                                   saturation: 0.85 - 0.25 * energy,
                                   brightness: 1.0)

                let rect = CGRect(x: centre.x + offsetX - radius,
                                  y: centre.y + offsetY - radius,
                                  width: radius * 2,
                                  height: radius * 2)

                // Мягкий край: цвет к прозрачному по кубической кривой — так пятно
                // выглядит объёмным, а не наклейкой.
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: colour.opacity(0.55 * intensity), location: 0.0),
                            .init(color: colour.opacity(0.28 * intensity), location: 0.35),
                            .init(color: colour.opacity(0.08 * intensity), location: 0.65),
                            .init(color: colour.opacity(0.0), location: 1.0),
                        ]),
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: 0,
                        endRadius: radius))
            }
        }
    }

    private func averageEnergy(in range: Range<Int>) -> Double {
        var sum = 0.0
        var count = 0
        for index in range where index < bands.count {
            sum += Double(bands[index])
            count += 1
        }
        return count > 0 ? min(1, sum / Double(count)) : 0
    }
}

// MARK: - Кольцо спектра

/// Шестнадцать лучей по кругу с подсветкой и пиковыми отметками.
///
/// Круговая раскладка выбрана не для красоты: она даёт свету исходить из одной точки,
/// а объём читается за счёт того, что каждый луч светится сам и подсвечивает соседей.
private struct SpectrumRing: View {
    let bands: [Float]
    let peaks: [Float]
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height)
            let innerRadius = base * 0.13
            let maxLength = base * 0.30
            let count = 16

            // Медленное вращение — картинка не застывает даже на ровном звуке.
            let rotation = time * 0.06

            // Ядро: яркая сердцевина, пульсирующая общей громкостью.
            let overall = bands.isEmpty ? 0 : Double(bands.reduce(0, +)) / Double(bands.count)
            let coreRadius = innerRadius * (0.72 + 0.34 * overall)
            context.blendMode = .plusLighter
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - coreRadius * 2.4,
                                       y: centre.y - coreRadius * 2.4,
                                       width: coreRadius * 4.8,
                                       height: coreRadius * 4.8)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.55 + 0.35 * overall), location: 0.0),
                        .init(color: Color(hue: 0.09, saturation: 0.7, brightness: 1)
                                .opacity(0.30 + 0.30 * overall), location: 0.28),
                        .init(color: .clear, location: 1.0),
                    ]),
                    center: centre, startRadius: 0, endRadius: coreRadius * 2.4))

            for index in 0..<count {
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let peak = index < peaks.count ? CGFloat(peaks[index]) : 0

                let angle = rotation + Double(index) / Double(count) * 2 * .pi - .pi / 2
                let hue = 0.02 + 0.62 * Double(index) / Double(count - 1)
                let colour = Color(hue: hue, saturation: 0.8, brightness: 1.0)

                let length = innerRadius * 0.2 + value * maxLength
                let thickness = base * 0.020 * (0.65 + 0.55 * value)

                let from = CGPoint(x: centre.x + cos(angle) * innerRadius,
                                   y: centre.y + sin(angle) * innerRadius)
                let to = CGPoint(x: centre.x + cos(angle) * (innerRadius + length),
                                 y: centre.y + sin(angle) * (innerRadius + length))

                // Ореол вокруг луча — то, что и делает его объёмным.
                var halo = Path()
                halo.move(to: from)
                halo.addLine(to: to)
                context.stroke(halo,
                               with: .color(colour.opacity(0.16 + 0.24 * value)),
                               style: StrokeStyle(lineWidth: thickness * 3.4, lineCap: .round))

                // Сам луч: от насыщенного у основания к белому на конце.
                context.stroke(halo,
                               with: .linearGradient(
                                   Gradient(colors: [
                                       colour.opacity(0.95),
                                       Color.white.opacity(0.55 + 0.45 * value),
                                   ]),
                                   startPoint: from, endPoint: to),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                // Пиковая отметка — короткая яркая риска на недавнем максимуме.
                if peak > 0.03 {
                    let peakDistance = innerRadius + innerRadius * 0.2 + peak * maxLength
                    let peakFrom = CGPoint(x: centre.x + cos(angle) * (peakDistance - base * 0.008),
                                           y: centre.y + sin(angle) * (peakDistance - base * 0.008))
                    let peakTo = CGPoint(x: centre.x + cos(angle) * (peakDistance + base * 0.008),
                                         y: centre.y + sin(angle) * (peakDistance + base * 0.008))
                    var mark = Path()
                    mark.move(to: peakFrom)
                    mark.addLine(to: peakTo)
                    context.stroke(mark,
                                   with: .color(.white.opacity(0.75)),
                                   style: StrokeStyle(lineWidth: thickness * 0.55, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - Плоская полоса для строки меню и компактных мест

struct SpectrumStrip: View {
    let bands: [Float]
    var barCount: Int = 16

    var body: some View {
        Canvas { context, size in
            guard barCount > 0 else { return }
            let gap: CGFloat = 1
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            guard barWidth > 0 else { return }

            for index in 0..<barCount {
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = max(1, value * size.height)
                let rect = CGRect(x: CGFloat(index) * (barWidth + gap),
                                  y: size.height - height,
                                  width: barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 3),
                             with: .color(.primary))
            }
        }
    }
}
