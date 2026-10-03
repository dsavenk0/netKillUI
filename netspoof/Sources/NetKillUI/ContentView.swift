import SwiftUI
import ARPSpoofCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            switch model.activeScreen {
            case .home:     HomeLauncher()
            case .devices:  DevicesScreen()
            case .defense:  DefenseScreen()
            case .settings: SettingsScreen()
            }
        }
        .background(Color.nkBG)
        .foregroundColor(.nkFG)
        .preferredColorScheme(model.darkTheme ? .dark : .light)
        .onAppear { model.showConsentOnLaunch() }
        .sheet(isPresented: $model.showConsent) {
            ConsentView().environmentObject(model)
        }
        .alert("Ошибка", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Devices screen (бывший главный экран)

private struct DevicesScreen: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Toolbar()
            Divider().overlay(Color.nkLine)
            if let alert = model.alertBanner {
                AlertBanner(text: alert) { model.alertBanner = nil }
                Divider().overlay(Color.nkLine)
            }
            if let hint = model.hintBanner {
                HintBanner(text: hint) { model.hintBanner = nil }
                Divider().overlay(Color.nkLine)
            }
            if !model.selection.isEmpty {
                SelectionBar()
                Divider().overlay(Color.nkLine)
            }
            if model.monitor {
                TrafficRadar(
                    devices: model.devices.filter { $0.online && !$0.isGateway && !$0.isSelf },
                    rates: model.rates
                )
                .frame(height: 230)
                .padding(.vertical, 10)
                Divider().overlay(Color.nkLine)
            }
            SectionHeader()
            DeviceList()
            StatusBar()
        }
    }
}


// MARK: - Defense / Settings screens

private struct DefenseScreen: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(icon: "shield.lefthalf.filled", title: "Self-defense")
            if let alert = model.alertBanner {
                AlertBanner(text: alert) { model.alertBanner = nil }
                Divider().overlay(Color.nkLine)
            }
            VStack(alignment: .leading, spacing: 14) {
                statusRow("Детект чужих ARP-спуферов",
                          model.connected ? "активен" : "нужен запуск движка",
                          ok: model.connected)
                statusRow("Автозакрепление шлюза при атаке", "включено", ok: true)
                statusRow("Шлюз", model.gateway.isEmpty ? "—" : model.gateway, ok: !model.gateway.isEmpty)

                Text("Если кто-то в сети выдаёт себя за твой шлюз, netKillUI покажет "
                     + "предупреждение и статически закрепит настоящий MAC шлюза в твоём "
                     + "ARP-кэше — тебя нельзя будет увести. При выходе закрепление снимается.")
                    .font(.system(size: 12.5)).foregroundColor(.nkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.nkBG)
    }

    private func statusRow(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundColor(.nkFG)
            Spacer()
            Text(value).font(.mono(11.5)).foregroundColor(ok ? .nkAccent : .nkDim)
        }
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(icon: "gearshape.fill", title: "Settings")
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(get: { model.darkTheme },
                                     set: { _ in model.toggleTheme() })) {
                    Text("Тёмная тема").font(.system(size: 13)).foregroundColor(.nkFG)
                }
                if model.connected {
                    Toggle(isOn: Binding(get: { model.ninja },
                                         set: { _ in model.toggleNinja() })) {
                        Text("Ниндзя (тихий режим)").font(.system(size: 13)).foregroundColor(.nkFG)
                    }
                } else {
                    Toggle(isOn: $model.maskMac) {
                        Text("Маскировать MAC при старте").font(.system(size: 13)).foregroundColor(.nkFG)
                    }
                }
                Divider().overlay(Color.nkLine)
                Text("netKillUI — ARP-инструмент для своей сети. Только авторизованное использование.")
                    .font(.system(size: 12)).foregroundColor(.nkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .tint(.nkAccent)
            .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.nkBG)
    }
}

/// Шапка раздела: иконка + название.
private struct ScreenHeader: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundColor(.nkAccent)
            Text(title).font(.mono(13, weight: .bold)).foregroundColor(.nkFG)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.nkElev)
        .overlay(Divider().overlay(Color.nkLine), alignment: .bottom)
    }
}

// MARK: - Titlebar

/// Терминальный мигающий курсор у названия.
private struct BlinkingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            Text("▊")
                .font(.mono(13, weight: .bold))
                .foregroundColor(.nkAccent)
                .opacity(on ? 1 : 0)
        }
    }
}

