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
}

// MARK: - Разбор аргументов

func printUsage() {
    print("""
    srwled — сервер звуковой синхронизации для лент с WLED

    Использование:
      srwled --targets 192.168.1.50,192.168.1.51   отправка на конкретные адреса
      srwled --mode broadcast                       широковещательно по сети
      srwled --mode multicast                       на 239.0.0.1

    Параметры:
      --targets <список>   адреса лент через запятую (включает точечную отправку)
      --mode <режим>       broadcast | subnet | multicast | targets
      --port <номер>       порт (по умолчанию 11988)
      --seconds <N>        работать N секунд и выйти (по умолчанию до Ctrl-C)
      --quiet              не печатать индикатор уровня
      --help               эта справка

    Сравнение обработки:
      --original           вести себя в точности как Windows-версия
      --bands <вариант>    wled (по умолчанию) | custom — сетка полос
      --window <вариант>   hann (по умолчанию) | flattop — окно анализа
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

        case "--targets":
            guard let list = value() else { print("--targets требует список адресов"); return nil }
            options.settings.targetIPList = [list]
            options.settings.sendMode = .targetIPList

        case "--mode":
            guard let mode = value() else { print("--mode требует значение"); return nil }
            switch mode {
            case "broadcast": options.settings.sendMode = .broadcastLAN
            case "subnet": options.settings.sendMode = .broadcastSubnet
            case "multicast": options.settings.sendMode = .multicast
            case "targets": options.settings.sendMode = .targetIPList
            default: print("неизвестный режим: \(mode)"); return nil
            }

        case "--port":
            guard let text = value(), let port = UInt16(text) else {
                print("--port требует число"); return nil
            }
            options.settings.port = port

        case "--seconds":
            guard let text = value(), let seconds = Double(text) else {
                print("--seconds требует число"); return nil
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
            guard let value = value() else { print("--bands требует значение"); return nil }
            switch value {
            case "wled": options.settings.bandLayout = .wled
            case "custom": options.settings.bandLayout = .custom
            default: print("--bands принимает wled или custom"); return nil
            }

        case "--window":
            guard let value = value() else { print("--window требует значение"); return nil }
            switch value {
            case "hann": options.settings.window = .hann
            case "flattop": options.settings.window = .flatTop
            default: print("--window принимает hann или flattop"); return nil
            }

        case "--quiet":
            options.quiet = true

        default:
            print("неизвестный параметр: \(flag)")
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
        print("Некуда отправлять: укажи --targets со списком адресов или выбери --mode broadcast.")
        return 1
    }

    let transport: PacketTransport
    do {
        transport = try UDPTransport(
            allowBroadcast: PacketSender.needsBroadcast(options.settings.sendMode))
    } catch {
        print("Не удалось открыть сокет: \(error)")
        return 1
    }

    let sender = PacketSender(settings: options.settings, transport: transport)
    let box = PipelineBox()
    let tap = SystemAudioTap()

    do {
        try tap.start { samples, channels in
            box.pipeline?.process(interleaved: samples, channels: channels)
        }
    } catch {
        print("""
        Не удалось запустить захват системного звука: \(error)

        Если macOS не спросила разрешение — выдай его вручную:
          Системные настройки → Конфиденциальность и безопасность → Запись звука.
        """)
        return 1
    }

    guard let format = tap.format,
          let pipeline = AudioPipeline(settings: options.settings, sampleRate: format.sampleRate)
    else {
        print("Не удалось подготовить обработку звука.")
        try? tap.stop()
        return 1
    }
    box.set(pipeline)

    print("Источник звука: \(tap.outputDeviceName), \(Int(format.sampleRate)) Гц, \(format.channels) кан.")
    print("Отправка: \(endpoints.map(\.description).joined(separator: ", "))")
    print("Обработка: полосы \(options.settings.bandLayout.rawValue), окно "
          + "\(options.settings.window.rawValue), уровень \(options.settings.loudness.rawValue)")
    print("")

    // Отправка идёт в отдельном потоке, разбуженном самим анализом.
    //
    // Не в аудиоколбэке — системный вызов в нём даёт рывки. Но и не по независимому таймеру:
    // таймер Dispatch и аудиоустройство тактируются разными часами, бьются друг о друга,
    // и ограничитель периодически срезает кадр. На живом прогоне это давало 40 пакетов
    // в секунду вместо 47. Семафор привязывает отправку ровно к готовности кадра.
    let frameReady = DispatchSemaphore(value: 0)
    let stopping = OnceFlag()
    pipeline.onPacketUpdated = { frameReady.signal() }

    let senderFinished = DispatchSemaphore(value: 0)
    let senderThread = Thread {
        while !stopping.isSet {
            // Таймаут нужен, чтобы keep-alive шёл даже если звук исчез совсем
            // (например, устройство вывода пропало).
            _ = frameReady.wait(timeout: .now() + .milliseconds(100))
            guard !stopping.isSet, let pipeline = box.pipeline else { continue }
            sender.send(pipeline.currentPacket())
            sender.sendKeepAliveIfNeeded()
        }
        senderFinished.signal()
    }
    senderThread.name = "srwled.sender"
    senderThread.qualityOfService = .userInteractive
    senderThread.start()

    let uiTimer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "srwled.ui"))
    if !options.quiet {
        let blocks = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        uiTimer.schedule(deadline: .now() + 0.3, repeating: 0.1)
        uiTimer.setEventHandler {
            guard let pipeline = box.pipeline else { return }
            let bar = pipeline.currentBands().map { value -> String in
                let index = min(blocks.count - 1, max(0, Int(value * Float(blocks.count - 1) + 0.5)))
                return blocks[index]
            }.joined()
            let status = pipeline.isSilent ? "тишина" : "звук  "
            let failure = sender.lastError.map { " ⚠︎ \($0)" } ?? ""
            print("\r[\(bar)] \(status)  пакетов: \(sender.packetsSent)\(failure)   ", terminator: "")
            fflush(stdout)
        }
        uiTimer.resume()
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

    if options.seconds > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + options.seconds) {
            if once.fire() { done.signal() }
        }
    }

    done.wait()

    _ = stopping.fire()
    frameReady.signal()              // разбудить поток отправки, чтобы он вышел
    if !options.quiet { uiTimer.cancel() }
    // Дожидаемся именно завершения потока, а не фиксированной паузы: пауза создавала
    // разрыв в потоке пакетов на ровном месте.
    _ = senderFinished.wait(timeout: .now() + .milliseconds(300))

    // Гасим ленту, а не бросаем её в последнем кадре: ни ваниль, ни MM полосы сами не гасят.
    print("\n\nГашение ленты…")
    sender.fadeOut { seconds in Thread.sleep(forTimeInterval: seconds) }

    try? tap.stop()
    print("Отправлено пакетов: \(sender.packetsSent). Захват остановлен, устройства освобождены.")
    return 0
}

exit(runServer())
