import SwiftUI
import AppKit

@main
struct NetKillUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("netKillUI") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Нужно, чтобы не-бандл бинарь (`swift run`) всплывал как обычное окно.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Палитра (хакерский терминал × чистота Apple)

// Динамические цвета: светлая (чистота Apple) ↔ тёмная (терминал).
// Следуют appearance окна, который задаёт .preferredColorScheme.
private func nkDynamic(_ l: (Double, Double, Double), _ d: (Double, Double, Double)) -> Color {
    Color(nsColor: NSColor(name: nil) { ap in
        let dark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = dark ? d : l
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    })
}

extension Color {
    //                          light (Apple)                 dark (terminal)
    static let nkBG     = nkDynamic((1.000, 1.000, 1.000), (0.035, 0.040, 0.047))
    static let nkElev   = nkDynamic((0.961, 0.961, 0.969), (0.082, 0.094, 0.110))
    static let nkLine   = nkDynamic((0.890, 0.890, 0.910), (0.137, 0.153, 0.176))
    static let nkFG     = nkDynamic((0.114, 0.114, 0.122), (0.902, 0.910, 0.922))
    static let nkDim    = nkDynamic((0.431, 0.431, 0.451), (0.510, 0.540, 0.576))
    static let nkAccent = nkDynamic((0.851, 0.318, 0.039), (1.000, 0.420, 0.000))
    static let nkOnline = nkDynamic((0.086, 0.639, 0.290), (0.290, 0.870, 0.500))
    static let nkSelect = nkDynamic((0.145, 0.388, 0.922), (0.360, 0.580, 1.000))
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