private struct TitleBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            if UIConfig.homeLauncher && model.activeScreen != .home {
                Button(action: { model.goHome() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.nkAccent)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("На главный экран")
            }
            HStack(spacing: 2) {
                (Text("net").foregroundColor(.nkFG)
                    + Text("Kill").foregroundColor(.nkAccent)
                    + Text("UI").foregroundColor(.nkFG))
                    .font(.mono(13, weight: .bold))
                BlinkingCursor()
            }
            Spacer()
            Circle()
                .fill(model.connected ? Color.nkOnline : Color.nkDim)
                .frame(width: 7, height: 7)
            Text(model.connected ? "engine up" : "offline")
                .font(.mono(10))
                .foregroundColor(.nkDim)
                .padding(.leading, 6)
            if !model.connected {
                // MAC-mask — выбор ДО запуска: применяется при Start engine.
                Button(action: { model.maskMac.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: model.maskMac ? "shield.lefthalf.filled" : "shield")
                            .font(.system(size: 13, weight: .medium))
                        Text("Mask MAC").font(.mono(10))
                    }
                    .foregroundColor(model.maskMac ? .nkAccent : .nkDim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(model.maskMac ? Color.nkAccent.opacity(0.5) : Color.nkLine, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Маскировать свой MAC при запуске: подменяем аппаратный адрес на правдоподобный (префикс вендора + случайный хвост), чтобы скрыть личность устройства. ВАЖНО: на встроенном Wi-Fi Apple Silicon не закрепляется (сообщим честно) — работает на USB-Ethernet. При выходе MAC восстанавливается.")
                .padding(.leading, 8)
            }
            if model.connected && model.masked {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.nkAccent)
                    .help("MAC замаскирован на эту сессию")
                    .padding(.leading, 6)
            }
            if model.connected {
                // Явная кнопка-пилюля с подписью — чтобы читалась как тумблер, а не декор.
                Button(action: { model.toggleNinja() }) {
                    HStack(spacing: 5) {
                        Text("🥷")
                            .font(.system(size: 14))
                            .grayscale(1).saturation(0)          // монохромный emoji
                            .opacity(model.ninja ? 1 : 0.6)
                        Text("Ninja").font(.mono(10.5))
                    }
                    .foregroundColor(model.ninja ? .nkAccent : .nkDim)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(model.ninja ? Color.nkAccent.opacity(0.12) : Color.nkElev)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(model.ninja ? Color.nkAccent.opacity(0.5) : Color.nkLine, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Тихий режим: пассивное обнаружение (ARP-кэш ОС, без свипа) + умеренный темп травли. Меньше следов в разведке — но не невидимость: ARP-poisoning всё равно детектируется.")
                .padding(.leading, 10)
            }
            Button(action: { model.toggleTheme() }) {
                Image(systemName: model.darkTheme ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.nkAccent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Светлая/тёмная тема")
            .padding(.leading, 16)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.nkElev)
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(model.availableInterfaces, id: \.self) { i in
                    Button(i) { model.interface = i }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "network").font(.system(size: 11)).foregroundColor(.nkDim)
                    Text(model.interface).foregroundColor(.nkFG)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if model.connected {
                toolButton("⟳ Scan", disabled: model.scanning) { model.scan() }
            } else {
                toolButton("⏻ Start engine", accent: true) { model.requestStart() }
            }

            Spacer()

            // Монитор трафика — только вне ниндзя (активный MITM = шум/засветка).
            if model.connected && !model.ninja {
                toolButton(model.monitor ? "◉ Monitor" : "◯ Monitor", accent: model.monitor,
                           help: "Замер трафика: прозрачный MITM всех на время замера — никого не режем, показываем KB/s по устройствам. Решай кого блокировать. В ниндзя недоступно.") {
                    model.toggleMonitor()
                }
            }
            if !model.ninja {
                toolButton("▶ Spoof All", accent: true) { model.spoofAll() }
            }
            toolButton("■ Stop All") { model.stopAll() }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.nkBG)
    }

    private func toolButton(_ title: String, accent: Bool = false, disabled: Bool = false,
                            help: String = "", _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundColor(accent ? .nkAccent : .nkFG)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent ? Color.nkAccent.opacity(0.10) : Color.nkElev)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accent ? Color.nkAccent.opacity(0.45) : Color.nkLine, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(help)
    }
}

// MARK: - Selection bar

private struct SelectionBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            (Text("\(model.selection.count)").foregroundColor(.nkSelect).bold()
                + Text(" selected").foregroundColor(.nkDim))
                .font(.mono(12))
            Spacer()
            smallButton("▶ Spoof selected", accent: true) { model.spoofSelected() }
            smallButton("■ Stop selected") { model.stopSelected() }
            smallButton("✕ Deselect", ghost: true) { model.clearSelection() }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.nkSelect.opacity(0.10))
    }

    private func smallButton(_ t: String, accent: Bool = false, ghost: Bool = false,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundColor(ghost ? .nkDim : (accent ? .nkAccent : .nkFG))
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(ghost ? Color.clear : (accent ? Color.nkAccent.opacity(0.10) : Color.nkElev)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(ghost ? Color.clear : (accent ? Color.nkAccent.opacity(0.45) : Color.nkLine), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

private struct AlertBanner: View {
    let text: String
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.mono(12)).foregroundColor(.nkAccent)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Text("✕").font(.mono(12)).foregroundColor(.nkDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.nkAccent.opacity(0.12))
    }
}

/// Спокойная подсказка (не тревога): приглушённый фон, текст в основном цвете.
private struct HintBanner: View {
    let text: String
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.mono(11.5)).foregroundColor(.nkFG)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Text("✕").font(.mono(12)).foregroundColor(.nkDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.nkElev)
    }
}

