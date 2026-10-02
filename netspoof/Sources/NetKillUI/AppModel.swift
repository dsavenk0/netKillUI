import Foundation
import Combine
import ARPSpoofCore

struct Device: Identifiable, Hashable {
    let mac: MACAddress
    var ip: IPv4Address
    var vendor: String
    var name: String?
    var isGateway: Bool
    var active: Bool                 // движок травит прямо сейчас
    var isSelf: Bool = false
    var online: Bool = true          // замечен в последнем скане
    var blocked: Bool = false        // постоянная блокировка (переживает перезапуск)
    var id: MACAddress { mac }
}

/// Запись в кеше устройств — чтобы показывать оффлайн-устройства и их данные.
private struct CachedDevice: Codable {
    var mac: String
    var ip: String
    var vendor: String
    var name: String?
    var lastSeen: Date
}

final class AppModel: ObservableObject {
    @Published var interface = "en0"
    @Published var availableInterfaces: [String] = []
    @Published var devices: [Device] = []
    @Published var selection = Set<MACAddress>()
    @Published var forwarding = false
    @Published var cutMode = true    // true = Cut (обрыв), false = Intercept (MITM)
    @Published var ninja = false     // тихий режим: пассивный скан + oneway + реже
    @Published var gateway = ""
    @Published var connected = false
    @Published var scanning = false
    @Published var statusLine = "не подключено"
    @Published var showConsent = false
    @Published var errorMessage: String?
    @Published var alertBanner: String?   // чужой ARP-спуфер в сети (предупреждение)
    @Published var hintBanner: String?    // мягкая подсказка (например, Private Wi-Fi Address)
    @Published var maskMac: Bool = UserDefaults.standard.bool(forKey: "nku.maskmac") {
        didSet { UserDefaults.standard.set(maskMac, forKey: "nku.maskmac") }
    }
    @Published var masked = false         // MAC реально замаскирован (из ready)
    @Published var darkTheme: Bool = (UserDefaults.standard.object(forKey: "nku.dark") as? Bool) ?? true

    private let client = SocketClient()
    private let socketPath = "/tmp/netkillui.sock"
    private var activeMacs = Set<MACAddress>()
    private var selfMAC: MACAddress?
    private var selfIP: IPv4Address?

    // Кеш устройств + постоянный блок-лист, РАЗДЕЛЁННЫЕ ПО СЕТЯМ (ключ — MAC шлюза,
    // стабильный отпечаток сети): устройства и блокировки разных сетей не смешиваются.
    private var networkKey = ""
    private var cache: [String: CachedDevice] = [:]
    private var blockedMacs: Set<String> = []
    private var autoScanTimer: Timer?

