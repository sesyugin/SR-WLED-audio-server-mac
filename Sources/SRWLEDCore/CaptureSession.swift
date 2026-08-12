import CoreAudio
import Foundation

/// Захват звука вместе с обработкой, умеющий пересобрать себя при смене звукового тракта.
///
/// Отправитель сюда намеренно не входит и переживает любые пересборки: он владеет
/// счётчиком кадров, а тот обязан оставаться строго монотонным. Пересоздать отправитель
/// на переключении наушников — значит начать счётчик заново, и WLED-MM отбросит пакеты.
public final class CaptureSession: @unchecked Sendable {

    /// Событие захвата.
    ///
    /// Причина — ключ перевода, подробность — то, что не переводят: имена устройств,
    /// числа, текст системной ошибки. Раньше сюда клали готовую русскую строку,
    /// и она доезжала до интерфейса на любом языке.
    public enum Event: Sendable {
        case started(sampleRate: Double, channels: Int, device: String)
        case restarted(reason: S, detail: String)
        case failed(reason: S, detail: String)
        case stopped
    }

    private let settings: Settings
    private let onFrameReady: @Sendable () -> Void
    private let onEvent: @Sendable (Event) -> Void

    private let lock = NSLock()
    private var tap: SystemAudioTap?
    private var watcher: AudioDeviceWatcher?
    private var currentPipeline: AudioPipeline?
    private var isStopping = false
    /// Перезапуски выполняются строго по одному.
    private let restartQueue = DispatchQueue(label: "srwled.capture.restart")

    public private(set) var deviceName = ""
    public private(set) var sampleRate: Double = 0
    public private(set) var channels = 0

    public init(settings: Settings,
                onFrameReady: @escaping @Sendable () -> Void,
                onEvent: @escaping @Sendable (Event) -> Void)
    {
        self.settings = settings
        self.onFrameReady = onFrameReady
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    public var pipeline: AudioPipeline? {
        lock.lock(); defer { lock.unlock() }
        return currentPipeline
    }

    public func start() throws {
        lock.lock()
        isStopping = false
        lock.unlock()

        try startCapture()

        // Наблюдатель ставится после успешного старта: следим за тем самым устройством,
        // на котором построен захват.
        let watcher = AudioDeviceWatcher { [weak self] change in
            self?.handleChange(change)
        }
        watcher.start(watching: tap?.outputDeviceID ?? AudioObjectID(kAudioObjectUnknown))
        lock.lock()
        self.watcher = watcher
        lock.unlock()

        onEvent(.started(sampleRate: sampleRate, channels: channels, device: deviceName))
    }

    /// Принудительная пересборка. Нужна после пробуждения: устройства нередко
    /// возвращаются с другими параметрами, а уведомления об этом приходят не всегда.
    public func restart(reason: S) {
        restartQueue.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let stopping = self.isStopping
            self.lock.unlock()
            guard !stopping else { return }

            self.stopCapture()
            do {
                try self.startCapture()
            } catch {
                self.onEvent(.failed(reason: .failRestart, detail: "\(error)"))
                return
            }

            self.lock.lock()
            let watcher = self.watcher
            let deviceID = self.tap?.outputDeviceID ?? AudioObjectID(kAudioObjectUnknown)
            self.lock.unlock()
            watcher?.start(watching: deviceID)

            self.onEvent(.restarted(reason: reason, detail: ""))
        }
    }

    public func stop() {
        lock.lock()
        isStopping = true
        let watcher = self.watcher
        self.watcher = nil
        lock.unlock()

        watcher?.stop()
        stopCapture()
        onEvent(.stopped)
    }

    // MARK: - Внутреннее

    private func startCapture() throws {
        let tap = SystemAudioTap()

        // Колбэк читает обработку через замыкание, а не через сохранённую ссылку:
        // при пересборке она меняется, и старый кадр не должен попасть в новую.
        try tap.start { [weak self] samples, channelCount in
            guard let self else { return }
            self.lock.lock()
            let pipeline = self.currentPipeline
            self.lock.unlock()
            pipeline?.process(interleaved: samples, channels: channelCount)
        }

        guard let format = tap.format,
              let pipeline = AudioPipeline(settings: settings, sampleRate: format.sampleRate)
        else {
            try? tap.stop()
            throw SystemAudioTap.TapError.missingValue("формат захвата")
        }

        pipeline.onPacketUpdated = onFrameReady

        lock.lock()
        self.tap = tap
        self.currentPipeline = pipeline
        self.deviceName = tap.outputDeviceName
        self.sampleRate = format.sampleRate
        self.channels = format.channels
        lock.unlock()
    }

    private func stopCapture() {
        lock.lock()
        let tap = self.tap
        self.tap = nil
        self.currentPipeline = nil
        lock.unlock()

        try? tap?.stop()
    }

    private func handleChange(_ change: AudioDeviceWatcher.Change) {
        restartQueue.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let stopping = self.isStopping
            let previousRate = self.sampleRate
            let previousDevice = self.deviceName
            self.lock.unlock()
            guard !stopping else { return }

            self.stopCapture()

            do {
                try self.startCapture()
            } catch {
                self.onEvent(.failed(reason: .failRestart, detail: "\(error)"))
                return
            }

            self.lock.lock()
            let newRate = self.sampleRate
            let newDevice = self.deviceName
            let watcher = self.watcher
            let deviceID = self.tap?.outputDeviceID ?? AudioObjectID(kAudioObjectUnknown)
            self.lock.unlock()

            // Переставляем наблюдателя на новое устройство, иначе смену частоты
            // на нём мы уже не увидим.
            watcher?.start(watching: deviceID)

            // Подробность — только имена и числа: их не переводят, и собрать их
            // здесь можно, не зная языка интерфейса.
            var detail = ""
            if newDevice != previousDevice {
                detail = "\(previousDevice) → \(newDevice)"
            } else if newRate != previousRate {
                detail = "\(Int(previousRate)) → \(Int(newRate))"
            }
            self.onEvent(.restarted(reason: change.key, detail: detail))
        }
    }
}
