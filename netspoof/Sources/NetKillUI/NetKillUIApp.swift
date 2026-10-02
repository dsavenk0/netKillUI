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

extension Color {
    static let nkBG      = Color(red: 0.035, green: 0.040, blue: 0.047)
    static let nkElev    = Color(red: 0.082, green: 0.094, blue: 0.110)
    static let nkLine    = Color(red: 0.137, green: 0.153, blue: 0.176)
    static let nkFG      = Color(red: 0.902, green: 0.910, blue: 0.922)
    static let nkDim     = Color(red: 0.510, green: 0.540, blue: 0.576)
    static let nkAccent  = Color(red: 1.000, green: 0.420, blue: 0.000)
    static let nkOnline  = Color(red: 0.290, green: 0.870, blue: 0.500)
    static let nkSelect  = Color(red: 0.360, green: 0.580, blue: 1.000)
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
