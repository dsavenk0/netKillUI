import Foundation
import ARPSpoofCore

// MARK: - IP forwarding control

final class ForwardingControl {
    /// cut=true  → forwarding ВЫКЛ: трафик целей упирается в нас и обрывается (kill).
    /// cut=false → forwarding ВКЛ при активных целях: прозрачный MITM (перехват).
    var cutMode: Bool
    private(set) var enabledByUs = false

    init(cutMode: Bool) { self.cutMode = cutMode }

    var isOn: Bool { getIPForwarding() == 1 }

    /// Привести forwarding к нужному состоянию исходя из режима и наличия целей.
    func apply(hasActive: Bool) {
        if cutMode {
            // В cut-режиме форвардинг должен быть выключен (даже если его включил
            // кто-то до нас) — иначе цель не отвалится.
            if getIPForwarding() == 1 { setIPForwarding(false) }
            enabledByUs = false
        } else if hasActive {
            if getIPForwarding() != 1, setIPForwarding(true) { enabledByUs = true }
        } else {
            disableIfEnabled()
        }
    }

    func disableIfEnabled() {
        if enabledByUs { setIPForwarding(false); enabledByUs = false }
    }
}

// MARK: - JSON helpers

private func sendJSON(_ fd: Int32, _ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    data.append(0x0A)
    data.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, raw.count) }
}

private func macList(_ cmd: [String: Any]) -> [MACAddress] {
    var out = [MACAddress]()
    if let s = cmd["mac"] as? String, let m = MACAddress(s) { out.append(m) }
    if let arr = cmd["macs"] as? [String] {
        for s in arr { if let m = MACAddress(s) { out.append(m) } }
    }
    return out
}

private func statusPayload(_ engine: SpoofEngine, _ fwd: ForwardingControl) -> [String: Any] {
    let targets: [[String: String]] = engine.active.map { mac in
        ["mac": mac.description, "ip": engine.currentIP(of: mac)?.description ?? ""]
    }
    return [
        "event": "status",
        "targets": targets,
        "forwarding": fwd.isOn,
        "cut": fwd.cutMode,
        "gateway": engine.gatewayIP.description,
    ]
}

// MARK: - Unix socket

func makeListeningSocket(path: String, owner: String?) -> Int32? {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutablePointer(to: &addr.sun_path) { raw in
        raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
            _ = strncpy(dst, path, capacity - 1)
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) { ap in
        ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
    }
    guard bound == 0 else { close(fd); return nil }
    chmod(path, 0o600)
    // GUI запускает serve как root (osascript), но подключается как пользователь —
    // отдаём сокет владельцу, чтобы доступ был только у него, а не 0666 для всех.
    if let owner, let pw = getpwnam(owner) {
        chown(path, pw.pointee.pw_uid, pw.pointee.pw_gid)
    }
    guard listen(fd, 1) == 0 else { close(fd); return nil }
    return fd
}

// MARK: - Command handling

private func handle(_ cmd: [String: Any], client: Int32,
                    engine: SpoofEngine, fwd: ForwardingControl) {
    guard let c = cmd["cmd"] as? String else {
        sendJSON(client, ["event": "error", "message": "нет поля cmd"]); return
    }
    switch c {
    case "scan":
        // Прогрессивно: сперва быстрый ARP-список, затем имена отдельным событием.
        print("cmd scan: обнаружение хостов…")
        let hosts = engine.spoofer.discoverHosts()
        for h in hosts { engine.observe(h) }
        let list = hosts.map { h in
            ["ip": h.ip.description, "mac": h.mac.description, "vendor": h.vendor]
        }
        sendJSON(client, ["event": "devices", "list": list])
        print("cmd scan: \(hosts.count) хостов, резолвлю имена…")
        let names = engine.spoofer.resolveNames(for: hosts)
        if !names.isEmpty {
            let pairs = names.map { ["mac": $0.key.description, "name": $0.value] }
            sendJSON(client, ["event": "deviceNames", "names": pairs])
        }
        print("cmd scan: имена отправлены (\(names.count))")

    case "start":
        let macs = macList(cmd)
        for m in macs { engine.start(m) }
        fwd.apply(hasActive: !engine.active.isEmpty)
        print("cmd start: запрошено \(macs.count), активно \(engine.active.count), cut=\(fwd.cutMode), fwd=\(fwd.isOn)")
        sendJSON(client, statusPayload(engine, fwd))

    case "stop":
        let macs = macList(cmd)
        for m in macs { engine.stop(m) }
        fwd.apply(hasActive: !engine.active.isEmpty)
        print("cmd stop: запрошено \(macs.count), активно \(engine.active.count)")
        sendJSON(client, statusPayload(engine, fwd))

    case "stopAll":
        engine.stopAll()
        fwd.apply(hasActive: false)
        print("cmd stopAll: активно \(engine.active.count)")
        sendJSON(client, statusPayload(engine, fwd))

    case "mode":
        if let cut = cmd["cut"] as? Bool {
            fwd.cutMode = cut
            fwd.apply(hasActive: !engine.active.isEmpty)
            print("cmd mode: cut=\(cut), fwd=\(fwd.isOn)")
        }
        sendJSON(client, statusPayload(engine, fwd))

    case "status":
        sendJSON(client, statusPayload(engine, fwd))

    default:
        sendJSON(client, ["event": "error", "message": "неизвестная команда \(c)"])
    }
}

