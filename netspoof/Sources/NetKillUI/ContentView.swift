import SwiftUI
import ARPSpoofCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
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
            SectionHeader()
            DeviceList()
            StatusBar()
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
                Button(action: { model.toggleNinja() }) {
                    Text("🥷")
                        .font(.system(size: 15))
                        .grayscale(1).saturation(0)          // монохромный emoji
                        .opacity(model.ninja ? 1 : 0.45)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(model.ninja ? Color.nkAccent.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(model.ninja ? Color.nkAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Тихий режим: пассивное обнаружение без ARP-свипа + oneway-спуфинг, реже переотправка. Меньше следов — но не невидимость: ARP-poisoning всё равно детектируется.")
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

            StatusChip(device: device)
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
    var body: some View {
        Group {
            if device.isSelf {
                chip("THIS MAC", color: .nkSelect)
            } else if device.isGateway {
                chip("⌂ GATEWAY", color: .nkDim)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("⚠").font(.system(size: 22)).foregroundColor(.nkAccent)
                Text("Авторизованное использование")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.nkFG)
            }
            Text("netKillUI выполняет ARP-спуфинг — перехват и разрыв трафика в локальной сети. "
                 + "Используйте его только в сети, которой владеете, или имея письменное разрешение "
                 + "владельца. Применение к чужим устройствам без согласия незаконно.")
                .font(.system(size: 13)).foregroundColor(.nkDim)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $agreed) {
                Text("Подтверждаю: только своя или разрешённая сеть, не в вредоносных целях.")
                    .font(.system(size: 12.5)).foregroundColor(.nkFG)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Отмена") { model.declineConsent() }
                Button("Согласен") { model.acceptConsent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!agreed)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.nkElev)
    }
}