private struct SectionHeader: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Text("┌─ DEVICES").font(.mono(11)).foregroundColor(.nkDim)
            Spacer()
            if model.scanning {
                // Заметная анимация и во время ПОВТОРНОГО скана (не только пустого экрана).
                ScanMeter(width: 16, fontSize: 11, kerning: 1)
                Text(model.ninja ? "passive scan…" : "scanning…")
                    .font(.mono(11)).foregroundColor(.nkAccent)
            } else {
                let online = model.devices.filter { $0.online }.count
                let offline = model.devices.count - online
                (Text("\(online) online").foregroundColor(.nkAccent)
                    + Text(" · \(offline) offline").foregroundColor(.nkDim))
                    .font(.mono(11))
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }
}

// MARK: - Device list

private struct DeviceList: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if model.devices.isEmpty {
                EmptyState()
            } else {
                List(selection: $model.selection) {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device)
                            .tag(device.mac)
                            .listRowBackground(rowBackground(device))
                            .listRowSeparatorTint(Color.nkLine)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.nkBG)
    }

    private func rowBackground(_ d: Device) -> some View {
        ZStack {
            (d.active ? Color.nkAccent.opacity(0.09) : Color.clear)
            if model.selection.contains(d.mac) { Color.nkSelect.opacity(0.12) }
            if d.active {
                HStack { Rectangle().fill(Color.nkAccent).frame(width: 2); Spacer() }
            }
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject var model: AppModel
    let device: Device

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { model.toggle(device) }) {
                // ◉ — заблокировано (постоянно), ◯ — нет. Серый у оффлайн.
                Text(device.isGateway || device.isSelf ? "—" : (device.blocked ? "◉" : "◯"))
                    .font(.mono(18))
                    .foregroundColor(device.blocked ? .nkAccent : .nkDim)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .disabled(device.isGateway || device.isSelf)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.ip.description).font(.mono(14, weight: .medium))
            }
            .frame(width: 140, alignment: .leading)

            Text(device.mac.description).font(.mono(12.5)).foregroundColor(.nkDim)
                .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name ?? device.vendor)
                    .font(.system(size: 13)).foregroundColor(.nkFG)
                    .lineLimit(1).truncationMode(.tail)
                if device.name != nil {
                    Text(device.vendor)
                        .font(.mono(10)).foregroundColor(.nkDim)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusChip(device: device, monitoring: model.monitor, rate: model.rates[device.mac])
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .opacity(device.online || device.isSelf ? 1 : 0.5)   // оффлайн — приглушённо
        .contextMenu {
            if !device.isGateway && !device.isSelf {
                Button(device.blocked ? "Unblock" : "Block") { model.toggle(device) }
            }
        }
    }
}

