import Foundation

/// Сглаживание полос между кадрами.
///
/// Причина существования: обработка звука отдаёт полосы примерно 94 раза в секунду,
/// а интерфейс обновляет свои поля десять раз в секунду. Если рисовать 60 кадров,
/// но брать значения из обновляемого десять раз поля, картинка скачет ступеньками —
/// это и читается как дешёвая дёрганая анимация. Здесь значения тянутся к цели
/// непрерывно, с разными постоянными времени на рост и спад: быстро вверх, чтобы
/// удар не смазался, медленно вниз, чтобы свет красиво угасал.
public final class SpectrumSmoother {
    public private(set) var values: [Double]
    public private(set) var peaks: [Double]
    /// Общая громкость, тоже сглаженная — от неё зависит дыхание всей сцены.
    public private(set) var energy: Double = 0

    private var lastTime: TimeInterval = 0

    private let attack: Double
    private let release: Double
    private let peakRelease: Double

    public init(count: Int = 16,
                attackSeconds: Double = 0.045,
                releaseSeconds: Double = 0.38,
                peakReleaseSeconds: Double = 1.4)
    {
        values = Array(repeating: 0, count: count)
        peaks = Array(repeating: 0, count: count)
        attack = attackSeconds
        release = releaseSeconds
        peakRelease = peakReleaseSeconds
    }

    /// Подтягивает значения к целевым за прошедшее время.
    /// Шаг считается от настоящего времени, а не от номера кадра, — тогда движение
    /// не зависит от того, успела ли отрисоваться прошлая картинка.
    public func step(target: [Float], time: TimeInterval) {
        // Самый первый шаг — мгновенный: иначе картинка секунду разгорается из нуля,
        // а одиночный кадр (предпросмотр) вышел бы просто чёрным.
        let isFirst = lastTime == 0
        let delta = isFirst ? 1.0 / 60.0 : min(0.1, max(0.0001, time - lastTime))
        lastTime = time

        if isFirst {
            for index in values.indices {
                let goal = index < target.count ? min(1, max(0, Double(target[index]))) : 0
                values[index] = goal
                peaks[index] = goal
            }
            energy = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return
        }

        let attackFactor = 1 - exp(-delta / attack)
        let releaseFactor = 1 - exp(-delta / release)
        let peakFactor = 1 - exp(-delta / peakRelease)

        var sum = 0.0
        for index in values.indices {
            let goal = index < target.count ? min(1, max(0, Double(target[index]))) : 0
            let factor = goal > values[index] ? attackFactor : releaseFactor
            values[index] += (goal - values[index]) * factor

            // Пик мгновенно догоняет значение и медленно оседает.
            peaks[index] = values[index] > peaks[index]
                ? values[index]
                : peaks[index] + (values[index] - peaks[index]) * peakFactor

            sum += values[index]
        }

        let goalEnergy = values.isEmpty ? 0 : sum / Double(values.count)
        energy += (goalEnergy - energy) * (goalEnergy > energy ? attackFactor : releaseFactor)
    }
}
