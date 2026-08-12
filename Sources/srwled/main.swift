import Dispatch
import Foundation
import SRWLEDCore

// Консольная версия сервера: захватывает системный звук и шлёт пакеты на ленты.
// Нужна для этапа M0 — доказать, что пакеты доходят, ещё до всякого интерфейса.
//
// Вся работа вынесена в обычную функцию: код верхнего уровня в Swift 6 неявно @MainActor,
// а замыкания аудиопотока и таймеров обязаны быть @Sendable — внутри функции этого конфликта нет.

// MARK: - Вспомогательные типы

/// Держатель обработки: аудиопоток может позвать колбэк раньше, чем мы успеем её создать.
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

/// Флаг «сработало один раз»: чтобы Ctrl-C и таймер не завершили работу дважды.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return fired
    }
}

struct Options {
    var settings = Settings()
    var seconds: Double = 0          // 0 — до Ctrl-C
    var quiet = false
    /// Через сколько секунд принудительно пересобрать захват — для проверки
    /// того, что перезапуск не рвёт поток и не сбивает счётчик кадров.
    var restartAfter: Double = 0
}

// MARK: - Разбор аргументов

/// Язык консольной версии — язык системы, как и у приложения.
///
/// Читается один раз: за время работы он не меняется, а обращений к нему
/// в горячем пути отправки быть не должно.
let cliLanguage = Language.systemDefault

func t(_ key: S, _ values: String...) -> String {
    values.isEmpty ? L10n.string(key, cliLanguage)
                   : L10n.string(key, cliLanguage, values)
}

func printUsage() {
    // Имена параметров не переводятся: их набирают, а не читают.
    print("""
    srwled — \(t(.cliTagline))

    \(t(.cliUsage))
      srwled --targets 192.168.1.50,192.168.1.51   \(t(.cliUseTargets))
      srwled --mode broadcast                       \(t(.cliUseBroadcast))
      srwled --mode multicast                       \(t(.cliUseMulticast))

    \(t(.cliOptions))
      --targets <...>      \(t(.cliOptTargets))
      --mode <...>         \(t(.cliOptMode)): broadcast | subnet | multicast | targets
      --port <N>           \(t(.cliOptPort))
      --seconds <N>        \(t(.cliOptSeconds))
      --quiet              \(t(.cliOptQuiet))
      --restart-after <N>  \(t(.cliOptRestart))
      --version            \(t(.cliOptVersion))
      --help               \(t(.cliOptHelp))

    \(t(.cliCompare))
      --original           \(t(.cliOptOriginal))
      --bands <...>        \(t(.cliOptBands))
      --window <...>       \(t(.cliOptWindow))
    """)
}

func parseOptions() -> Options?? {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())

    while !arguments.isEmpty {
        let flag = arguments.removeFirst()
        func value() -> String? { arguments.isEmpty ? nil : arguments.removeFirst() }

        switch flag {
        case "--help", "-h":
            printUsage()
            return .some(nil)          // штатный выход

        case "--version", "-v":
            print("srwled \(Version.current) (\(t(.cliBuild)) \(Version.build))")
            return .some(nil)

        case "--targets":
            guard let list = value() else { print(t(.cliNeedsList, "--targets")); return nil }
            options.settings.targetIPList = [list]
            options.settings.sendMode = .targetIPList

        case "--mode":
            guard let mode = value() else { print(t(.cliNeedsValue, "--mode")); return nil }
            switch mode {
            case "broadcast": options.settings.sendMode = .broadcastLAN
            case "subnet": options.settings.sendMode = .broadcastSubnet
            case "multicast": options.settings.sendMode = .multicast
            case "targets": options.settings.sendMode = .targetIPList
            default: print(t(.cliUnknownMode, mode)); return nil
            }

        case "--port":
            guard let text = value(), let port = UInt16(text) else {
                print(t(.cliNeedsNumber, "--port")); return nil
            }
            options.settings.port = port

        case "--seconds":
            guard let text = value(), let seconds = Double(text) else {
                print(t(.cliNeedsNumber, "--seconds")); return nil
            }
            options.seconds = seconds

        case "--original":
            // Полностью поведение Windows-версии — для сравнения бок о бок.
            let network = options.settings
            options.settings = Settings.originalCompatible()
            options.settings.port = network.port
            options.settings.sendMode = network.sendMode
            options.settings.targetIPList = network.targetIPList
            options.settings.broadcastIPList = network.broadcastIPList

        case "--bands":
            guard let value = value() else { print(t(.cliNeedsValue, "--bands")); return nil }
            switch value {
            case "wled": options.settings.bandLayout = .wled
            case "custom": options.settings.bandLayout = .custom
            default: print(t(.cliAccepts, "--bands", "wled, custom")); return nil
            }

        case "--window":
            guard let value = value() else { print(t(.cliNeedsValue, "--window")); return nil }
            switch value {
            case "hann": options.settings.window = .hann
            case "flattop": options.settings.window = .flatTop
            default: print(t(.cliAccepts, "--window", "hann, flattop")); return nil
            }

        case "--restart-after":
            guard let text = value(), let seconds = Double(text) else {
                print(t(.cliNeedsNumber, "--restart-after")); return nil
            }
            options.restartAfter = seconds

        case "--quiet":
            options.quiet = true

        default:
            print(t(.cliUnknownOption, flag))
            printUsage()
            return nil
        }
    }
    return .some(options)
}

// MARK: - Основная работа

