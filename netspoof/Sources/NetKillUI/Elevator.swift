import Foundation

/// Запуск root-демона `netspoof serve` через системный диалог администратора
/// (osascript `do shell script … with administrator privileges`). Подпись не нужна.
enum Elevator {
    /// Путь к бинарю netspoof рядом с GUI (в dev оба в .build/debug).
    static func serveBinaryPath() -> String {
        let gui = URL(fileURLWithPath: CommandLine.arguments[0])
        return gui.deletingLastPathComponent().appendingPathComponent("netspoof").path
    }

    /// Запустить serve в фоне как root. Возвращает nil при успехе или текст
    /// ошибки (например, отмену диалога пароля).
    @discardableResult
    static func launchServe(binary: String, iface: String, socketPath: String, owner: String,
                            maskMAC: Bool = false) -> String? {
        // Демон сам чистит прежние экземпляры при старте (killOtherNetspoofInstances,
        // по PID — без pkill и само-ловушек). Без nohup (под osascript нет tty) —
        // демон сам игнорирует SIGHUP; stdio в файл/-devnull, & — в фон.
        let maskFlag = maskMAC ? " --mask-mac" : ""
        let cmd = "'\(binary)' serve -i \(iface) --socket '\(socketPath)' --owner \(owner)\(maskFlag)"
            + " </dev/null >/tmp/netkillui-serve.log 2>&1 &"
        let apple = "do shell script \"\(cmd)\" with administrator privileges"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", apple]
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch {
            return "не удалось запустить osascript: \(error.localizedDescription)"
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return msg.isEmpty ? "osascript завершился с кодом \(p.terminationStatus)" : msg
        }
        return nil
    }
}
