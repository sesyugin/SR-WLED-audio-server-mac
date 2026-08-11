import Foundation
import SRWLEDCore

// Проверки этапа M3 — динамика картинки. Меряют ровно те метрики, что записаны в плане.
// Все сигналы синтетические и детерминированные: ни звука, ни сети, ни случайности.

/// Детерминированный генератор шума — чтобы прогон был воспроизводимым.
private struct Noise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func white() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = UInt32(truncatingIfNeeded: state >> 33)
        return Float(bits) / Float(UInt32.max) * 2 - 1
    }

    // Экономичный фильтр Пола Келлета: даёт спад примерно 10 дБ на декаду.
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0

    mutating func pink() -> Float {
        let w = white()
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 0.1526913
        return (b0 + b1 + b2 + w * 0.1848) * 0.25
    }
}

private func feed(_ pipeline: AudioPipeline, _ samples: [Float]) {
    samples.withUnsafeBufferPointer { pipeline.process(interleaved: $0, channels: 2) }
}

private func toStereo(_ mono: [Float]) -> [Float] {
    var out = [Float]()
    out.reserveCapacity(mono.count * 2)
    for value in mono { out.append(value); out.append(value) }
    return out
}

private func decibels(_ ratio: Float) -> Float {
    ratio > 0 ? 20 * log10(ratio) : -120
}

