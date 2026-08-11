import Foundation
import SRWLEDCore

// Проверки исправлений этапа M1. Все на синтетических массивах: ни звука, ни сети.

private func stereoSine(frequency: Double, amplitude: Float, frames: Int, sampleRate: Double) -> [Float] {
    var samples = [Float]()
    samples.reserveCapacity(frames * 2)
    for i in 0..<frames {
        let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        samples.append(value)
        samples.append(value)
    }
    return samples
}

private func feed(_ pipeline: AudioPipeline, _ samples: [Float]) {
    samples.withUnsafeBufferPointer { buffer in
        pipeline.process(interleaved: buffer, channels: 2)
    }
}

/// Прогоняет ровный синус заданной амплитуды и возвращает установившийся уровень из пакета.
private func steadyLevel(amplitude: Float, settings: Settings, sampleRate: Double = 48000) -> Float {
    guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else { return -1 }
    for _ in 0..<16 {
        feed(pipeline, stereoSine(frequency: 1000, amplitude: amplitude,
                                  frames: 1024, sampleRate: sampleRate))
    }
    return pipeline.currentPacket().sampleRaw
}

func runCorrectnessTests(_ t: TestRunner) {

    // MARK: - Громкость

    t.suite("Уровень в пакете отражает громкость") { t in

        // Ступени -6, -20, -40, -54 dBFS.
        let amplitudes: [Float] = [0.501, 0.1, 0.01, 0.002]

        t.test("Исправленный режим: уровень строго убывает со звуком") { t in
            var settings = Settings()          // по умолчанию loudness = .rms
            let levels = amplitudes.map { steadyLevel(amplitude: $0, settings: settings) }

            for i in 1..<levels.count {
                t.expect(levels[i] < levels[i - 1],
                         "уровень не убыл: \(levels[i-1]) → \(levels[i]) " +
                         "при падении сигнала на 14-20 дБ")
            }
            let span = levels.first! - levels.last!
            t.expect(span > 100,
                     "разброс уровня всего \(Int(span)) из 255 при изменении сигнала на 48 дБ")

            settings.loudness = .rms
            _ = settings
        }

        t.test("Режим оригинала: уровень почти не замечает громкости — это и есть дефект") { t in
            var settings = Settings.originalCompatible()
            settings.loudness = .spectralRatio
            let levels = amplitudes.map { steadyLevel(amplitude: $0, settings: settings) }

            let span = abs(levels.first! - levels.last!)
            t.expect(span < 40,
                     "ожидалось, что старый режим слабо реагирует на громкость, " +
                     "но разброс вышел \(Int(span)) — проверь, тот ли режим включён")
        }
    }

    // MARK: - Сетка полос

    t.suite("Полосы совпадают с прошивкой") { t in

        t.test("Таблица границ — ровно та, что зашита в WLED") { t in
            let edges = Bucketizer.wledBandEdges
            t.expectEqual(edges.count, 17, "17 границ на 16 полос")
            t.expectEqual(edges.first, 43, "нижняя граница первой полосы")
            t.expectEqual(edges.last, 9259, "верхняя граница последней полосы")
            // Несколько опорных точек из audio_reactive.cpp
            t.expectEqual(edges[1], 86, "граница 0-й и 1-й полосы")
            t.expectEqual(edges[8], 1120, "граница 7-й и 8-й полосы")
            t.expectEqual(edges[15], 7106, "граница 14-й и 15-й полосы")
        }

        // Сколько бинов БПФ реально попадает в полосу [low, high] включительно.
        // Это и есть то, чем полоса наполняется; ширина в герцах сама по себе ничего не значит.
        func binsInBand(low: Double, high: Double, fftSize: Int = 2048, sampleRate: Double = 48000) -> Int {
            let step = sampleRate / Double(fftSize)
            var count = 0
            var k = 0
            while Double(k) * step <= high {
                if Double(k) * step >= low { count += 1 }
                k += 1
            }
            return count
        }

        t.test("В сетке WLED каждая полоса наполняется минимум двумя бинами") { t in
            let edges = Bucketizer.wledBandEdges
            for i in 0..<(edges.count - 1) {
                let count = binsInBand(low: Double(edges[i]), high: Double(edges[i + 1]))
                t.expect(count >= 2,
                         "полоса \(i) (\(Int(edges[i]))–\(Int(edges[i+1])) Гц) получает всего " +
                         "\(count) бин — её значение пришлось бы выдумывать")
            }
        }

        t.test("Старая сетка 40..10000 оставляла нижние полосы на одном бине") { t in
            // Документируем, почему меняется значение по умолчанию.
            let ratio = pow(10000.0 / 40.0, 1.0 / 16.0)
            var starved = 0
            var report = [String]()
            for i in 0..<16 {
                let low = 40.0 * pow(ratio, Double(i))
                let high = 40.0 * pow(ratio, Double(i + 1))
                let count = binsInBand(low: low, high: high)
                if count < 2 {
                    starved += 1
                    report.append("\(i): \(Int(low))–\(Int(high)) Гц → \(count)")
                }
            }
            t.expect(starved >= 3,
                     "ожидалось минимум три обделённых полосы, вышло \(starved) [\(report.joined(separator: "; "))]")
        }
    }

    // MARK: - Окно

    t.suite("Окно анализа") { t in

        t.test("Пик синуса равен A/N — нормировка не зависит от формы окна") { t in
            let size = 2048
            let sampleRate = 48000.0
            // Частота ровно в центре бина 100.
            let frequency = 100.0 * sampleRate / Double(size)

            for kind in [WindowKind.hann, .flatTop] {
                guard let fft = FFTProcessor(size: size, sampleRate: sampleRate, kind: kind) else {
                    t.expect(false, "не создалось БПФ для \(kind)"); continue
                }
                let samples = (0..<size).map { i in
                    Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
                }
                samples.withUnsafeBufferPointer { fft.process($0) }

                let expected = Float(1.0 / Double(size))     // 4.8828e-4
                let actual = fft.magnitudes[100]
                let error = abs(actual - expected) / expected
                t.expect(error < 0.01,
                         "\(kind): пик \(actual) вместо \(expected), отклонение \(Int(error * 100))%")
            }
        }

        t.test("Hann держит тон в своей полосе, FlatTop размазывает") { t in
            let sampleRate = 48000.0
            let size = 2048
            let frequency = 100.0 * sampleRate / Double(size)

            func bandsLit(_ kind: WindowKind) -> Int {
                guard let fft = FFTProcessor(size: size, sampleRate: sampleRate, kind: kind) else { return -1 }
                let samples = (0..<size).map { i in
                    Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
                }
                samples.withUnsafeBufferPointer { fft.process($0) }
                let peak = fft.magnitudes.max() ?? 0
                // Считаем бины выше -20 дБ от пика.
                return fft.magnitudes.filter { $0 > peak * 0.1 }.count
            }

            let hann = bandsLit(.hann)
            let flatTop = bandsLit(.flatTop)
            t.expect(hann < flatTop,
                     "Hann должен задевать меньше бинов, чем FlatTop: \(hann) против \(flatTop)")
            t.expect(hann <= 3, "Hann задел \(hann) бинов выше -20 дБ, ожидалось не больше 3")
        }
    }

    // MARK: - Постоянная составляющая и удар

    t.suite("Постоянная составляющая и признак удара") { t in

        t.test("Смещение входа не зажигает нижнюю полосу") { t in
            let sampleRate = 48000.0
            var settings = Settings()
            settings.removeDCOffset = true

            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не создалась обработка"); return
            }

            // Чистое смещение без всякого звука.
            let dc = [Float](repeating: 0.5, count: 2048 * 2)
            for _ in 0..<12 { feed(pipeline, dc) }

            let bins = pipeline.currentPacket().fftBins
            t.expect(bins[0] < 30,
                     "нижняя полоса светит на \(bins[0]) из 254 от одного лишь смещения")
        }

        t.test("Признак удара уходит одиночным импульсом") { t in
            let sampleRate = 48000.0
            var settings = Settings()
            settings.beatLatch = true

            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не создалась обработка"); return
            }

            var peaks = [UInt8]()
            // Набираем историю детектора, затем бьём длинными громкими всплесками.
            for round in 0..<160 {
                let loud = round > 60 && (round / 6) % 2 == 0
                feed(pipeline, stereoSine(frequency: 80,
                                          amplitude: loud ? 0.9 : 0.05,
                                          frames: 1024, sampleRate: sampleRate))
                peaks.append(pipeline.currentPacket().samplePeak)
            }

            var consecutive = 0
            for i in 1..<peaks.count where peaks[i] == 1 && peaks[i - 1] == 1 {
                consecutive += 1
            }
            t.expectEqual(consecutive, 0,
                          "флаг удара продержался подряд \(consecutive) раз — эффекты будут срабатывать непрерывно")
            t.expect(peaks.contains(1), "на всплесках удар обязан хоть раз сработать")
        }
    }
}
