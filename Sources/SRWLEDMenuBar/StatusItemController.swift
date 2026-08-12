import AppKit
import Combine
import SwiftUI
import SRWLEDVisuals

/// Значок в строке меню на AppKit.
///
/// Не SwiftUI `MenuBarExtra` по одной причине: его метка рендерится в статичное
/// изображение, а нам нужен живой спектр, перерисовываемый десять раз в секунду.
/// `NSStatusItem` даёт прямой доступ к изображению кнопки.
///
/// Замечание на будущее: наличие значка нельзя проверять через `CGWindowListCopyWindowInfo` —
/// macOS рисует строку меню сама, и отдельными окнами элементы там не числятся.
/// Проверять надо через сам `NSStatusItem`: `isVisible`, `button`, `button.image`.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var model: AppModel?
    private var refreshTimer: Timer?

    /// Слепок полос, по которому был нарисован значок. Спектр в строке меню
    /// шириной 34 точки: полоса в нём — два пикселя, и разницу меньше
    /// двадцатой доли высоты там не видно физически. Значок перерисовывается
    /// только когда слепок изменился.
    ///
    /// Дело не в экономии на самой отрисовке — она копеечная. Каждая
    /// перерисовка создавала новый NSImage и отдавала его строке меню:
    /// десять раз в секунду, двадцать тысяч изображений за полчаса работы.
    /// Система их кэширует, и к концу такого сеанса приложение занимало
    /// памятью заметно больше, чем в начале.
    private var drawnBands: [UInt8] = []
    /// Каким был признак «показывать спектр» на прошлой отрисовке.
    private var drawnAsSpectrum: Bool?

    func install(model: AppModel) {
        self.model = model

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.toolTip = Brand.name
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.contentViewController = NSHostingController(rootView: MenuContent(model: model))
        self.popover = popover

        redraw()

        // Десять раз в секунду: глазу достаточно, батарее не больно.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.redraw() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func remove() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    // MARK: Отрисовка

    private func redraw() {
        guard let model, let button = statusItem?.button else { return }

        let asSpectrum = model.showSpectrumInMenuBar && model.isRunning
        if asSpectrum {
            // Квантуем в двадцать ступеней: столько их и различимо на высоте
            // значка. В тишине и на ровном звуке слепок не меняется вовсе,
            // и строка меню не трогается ни разу.
            let quantised = model.bands.map { UInt8(max(0, min(20, ($0 * 20).rounded()))) }
            guard quantised != drawnBands || drawnAsSpectrum != true else { return }
            drawnBands = quantised
            drawnAsSpectrum = true
            button.image = Self.spectrumImage(bands: model.bands)
        } else {
            guard drawnAsSpectrum != false || button.image == nil else { return }
            drawnAsSpectrum = false
            drawnBands = []
            let symbol = NSImage(systemSymbolName: model.state.symbol,
                                 accessibilityDescription: model.state.title)
            symbol?.isTemplate = true
            button.image = symbol
        }
    }

    /// Рисует 16 полосок в изображение-шаблон: система сама перекрасит его
    /// под светлую или тёмную строку меню.
    private static func spectrumImage(bands: [Float]) -> NSImage {
        let size = NSSize(width: 34, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let count = 16
            let gap: CGFloat = 0.7
            let barWidth = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
            guard barWidth > 0 else { return true }

            NSColor.black.setFill()
            for index in 0..<count {
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = max(1.5, value * rect.height)
                let bar = NSRect(x: CGFloat(index) * (barWidth + gap),
                                 y: 0,
                                 width: barWidth,
                                 height: height)
                NSBezierPath(roundedRect: bar,
                             xRadius: barWidth / 3,
                             yRadius: barWidth / 3).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Взаимодействие

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
