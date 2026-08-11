import Foundation

/// Отправка пакетов на ленты.
///
/// Три вещи, ради которых этот класс отдельный и тестируемый:
///
/// 1. **Счётчик кадров монотонный.** WLED-MM принимает пакет, только если счётчик вырос
///    относительно предыдущего. Оригинал обнулял счётчик на тишине — после первой же паузы
///    лента переставала принимать. Поэтому счётчиком владеет отправитель, а не обработка звука,
///    и увеличивается он на каждой отправке независимо от того, что там со звуком.
///
/// 2. **Ограничение частоты.** Документация WLED-MM: «An external sender may be slower,
///    but not faster than 20ms = 50fps». Быстрее — прошивка захлёбывается. Ограничитель стоит
///    здесь, чтобы никакие будущие правки анализа не смогли случайно превысить предел.
///
/// 3. **Keep-alive.** При 2500 мс молчания WLED считает источник потерянным. Шлём последний
///    пакет не реже чем раз в 500 мс — пятикратный запас.
public final class PacketSender: @unchecked Sendable {
    /// Минимальный интервал между пакетами — ровно нижняя граница, названная в документации
    /// WLED-MM: «not faster than 20ms = 50fps».
    ///
    /// Важно, чтобы порог был строго меньше естественного шага анализа (1024 отсчёта при
    /// 48 кГц — это 21.33 мс). Иначе дрожание таймера сбрасывает каждый второй кадр:
    /// с порогом 21 мс живой прогон давал 24 пакета в секунду вместо 47.
    public static let minSendInterval: TimeInterval = 0.020

    /// Не реже этого шлём повтор, даже если звука нет.
    public static let keepAliveInterval: TimeInterval = 0.5

    private let settings: Settings
    private let transport: PacketTransport
    private let now: @Sendable () -> TimeInterval

    private let lock = NSLock()
    private var frameCounter: UInt8 = 0
    private var lastSentAt: TimeInterval = -.infinity
    private var lastPacket = AudioSyncPacket()

    public private(set) var packetsSent = 0
    public private(set) var lastError: String?

    public let endpoints: [Endpoint]

    public init(settings: Settings,
                transport: PacketTransport,
                now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate })
    {
        self.settings = settings
        self.transport = transport
        self.now = now
        self.endpoints = Self.resolveEndpoints(settings: settings)
    }

    /// Список адресатов для выбранного режима. Чистая функция — её и проверяют тесты.
    public static func resolveEndpoints(settings: Settings) -> [Endpoint] {
        let port = settings.port
        switch settings.sendMode {
        case .broadcastLAN:
            return [Endpoint(host: "255.255.255.255", port: port)]
        case .multicast:
            return [Endpoint(host: "239.0.0.1", port: port)]
        case .broadcastSubnet:
            return parseIPList(settings.broadcastIPList).map { Endpoint(host: $0, port: port) }
        case .targetIPList:
            return parseIPList(settings.targetIPList).map { Endpoint(host: $0, port: port) }
        }
    }

    /// Требуется ли для режима разрешение на широковещательную рассылку.
    public static func needsBroadcast(_ mode: Settings.SendMode) -> Bool {
        mode == .broadcastLAN || mode == .broadcastSubnet
    }

    /// Разбор списка адресов: как в оригинале, разделителем считается любой символ,
    /// кроме цифры и точки. То есть запятая, точка с запятой, пробел и перевод строки — все годятся.
    public static func parseIPList(_ list: [String]) -> [String] {
        list.flatMap { entry -> [String] in
            entry.split(whereSeparator: { !$0.isNumber && $0 != "." })
                 .map(String.init)
        }
        .filter(isValidIPv4)
    }

    static func isValidIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    /// Отправляет пакет. Возвращает false, если сработал ограничитель частоты
    /// и пакет намеренно пропущен.
    @discardableResult
    public func send(_ packet: AudioSyncPacket) -> Bool {
        lock.lock()
        let timestamp = now()
        guard timestamp - lastSentAt >= Self.minSendInterval else {
            lock.unlock()
            return false
        }
        var outgoing = packet
        frameCounter &+= 1                 // монотонно и с корректным переходом 255 -> 0
        outgoing.frameCounter = frameCounter
        lastPacket = outgoing
        lastSentAt = timestamp
        lock.unlock()

        deliver(outgoing)
        return true
    }

    /// Вызывается по таймеру. Если давно не отправляли — повторяет последний пакет,
    /// чтобы прошивка не сочла источник потерянным.
    public func sendKeepAliveIfNeeded() {
        lock.lock()
        let timestamp = now()
        guard timestamp - lastSentAt >= Self.keepAliveInterval else {
            lock.unlock()
            return
        }
        var outgoing = lastPacket
        frameCounter &+= 1
        outgoing.frameCounter = frameCounter
        lastPacket = outgoing
        lastSentAt = timestamp
        lock.unlock()

        deliver(outgoing)
    }

    /// Плавное гашение при выходе: ни ваниль, ни MM не гасят полосы сами — без этого
    /// эквалайзер застынет в последнем виде до перезагрузки ленты.
    ///
    /// Ограничитель частоты здесь намеренно обходится: интервал между кадрами задаётся
    /// вызывающей стороной, а серия конечна.
    public func fadeOut(steps: Int = 10, pause: (TimeInterval) -> Void) {
        lock.lock()
        var packet = lastPacket
        lock.unlock()

        for _ in 0..<steps {
            packet.decay(rate: 0.5)
            lock.lock()
            frameCounter &+= 1
            packet.frameCounter = frameCounter
            lastPacket = packet
            lastSentAt = now()
            lock.unlock()

            deliver(packet)
            pause(Self.minSendInterval)
        }

        // Финальный гарантированно нулевой кадр.
        var silent = AudioSyncPacket()
        lock.lock()
        frameCounter &+= 1
        silent.frameCounter = frameCounter
        lastPacket = silent
        lastSentAt = now()
        lock.unlock()

        deliver(silent)
    }

    private func deliver(_ packet: AudioSyncPacket) {
        let bytes = packet.encoded()
        var failure: String?

        for endpoint in endpoints {
            do {
                try transport.send(bytes, to: endpoint)
            } catch {
                failure = "\(error)"
            }
        }

        lock.lock()
        packetsSent += 1
        lastError = failure
        lock.unlock()
    }

    /// Текущее значение счётчика — для тестов и индикации.
    public var currentFrameCounter: UInt8 {
        lock.lock()
        defer { lock.unlock() }
        return frameCounter
    }
}
