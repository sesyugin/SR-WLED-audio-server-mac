import AppKit
import SwiftUI
import SRWLEDVisuals

// Рендерит кадры визуализации и знак приложения в PNG. Сам в приложение не входит:
// нужен при работе над оформлением и при сборке бандла — иконку .icns собирают
// из того, что он разложит.
//
//   SRWLEDPreview                  кадры сцены и иконка
//   SRWLEDPreview --icon-only      только иконка (сборка бандла)
//
// Куда писать: SRWLED_ICONSET — каталог iconset, SRWLED_OUT — каталог кадров.

let arguments = Set(CommandLine.arguments.dropFirst())
let iconsetPath = ProcessInfo.processInfo.environment["SRWLED_ICONSET"]
    ?? NSTemporaryDirectory() + "Auralis.iconset"
let outputPath = ProcessInfo.processInfo.environment["SRWLED_OUT"]
    ?? NSTemporaryDirectory()

@MainActor
func render(name: String, bands: [Float], peaks: [Float], palette: Palette, size: CGSize) {
    // Время назначено, а не взято с часов: венец вращается, и без этого
    // каждый прогон превью показывал сцену под новым углом — сравнить кадр
    // до правки с кадром после было невозможно. Значение произвольное,
    // важно лишь то, что оно одно и то же от прогона к прогону.
    let tintValue = ProcessInfo.processInfo.environment["SRWLED_TINT"].flatMap(Double.init)
    let view = CrownScene(sampler: { bands }, isRunning: true, palette: palette,
                          tint: tintValue,
                          frozenTime: 41.7)
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

    let url = URL(fileURLWithPath: outputPath)
        .appendingPathComponent("srwled-preview-\(name).png")
    try? png.write(to: url)
    print("готово: \(url.path)")
}

/// Иконка приложения: рисуем знак и раскладываем по размерам для iconutil.
///
/// Возвращает признак успеха, а не молчит: сборка бандла на этом стоит, и
/// незамеченный провал раньше давал приложение вовсе без иконки — либо, что хуже,
/// с иконкой от прошлой сборки, случайно оставшейся в общем /tmp.
@MainActor
func renderIcon(into directory: String) -> Bool {
    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data("не удалось создать \(directory): \(error)\n".utf8))
        return false
    }

    var written = 0
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
            do {
                try png.write(to: URL(fileURLWithPath: path))
                written += 1
            } catch {
                FileHandle.standardError.write(Data("не записан \(path): \(error)\n".utf8))
                return false
            }
        }
    }

    // iconutil откажется собирать неполный набор, а молча пропущенный размер
    // всплыл бы уже готовым бандлом с пустым местом вместо значка.
    let expected = sizes.reduce(0) { $0 + ($1 * 2 <= 1024 ? 2 : 1) }
    guard written == expected else {
        FileHandle.standardError.write(Data("нарисовано \(written) размеров из \(expected)\n".utf8))
        return false
    }
    print("иконка разложена: \(directory) — \(written) размеров")
    return true
}

// Три характерных состояния: тихо, средняя музыка, громкий бас.
let quiet: [Float] = Array(repeating: 0.05, count: 16)
let music: [Float] = [0.85, 0.72, 0.55, 0.48, 0.62, 0.40, 0.35, 0.44,
                      0.30, 0.38, 0.26, 0.33, 0.22, 0.28, 0.18, 0.14]
let loud: [Float] = [1.0, 0.95, 0.80, 0.62, 0.70, 0.55, 0.50, 0.58,
                     0.45, 0.52, 0.40, 0.46, 0.34, 0.40, 0.28, 0.24]

let size = CGSize(width: 900, height: 506)

/// Замер цены кадра. Оптимизацию иначе не проверить: время всего прогона
/// превью на три четверти состоит из запуска процесса и упаковки PNG,
/// и правка, ускоряющая отрисовку вдвое, в нём не видна вовсе.
///
/// Размер взят не превьюшный, а рабочий: у окна приложения он вдвое меньше,
/// и половина тел сцены уходит за порог мелкой отрисовки — цена кадра там
/// совсем другая, чем на большом кадре для просмотра.
@MainActor
func benchmark(frames: Int) {
    let size = CGSize(width: 1180, height: 700)
    var total: Double = 0
    for index in 0..<frames {
        // Время сдвигается от кадра к кадру: на замороженном венец стоит,
        // и часть работы отпадает по совпадению значений.
        let view = CrownScene(sampler: { music }, isRunning: true, palette: .amber,
                              frozenTime: 40 + Double(index) * 0.017,
                              light: ProcessInfo.processInfo.environment["SRWLED_LIGHT"] != nil)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let started = ProcessInfo.processInfo.systemUptime
        _ = renderer.nsImage
        total += ProcessInfo.processInfo.systemUptime - started
    }
    let perFrame = total / Double(frames) * 1000
    print(String(format: "кадр: %.1f мс, это %.0f к/с при полной загрузке одного ядра",
                 perFrame, 1000 / perFrame))
}

/// Фазы разгорания гряды — единственный способ увидеть моторику, не снимая экран.
/// Кадры кладутся в один ряд, чтобы сравнивать их глазом, а не по очереди.
@MainActor
func renderIgnition() {
    let phases: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]
    let strip = CGSize(width: 272, height: 46)
    let view = VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
            HStack(spacing: 10) {
                Text(String(format: "%.2f", phase))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                SpectrumStrip(bands: music, ignition: phase)
                    .frame(width: strip.width, height: strip.height)
            }
        }
    }
    .padding(14)
    .background(Color(white: 0.12))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: outputPath).appendingPathComponent("srwled-ignition.png")
    try? png.write(to: url)
    print("готово: \(url.path)")
}

MainActor.assumeIsolated {
    if ProcessInfo.processInfo.environment["SRWLED_BENCH"] != nil {
        benchmark(frames: 24)
        exit(0)
    }

    if arguments.contains("--ignition") {
        renderIgnition()
        exit(0)
    }

    // Ненулевой код возврата обязателен: сборка бандла падает на нём, а не
    // доезжает до конца с приложением без иконки.
    if arguments.contains("--icon-only") {
        exit(renderIcon(into: iconsetPath) ? 0 : 1)
    }

    render(name: "quiet", bands: quiet, peaks: quiet, palette: .amber, size: size)
    render(name: "music", bands: music, peaks: music.map { min(1, $0 + 0.1) },
           palette: .amber, size: size)
    render(name: "loud", bands: loud, peaks: loud, palette: .amber, size: size)
    render(name: "ice", bands: music, peaks: music, palette: .ice, size: size)
    if !renderIcon(into: iconsetPath) { exit(1) }
}
