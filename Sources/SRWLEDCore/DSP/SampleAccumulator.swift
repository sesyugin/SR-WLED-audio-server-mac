import Foundation

/// Копит моно-отсчёты и выдаёт перекрывающиеся кадры фиксированной длины.
///
/// БПФ нужна степень двойки, а CoreAudio отдаёт по ~512 отсчётов за вызов.
/// Оригинал накапливает 2048 со сдвигом 1024 — то есть кадры перекрываются наполовину,
/// что даёт вдвое больше пакетов и заметно более плавную картинку на ленте.
public final class SampleAccumulator {
    public let frameSize: Int
    public let slide: Int

    private var buffer: [Float]
    private var filled = 0

    public init(frameSize: Int, slide: Int) {
        precondition(slide > 0 && slide <= frameSize)
        self.frameSize = frameSize
        self.slide = slide
        // Запас на подачу больше кадра за раз.
        self.buffer = [Float](repeating: 0, count: frameSize * 2)
    }

    /// Добавляет отсчёты и вызывает `onFrame` для каждого набравшегося кадра.
    public func append(_ samples: UnsafeBufferPointer<Float>,
                       onFrame: (UnsafeBufferPointer<Float>) -> Void)
    {
        var offset = 0
        while offset < samples.count {
            if filled + (samples.count - offset) > buffer.count {
                buffer.append(contentsOf: repeatElement(0, count: buffer.count))
            }

            let chunk = min(samples.count - offset, buffer.count - filled)
            for i in 0..<chunk {
                buffer[filled + i] = samples[offset + i]
            }
            filled += chunk
            offset += chunk

            while filled >= frameSize {
                buffer.withUnsafeBufferPointer { pointer in
                    onFrame(UnsafeBufferPointer(rebasing: pointer[0..<frameSize]))
                }

                // Сдвигаем окно: выбрасываем `slide` отсчётов, остальное оставляем на следующий кадр.
                // memmove, а не срез массива, — области перекрываются, и это горячий путь
                // аудиопотока, где лишние аллокации недопустимы.
                if filled > slide {
                    let remaining = filled - slide
                    buffer.withUnsafeMutableBytes { raw in
                        let base = raw.baseAddress!
                        let stride = MemoryLayout<Float>.stride
                        memmove(base, base + slide * stride, remaining * stride)
                    }
                }
                filled -= slide
            }
        }
    }

    public func reset() {
        filled = 0
    }
}
