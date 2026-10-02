import SwiftUI
import ARPSpoofCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            Toolbar()
            Divider().overlay(Color.nkLine)
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
        .preferredColorScheme(.dark)
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

private struct TitleBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            (Text("net").foregroundColor(.nkFG)
                + Text("Kill").foregroundColor(.nkAccent)
                + Text("UI").foregroundColor(.nkFG))
                .font(.mono(13, weight: .bold))
            Spacer()
            Circle()
                .fill(model.connected ? Color.nkOnline : Color.nkDim)
                .frame(width: 7, height: 7)
            Text(model.connected ? "engine up" : "offline")
                .font(.mono(10))
                .foregroundColor(.nkDim)
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
                Text("if ").foregroundColor(.nkFG) + Text(model.interface).foregroundColor(.nkDim)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if model.connected {
                toolButton("⟳ Scan", disabled: model.scanning) { model.scan() }
            } else {
                toolButton("⏻ Start engine", accent: true) { model.requestStart() }
            }

            Spacer()

            toolButton("▶ Spoof All", accent: true) { model.spoofAll() }
            toolButton("■ Stop All") { model.stopAll() }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.nkBG)
    }

    private func toolButton(_ title: String, accent: Bool = false, disabled: Bool = false,
                            _ action: @escaping () -> Void) -> some View {
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

private struct SectionHeader: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            Text("┌─ DEVICES").font(.mono(11)).foregroundColor(.nkDim)
            Spacer()
            let active = model.devices.filter { $0.active }.count
            (Text("\(model.devices.count) hosts · ").foregroundColor(.nkDim)
                + Text("\(active) active").foregroundColor(.nkAccent))
                .font(.mono(11))
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
                Text(device.isGateway ? "—" : (device.active ? "◉" : "◯"))
                    .font(.mono(18))
                    .foregroundColor(device.active ? .nkAccent : .nkDim)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            .disabled(device.isGateway)

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
        .contextMenu {
            if !device.isGateway {
                Button(device.active ? "Stop spoof" : "Spoof") { model.toggle(device) }
            }
        }
    }
}

private struct StatusChip: View {
    let device: Device
    var body: some View {
        Group {
            if device.isGateway {
                chip("⌂ GATEWAY", color: .nkDim)
            } else if device.active {
                chip("● SPOOFING", color: .nkAccent, filled: true)
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

private struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 10) {
            Text(model.scanning ? "▓▓▓░ сканирую сеть…"
                 : (model.connected ? "хостов не найдено" : "движок не запущен"))
                .font(.mono(13)).foregroundColor(.nkDim)
            if !model.connected && !model.scanning {
                Text("нажмите ⏻ Start engine, чтобы просканировать сеть")
                    .font(.system(size: 12)).foregroundColor(.nkDim)
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
                Button("Согласен, запустить") { model.acceptConsent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!agreed)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.nkElev)
    }
}
