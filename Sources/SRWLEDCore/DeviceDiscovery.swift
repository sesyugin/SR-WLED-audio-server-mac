import Foundation
import Network

/// Найденная в сети лента.
public struct DiscoveredDevice: Sendable, Identifiable, Equatable {
    public let name: String
    public let host: String
    public let port: UInt16

    /// Состояние синхронизации, вычитанное с устройства. Пока не спрашивали — nil.
    public var status: DeviceStatus?

    public var id: String { host }

    public init(name: String, host: String, port: UInt16 = 80, status: DeviceStatus? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.status = status
    }
}

/// Что лента сообщает о себе через свой JSON API.
public struct DeviceStatus: Sendable, Equatable {
    public enum SyncState: String, Sendable {
        case receivingV2 = "принимает, протокол v2"
        case receivingV1 = "принимает, протокол v1"
        case idle = "ждёт сигнала"
        case sending = "сама передаёт"
        case disabled = "синхронизация выключена"
        case noUsermod = "звуковой модуль не собран"
        case unknown = "непонятно"
    }

    public let version: String
    public let syncState: SyncState
    public let rawAudioSource: String

    public var isReceivingFromUs: Bool {
        syncState == .receivingV2 || syncState == .receivingV1
    }
}

/// Автопоиск лент с WLED и опрос их состояния.
///
/// Зачем: у Windows-версии автопоиска нет вовсе, и адреса приходится вводить руками —
/// это её самый частый класс обращений. Плюс опрос `/json/info` даёт удалённую проверку
/// того, что наш пакет вообще принят: суффикс версии прошивка выставляет, только если
/// пакет прошёл обе её проверки — размер ровно 44 байта и верный заголовок.
public final class DeviceDiscovery: @unchecked Sendable {

    private let browserQueue = DispatchQueue(label: "srwled.discovery")
    private var browser: NWBrowser?
    private let lock = NSLock()
    private var found: [String: DiscoveredDevice] = [:]

    /// Вызывается при любом изменении списка.
    public var onUpdate: (@Sendable ([DiscoveredDevice]) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public var devices: [DiscoveredDevice] {
        lock.lock(); defer { lock.unlock() }
        return found.values.sorted { $0.name < $1.name }
    }

    // MARK: - Поиск

    public func start() {
        stop()

        // WLED публикует себя как _wled._tcp. Ленты, у которых mDNS выключен,
        // придётся вводить руками — для этого остаётся поле со списком адресов.
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_wled._tcp", domain: nil),
                                using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                self.resolve(serviceName: name, endpoint: result.endpoint)
            }
        }

        browser.start(queue: browserQueue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Превращает найденную службу в адрес. Bonjour отдаёт имя, а нам нужен IP.
    private func resolve(serviceName: String, endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   case let .hostPort(host, port) = remote
                {
                    let address: String
                    switch host {
                    case .ipv4(let value): address = "\(value)".components(separatedBy: "%").first ?? "\(value)"
                    case .ipv6(let value): address = "\(value)"
                    case .name(let value, _): address = value
                    @unknown default: address = "\(host)"
                    }
                    self.add(DiscoveredDevice(name: serviceName,
                                              host: address,
                                              port: port.rawValue))
                }
                connection.cancel()
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: browserQueue)
    }

    private func add(_ device: DiscoveredDevice) {
        lock.lock()
        let isNew = found[device.host] == nil
        if isNew { found[device.host] = device }
        let snapshot = found.values.sorted { $0.name < $1.name }
        lock.unlock()

        if isNew { onUpdate?(snapshot) }
    }

    /// Добавляет устройство вручную — для лент без mDNS.
    public func addManual(host: String, name: String = "введено вручную") {
        add(DiscoveredDevice(name: name, host: host))
    }

    // MARK: - Опрос состояния

    /// Спрашивает у ленты, принимает ли она наш поток.
    public func refreshStatus(of device: DiscoveredDevice,
                              timeout: TimeInterval = 3,
                              completion: @escaping @Sendable (DeviceStatus?) -> Void)
    {
        guard let url = URL(string: "http://\(device.host)/json/info") else {
            completion(nil); return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let status = Self.parseInfo(data) else {
                completion(nil); return
            }
            self?.updateStatus(host: device.host, status: status)
            completion(status)
        }.resume()
    }

    private func updateStatus(host: String, status: DeviceStatus) {
        lock.lock()
        found[host]?.status = status
        let snapshot = found.values.sorted { $0.name < $1.name }
        lock.unlock()
        onUpdate?(snapshot)
    }

    /// Разбирает ответ `/json/info`.
    ///
    /// Прошивка кладёт состояние синхронизации в массив `u` («usermods») под ключом,
    /// начинающимся с «UDP Sound Sync». Суффикс « v2» появляется, только если пакет
    /// прошёл обе проверки прошивки — размер и заголовок.
    public static func parseInfo(_ data: Data) -> DeviceStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let version = root["ver"] as? String ?? "неизвестна"
        let usermods = root["u"] as? [String: Any] ?? [:]

        // Ищем строку про звуковую синхронизацию среди всех ключей usermods.
        var audioText = ""
        for (key, value) in usermods {
            let lowered = key.lowercased()
            guard lowered.contains("sound") || lowered.contains("audio") else { continue }
            if let parts = value as? [Any] {
                audioText += parts.map { "\($0)" }.joined(separator: " ") + " "
            } else {
                audioText += "\(value) "
            }
        }

        let text = audioText.lowercased()
        let state: DeviceStatus.SyncState

        if audioText.isEmpty {
            state = .noUsermod
        } else if text.contains("v2") && text.contains("receiv") {
            state = .receivingV2
        } else if text.contains("v1") && text.contains("receiv") {
            state = .receivingV1
        } else if text.contains("send") || text.contains("transmit") {
            state = .sending
        } else if text.contains("idle") || text.contains("waiting") {
            state = .idle
        } else if text.contains("off") || text.contains("disabled") {
            state = .disabled
        } else {
            state = .unknown
        }

        return DeviceStatus(version: version,
                            syncState: state,
                            rawAudioSource: audioText.trimmingCharacters(in: .whitespaces))
    }
}
