import AppKit
import SwiftUI
import SRWLEDVisuals
import SRWLEDCore

/// Содержимое MenuBarExtra создаётся только при открытии меню, поэтому автозапуск
/// вешаем на делегат приложения — иначе сервер поднимался бы лишь после первого клика.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Создаётся лениво в главном акторе: StatusItemController изолирован в нём,
    /// а сам делегат — нет.
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let controller = StatusItemController()
            controller.install(model: AppModel.shared)
            statusItem = controller
            AppModel.shared.startAutomaticallyIfReady()
        }

        // После сна аудиоустройства нередко возвращаются с другими параметрами,
        // а уведомления CoreAudio об этом приходят не всегда — пересобираем захват сами.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.handleWake()
            }
        }
    }

    /// Клик по значку в Dock при закрытом окне возвращает окно, а не создаёт пустоту.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Гасим ленту перед выходом, иначе эквалайзер застынет в последнем виде.
        MainActor.assumeIsolated {
            statusItem?.remove()
            AppModel.shared.stop()
        }
    }
}

@main
struct SRWLEDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow

    private func openAbout() {
        openWindow(id: "about")
    }

    var body: some Scene {
        // Главное окно: значок в Dock, крупная визуализация, все настройки.
        Window(Brand.shortName, id: "main") {
            MainWindow(model: model)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(model.localized(.aboutApp)) { openAbout() }
            }
        }

        Window("О программе", id: "about") {
            AboutWindow(model: model)
        }
        .windowResizability(.contentSize)

        // Значок в строке меню делает StatusItemController на AppKit:
        // сцена MenuBarExtra в этом приложении элемент не создаёт вовсе.
    }
}
