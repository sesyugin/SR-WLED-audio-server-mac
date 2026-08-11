import Foundation

/// Полная цепочка обработки: отсчёты с аудиоустройства -> готовый пакет WLED.
///
/// Порядок повторяет `AudioCaptureManager.SetupChain()` оригинала:
/// сведение в моно -> накопление кадра -> статистика -> проверка тишины ->
/// БПФ -> детектор бита -> 16 полос -> АРУ -> заполнение пакета.
///
/// Вызывается с аудиопотока CoreAudio, поэтому класс намеренно не изолирован
/// ни в какой актор и не аллоцирует в горячем пути.
public final class AudioPipeline: @unchecked Sendable {
    /// Размер окна БПФ. Разрешение по частоте — вдвое меньше.
    public static let frameSize = 2048
    public static let frameSlide = 1024

    private let settings: Settings
    private let accumulator: SampleAccumulator
    private let fft: FFTProcessor
    private let beatDetector: BeatDetector
    private let bucketizer: Bucketizer
    private let gainControl: GainControl

    private var monoBuffer = [Float]()
    private let lock = NSLock()
    private var packet = AudioSyncPacket()

    /// Последние значения полос — для индикатора в интерфейсе.
    private var latestBands = [Float](repeating: 0, count: 16)

    /// Вызывается после каждого обновления пакета (в том числе по тишине).
    public var onPacketUpdated: (@Sendable () -> Void)?

    public private(set) var isSilent = false

    public init?(settings: Settings, sampleRate: Double) {
        guard let fft = FFTProcessor(size: Self.frameSize, sampleRate: sampleRate) else {
            return nil
        }
        self.settings = settings
        self.fft = fft
        self.accumulator = SampleAccumulator(frameSize: Self.frameSize, slide: Self.frameSlide)
        self.beatDetector = BeatDetector()
        self.bucketizer = Bucketizer(freqMin: settings.fftLow,
                                     freqMax: settings.fftHigh,
                                     logFreqScale: settings.fftFreqLogScale,
                                     valueScale: settings.fftValueScale)
        self.gainControl = GainControl(manual: settings.manualGain,
                                       manualSpanReference: settings.manualGainReference)
    }

    /// Снимок текущего пакета — потокобезопасно.
    public func currentPacket() -> AudioSyncPacket {
        lock.lock()
        defer { lock.unlock() }
        return packet
    }

    public func currentBands() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return latestBands
    }

    /// Точка входа с аудиопотока. `samples` — чередующиеся каналы.
    public func process(interleaved samples: UnsafeBufferPointer<Float>, channels: Int) {
        guard channels > 0, !samples.isEmpty else {
            handleSilence()
            return
        }

        // Сведение в моно усреднением каналов — как `SampleConverter` оригинала.
        let frames = samples.count / channels
        if monoBuffer.count < frames {
            monoBuffer = [Float](repeating: 0, count: frames)
        }
        for frame in 0..<frames {
            var sum: Float = 0
            let base = frame * channels
            for channel in 0..<channels {
                sum += samples[base + channel]
            }
            monoBuffer[frame] = sum / Float(channels)
        }

        monoBuffer.withUnsafeBufferPointer { pointer in
            let mono = UnsafeBufferPointer(rebasing: pointer[0..<frames])
            accumulator.append(mono) { frame in
                processFrame(frame)
            }
        }
    }

    private func processFrame(_ frame: UnsafeBufferPointer<Float>) {
        // --- статистика по кадру ---
        var zeroCrossings = 0
        var maxAbs: Float = 0
        var previous = frame[0]
        maxAbs = abs(previous)
        for i in 1..<frame.count {
            let value = frame[i]
            if previous > 0 && value <= 0 { zeroCrossings += 1 }
            if previous < 0 && value >= 0 { zeroCrossings += 1 }
            maxAbs = max(maxAbs, abs(value))
            previous = value
        }

        // --- тишина ---
        if maxAbs < settings.squelch {
            handleSilence()
            return
        }

        // --- спектр ---
        fft.process(frame)
        beatDetector.process(fft)
        bucketizer.process(fft)
        gainControl.process(buckets: bucketizer.buckets)

        // --- заполнение пакета ---
        let buckets = bucketizer.buckets
        let span = gainControl.span
        let offset = gainControl.offset

        let bucketMax = buckets.map { abs($0.value) }.max() ?? 0
        let bucketAvg = buckets.reduce(0) { $0 + abs($1.value) } / Float(buckets.count)

        lock.lock()

        for i in buckets.indices {
            // Потолок 254, а не 255: WLED ограничивает канал эквалайзера этим значением,
            // и 255 у него заворачивается — яркий пик превращается в тусклый мусор.
            packet.fftBins[i] = Self.clampToByte((buckets[i].value + offset) / span * 254,
                                                 maximum: 254)
            latestBands[i] = Float(packet.fftBins[i]) / 254
        }

        let raw = bucketMax > 0 ? bucketAvg / bucketMax * 255 : 0
        packet.sampleRaw = Self.sanitized(raw)
        packet.sampleSmth = packet.sampleRaw
        packet.samplePeak = beatDetector.detected ? 1 : 0

        // WLED делит это значение на 16/8/4/2 в разных эффектах, чтобы уложить в uint8.
        // Зажим сверху обязателен: без него на каждой атаке значение вылетает за предел
        // и заворачивается при приведении к байту — вспышка гаснет вместо того, чтобы быть яркой.
        let wledPeakValueMax: Float = 255 * 16
        packet.fftMagnitude = min(Self.sanitized((bucketizer.peakValue + offset) / span * wledPeakValueMax),
                                  wledPeakValueMax)
        packet.fftMajorPeak = Self.sanitized(bucketizer.peakFrequency)

        // Оригинал считает это целочисленным делением, отчего значение почти всегда 0.
        // Здесь — как задумывалось: доля пересечений нуля, приведённая к 0..255.
        packet.zeroCrossingCount = UInt16(Self.clampToByte(Float(zeroCrossings) / Float(frame.count) * 255))

        packet.pressure = Self.sanitized(pow(maxAbs * 16, 2))

        isSilent = false
        lock.unlock()

        onPacketUpdated?()
    }

    private func handleSilence() {
        lock.lock()
        packet.decay(rate: 0.85)
        packet.fftMajorPeak = 0
        packet.samplePeak = 0
        packet.zeroCrossingCount = 0
        // Счётчик кадров здесь намеренно не трогаем: им владеет PacketSender и держит его
        // строго монотонным. Оригинал обнулял его на тишине, из-за чего WLED-MM переставал
        // принимать пакеты после первой же паузы.
        for i in latestBands.indices {
            latestBands[i] = Float(packet.fftBins[i]) / 255
        }
        isSilent = true
        lock.unlock()

        onPacketUpdated?()
    }

    /// Приведение к байту с защитой от NaN/inf — иначе конверсия в UInt8 уронит процесс.
    private static func clampToByte(_ value: Float, maximum: Float = 255) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8(min(max(value, 0), maximum))
    }

    private static func sanitized(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
