import Foundation
import ServiceManagement

/// Автозапуск при входе в систему.
///
/// Обёрнут отдельно, потому что состояний у него четыре, а не два: система может
/// ждать подтверждения пользователя или быть настроенной так, что запуск запрещён.
/// Показывать это как обычный переключатель «вкл/выкл» — врать человеку.
enum LoginItem {

    enum State {
        case enabled
        case disabled
        case requiresApproval
        case notSupported

        var isOn: Bool { self == .enabled }

        var explanation: String? {
            switch self {
            case .requiresApproval:
                return "Разреши запуск в Системных настройках → Основные → Объекты входа"
            case .notSupported:
                return "Автозапуск доступен только для приложения, установленного в /Applications"
            default:
                return nil
            }
        }
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notSupported
        @unknown default: return .notSupported
        }
    }

    /// Возвращает текст ошибки, если включить не удалось.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