// MARK: - Serve loop (single-threaded poll multiplex)

func runServe(info: InterfaceInfo, engine: SpoofEngine, bpf: BPFDevice,
              listenFD: Int32, intervalMS: Int, fwd: ForwardingControl) {
    signal(SIGPIPE, SIG_IGN) // запись в закрытый сокет не должна убивать процесс
    signal(SIGHUP, SIG_IGN)  // пережить выход admin-шелла (запуск без nohup)

    while gStop == 0 {
        // Ждём клиента через poll, чтобы не блокироваться в accept() и ловить Ctrl-C.
        var lfd = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
        if poll(&lfd, 1, 300) <= 0 { continue }
        if gStop != 0 { break }

        let client = accept(listenFD, nil, nil)
        if client < 0 { continue }
        print("client: подключился")

        sendJSON(client, [
            "event": "ready",
            "iface": info.name,
            "ip": info.ip.description,
            "mac": info.mac.description,
            "gateway": engine.gatewayIP.description,
            "gatewayMac": engine.gatewayMAC.description,
        ])

        var buf = [UInt8]()
        var lastTick = Date()

        clientLoop: while gStop == 0 {
            var fds = [
                pollfd(fd: client, events: Int16(POLLIN), revents: 0),
                pollfd(fd: bpf.fd, events: Int16(POLLIN), revents: 0),
            ]
            _ = poll(&fds, 2, 150)

            // Тик травли по расписанию.
            if Date().timeIntervalSince(lastTick) * 1000 >= Double(intervalMS) {
                engine.tick()
                lastTick = Date()
            }

            // Команды от клиента.
            if fds[0].revents & Int16(POLLIN) != 0 || fds[0].revents & Int16(POLLHUP) != 0 {
                var tmp = [UInt8](repeating: 0, count: 4096)
                let n = read(client, &tmp, tmp.count)
                if n <= 0 { break clientLoop } // клиент отключился
                buf.append(contentsOf: tmp[0..<n])
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = Array(buf[0..<nl])
                    buf.removeSubrange(0...nl)
                    if let obj = try? JSONSerialization.jsonObject(with: Data(line)),
                       let cmd = obj as? [String: Any] {
                        handle(cmd, client: client, engine: engine, fwd: fwd)
                    }
                }
            }

            // ARP-трафик → обновление связок MAC→IP, уведомление о переезде цели.
            if fds[1].revents & Int16(POLLIN) != 0 {
                for f in bpf.receive(timeoutMS: 0) {
                    if let moved = engine.ingest(f), engine.active.contains(moved),
                       let ip = engine.currentIP(of: moved) {
                        sendJSON(client, ["event": "targetMoved", "mac": moved.description, "ip": ip.description])
                    }
                }
            }
        }

        // Watchdog: клиент ушёл — восстановить кэши и выключить forwarding.
        print("client: отключился — восстанавливаю ARP-кэши")
        engine.stopAll()
        fwd.disableIfEnabled()
        close(client)

        // Единственный клиент — GUI. Он ушёл → демон завершает работу,
        // чтобы не оставлять висящий root-процесс.
        break
    }
}
