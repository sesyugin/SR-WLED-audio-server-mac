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

    private let settings: Settings
    private let accumulator: SampleAccumulator
    private let fft: FFTProcessor
    private let beatDetector: BeatDetector
    private let bucketizer: Bucketizer
    private let gainControl: GainControl
    private let smoother: BandSmoother?

    private var monoBuffer = [Float]()
    private let lock = NSLock()
    private var packet = AudioSyncPacket()

    private let framesPerSecond: Float
    /// Буфер для копии кадра со снятым постоянным смещением.
    private var dcCorrected = [Float]()
    /// Сглаженный уровень для поля sampleSmth.
    private var smoothedLoudness: Float = 0
    /// Предыдущее состояние детектора — для одиночного импульса удара.
    private var beatWasDetected = false

    /// Последние значения полос — для индикатора в интерфейсе.
    private var latestBands = [Float](repeating: 0, count: 16)

    /// Вызывается после каждого обновления пакета (в том числе по тишине).
    public var onPacketUpdated: (@Sendable () -> Void)?

    public private(set) var isSilent = false

    public init?(settings: Settings, sampleRate: Double) {
        guard let fft = FFTProcessor(size: Self.frameSize,
                                     sampleRate: sampleRate,
                                     kind: settings.window) else {
            return nil
        }
        let slide = max(1, min(settings.frameSlide, Self.frameSize))
        self.framesPerSecond = Float(sampleRate / Double(slide))
        self.settings = settings
        self.fft = fft
        self.accumulator = SampleAccumulator(frameSize: Self.frameSize, slide: slide)

        let fps = Float(sampleRate / Double(slide))
        self.beatDetector = BeatDetector(mode: settings.beatLatch ? .spectralFlux : .originalAverage,
                                         framesPerSecond: fps)

        switch settings.bandLayout {
        case .wled:
            self.bucketizer = Bucketizer(edges: Bucketizer.wledBandEdges,
                                         valueScale: settings.fftValueScale,
                                         normalization: settings.normalization,
                                         aggregation: settings.aggregation,
                                         fftSize: Self.frameSize)
        case .custom:
            self.bucketizer = Bucketizer(freqMin: settings.fftLow,
                                         freqMax: settings.fftHigh,
                                         logFreqScale: settings.fftFreqLogScale,
                                         valueScale: settings.fftValueScale,
                                         normalization: settings.normalization,
                                         aggregation: settings.aggregation,
                                         fftSize: Self.frameSize)
        }

        self.smoother = settings.bandSmoothing
            ? BandSmoother(bandCount: 16,
                           attackSeconds: settings.attackSeconds,
                           releaseSeconds: settings.releaseSeconds,
                           framesPerSecond: fps)
            : nil

        self.gainControl = GainControl(mode: settings.gainMode,
                                       manual: settings.manualGain,
                                       manualSpanReference: settings.manualGainReference,
                                       floor: settings.gainFloor,
                                       attackSeconds: settings.gainAttackSeconds,
                                       releaseSeconds: settings.gainReleaseSeconds,
                                       framesPerSecond: fps)
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
        // --- постоянная составляющая ---
        // Без вычитания среднего смещение входа зажигает нижнюю полосу и перебивает музыку.
        var offsetToRemove: Float = 0
        if settings.removeDCOffset {
            var sum: Float = 0
            for value in frame where value.isFinite { sum += value }
            offsetToRemove = sum / Float(frame.count)
        }

        // --- статистика по кадру ---
        var zeroCrossings = 0
        var maxAbs: Float = 0
        var sumOfSquares: Double = 0
        var previous = frame[0] - offsetToRemove
        maxAbs = abs(previous)
        sumOfSquares = Double(previous) * Double(previous)

        for i in 1..<frame.count {
            let value = frame[i] - offsetToRemove
            guard value.isFinite else { continue }
            if previous > 0 && value <= 0 { zeroCrossings += 1 }
            if previous < 0 && value >= 0 { zeroCrossings += 1 }
            maxAbs = max(maxAbs, abs(value))
            sumOfSquares += Double(value) * Double(value)
            previous = value
        }

        let rms = Float((sumOfSquares / Double(frame.count)).squareRoot())

        // --- тишина ---
        if maxAbs < settings.squelch {
            handleSilence()
            return
        }

        // --- спектр ---
        if settings.removeDCOffset && offsetToRemove != 0 {
            // Копируем со снятым смещением: исходный буфер принадлежит накопителю.
            if dcCorrected.count < frame.count {
                dcCorrected = [Float](repeating: 0, count: frame.count)
            }
            for i in 0..<frame.count { dcCorrected[i] = frame[i] - offsetToRemove }
            dcCorrected.withUnsafeBufferPointer { buffer in
                fft.process(UnsafeBufferPointer(rebasing: buffer[0..<frame.count]))
            }
        } else {
            fft.process(frame)
        }
        beatDetector.process(fft)
        bucketizer.process(fft)

        // Сглаживание до АРУ: регулировка видит уже сглаженные пики и меньше дёргается.
        var buckets = bucketizer.buckets
        smoother?.apply(to: &buckets)
        gainControl.process(buckets: buckets)

        // --- заполнение пакета ---
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

        // --- уровень ---
        switch settings.loudness {
        case .rms:
            // Действительная громкость кадра, приведённая к 0…255 равномерно в децибелах:
            // -60 dBFS даёт 0, полная шкала — 255. Именно этого ждут эффекты WLED.
            packet.sampleRaw = Self.sanitized(Self.loudnessByte(rms: rms))
        case .spectralRatio:
            // Поведение оригинала: отношение средней полосы к максимальной. Это мера
            // «плоскости» спектра, а не громкость, — сохранено только для сравнения.
            packet.sampleRaw = Self.sanitized(bucketMax > 0 ? bucketAvg / bucketMax * 255 : 0)
        }

        // sampleSmth — сглаженная версия того же уровня, постоянная времени около 50 мс.
        let alpha = min(1, 1 - exp(-1 / (0.05 * framesPerSecond)))
        smoothedLoudness += alpha * (packet.sampleRaw - smoothedLoudness)
        packet.sampleSmth = Self.sanitized(smoothedLoudness)

        // Признак удара: одиночный импульс на фронте, иначе эффекты вроде Puddlepeak
        // срабатывают непрерывно. WLED сбрасывает флаг сам через max(50 мс, кадр).
        let beat = beatDetector.detected
        if settings.beatLatch {
            packet.samplePeak = (beat && !beatWasDetected) ? 1 : 0
        } else {
            packet.samplePeak = beat ? 1 : 0
        }
        beatWasDetected = beat

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

    /// Громкость кадра в диапазоне 0…255, равномерно по децибелам.
    /// Нижняя граница -60 dBFS: тише этого музыки в помещении не бывает,
    /// а весь запас шкалы уходит на полезный диапазон.
    static func loudnessByte(rms: Float, floorDB: Float = -60) -> Float {
        guard rms > 0, rms.isFinite else { return 0 }
        let dB = 20 * log10(rms)
        let normalized = (dB - floorDB) / (0 - floorDB)
        return min(max(normalized, 0), 1) * 255
    }
}
