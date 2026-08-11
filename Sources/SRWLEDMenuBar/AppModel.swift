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

    /// Последняя причина пересборки захвата — показывается в меню.
    @Published private(set) var lastRestartReason: String?
    @Published private(set) var diagnostics = Diagnostics(lines: [])
    @Published var launchAtLogin: Bool = LoginItem.state.isOn {
        didSet {
            guard launchAtLogin != oldValue else { return }
            loginItemProblem = LoginItem.set(launchAtLogin) ?? LoginItem.state.explanation
        }
    }
    @Published private(set) var loginItemProblem: String? = LoginItem.state.explanation

    private let defaults = UserDefaults.standard
    private var session: CaptureSession?
    private var sender: PacketSender?
    private var senderThread: Thread?
    private var silenceStartedAt: Date?
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
        let ready = frameReady

        // Захват умеет пересобирать себя при смене наушников, частоты или устройства.
        // Отправитель при этом остаётся тем же — он владеет счётчиком кадров,
        // а тот обязан быть строго монотонным, иначе WLED-MM отбросит пакеты.
        let session = CaptureSession(
            settings: settings,
            onFrameReady: { ready.signal() },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            })

        do {
            try session.start()
        } catch {
            state = .failed("Не удалось прочитать системный звук")
            return
        }

        self.session = session
        self.sender = sender
        self._stopping.value = false
        self.quietFrames = 0
        self.silenceStartedAt = nil

        sourceDescription = "\(session.deviceName) · \(Int(session.sampleRate)) Гц"
        destinationDescription = endpoints.map(\.description).joined(separator: ", ")

        // Отправка в отдельном потоке, разбуженном самим анализом: в аудиоколбэке
        // системных вызовов быть не должно, а независимый таймер бьётся с часами
        // аудиоустройства и теряет кадры.
        // Замыкание намеренно не захватывает self: класс изолирован в главном акторе,
        // а этот поток к нему не принадлежит.
        let stopFlag = _stopping
        let thread = Thread {
            while !stopFlag.value {
                _ = ready.wait(timeout: .now() + .milliseconds(100))
                guard !stopFlag.value, let pipeline = session.pipeline else { continue }
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

        session?.stop()
        session = nil
        sender = nil
        senderThread = nil
        lastRestartReason = nil

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

    /// Пробуждение после сна: пересобираем захват, но отправитель не трогаем —
    /// счётчик кадров обязан остаться монотонным.
    func handleWake() {
        guard isRunning else { return }
        session?.restart(reason: "пробуждение после сна")
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

    /// События захвата: пересборка при смене устройства, ошибки.
    private func handle(_ event: CaptureSession.Event) {
        switch event {
        case .started(let sampleRate, _, let device):
            sourceDescription = "\(device) · \(Int(sampleRate)) Гц"

        case .restarted(let reason):
            sourceDescription = "\(session?.deviceName ?? "") · \(Int(session?.sampleRate ?? 0)) Гц"
            lastRestartReason = reason
            silenceStartedAt = nil
            quietFrames = 0

        case .failed(let message):
            state = .failed(message)

        case .stopped:
            break
        }
    }

    private func refresh() {
        guard let session, let sender, let pipeline = session.pipeline else { return }

        bands = pipeline.currentBands()
        let sent = sender.packetsSent
        packetsPerSecond = max(0, (sent - lastPacketCount) * 10)
        lastPacketCount = sent
        totalPackets = sent

        if pipeline.isSilent {
            if silenceStartedAt == nil { silenceStartedAt = Date() }
            quietFrames += 1
            // Десять секунд идеальной цифровой тишины при работающем захвате —
            // почти наверняка не выдано разрешение: macOS в этом случае не отдаёт
            // ни ошибки, ни события, просто кладёт в буфер нули.
            state = quietFrames > 100 ? .noSignal : .silent
        } else {
            silenceStartedAt = nil
            quietFrames = 0
            state = .playing
        }

        if let failure = sender.lastError {
            state = .failed(failure)
        }

        diagnostics = Diagnostics.make(
            captureRunning: true,
            digitalSilenceSeconds: silenceStartedAt.map { Date().timeIntervalSince($0) } ?? 0,
            deviceName: session.deviceName,
            sampleRate: session.sampleRate,
            endpoints: sender.endpoints,
            packetsPerSecond: packetsPerSecond,
            networkError: sender.lastError,
            bandsAlive: bands.contains { $0 > 0 })
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
