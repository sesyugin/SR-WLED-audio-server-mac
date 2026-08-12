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
            Self.closeRestoredAboutWindow()
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

    /// Закрывает «О программе», если его вернуло восстановление окон.
    ///
    /// macOS запоминает открытые окна и открывает их снова при следующем запуске.
    /// Для главного окна это правильно, а для «О программе» — нет: посмотрел
    /// один раз, и оно встречает тебя при каждом запуске, пока не догадаешься
    /// закрыть его перед выходом. `restorationBehavior` появился только
    /// в macOS 15, а нижняя граница у нас 14.2 — поэтому закрываем руками.
    @MainActor
    private static func closeRestoredAboutWindow() {
        // На следующем витке цикла: во время самого запуска восстановленные
        // окна ещё не созданы.
        DispatchQueue.main.async {
            for window in NSApp.windows
            where window.identifier?.rawValue.contains("about") == true {
                window.close()
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
        Window(Brand.name, id: "main") {
            MainWindow(model: model)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(model.localized(.aboutApp)) { openAbout() }
            }
        }

        Window(model.localized(.aboutApp), id: "about") {
            AboutWindow(model: model)
        }
        .windowResizability(.contentSize)

        // Значок в строке меню делает StatusItemController на AppKit:
        // сцена MenuBarExtra в этом приложении элемент не создаёт вовсе.
    }
}