func runDynamicsTests(_ t: TestRunner) {
    let sampleRate = 48000.0

    // MARK: - Дрожание полос

    t.suite("Дрожание полос на ровном звуке") { t in

        /// Коэффициент вариации значений одной полосы за много кадров.
        func jitter(smoothing: Bool) -> Float {
            var settings = Settings()
            settings.bandSmoothing = smoothing
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else { return -1 }

            var noise = Noise(seed: 777)
            var samples = [Float]()
            for _ in 0..<(512 * 400) { samples.append(noise.pink() * 0.3) }

            var series = [Float]()
            var offset = 0
            while offset + 512 <= samples.count {
                feed(pipeline, toStereo(Array(samples[offset..<(offset + 512)])))
                offset += 512
                if offset > 512 * 80 {          // даём установиться
                    series.append(pipeline.currentBands()[6])
                }
            }

            guard series.count > 10 else { return -1 }
            let mean = series.reduce(0, +) / Float(series.count)
            guard mean > 0 else { return -1 }
            let variance = series.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(series.count)
            return variance.squareRoot() / mean
        }

        t.test("Сглаживание убирает мерцание на неизменном звуке") { t in
            let withSmoothing = jitter(smoothing: true)
            let without = jitter(smoothing: false)

            t.note("дрожание полосы: со сглаживанием \(Int(withSmoothing * 100))%, " +
                   "без него \(Int(without * 100))%")
            t.expect(without > 0 && withSmoothing > 0, "не удалось измерить дрожание")
            t.expect(withSmoothing < without,
                     "сглаживание обязано уменьшать дрожание: " +
                     "\(Int(withSmoothing * 100))% против \(Int(without * 100))%")
            t.expect(withSmoothing <= 0.12,
                     "дрожание \(Int(withSmoothing * 100))% при цели не выше 12%")
        }
    }

    // MARK: - Приседание на удар

    t.suite("АРУ не гасит ленту на ударе") { t in

        /// Ровный тон 1 кГц; при `withKick` в середине прогона добавляется ОДИН басовый удар.
        ///
        /// Эталон снимается отдельным прогоном без ударов: если мерить «спокойный» уровень
        /// между частыми ударами, опора АРУ не успевает вернуться, спокойный уровень тоже
        /// занижен, и просадка съедается — именно на этом первая версия теста и врала.
        func toneBandLevels(mode: GainMode, withKick: Bool) -> (steady: Float, minimum: Float) {
            var settings = Settings()
            settings.gainMode = mode
            settings.bandSmoothing = true
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                return (0, 0)
            }

            // Полоса 7 таблицы WLED — 818…1120 Гц, туда попадает тон 1 кГц.
            let toneBand = 7
            let hop = 512
            let kickFrames = 200..<210        // один удар примерно на 107 мс

            var phase = 0.0
            var bassPhase = 0.0
            var beforeKick = [Float]()
            var duringKick = [Float]()

            for frameIndex in 0..<260 {
                let kicking = withKick && kickFrames.contains(frameIndex)
                var chunk = [Float]()
                chunk.reserveCapacity(hop)
                for _ in 0..<hop {
                    let tone = 0.15 * Float(sin(phase))
                    let bass = kicking ? 0.9 * Float(sin(bassPhase)) : 0
                    chunk.append(tone + bass)
                    phase += 2 * Double.pi * 1000 / sampleRate
                    bassPhase += 2 * Double.pi * 60 / sampleRate
                }
                feed(pipeline, toStereo(chunk))

                let value = pipeline.currentBands()[toneBand]
                // Устоявшийся уровень берём задолго до удара.
                if (150..<190).contains(frameIndex) { beforeKick.append(value) }
                // Просадку — во время удара и сразу после него.
                if (200..<230).contains(frameIndex) { duringKick.append(value) }
            }

            let steady = beforeKick.isEmpty ? 0 : beforeKick.reduce(0, +) / Float(beforeKick.count)
            return (steady, duringKick.min() ?? 0)
        }

        func duckingDepth(mode: GainMode) -> (steady: Float, dip: Float) {
            let reference = toneBandLevels(mode: mode, withKick: false)
            let kicked = toneBandLevels(mode: mode, withKick: true)
            return (reference.steady, kicked.minimum)
        }

        t.test("Удар бочки не роняет остальные полосы") { t in
            let stable = duckingDepth(mode: .stable)
            let original = duckingDepth(mode: .original)

            let stableDrop = decibels(stable.dip / max(stable.steady, 1e-6))
            let originalDrop = decibels(original.dip / max(original.steady, 1e-6))

            t.note("просадка соседней полосы на ударе: новая АРУ " +
                   "\(String(format: "%.1f", stableDrop)) дБ, старая " +
                   "\(String(format: "%.1f", originalDrop)) дБ")
            t.expect(stableDrop > originalDrop,
                     "новая АРУ обязана проседать меньше старой: " +
                     "\(String(format: "%.1f", stableDrop)) дБ против " +
                     "\(String(format: "%.1f", originalDrop)) дБ")
            t.expect(stableDrop > -2.5,
                     "просадка \(String(format: "%.1f", stableDrop)) дБ — лента заметно гаснет на ударе")
        }

        t.test("Медленная опора не стала тупой: на устойчивую смену уровня реагирует") { t in
            // Через весь конвейер это не измерить: при единственном тоне АРУ нормирует
            // по нему же, и уровень всегда около единицы независимо от громкости.
            // Поэтому проверяем саму регулировку на заданной последовательности полос.
            let fps: Float = 93.75
            let gain = GainControl(mode: .stable, floor: 0.02,
                                   attackSeconds: 1.0, releaseSeconds: 2.0,
                                   framesPerSecond: fps)

            func run(level: Float, seconds: Float) {
                for _ in 0..<Int(seconds * fps) {
                    gain.process(buckets: [Bucketizer.Bucket(value: level)])
                }
            }

            run(level: 0.4, seconds: 4)
            let settledQuiet = gain.span

            // Одиночный удар длиной ~100 мс почти не должен двигать опору.
            run(level: 1.0, seconds: 0.107)
            let afterKick = gain.span

            // А вот устойчиво громкий кусок обязан её поднять.
            run(level: 1.0, seconds: 4)
            let settledLoud = gain.span

            // И вернуть обратно, когда стало тихо.
            run(level: 0.4, seconds: 8)
            let backDown = gain.span

            t.note("опора АРУ: тихо \(String(format: "%.3f", settledQuiet)), " +
                   "после удара \(String(format: "%.3f", afterKick)), " +
                   "громко \(String(format: "%.3f", settledLoud)), " +
                   "снова тихо \(String(format: "%.3f", backDown))")

            t.expect(abs(afterKick - settledQuiet) < 0.1,
                     "одиночный удар сдвинул опору с \(String(format: "%.3f", settledQuiet)) " +
                     "до \(String(format: "%.3f", afterKick)) — отсюда и берётся приседание")
            t.expect(settledLoud > 0.9,
                     "на устойчиво громком опора обязана дойти до уровня сигнала, " +
                     "вышло \(String(format: "%.3f", settledLoud))")
            t.expect(backDown < 0.55,
                     "после возврата к тихому опора обязана опуститься, " +
                     "вышло \(String(format: "%.3f", backDown))")
        }

        t.test("В паузе усиление не раскручивается до упора") { t in
            var settings = Settings()
            settings.gainMode = .stable
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не создалась обработка"); return
            }

            // Очень тихий фоновый шум — примерно -66 dBFS.
            var noise = Noise(seed: 4242)
            for _ in 0..<300 {
                var chunk = [Float]()
                for _ in 0..<512 { chunk.append(noise.white() * 0.0005) }
                feed(pipeline, toStereo(chunk))
            }

            let bands = pipeline.currentPacket().fftBins
            let brightest = bands.max() ?? 0
            t.expect(brightest < 100,
                     "на фоновом шуме полосы вышли на \(brightest) из 254 — усиление раскрутилось")
        }
    }

    // MARK: - Ровность полос

    t.suite("Ровность полос на розовом шуме") { t in

        func bandSpreadDB(aggregation: BandAggregation) -> Float {
            var settings = Settings()
            settings.aggregation = aggregation
            settings.bandSmoothing = true
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else { return 999 }

            var noise = Noise(seed: 31337)
            for _ in 0..<400 {
                var chunk = [Float]()
                for _ in 0..<512 { chunk.append(noise.pink() * 0.5) }
                feed(pipeline, toStereo(chunk))
            }

            // Края отбрасываем: нижняя полоса упирается в шумовой пол генератора,
            // верхняя — в спад фильтра розового шума.
            let bands = Array(pipeline.currentBands()[1..<15])
            guard let high = bands.max(), let low = bands.min(), low > 0 else { return 999 }
            return decibels(high / low)
        }

        t.test("Агрегация по энергии ровнее, чем максимум по бинам") { t in
            let energy = bandSpreadDB(aggregation: .energy)
            let maximum = bandSpreadDB(aggregation: .maximum)

            t.note("разброс полос на розовом шуме: по энергии " +
                   "\(String(format: "%.1f", energy)) дБ, по максимуму " +
                   "\(String(format: "%.1f", maximum)) дБ")
            t.expect(energy < maximum,
                     "энергия обязана давать более ровную картину: " +
                     "\(String(format: "%.1f", energy)) дБ против \(String(format: "%.1f", maximum)) дБ")
            t.expect(energy < 12,
                     "разброс полос \(String(format: "%.1f", energy)) дБ — картинка заметно перекошена")
        }
    }

    // MARK: - Задержка

    t.suite("Задержка от звука до пакета") { t in

        /// Сколько миллисекунд проходит от начала тона до момента, когда полоса
        /// перешла половину установившегося значения.
        func latencyMilliseconds(slide: Int) -> Float {
            var settings = Settings()
            settings.frameSlide = slide
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else { return 999 }

            // Сначала тишина, чтобы всё улеглось.
            for _ in 0..<40 {
                feed(pipeline, toStereo([Float](repeating: 0, count: slide)))
            }

            // Затем ровный тон 1 кГц. Считаем кадры до перехода половины уровня.
            var phase = 0.0
            var values = [Float]()
            for _ in 0..<60 {
                var chunk = [Float]()
                for _ in 0..<slide {
                    chunk.append(0.5 * Float(sin(phase)))
                    phase += 2 * Double.pi * 1000 / sampleRate
                }
                feed(pipeline, toStereo(chunk))
                values.append(pipeline.currentBands()[7])
            }

            let steady = values.suffix(10).reduce(0, +) / 10
            guard steady > 0 else { return 999 }
            guard let crossing = values.firstIndex(where: { $0 >= steady * 0.5 }) else { return 999 }

            // Кадр выдаётся после накопления slide отсчётов.
            return Float(Double(crossing + 1) * Double(slide) / sampleRate * 1000)
        }

        t.test("Шаг 512 быстрее шага 1024") { t in
            let fast = latencyMilliseconds(slide: 512)
            let slow = latencyMilliseconds(slide: 1024)

            t.note("задержка до половины уровня: шаг 512 — \(Int(fast)) мс, " +
                   "шаг 1024 — \(Int(slow)) мс")
            t.expect(fast < slow,
                     "мелкий шаг обязан давать меньшую задержку: " +
                     "\(Int(fast)) мс против \(Int(slow)) мс")
            t.expect(fast <= 40,
                     "задержка \(Int(fast)) мс при цели около 21 мс")
        }
    }
}
