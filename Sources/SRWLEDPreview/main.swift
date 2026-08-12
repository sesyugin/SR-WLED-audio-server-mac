import AppKit
import SwiftUI
import SRWLEDVisuals

// Рендерит кадры визуализации в PNG — чтобы смотреть на результат, а не гадать.
// Не входит в приложение, нужен только при работе над оформлением.

@MainActor
func render(name: String, bands: [Float], peaks: [Float], palette: Palette, size: CGSize) {
    let view = StageScene(sampler: { bands }, isRunning: true,
                          palette: palette, packetsPerSecond: 47)
        .frame(width: size.width, height: size.height)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        print("не удалось отрисовать \(name)")
        return
    }

    let url = URL(fileURLWithPath: "/tmp/srwled-preview-\(name).png")
    try? png.write(to: url)
    print("готово: \(url.path)")
}

// Иконка приложения: рисуем знак и раскладываем по размерам для iconutil.
@MainActor
func renderIcon() {
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    let directory = "/tmp/Auralis.iconset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    for side in sizes {
        for scale in [1, 2] {
            let pixels = side * scale
            guard pixels <= 1024 else { continue }
            let renderer = ImageRenderer(
                content: AppIconCanvas().frame(width: CGFloat(pixels), height: CGFloat(pixels)))
            renderer.scale = 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            let suffix = scale == 1 ? "" : "@2x"
            let path = "\(directory)/icon_\(side)x\(side)\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
    print("иконка разложена: \(directory)")

    // Отдельный крупный кадр знака — для README и страницы релиза.
    let renderer = ImageRenderer(content: AppIconCanvas().frame(width: 512, height: 512))
    renderer.scale = 2
    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/srwled-preview-icon.png"))
        print("готово: /tmp/srwled-preview-icon.png")
    }
}

// Три характерных состояния: тихо, средняя музыка, громкий бас.
let quiet: [Float] = Array(repeating: 0.05, count: 16)
let music: [Float] = [0.85, 0.72, 0.55, 0.48, 0.62, 0.40, 0.35, 0.44,
                      0.30, 0.38, 0.26, 0.33, 0.22, 0.28, 0.18, 0.14]
let loud: [Float] = [1.0, 0.95, 0.80, 0.62, 0.70, 0.55, 0.50, 0.58,
                     0.45, 0.52, 0.40, 0.46, 0.34, 0.40, 0.28, 0.24]

let size = CGSize(width: 760, height: 520)

MainActor.assumeIsolated {
    render(name: "quiet", bands: quiet, peaks: quiet, palette: .amber, size: size)
    render(name: "music", bands: music, peaks: music.map { min(1, $0 + 0.1) },
           palette: .amber, size: size)
    render(name: "loud", bands: loud, peaks: loud, palette: .amber, size: size)
    render(name: "ice", bands: music, peaks: music, palette: .ice, size: size)
    renderIcon()
}
