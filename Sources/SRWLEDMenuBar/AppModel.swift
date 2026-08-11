import Combine
import Foundation
import SRWLEDCore

/// Состояние сервера, которое видит человек.
enum ServerState: Equatable {
    case stopped
    case playing
    case silent
    case noSignal          // захват идёт, но в буфере ровно нули — обычно нет разрешения
    case failed(String)

    var title: String {
        switch self {
        case .stopped: return "Остановлено"
        case .playing: return "Звук идёт"
        case .silent: return "Тишина"
        case .noSignal: return "Нет сигнала"
        case .failed(let message): return message
        }
    }

    var symbol: String {
        switch self {
        case .stopped: return "pause.circle"
        case .playing: return "waveform"
        case .silent: return "waveform.badge.minus"
        case .noSignal: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }
}

/// Связывает захват звука, обработку и отправку; отдаёт интерфейсу готовое состояние.
@MainActor
final class AppModel: ObservableObject {

    /// Один экземпляр на приложение: к нему обращается и интерфейс, и делегат.
    static let shared = AppModel()

    // MARK: Наблюдаемое состояние

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var bands = [Float](repeating: 0, count: 16)
    @Published private(set) var packetsPerSecond = 0
    @Published private(set) var totalPackets = 0
    @Published private(set) var sourceDescription = ""
    @Published private(set) var destinationDescription = ""

    // MARK: Настройки, сохраняемые между запусками

    @Published var targets: String {
        didSet { defaults.set(targets, forKey: Keys.targets) }
    }
    @Published var sendMode: Settings.SendMode {
        didSet { defaults.set(sendMode.rawValue, forKey: Keys.sendMode) }
    }
    @Published var port: Int {
        didSet { defaults.set(port, forKey: Keys.port) }
    }
    @Published var useOriginalBehaviour: Bool {
        didSet { defaults.set(useOriginalBehaviour, forKey: Keys.original) }
    }
    @Published var showSpectrumInMenuBar: Bool {
        didSet { defaults.set(showSpectrumInMenuBar, forKey: Keys.spectrum) }
    }

    /// Первый запуск показывает объяснение и не лезет за разрешениями сам.
    @Published private(set) var isFirstRun: Bool

    private enum Keys {
        static let targets = "targets"
        static let sendMode = "sendMode"
        static let port = "port"
        static let original = "originalBehaviour"
        static let spectrum = "spectrumInMenuBar"
        static let launched = "hasLaunchedBefore"
    }

    // MARK: Внутренности

    private let defaults = UserDefaults.standard
    private var tap: SystemAudioTap?
    private var pipeline: AudioPipeline?
    private var sender: PacketSender?
    private var senderThread: Thread?
    private let frameReady = DispatchSemaphore(value: 0)
    /// Флаг остановки, который читает поток отправки. Отдельная ячейка, а не свойство
    /// модели, — модель живёт в главном акторе, поток к нему не относится.
    private let _stopping = Box(false)
    private var uiTimer: Timer?
    private var lastPacketCount = 0
    private var quietFrames = 0

    /// Не даём системе усыпить фоновый процесс: без этого через несколько минут
    /// отправка начинает идти рывками.
    private var activityToken: NSObjectProtocol?

    init() {
        targets = defaults.string(forKey: Keys.targets) ?? ""
        sendMode = Settings.SendMode(rawValue: defaults.string(forKey: Keys.sendMode) ?? "")
            ?? .broadcastLAN
        let storedPort = defaults.integer(forKey: Keys.port)
        port = storedPort == 0 ? 11988 : storedPort
        useOriginalBehaviour = defaults.bool(forKey: Keys.original)
        showSpectrumInMenuBar = defaults.object(forKey: Keys.spectrum) as? Bool ?? true
        isFirstRun = !defaults.bool(forKey: Keys.launched)
    }

    /// Вызывается при появлении интерфейса. На первом запуске ничего не трогаем:
    /// человек сначала читает, зачем нужны разрешения, и жмёт «Запустить» сам.
    func startAutomaticallyIfReady() {
        guard !isFirstRun, !isRunning else { return }
        start()
    }

    var isRunning: Bool {
        if case .stopped = state { return false }
        if case .failed = state { return false }
        return true
    }

    // MARK: Управление

    func buildSettings() -> Settings {
        var settings = useOriginalBehaviour ? Settings.originalCompatible() : Settings()
        settings.port = UInt16(max(1, min(port, 65535)))
        settings.sendMode = sendMode
        settings.targetIPList = [targets]
        settings.broadcastIPList = [targets]
        return settings
    }