private struct StatusChip: View {
    let device: Device
    var monitoring: Bool = false
    var rate: Double? = nil
    var body: some View {
        Group {
            if device.isSelf {
                chip("THIS MAC", color: .nkSelect)
            } else if device.isGateway {
                chip("⌂ GATEWAY", color: .nkDim)
            } else if monitoring {
                // Замер трафика: показываем KB/s (акцент — у заметной нагрузки).
                let kb = rate ?? 0
                chip(String(format: "%@ %.0f KB/s", kb > 1 ? "↓" : "·", kb),
                     color: kb > 20 ? .nkAccent : (kb > 1 ? .nkFG : .nkDim),
                     filled: kb > 20)
            } else if device.active {
                chip("● SPOOFING", color: .nkAccent, filled: true)
            } else if device.blocked {
                // Заблокировано, но сейчас не травится: оффлайн — ждём появления.
                chip(device.online ? "◉ BLOCKED" : "⏳ BLOCKED", color: .nkAccent)
            } else if !device.online {
                chip("◦ offline", color: .nkDim)
            } else {
                chip("◦ idle", color: .nkDim)
            }
        }
        .frame(width: 110, alignment: .trailing)
    }

    private func chip(_ t: String, color: Color, filled: Bool = false) -> some View {
        Text(t).font(.mono(10.5))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundColor(color)
            .background(RoundedRectangle(cornerRadius: 99)
                .fill(filled ? color.opacity(0.10) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 99)
                .stroke(filled ? color.opacity(0.45) : Color.nkLine, lineWidth: 1))
    }
}

// MARK: - Traffic radar

/// Радар в стиле приложения для режима Monitor: тёмный круг, концентрические
/// кольца, вращающийся луч развёртки; устройства — блипы по кругу, размер и
/// яркость ∝ KB/s, вспыхивают, когда луч проходит мимо.
private struct TrafficRadar: View {
    let devices: [Device]
    let rates: [MACAddress: Double]

    private let sweepPeriod: Double = 4.0   // секунд на оборот

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2 - 10
                guard R > 10 else { return }

                // Кольца.
                for k in 1...4 {
                    let r = R * CGFloat(k) / 4
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(.nkLine), lineWidth: 1)
                }
                // Перекрестье.
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - R, y: c.y)); cross.addLine(to: CGPoint(x: c.x + R, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - R)); cross.addLine(to: CGPoint(x: c.x, y: c.y + R))
                ctx.stroke(cross, with: .color(.nkLine.opacity(0.6)), lineWidth: 1)

                // Луч развёртки с затухающим шлейфом.
                let sweep = (t.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod) * 2 * .pi
                func pt(_ a: Double, _ r: CGFloat) -> CGPoint {
                    CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                }
                for i in 0..<28 {
                    let a = sweep - Double(i) * 0.028
                    let op = (1 - Double(i) / 28) * 0.30
                    var p = Path(); p.move(to: c); p.addLine(to: pt(a, R))
                    ctx.stroke(p, with: .color(.nkAccent.opacity(op)), lineWidth: 2)
                }
                var lead = Path(); lead.move(to: c); lead.addLine(to: pt(sweep, R))
                ctx.stroke(lead, with: .color(.nkAccent), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                         with: .color(.nkAccent))

                // Блипы устройств.
                for d in devices {
                    let a = angle(d.mac)
                    let rf = radiusFactor(d.mac)
                    let p = pt(a, R * rf)
                    let kb = rates[d.mac] ?? 0
                    let blip = 3.0 + min(13.0, sqrt(kb) * 2.2)

                    // Подсветка, когда луч рядом (классический радар).
                    var da = (sweep - a).truncatingRemainder(dividingBy: 2 * .pi)
                    if da < 0 { da += 2 * .pi }
                    let glow = da < 0.9 ? (1 - da / 0.9) : 0
                    let op = 0.35 + 0.65 * glow + min(0.3, kb / 80)

                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - blip, y: p.y - blip, width: 2 * blip, height: 2 * blip)),
                             with: .color(.nkAccent.opacity(min(1, op))))
                    if glow > 0.05 {
                        let g = blip + 5
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: 2 * g, height: 2 * g)),
                                 with: .color(.nkAccent.opacity(0.18 * glow)))
                    }
                    // Подпись у заметной нагрузки.
                    if kb > 1 {
                        let label = d.name ?? ".\(d.ip.description.split(separator: ".").last.map(String.init) ?? "")"
                        ctx.draw(Text("\(label)  \(Int(kb))k").font(.mono(9)).foregroundColor(.nkDim),
                                 at: CGPoint(x: p.x, y: p.y - blip - 8))
                    }
                }
            }
        }
    }

    private func angle(_ mac: MACAddress) -> Double {
        let h = mac.bytes.enumerated().reduce(0) { $0 &+ Int($1.element) &* (($1.offset + 1) * 37) }
        return Double(((h % 360) + 360) % 360) * .pi / 180
    }
    private func radiusFactor(_ mac: MACAddress) -> Double {
        let h = mac.bytes.reduce(0) { $0 &+ Int($1) }
        return 0.42 + Double(h % 100) / 100 * 0.46   // 0.42..0.88, стабильно
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(model.devices.contains { $0.active } ? Color.nkAccent : Color.nkDim)
                .frame(width: 9, height: 9)
            Text(model.statusLine).font(.mono(11.5)).foregroundColor(.nkDim)
            Spacer()
            Text(model.scanning ? "▓▓▓░ scanning" : (model.connected ? "ready" : "offline"))
                .font(.mono(11.5))
                .foregroundColor(model.scanning ? .nkAccent : .nkDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.nkElev)
    }
}

