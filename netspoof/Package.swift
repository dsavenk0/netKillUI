// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "netspoof",
    platforms: [.macOS(.v13)],
    targets: [
        // Тонкий C-слой: ioctl'ы BPF используют макросы _IOW/_IOWR,
        // которые не импортируются в Swift напрямую.
        .target(name: "CBPF"),
        .target(name: "ARPSpoofCore", dependencies: ["CBPF"]),
        .executableTarget(name: "netspoof", dependencies: ["ARPSpoofCore"]),
        // Нативный SwiftUI-фронтенд. Запускает netspoof serve (root через osascript)
        // и общается с ним по unix-сокету.
        .executableTarget(name: "NetKillUI", dependencies: ["ARPSpoofCore"]),
        .testTarget(name: "ARPSpoofCoreTests", dependencies: ["ARPSpoofCore"]),
    ],
    // tools-version 6.0 нужен для корректной линковки swift-testing (Testing),
    // но язык держим в режиме 5 — строгий параллелизм пока не включаем.
    swiftLanguageModes: [.v5]
)
