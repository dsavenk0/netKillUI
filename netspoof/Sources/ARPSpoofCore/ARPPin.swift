import Foundation

/// Активная защита себя от ARP-спуфинга: статически закрепляем правильную связку
/// `IP → MAC` в собственном ARP-кэше. Статическая запись не перезаписывается
/// чужими ARP-ответами, поэтому нас нельзя увести (в частности — закрепляем шлюз).
///
/// Реализовано через `/usr/sbin/arp` (демон уже root): на современном macOS это
/// штатный и надёжный путь (внутри — routing socket), в отличие от хрупкого
/// ручного RTM_ADD. Действие редкое (срабатывает только при атаке), поэтому
/// короткий субпроцесс здесь оправдан.
public enum ARPPin {
    /// Закрепить `ip → mac` статически (сначала снять прежнюю запись).
    public static func pin(ip: IPv4Address, mac: MACAddress) {
        run(["-d", ip.description])                       // убрать текущую (динамическую)
        run(["-s", ip.description, mac.description])       // добавить статическую
    }

    /// Снять закрепление — вернуть обычное динамическое поведение.
    public static func unpin(ip: IPv4Address) {
        run(["-d", ip.description])
    }

    private static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { /* best-effort */ }
    }
}
