import Foundation
import SRWLEDCore

/// Генерирует чередующиеся стерео-отсчёты синуса.
private func sineFrames(frequency: Double, amplitude: Float, frames: Int, sampleRate: Double) -> [Float] {
    var samples = [Float]()
    samples.reserveCapacity(frames * 2)
    for i in 0..<frames {
        let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        samples.append(value)   // левый
        samples.append(value)   // правый
    }
    return samples
}

private func feed(_ pipeline: AudioPipeline, _ samples: [Float]) {
    samples.withUnsafeBufferPointer { buffer in
        pipeline.process(interleaved: buffer, channels: 2)
    }
}

func runPipelineTests(_ t: TestRunner) {
    t.suite("Обработка звука") { t in
        let sampleRate = 48000.0
        var settings = Settings()
        settings.fftValueScale = .squareRoot

        t.test("Громкий сигнал не выводит полосы за 254") { t in
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не удалось создать обработку"); return
            }

            // Синус полной шкалы — самое громкое, что вообще может прийти с тапа.
            for _ in 0..<12 {
                feed(pipeline, sineFrames(frequency: 1000, amplitude: 1.0,
                                          frames: 1024, sampleRate: sampleRate))
            }

            let packet = pipeline.currentPacket()
            let loudest = packet.fftBins.max() ?? 0
            t.expect(loudest <= 254,
                     "максимальная полоса \(loudest), а WLED заворачивает всё выше 254")
            t.expect(loudest > 0, "на громком синусе полосы обязаны ожить")
        }

        t.test("Магнитуда пика не вылетает за предел WLED") { t in
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не удалось создать обработку"); return
            }

            for _ in 0..<12 {
                feed(pipeline, sineFrames(frequency: 440, amplitude: 1.0,
                                          frames: 1024, sampleRate: sampleRate))
            }

            let magnitude = pipeline.currentPacket().fftMagnitude
            t.expect(magnitude <= 255 * 16,
                     "магнитуда \(magnitude) превышает 4080 и завернётся при приведении к байту")
            t.expect(magnitude.isFinite, "магнитуда обязана быть конечным числом")
        }

        t.test("Пик попадает в правильную полосу спектра") { t in
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не удалось создать обработку"); return
            }

            for _ in 0..<12 {
                feed(pipeline, sineFrames(frequency: 1000, amplitude: 0.5,
                                          frames: 1024, sampleRate: sampleRate))
            }

            let peak = pipeline.currentPacket().fftMajorPeak
            // Допуск задан шириной главного лепестка окна FlatTop: у него вершина намеренно
            // плоская (±2 бина по 23.4 Гц), поэтому максимум внутри неё гуляет.
            // После перехода на окно Hann в M1 допуск ужесточается до половины бина, 12 Гц.
            t.expect(abs(peak - 1000) <= 60,
                     "пик определён как \(Int(peak)) Гц вместо 1000 — вне лепестка FlatTop")
        }

        t.test("Тишина даёт нули и поднимает флаг тишины") { t in
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не удалось создать обработку"); return
            }

            let silence = [Float](repeating: 0, count: 2048 * 2)
            for _ in 0..<40 { feed(pipeline, silence) }

            let packet = pipeline.currentPacket()
            t.expect(pipeline.isSilent, "флаг тишины должен подняться")
            t.expect(packet.fftBins.allSatisfy { $0 == 0 },
                     "на тишине полосы обязаны догаснуть до нуля")
            t.expectEqual(packet.samplePeak, 0, "удара в тишине быть не может")
        }

        t.test("Мусор на входе не роняет обработку и не портит пакет") { t in
            guard let pipeline = AudioPipeline(settings: settings, sampleRate: sampleRate) else {
                t.expect(false, "не удалось создать обработку"); return
            }

            // Постоянное смещение, клиппинг и нечисловые значения вперемешку.
            var nasty = [Float]()
            for i in 0..<(2048 * 2) {
                switch i % 4 {
                case 0: nasty.append(1000)
                case 1: nasty.append(-1000)
                case 2: nasty.append(0.5)
                default: nasty.append(Float.nan)
                }
            }
            for _ in 0..<4 { feed(pipeline, nasty) }

            let bytes = pipeline.currentPacket().encoded()
            t.expectEqual(bytes.count, 44, "пакет обязан остаться валидным")
            t.expect(Array(bytes[18..<34]).allSatisfy { $0 <= 254 }, "полосы в допустимых пределах")
        }
    }
}
