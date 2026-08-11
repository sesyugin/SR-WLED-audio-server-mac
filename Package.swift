// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SRWLEDAudioServer",
    // 14.2 — минимальная версия с AudioHardwareCreateProcessTap.
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "SRWLEDCore", targets: ["SRWLEDCore"]),
    ],
    targets: [
        // Ядро: захват звука, DSP-цепочка, сборка пакета WLED.
        .target(name: "SRWLEDCore", path: "Sources/SRWLEDCore"),

        // Консольный сервер: захват звука + отправка на ленты.
        .executableTarget(name: "srwled", dependencies: ["SRWLEDCore"], path: "Sources/srwled"),

        // Отладочный спайк: проверка захвата системного звука.
        .executableTarget(name: "TapSpike", path: "Sources/TapSpike"),

        // Проверки ядра. Собственный прогонщик вместо XCTest/swift-testing: оба идут
        // только с Xcode, а проект должен проверяться на голых Command Line Tools.
        // Ни одна проверка не трогает аудиоустройства и не шлёт пакеты в реальную сеть.
        .executableTarget(name: "SRWLEDTests",
                          dependencies: ["SRWLEDCore"],
                          path: "Sources/SRWLEDTests"),
    ]
)
