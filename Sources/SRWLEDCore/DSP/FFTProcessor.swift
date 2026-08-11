import Accelerate
import Foundation

/// Прямое преобразование Фурье с окном Flat Top.
///
/// Оригинал использует FftSharp: `FFT.Forward` + `FFT.Magnitude(positiveOnly: true)`
/// и окно `FftSharp.Windows.FlatTop`, нормированное по сумме. Здесь то же самое на vDSP.
/// Нормировки воспроизведены точно — от них зависят подобранные автором константы
/// шкалирования в `Bucketizer`.
public final class FFTProcessor {
    /// Длина окна БПФ (должна быть степенью двойки).
    public let size: Int

    /// Амплитудный спектр, `size/2 + 1` значений (только положительные частоты).
    public private(set) var magnitudes: [Float]

    /// Частота каждого бина в герцах.
    public let frequencies: [Float]

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]

    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]

    public init?(size: Int, sampleRate: Double, kind: WindowKind = .hann) {
        precondition(size > 0 && size & (size - 1) == 0, "Размер БПФ должен быть степенью двойки")

        self.size = size
        self.log2n = vDSP_Length(log2(Double(size)).rounded())

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup

        self.window = Self.makeWindow(kind, size: size)
        self.windowed = [Float](repeating: 0, count: size)
        self.realp = [Float](repeating: 0, count: size / 2)
        self.imagp = [Float](repeating: 0, count: size / 2)

        let binCount = size / 2 + 1
        self.magnitudes = [Float](repeating: 0, count: binCount)

        // FftSharp.FFT.FrequencyScale(length, rate, positiveOnly: true):
        //   шаг = rate / (length - 1) / 2, что для length = size/2+1 равно rate / size.
        let step = Float(sampleRate) / Float(size)
        self.frequencies = (0..<binCount).map { Float($0) * step }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Строит окно, нормированное так, чтобы сумма отсчётов равнялась единице.
    ///
    /// Нормировка по сумме (как `Window.NormalizeInPlace` в FftSharp) даёт удобное свойство:
    /// пик синуса амплитуды A на частоте бина равен ровно A/N независимо от формы окна.
    /// Поэтому смена окна не ломает шкалу — меняется только избирательность.
    private static func makeWindow(_ kind: WindowKind, size: Int) -> [Float] {
        let denominator = Double(size - 1)

        var kernel: [Double]
        switch kind {
        case .hann:
            // Главный лепесток шириной 2 бина — тон остаётся в своей полосе.
            kernel = (0..<size).map { i in
                0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / denominator)
            }

        case .flatTop:
            // Коэффициенты FftSharp.Windows.FlatTop — как в оригинале.
            let a0 = 0.21557895, a1 = 0.41663158, a2 = 0.277263158
            let a3 = 0.083578947, a4 = 0.006947368
            kernel = (0..<size).map { i in
                let x = 2.0 * Double.pi * Double(i) / denominator
                return a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x) + a4 * cos(4 * x)
            }
        }

        let sum = kernel.reduce(0, +)
        if sum != 0 {
            for i in kernel.indices { kernel[i] /= sum }
        }
        return kernel.map(Float.init)
    }

    /// Считает амплитудный спектр для `size` отсчётов.
    public func process(_ samples: UnsafeBufferPointer<Float>) {
        precondition(samples.count >= size, "Нужно как минимум \(size) отсчётов")

        // Применяем окно.
        vDSP_vmul(samples.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(size))

        let halfSize = size / 2
        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!,
                                            imagp: imagBuffer.baseAddress!)

                // Упаковка вещественного сигнала в split-complex (чётные -> realp, нечётные -> imagp).
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // vDSP_fft_zrip отдаёт F[k] = 2·X[k]; в realp[0]/imagp[0] упакованы
                // удвоенные DC и Найквист. FftSharp.Magnitude даёт |X[0]|/N для DC
                // и 2·|X[k]|/N для остальных — то есть |F[k]|/N.
                let n = Float(size)
                magnitudes[0] = abs(realBuffer[0]) / (2 * n)          // DC не удваивается
                magnitudes[halfSize] = abs(imagBuffer[0]) / n         // Найквист удваивается

                for k in 1..<halfSize {
                    let re = realBuffer[k]
                    let im = imagBuffer[k]
                    magnitudes[k] = (re * re + im * im).squareRoot() / n
                }
            }
        }

        // Оригинал глушит околонулевой шум перед бакетизацией.
        for i in magnitudes.indices where magnitudes[i] < 1e-9 {
            magnitudes[i] = 0
        }
    }

    /// Индексы бинов, попадающих в полосу [freqLow, freqHigh] включительно.
    public func indexes(freqLow: Float, freqHigh: Float) -> Range<Int> {
        guard let step = frequencies.count > 1 ? frequencies[1] : nil, step > 0 else {
            return 0..<0
        }
        let lower = max(0, Int((freqLow / step).rounded(.up)))
        let upper = min(frequencies.count - 1, Int((freqHigh / step).rounded(.down)))
        return lower <= upper ? lower..<(upper + 1) : lower..<lower
    }
}
