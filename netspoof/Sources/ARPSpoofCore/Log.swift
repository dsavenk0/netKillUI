import Foundation

public enum LogLevel: Int, Comparable {
    case debug = 0, info, warn, error
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    var tag: String { ["DEBUG", "INFO", "WARN", "ERROR"][rawValue] }
}

/// Простое структурное логирование: `[HH:mm:ss.SSS] LEVEL сообщение` в stderr.
/// Демон перенаправляет stderr в лог-файл (`>/tmp/…-serve.log 2>&1`), GUI
/// показывает его хвост при ошибке. Сообщение вычисляется лениво (@autoclosure),
/// поэтому отключённый уровень ничего не стоит.
public enum Log {
    public static var minLevel: LogLevel = .info

    public static func debug(_ m: @autoclosure () -> String) { emit(.debug, m) }
    public static func info(_ m: @autoclosure () -> String)  { emit(.info, m) }
    public static func warn(_ m: @autoclosure () -> String)  { emit(.warn, m) }
    public static func error(_ m: @autoclosure () -> String) { emit(.error, m) }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func emit(_ level: LogLevel, _ msg: () -> String) {
        guard level >= minLevel else { return }
        let line = "[\(fmt.string(from: Date()))] \(level.tag) \(msg())\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
