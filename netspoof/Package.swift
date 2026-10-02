// swift-tools-version:5.9
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
    ]
)
