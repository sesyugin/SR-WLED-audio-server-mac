import Foundation

/// Адресат отправки.
public struct Endpoint: Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public var description: String { "\(host):\(port)" }
}

/// Транспорт для пакетов. Вынесен в протокол, чтобы тесты гоняли отправку
/// без реальных сокетов и гарантированно не задели живые ленты в квартире.
public protocol PacketTransport: Sendable {
    func send(_ bytes: [UInt8], to endpoint: Endpoint) throws
}

/// Обычный UDP-сокет.
public final class UDPTransport: PacketTransport, @unchecked Sendable {
    public enum TransportError: Error, CustomStringConvertible {
        case socketFailed(errno: Int32)
        case optionFailed(String, errno: Int32)
        case badAddress(String)
        case sendFailed(Endpoint, errno: Int32)

        public var description: String {
            switch self {
            case .socketFailed(let code):
                return "не удалось создать сокет: \(String(cString: strerror(code)))"
            case .optionFailed(let option, let code):
                return "не удалось выставить \(option): \(String(cString: strerror(code)))"
            case .badAddress(let host):
                return "некорректный адрес: \(host)"
            case .sendFailed(let endpoint, let code):
                return "отправка на \(endpoint) не удалась: \(String(cString: strerror(code)))"
            }
        }
    }

    private let fd: Int32
    private let lock = NSLock()

    /// - Parameter allowBroadcast: включает `SO_BROADCAST`. Нужен только для режимов
    ///   широковещательной рассылки — в остальных намеренно выключен, чтобы случайная
    ///   отправка на 255.255.255.255 не прошла молча.
    public init(allowBroadcast: Bool) throws {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw TransportError.socketFailed(errno: errno) }

        if allowBroadcast {
            var enable: Int32 = 1
            let result = setsockopt(fd, SOL_SOCKET, SO_BROADCAST,
                                    &enable, socklen_t(MemoryLayout<Int32>.size))
            guard result == 0 else {
                close(fd)
                throw TransportError.optionFailed("SO_BROADCAST", errno: errno)
            }
        }
    }

    deinit {
        close(fd)
    }

    public func send(_ bytes: [UInt8], to endpoint: Endpoint) throws {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = endpoint.port.bigEndian

        guard inet_pton(AF_INET, endpoint.host, &address.sin_addr) == 1 else {
            throw TransportError.badAddress(endpoint.host)
        }

        lock.lock()
        defer { lock.unlock() }

        let sent = bytes.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(fd, buffer.baseAddress, buffer.count, 0,
                           sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent == bytes.count else {
            throw TransportError.sendFailed(endpoint, errno: errno)
        }
    }
}
