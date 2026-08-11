import AppKit
import SwiftUI

/// Содержимое MenuBarExtra создаётся только при открытии меню, поэтому автозапуск
/// вешаем на делегат приложения — иначе сервер поднимался бы лишь после первого клика.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.startAutomaticallyIfReady()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Гасим ленту перед выходом, иначе эквалайзер застынет в последнем виде.
        MainActor.assumeIsolated {
            AppModel.shared.stop()
        }
    }
}

@main
struct SRWLEDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Значок в строке меню. При включённой опции показывает живой спектр,
/// иначе — символ состояния.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.showSpectrumInMenuBar && model.isRunning {
            SpectrumStrip(bands: model.bands, barCount: 16)
                .frame(width: 34, height: 16)
        } else {
            Image(systemName: model.state.symbol)
        }
    }
}

/// Полоски спектра. Рисуются через Canvas: 16 прямоугольников дешевле,
/// чем столько же вью в стеке, а перерисовка идёт 10 раз в секунду.
struct SpectrumStrip: View {
    let bands: [Float]
    var barCount: Int = 16

    var body: some View {
        Canvas { context, size in
            guard barCount > 0 else { return }
            let gap: CGFloat = 1
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            guard barWidth > 0 else { return }

            for index in 0..<barCount {
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = max(1, value * size.height)
                let rect = CGRect(x: CGFloat(index) * (barWidth + gap),
                                  y: size.height - height,
                                  width: barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 3),
                             with: .color(.primary))
            }
        }
    }
}