// MARK: - Empty state

/// Анимированный ASCII-метр: бегущая волна блоков (█▓▒░) в акценте по тусклой дорожке.
private struct ScanMeter: View {
    var width: Int = 30
    var fontSize: CGFloat = 16
    var kerning: CGFloat = 2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            Text(bar(at: context.date))
                .font(.mono(fontSize))
                .kerning(kerning)
        }
    }

    private func bar(at date: Date) -> AttributedString {
        let period = width + 10
        let step = Int(date.timeIntervalSinceReferenceDate / 0.08)
        let head = step % period - 5
        var out = AttributedString()
        for i in 0..<width {
            let dist = abs(i - head)
            let ch: Character
            let bright: Bool
            switch dist {
            case 0: ch = "█"; bright = true
            case 1: ch = "▓"; bright = true
            case 2: ch = "▒"; bright = true
            default: ch = "░"; bright = false
            }
            var seg = AttributedString(String(ch))
            seg.foregroundColor = bright ? Color.nkAccent : Color.nkDim
            out.append(seg)
        }
        return out
    }
}

private struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            if model.scanning {
                ScanMeter()
                Text("сканирую сеть…").font(.mono(13)).foregroundColor(.nkDim)
            } else {
                Text(model.connected ? "хостов не найдено" : "движок не запущен")
                    .font(.mono(13)).foregroundColor(.nkDim)
                if !model.connected {
                    Text("нажмите ⏻ Start engine, чтобы просканировать сеть")
                        .font(.system(size: 12)).foregroundColor(.nkDim)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Consent / авторизованное использование

private struct ConsentView: View {
    @EnvironmentObject var model: AppModel
    @State private var agreed = false

    // Язык предупреждения — по системной локали (русский для ru, иначе английский).
    private var ru: Bool {
        (Locale.current.language.languageCode?.identifier ?? "en") == "ru"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("⚠").font(.system(size: 22)).foregroundColor(.nkAccent)
                Text(ru ? "Авторизованное использование" : "Authorized use only")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.nkFG)
            }
            Text(ru
                 ? "netKillUI выполняет ARP-спуфинг — перехват и разрыв трафика в локальной сети. "
                   + "Используйте его только в сети, которой владеете, или имея письменное разрешение "
                   + "владельца. Применение к чужим устройствам без согласия незаконно."
                 : "netKillUI performs ARP spoofing — it intercepts and disrupts traffic on a local "
                   + "network. Use it only on a network you own or have written permission to test. "
                   + "Using it against devices without consent is illegal.")
                .font(.system(size: 13)).foregroundColor(.nkDim)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $agreed) {
                Text(ru
                     ? "Подтверждаю: только своя или разрешённая сеть, не в вредоносных целях."
                     : "I confirm: only my own or an authorized network, not for malicious purposes.")
                    .font(.system(size: 12.5)).foregroundColor(.nkFG)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(ru ? "Отмена" : "Cancel") { model.declineConsent() }
                Button(ru ? "Согласен" : "I agree") { model.acceptConsent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!agreed)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.nkElev)
    }
}