    func start() {
        guard !isRunning else { return }

        if isFirstRun {
            defaults.set(true, forKey: Keys.launched)
            isFirstRun = false
        }

        let settings = buildSettings()
        let endpoints = PacketSender.resolveEndpoints(settings: settings)
        guard !endpoints.isEmpty else {
            state = .failed("Не указано, куда отправлять")
            return
        }

        let transport: PacketTransport
        do {
            transport = try UDPTransport(allowBroadcast: PacketSender.needsBroadcast(settings.sendMode))
        } catch {
            state = .failed("Сеть недоступна: \(error)")
            return
        }

        let sender = PacketSender(settings: settings, transport: transport)
        let tap = SystemAudioTap()
        let box = PipelineBox()

        do {
            try tap.start { samples, channels in
                box.pipeline?.process(interleaved: samples, channels: channels)
            }
        } catch {
            state = .failed("Не удалось прочитать системный звук")
            return
        }

        guard let format = tap.format,
              let pipeline = AudioPipeline(settings: settings, sampleRate: format.sampleRate)
        else {
            try? tap.stop()
            state = .failed("Не удалось подготовить обработку")
            return
        }

        box.set(pipeline)
        pipeline.onPacketUpdated = { [frameReady] in frameReady.signal() }

        self.tap = tap
        self.pipeline = pipeline
        self.sender = sender
        self._stopping.value = false
        self.quietFrames = 0

        sourceDescription = "\(tap.outputDeviceName) · \(Int(format.sampleRate)) Гц"
        destinationDescription = endpoints.map(\.description).joined(separator: ", ")

        // Отправка в отдельном потоке, разбуженном самим анализом: в аудиоколбэке
        // системных вызовов быть не должно, а независимый таймер бьётся с часами
        // аудиоустройства и теряет кадры.
        // Замыкание намеренно не захватывает self: класс изолирован в главном акторе,
        // а этот поток к нему не принадлежит. Берём только то, что потокобезопасно само по себе.
        let stopFlag = _stopping
        let ready = frameReady
        let thread = Thread {
            while !stopFlag.value {
                _ = ready.wait(timeout: .now() + .milliseconds(100))
                guard !stopFlag.value, let pipeline = box.pipeline else { continue }
                sender.send(pipeline.currentPacket())
                sender.sendKeepAliveIfNeeded()
            }
        }
        thread.name = "srwled.sender"
        thread.qualityOfService = .userInteractive
        thread.start()
        senderThread = thread

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Потоковая передача спектра на ленты")

        state = .silent
        startUITimer()
    }

    func stop() {
        guard isRunning else { return }

        _stopping.value = true
        frameReady.signal()

        // Гасим ленту: ни ваниль, ни MoonModules не гасят полосы при потере сигнала —
        // без этого эквалайзер застынет в последнем виде до перезагрузки ленты.
        sender?.fadeOut { seconds in Thread.sleep(forTimeInterval: seconds) }

        try? tap?.stop()
        tap = nil
        pipeline = nil
        sender = nil
        senderThread = nil

        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }

        uiTimer?.invalidate()
        uiTimer = nil

        bands = [Float](repeating: 0, count: 16)
        packetsPerSecond = 0
        state = .stopped
    }

    func restart() {
        if isRunning { stop() }
        start()
    }

    // MARK: Обновление интерфейса

    private func startUITimer() {
        _stopping.value = false
        uiTimer?.invalidate()
        // 10 раз в секунду: глазу достаточно, батарее не больно.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        uiTimer = timer
    }

    private func refresh() {
        guard let pipeline, let sender else { return }

        bands = pipeline.currentBands()
        let sent = sender.packetsSent
        packetsPerSecond = max(0, (sent - lastPacketCount) * 10)
        lastPacketCount = sent
        totalPackets = sent

        if let failure = sender.lastError {
            state = .failed(failure)
            return
        }

        if pipeline.isSilent {
            quietFrames += 1
            // Десять секунд идеальной цифровой тишины при работающем захвате —
            // почти наверняка не выдано разрешение: macOS в этом случае не отдаёт
            // ни ошибки, ни события, просто кладёт в буфер нули.
            state = quietFrames > 100 ? .noSignal : .silent
        } else {
            quietFrames = 0
            state = .playing
        }
    }
}

/// Держатель обработки: аудиопоток может позвать колбэк раньше, чем она создана.
final class PipelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AudioPipeline?

    var pipeline: AudioPipeline? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: AudioPipeline) {
        lock.lock(); value = newValue; lock.unlock()
    }
}

/// Простая потокобезопасная ячейка.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ value: T) { storage = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
