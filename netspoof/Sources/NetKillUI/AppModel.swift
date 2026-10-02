import Foundation
import Combine
import ARPSpoofCore

struct Device: Identifiable, Hashable {
    let mac: MACAddress
    var ip: IPv4Address
    var vendor: String
    var name: String?
    var isGateway: Bool
    var active: Bool
    var isSelf: Bool = false
    var id: MACAddress { mac }
}

final class AppModel: ObservableObject {
    @Published var interface = "en0"
    @Published var availableInterfaces: [String] = []
    @Published var devices: [Device] = []
    @Published var selection = Set<MACAddress>()
    @Published var forwarding = false
    @Published var gateway = ""
    @Published var connected = false
    @Published var scanning = false
    @Published var statusLine = "не подключено"
    @Published var showConsent = false
    @Published var errorMessage: String?
    @Published var darkTheme: Bool = (UserDefaults.standard.object(forKey: "nku.dark") as? Bool) ?? true

    private let client = SocketClient()
    private let socketPath = "/tmp/netkillui.sock"
    private var activeMacs = Set<MACAddress>()
    private var selfMAC: MACAddress?
    private var selfIP: IPv4Address?

    func toggleTheme() {
        darkTheme.toggle()
        UserDefaults.standard.set(darkTheme, forKey: "nku.dark")
    }

    private let consentKey = "nku.consent.accepted"
    private var consentAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }

    init() {
        interface = activeInterface() ?? "en0"
        availableInterfaces = listIPv4Interfaces()
        if availableInterfaces.isEmpty { availableInterfaces = [interface] }
    }

    // MARK: Соглашение об использовании

    func requestStart() {
        if consentAccepted { connect() } else { showConsent = true }
    }

    func acceptConsent() {
        consentAccepted = true
        showConsent = false
        connect()
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
        }

        let binary = Elevator.serveBinaryPath()
        let owner = NSUserName()
        let iface = interface
        let path = socketPath

        DispatchQueue.global().async { [weak self] in
            if let err = Elevator.launchServe(binary: binary, iface: iface, socketPath: path, owner: owner),
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
                    self?.client.send(["cmd": "status"])
                    self?.scan()
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
    }

    // MARK: Команды

    func scan() {
        guard connected else { return }
        scanning = true
        statusLine = "скан…"
        client.send(["cmd": "scan"])
    }

    func toggle(_ device: Device) {
        guard !device.isGateway, !device.isSelf else { return }
        setActive(!device.active, for: [device.mac])
    }

    func spoofSelected() { setActive(true, for: selectableMacs(in: selection)) }
    func stopSelected() { setActive(false, for: selectableMacs(in: selection)) }

    func spoofAll() {
        setActive(true, for: devices.filter { !$0.isGateway && !$0.isSelf }.map(\.mac))
    }

    func stopAll() {
        if connected { client.send(["cmd": "stopAll"]) }
        for i in devices.indices { devices[i].active = false }
        activeMacs.removeAll()
        updateStatusLine()
    }

    func clearSelection() { selection.removeAll() }

    // MARK: Внутреннее

    private func selectableMacs(in set: Set<MACAddress>) -> [MACAddress] {
        devices.filter { set.contains($0.mac) && !$0.isGateway && !$0.isSelf }.map(\.mac)
    }

    private func setActive(_ on: Bool, for macs: [MACAddress]) {
        guard !macs.isEmpty else { return }
        let strs = macs.map { $0.description }
        if connected {
            client.send(["cmd": on ? "start" : "stop", "macs": strs])
        }
        // оптимистично — сервер поправит статусом
        for i in devices.indices where macs.contains(devices[i].mac) {
            devices[i].active = on
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

        case "devices":
            if let list = obj["list"] as? [[String: String]] {
                var ds = list.compactMap { Device(fromJSON: $0) }
                for i in ds.indices {
                    if ds[i].ip.description == gateway { ds[i].isGateway = true }
                    if ds[i].mac == selfMAC || ds[i].ip == selfIP { ds[i].isSelf = true }
                    ds[i].active = activeMacs.contains(ds[i].mac)
                }
                ds.sort { $0.ip.hostOrder < $1.ip.hostOrder }
                devices = ds
            }
            scanning = false
            updateStatusLine()

        case "deviceNames":
            if let pairs = obj["names"] as? [[String: String]] {
                for p in pairs {
                    if let macS = p["mac"], let name = p["name"], let mac = MACAddress(macS),
                       let idx = devices.firstIndex(where: { $0.mac == mac }) {
                        devices[idx].name = name
                    }
                }
            }

        case "status":
            let targets = obj["targets"] as? [[String: String]] ?? []
            activeMacs = Set(targets.compactMap { MACAddress($0["mac"] ?? "") })
            forwarding = obj["forwarding"] as? Bool ?? false
            if let gw = obj["gateway"] as? String { gateway = gw }
            for i in devices.indices { devices[i].active = activeMacs.contains(devices[i].mac) }
            updateStatusLine()

        case "targetMoved":
            if let macS = obj["mac"] as? String, let ipS = obj["ip"] as? String,
               let mac = MACAddress(macS), let ip = IPv4Address(ipS),
               let idx = devices.firstIndex(where: { $0.mac == mac }) {
                devices[idx].ip = ip
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
        let fwd = forwarding ? "on" : "off"
        let gw = gateway.isEmpty ? "—" : gateway
        statusLine = "\(n) target\(n == 1 ? "" : "s") · fwd:\(fwd) · gw \(gw)"
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