func runServer() -> Int32 {
    guard let parsed = parseOptions() else { return 1 }
    guard let options = parsed else { return 0 }

    let endpoints = PacketSender.resolveEndpoints(settings: options.settings)
    guard !endpoints.isEmpty else {
        print("\(t(.failNoTargets)). \(t(.cliNoTargetsHint))")
        return 1
    }

    let transport: PacketTransport
    do {
        transport = try UDPTransport(
            allowBroadcast: PacketSender.needsBroadcast(options.settings.sendMode))
    } catch {
        print("\(t(.cliSocketFailed)): \(error)")
        return 1
    }

    let sender = PacketSender(settings: options.settings, transport: transport)
    let frameReady = DispatchSemaphore(value: 0)

    // Захват пересобирает себя сам при смене устройства вывода, частоты или после сна.
    // Отправитель при этом остаётся тем же: он владеет счётчиком кадров, а тот обязан
    // быть строго монотонным, иначе WLED-MM отбросит пакеты.
    let session = CaptureSession(
        settings: options.settings,
        onFrameReady: { frameReady.signal() },
        onEvent: { event in
            switch event {
            case .restarted(let reason, let detail):
                let tail = detail.isEmpty ? "" : ": \(detail)"
                print("\n[\(t(.captureRestarted)): \(t(reason))\(tail)]")
            case .failed(let reason, let detail):
                let tail = detail.isEmpty ? "" : ": \(detail)"
                print("\n[\(t(.cliCaptureError)): \(t(reason))\(tail)]")
            case .started, .stopped:
                break
            }
        })

    do {
        try session.start()
    } catch {
        print("""
        \(t(.failCapture)): \(error)

        \(t(.cliPermissionHint))
        """)
        return 1
    }

    print(t(.cliSource, session.deviceName, "\(Int(session.sampleRate))", "\(session.channels)"))
    print(t(.cliSending, endpoints.map(\.description).joined(separator: ", ")))
    print(t(.cliProcessing,
            options.settings.bandLayout.rawValue,
            options.settings.window.rawValue,
            options.settings.loudness.rawValue))
    print("")

    // Отправка идёт в отдельном потоке, разбуженном самим анализом.
    //
    // Не в аудиоколбэке — системный вызов в нём даёт рывки. Но и не по независимому таймеру:
    // таймер Dispatch и аудиоустройство тактируются разными часами, бьются друг о друга,
    // и ограничитель периодически срезает кадр. На живом прогоне это давало 40 пакетов
    // в секунду вместо 47. Семафор привязывает отправку ровно к готовности кадра.
    let stopping = OnceFlag()

    let senderFinished = DispatchSemaphore(value: 0)
    let senderThread = Thread {
        while !stopping.isSet {
            // Таймаут нужен, чтобы keep-alive шёл даже если звук исчез совсем
            // (например, устройство вывода пропало).
            _ = frameReady.wait(timeout: .now() + .milliseconds(100))
            guard !stopping.isSet, let pipeline = session.pipeline else { continue }
            sender.send(pipeline.currentPacket())
            sender.sendKeepAliveIfNeeded()
        }
        senderFinished.signal()
    }
    senderThread.name = "srwled.sender"
    senderThread.qualityOfService = .userInteractive
    senderThread.start()

    // Источник создаётся только когда он действительно нужен: неразрезюмированный
    // DispatchSource при уничтожении роняет процесс по SIGTRAP.
    var uiTimer: DispatchSourceTimer?
    if !options.quiet {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "srwled.ui"))
        let blocks = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        timer.schedule(deadline: .now() + 0.3, repeating: 0.1)
        timer.setEventHandler {
            guard let pipeline = session.pipeline else { return }
            let bar = pipeline.currentBands().map { value -> String in
                let index = min(blocks.count - 1, max(0, Int(value * Float(blocks.count - 1) + 0.5)))
                return blocks[index]
            }.joined()
            let status = pipeline.isSilent ? t(.silent) : t(.playing)
            let failure = sender.lastError.map { " ⚠︎ \($0)" } ?? ""
            print("\r[\(bar)] \(status)  \(t(.cliPackets)): \(sender.packetsSent)\(failure)   ", terminator: "")
            fflush(stdout)
        }
        timer.resume()
        uiTimer = timer
    }

    // Завершение по Ctrl-C или по таймеру.
    let done = DispatchSemaphore(value: 0)
    let once = OnceFlag()

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    for source in [sigint, sigterm] {
        source.setEventHandler { if once.fire() { done.signal() } }
        source.resume()
    }

    if options.restartAfter > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + options.restartAfter) {
            session.restart(reason: .restartCheck)
        }
    }

    if options.seconds > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + options.seconds) {
            if once.fire() { done.signal() }
        }
    }

    done.wait()

    _ = stopping.fire()
    frameReady.signal()              // разбудить поток отправки, чтобы он вышел
    uiTimer?.cancel()
    // Дожидаемся именно завершения потока, а не фиксированной паузы: пауза создавала
    // разрыв в потоке пакетов на ровном месте.
    _ = senderFinished.wait(timeout: .now() + .milliseconds(300))

    // Гасим ленту, а не бросаем её в последнем кадре: ни ваниль, ни MM полосы сами не гасят.
    print("\n\n\(t(.cliFading))")
    sender.fadeOut { seconds in Thread.sleep(forTimeInterval: seconds) }

    session.stop()
    print(t(.cliFinished, "\(sender.packetsSent)"))
    return 0
}

exit(runServer())
