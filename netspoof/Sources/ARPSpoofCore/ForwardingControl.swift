import Foundation

/// Управление IP-форвардингом под режим cut/intercept.
/// cut=true  → форвардинг ВЫКЛ: трафик целей упирается в нас и обрывается (kill).
/// cut=false → форвардинг ВКЛ при активных целях: прозрачный MITM (перехват).
///
/// Доступ к sysctl инъектируется (`read`/`write`), чтобы логику можно было
/// юнит-тестить без root; по умолчанию — реальные getIPForwarding/setIPForwarding.
public final class ForwardingControl {
    public var cutMode: Bool
    public private(set) var enabledByUs = false

    private let read: () -> Bool          // форвардинг сейчас включён?
    private let write: (Bool) -> Bool     // применить; true — успех

    public init(cutMode: Bool,
                read: @escaping () -> Bool = { getIPForwarding() == 1 },
                write: @escaping (Bool) -> Bool = { setIPForwarding($0) }) {
        self.cutMode = cutMode
        self.read = read
        self.write = write
    }

    public var isOn: Bool { read() }

    /// Привести форвардинг к нужному состоянию по режиму и наличию целей.
    public func apply(hasActive: Bool) {
        if cutMode {
            // В cut форвардинг должен быть выключен (даже если его включил кто-то
            // до нас) — иначе цель не отвалится.
            if read() { _ = write(false) }
            enabledByUs = false
        } else if hasActive {
            if !read(), write(true) { enabledByUs = true }
        } else {
            disableIfEnabled()
        }
    }

    /// Выключить форвардинг, только если включали его мы (чужой не трогаем).
    public func disableIfEnabled() {
        if enabledByUs { _ = write(false); enabledByUs = false }
    }
}