    private func loadNetwork() {
        if let d = UserDefaults.standard.data(forKey: "nku.cache.\(networkKey)"),
           let c = try? JSONDecoder().decode([String: CachedDevice].self, from: d) {
            cache = c
        } else {
            cache = [:]
        }
        blockedMacs = Set(UserDefaults.standard.stringArray(forKey: "nku.blocked.\(networkKey)") ?? [])
    }
    private func saveCache() {
        if let d = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(d, forKey: "nku.cache.\(networkKey)")
        }
    }
    private func saveBlocked() {
        UserDefaults.standard.set(Array(blockedMacs), forKey: "nku.blocked.\(networkKey)")
    }

    /// Переключиться на сеть по MAC шлюза: подгрузить её кеш и блок-лист.
    private func switchNetwork(to key: String) {
        guard !key.isEmpty, key != networkKey else { return }
        networkKey = key
        UserDefaults.standard.set(key, forKey: "nku.lastNetwork")
        loadNetwork()
        rebuildDevices(onlineMacs: [])   // дальше придёт свежий скан
    }

    func toggleTheme() {
        darkTheme.toggle()
        UserDefaults.standard.set(darkTheme, forKey: "nku.dark")
    }

    // Согласие в ТЕКУЩЕМ запуске (не персистим — предупреждение показываем при
    // каждом открытии приложения: это security-инструмент).
    private var consentAccepted = false
    private var consentShown = false

    init() {
        interface = activeInterface() ?? "en0"
        availableInterfaces = listIPv4Interfaces()
        if availableInterfaces.isEmpty { availableInterfaces = [interface] }
        // Показать кеш последней сети (всё оффлайн) до подключения.
        networkKey = UserDefaults.standard.string(forKey: "nku.lastNetwork") ?? ""
        loadNetwork()
        rebuildDevices(onlineMacs: [])
    }

    // MARK: Соглашение об использовании

    /// Показать предупреждение один раз при открытии приложения.
    func showConsentOnLaunch() {
        if !consentShown { consentShown = true; showConsent = true }
    }

    func requestStart() {
        if consentAccepted { connect() } else { showConsent = true }
    }

    func acceptConsent() {
        consentAccepted = true
        showConsent = false   // просто закрываем; запуск движка — отдельной кнопкой
    }

    func declineConsent() { showConsent = false }

    // MARK: Подключение к демону

    func connect() {
        guard !connected else { return }
        statusLine = "запуск движка (нужен пароль)…"
        client.onEvent = { [weak self] in self?.handle($0) }
        client.onClose = { [weak self] in
            self?.connected = false
            self?.statusLine = "движок отключён"
            self?.stopAutoScan()
        }

        let binary = Elevator.serveBinaryPath()
        let owner = NSUserName()
        let iface = interface
        let path = socketPath
        let mask = maskMac

        DispatchQueue.global().async { [weak self] in
            if let err = Elevator.launchServe(binary: binary, iface: iface, socketPath: path,
                                              owner: owner, maskMAC: mask),
               !err.isEmpty {
                DispatchQueue.main.async {
                    self?.statusLine = "движок не запущен"
                    self?.errorMessage = "Не удалось запустить движок:\n\n\(err)"
                }
                return
            }
            var ok = false
            for _ in 0..<20 {
                if self?.client.connect(path: path) == true { ok = true; break }
                Thread.sleep(forTimeInterval: 0.4)
            }
            DispatchQueue.main.async {
                self?.connected = ok
                if ok {
                    self?.statusLine = "подключено"
                    self?.client.send(["cmd": "mode", "cut": self?.cutMode ?? true])
                    self?.client.send(["cmd": "status"])
                    self?.scan()
                    self?.startAutoScan()   // периодически обновляем online/offline
                    // armBlocked() — в обработчике ready, когда известна сеть (gatewayMac).
                } else {
                    self?.statusLine = "движок не отвечает"
                    self?.errorMessage = "Движок запущен, но не отвечает на сокете.\n\n"
                        + "Последние строки лога:\n\(AppModel.tailLog())"
                }
            }
        }
    }

    private static func tailLog() -> String {
        let path = "/tmp/netkillui-serve.log"
        guard let s = try? String(contentsOfFile: path, encoding: .utf8), !s.isEmpty else {
            return "(лог пуст: \(path))"
        }
        return s.split(separator: "\n").suffix(12).joined(separator: "\n")
    }

    func disconnect() {
        client.send(["cmd": "stopAll"])
        client.close()
        connected = false
        statusLine = "отключено"
        stopAutoScan()
    }

    // MARK: Команды

    func scan() {
        guard connected else { return }
        scanning = true
        statusLine = ninja ? "пассивный скан…" : "скан…"
        client.send(["cmd": "scan"])
    }

    func toggleNinja() {
        ninja.toggle()
        if connected { client.send(["cmd": "ninja", "on": ninja]) }
    }


    /// Клик по устройству — постоянная блокировка (переживает перезапуск и
    /// переподключение устройства): blocked → движок травит, как только оно онлайн.
    func toggle(_ device: Device) {
        guard !device.isGateway, !device.isSelf else { return }
        setBlocked(!device.blocked, for: [device.mac])
    }

    func spoofSelected() { setBlocked(true, for: selectableMacs(in: selection)) }
    func stopSelected() { setBlocked(false, for: selectableMacs(in: selection)) }

    /// Заблокировать всех ОНЛАЙН (оффлайн нет смысла — travить нечего; появятся —
    /// отдельная блокировка). Исключаем себя и шлюз.
    func spoofAll() {
        setBlocked(true, for: devices.filter { !$0.isGateway && !$0.isSelf && $0.online }.map(\.mac))
    }

    /// Снять все блокировки и остановить травлю.
    func stopAll() {
        if connected { client.send(["cmd": "stopAll"]) }
        blockedMacs.removeAll()
        saveBlocked()
        for i in devices.indices { devices[i].active = false; devices[i].blocked = false }
        activeMacs.removeAll()
        updateStatusLine()
    }

    func clearSelection() { selection.removeAll() }

    // MARK: Внутреннее

    private func selectableMacs(in set: Set<MACAddress>) -> [MACAddress] {
        devices.filter { set.contains($0.mac) && !$0.isGateway && !$0.isSelf }.map(\.mac)
    }

    /// Поставить/снять постоянную блокировку для MAC и привести движок в
    /// соответствие (start = травить/ждать появления, stop = снять).
    private func setBlocked(_ on: Bool, for macs: [MACAddress]) {
        guard !macs.isEmpty else { return }
        for m in macs {
            if on { blockedMacs.insert(m.description) } else { blockedMacs.remove(m.description) }
        }
        saveBlocked()
        for i in devices.indices where macs.contains(devices[i].mac) {
            devices[i].blocked = on
        }
        setActive(on, for: macs)
    }

    /// Отправить движку start для всех заблокированных MAC текущей сети: онлайн
    /// начнут травиться сразу, оффлайн — движок будет ждать их появления (пассивно).
    private func armBlocked() {
        let macs = blockedMacs.compactMap { MACAddress($0) }
        if !macs.isEmpty { setActive(true, for: macs) }
    }

    private func setActive(_ on: Bool, for macs: [MACAddress]) {
        guard !macs.isEmpty else { return }
        let strs = macs.map { $0.description }
        if connected {
            client.send(["cmd": on ? "start" : "stop", "macs": strs])
        }
        // оптимистично — сервер поправит статусом. Оффлайн не травится сейчас.
        for i in devices.indices where macs.contains(devices[i].mac) {
            devices[i].active = on && devices[i].online
        }
        if on { activeMacs.formUnion(macs) } else { activeMacs.subtract(macs) }
        updateStatusLine()
    }

    private func handle(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String else { return }
        switch event {
        case "ready":
            gateway = obj["gateway"] as? String ?? gateway
            if let name = obj["iface"] as? String { interface = name }
            if let m = obj["mac"] as? String { selfMAC = MACAddress(m) }
            if let ip = obj["ip"] as? String { selfIP = IPv4Address(ip) }
            masked = obj["masked"] as? Bool ?? false
            if maskMac && !masked {
                alertBanner = "⚠ MAC-маскировка не применилась: встроенный Wi-Fi (Apple Silicon) "
                    + "не даёт сменить MAC. Работает на USB-Ethernet. Сейчас — реальный MAC."
            }
            // На Wi-Fi без приватного MAC (бит locally-administered не стоит) — мягко
            // посоветовать штатную «Частный адрес Wi-Fi»: честный путь маскировки.
            let wifi = obj["wifi"] as? Bool ?? false
            if wifi, !maskMac, !masked, let m = selfMAC, (m.bytes[0] & 0x02) == 0 {
                hintBanner = "💡 На Wi-Fi сеть видит твой реальный MAC. Включи «Частный адрес Wi-Fi» "
                    + "в Настройках → Wi-Fi → [сеть] — MAC станет приватным (Apple-штатно)."
            }
            // Сеть определяется MAC шлюза (отпечаток сети): грузим её кеш/блок-лист,
            // чтобы устройства разных сетей не смешивались, и армим блокировки.
            switchNetwork(to: (obj["gatewayMac"] as? String) ?? gateway)
            armBlocked()

        case "devices":
            if let list = obj["list"] as? [[String: String]] {
                ingestScan(list.compactMap { Device(fromJSON: $0) })
            }
            scanning = false
            updateStatusLine()

        case "deviceNames":
            if let pairs = obj["names"] as? [[String: String]] {
                for p in pairs {
                    guard let macS = p["mac"], let name = p["name"], let mac = MACAddress(macS) else { continue }
                    if let idx = devices.firstIndex(where: { $0.mac == mac }) { devices[idx].name = name }
                    if var c = cache[macS] { c.name = name; cache[macS] = c }
                }
                saveCache()
            }

        case "status":
            let targets = obj["targets"] as? [[String: String]] ?? []
            activeMacs = Set(targets.compactMap { MACAddress($0["mac"] ?? "") })
            forwarding = obj["forwarding"] as? Bool ?? false
            if let c = obj["cut"] as? Bool { cutMode = c }
            if let n = obj["ninja"] as? Bool { ninja = n }
            if let gw = obj["gateway"] as? String { gateway = gw }
            for i in devices.indices {
                devices[i].active = devices[i].online && activeMacs.contains(devices[i].mac)
            }
            updateStatusLine()

        case "targetMoved":
            if let macS = obj["mac"] as? String, let ipS = obj["ip"] as? String,
               let mac = MACAddress(macS), let ip = IPv4Address(ipS) {
                if let idx = devices.firstIndex(where: { $0.mac == mac }) { devices[idx].ip = ip }
                if var c = cache[macS] { c.ip = ipS; cache[macS] = c }
                saveCache()
            }

        case "alert":
            if (obj["kind"] as? String) == "arp-spoof",
               let mac = obj["mac"] as? String, let ip = obj["ip"] as? String {
                alertBanner = "⚠ Обнаружен ARP-спуфер: \(mac) выдаёт себя за \(ip)"
            }

        case "error":
            let msg = obj["message"] as? String ?? ""
            statusLine = "ошибка: \(msg)"
            errorMessage = msg

        default:
            break
        }
    }

    private func updateStatusLine() {
        let n = devices.filter { $0.active }.count
        let gw = gateway.isEmpty ? "—" : gateway
        statusLine = "\(n) target\(n == 1 ? "" : "s") · gw \(gw)"
    }

    // MARK: Кеш, online/offline, авто-скан

    /// Принять результат скана: обновить кеш увиденными, пересобрать список с
    /// пометкой online/offline, доармить заблокированных, которые стали онлайн.
    private func ingestScan(_ scanned: [Device]) {
        let now = Date()
        let onlineMacs = Set(scanned.map { $0.mac.description })
        for d in scanned {
            var c = cache[d.mac.description]
                ?? CachedDevice(mac: d.mac.description, ip: d.ip.description,
                                vendor: d.vendor, name: d.name, lastSeen: now)
            c.ip = d.ip.description
            c.vendor = d.vendor
            if let n = d.name { c.name = n }
            c.lastSeen = now
            cache[d.mac.description] = c
        }
        saveCache()
        rebuildDevices(onlineMacs: onlineMacs)

        // Заблокированные, которые сейчас онлайн и ещё не травятся — запустить.
        let toStart = devices
            .filter { $0.blocked && $0.online && !$0.active && !$0.isGateway && !$0.isSelf }
            .map(\.mac)
        if !toStart.isEmpty { setActive(true, for: toStart) }
    }

    /// Пересобрать `devices` из кеша: online — кто в onlineMacs, остальные offline.
    /// Online сверху, дальше по IP.
    private func rebuildDevices(onlineMacs: Set<String>) {
        var ds: [Device] = []
        for (macS, c) in cache {
            guard let mac = MACAddress(macS), let ip = IPv4Address(c.ip) else { continue }
            let online = onlineMacs.contains(macS)
            var d = Device(mac: mac, ip: ip, vendor: c.vendor, name: c.name,
                           isGateway: false, active: online && activeMacs.contains(mac))
            d.online = online
            d.blocked = blockedMacs.contains(macS)
            if ip.description == gateway { d.isGateway = true }
            if mac == selfMAC || ip == selfIP { d.isSelf = true }
            ds.append(d)
        }
        ds.sort { a, b in
            if a.online != b.online { return a.online && !b.online }
            return a.ip.hostOrder < b.ip.hostOrder
        }
        devices = ds
    }

    private func startAutoScan() {
        autoScanTimer?.invalidate()
        // Раз в минуту освежаем список: новые устройства + online/offline.
        autoScanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.connected, !self.scanning else { return }
            self.scan()
        }
    }

    private func stopAutoScan() {
        autoScanTimer?.invalidate()
        autoScanTimer = nil
    }

}

private extension Device {
    init?(fromJSON j: [String: String]) {
        guard let ipS = j["ip"], let macS = j["mac"],
              let ip = IPv4Address(ipS), let mac = MACAddress(macS) else { return nil }
        self.init(mac: mac, ip: ip, vendor: j["vendor"] ?? "Unknown",
                  name: j["name"], isGateway: false, active: false)
    }
}
