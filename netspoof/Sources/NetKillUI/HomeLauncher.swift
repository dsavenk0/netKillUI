import SwiftUI

// Home-лаунчер в стиле Flipper Zero: ряд CRT-плиток с гладкими иконками и
// боковыми пиксель-шевронами. Включается флагом `UIConfig.homeLauncher`.
// Вынесен отдельным файлом, чтобы легко отключать/дорабатывать независимо.

struct HomeLauncher: View {
    @EnvironmentObject var model: AppModel
    @State private var sel = 0

    private var tiles: [LauncherTile] {
        [
            LauncherTile(title: "Scan", symbol: "dot.radiowaves.left.and.right") {
                model.open(.devices); if model.connected { model.scan() }
            },
            LauncherTile(title: "Defense", symbol: "shield.lefthalf.filled") {
                model.open(.defense)
            },
            LauncherTile(title: "Settings", symbol: "gearshape.fill") {
                model.open(.settings)
            },
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            HStack(spacing: 30) {               // шевроны разнесены дальше от иконок
                PixelChevron(pointsRight: false)
                    .frame(width: 16, height: 46)
                    .onTapGesture { move(.left) }
                HStack(spacing: 18) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { idx, tile in
                        TileView(tile: tile, selected: idx == sel)
                            .onTapGesture { sel = idx; tile.action() }
                    }
                }
                PixelChevron(pointsRight: true)
                    .frame(width: 16, height: 46)
                    .onTapGesture { move(.right) }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 8)

            // Скрытая активация по Enter для клавиатурной навигации (как во Flipper).
            Button("") { tiles[sel].action() }
                .keyboardShortcut(.return, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)

            HStack(spacing: 16) {
                Text("←→ выбор").font(.mono(10)).foregroundColor(.nkDim)
                Text("⏎ открыть").font(.mono(10)).foregroundColor(.nkDim)
                Spacer()
                Circle().fill(model.connected ? Color.nkOnline : Color.nkDim).frame(width: 6, height: 6)
                Text(model.connected ? "engine up" : "offline").font(.mono(10)).foregroundColor(.nkDim)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.nkElev)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.nkBG)
        .focusable()
        .onMoveCommand { move($0) }
    }

    private func move(_ dir: MoveCommandDirection) {
        let n = tiles.count
        switch dir {
        case .left, .up:    sel = (sel - 1 + n) % n
        case .right, .down: sel = (sel + 1) % n
        @unknown default: break
        }
    }
}

private struct LauncherTile: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String         // SF-символ (гладкий), стилизуется под CRT в TileView
    let action: () -> Void
}

/// Плитка-«экран CRT»: гладкий SF-символ с фосфорным свечением, поверх — скан-
/// линии и виньетка старого монитора. Выбранная — «включённый» экран: залит
/// акцентом, глиф инвертирован.
private struct TileView: View {
    let tile: LauncherTile
    let selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Стекло экрана
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Color.nkAccent, Color.nkAccent.opacity(0.80)],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [Color.nkElev, Color.nkBG],
                                                         startPoint: .top, endPoint: .bottom)))
                // Глиф-«фосфор» со свечением
                Image(systemName: tile.symbol)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundColor(selected ? .nkBG : .nkAccent)
                    .shadow(color: selected ? .clear : Color.nkAccent.opacity(0.75), radius: 6)
                    .shadow(color: selected ? .clear : Color.nkAccent.opacity(0.4), radius: 13)
                // Эффект старого монитора
                CRTOverlay()
            }
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(selected ? Color.nkAccent.opacity(0.6) : Color.nkLine, lineWidth: 1)
            )
            .shadow(color: selected ? Color.nkAccent.opacity(0.5) : .black.opacity(0.3),
                    radius: selected ? 18 : 6, y: selected ? 6 : 3)
            .scaleEffect(selected ? 1.05 : 1.0)

            Text(tile.title)
                .font(.mono(12.5, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? .nkAccent : .nkFG)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: selected)
    }
}

/// Накладка «старого монитора» (CRT): горизонтальные скан-линии + виньетка
/// (кривизна экрана). Не перехватывает нажатия.
private struct CRTOverlay: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1.2)),
                             with: .color(.black.opacity(0.22)))
                    y += 3
                }
            }
            .blendMode(.multiply)

            RadialGradient(colors: [.clear, .black.opacity(0.4)],
                           center: .center, startRadius: 28, endRadius: 86)
        }
        .allowsHitTesting(false)
    }
}

/// Пиксельный шеврон-стрелка для боковой навигации (деталь меню Flipper).
private struct PixelChevron: View {
    let pointsRight: Bool
    var color: Color = .nkAccent
    private let rows = [
        "#.....",
        "##....",
        ".##...",
        "..##..",
        "...##.",
        "....##",
        "...##.",
        "..##..",
        ".##...",
        "##....",
        "#.....",
    ]
    var body: some View {
        Canvas { ctx, size in
            let h = rows.count, w = rows[0].count
            let px = min(size.width / CGFloat(w), size.height / CGFloat(h))
            let ox = (size.width - px * CGFloat(w)) / 2
            let oy = (size.height - px * CGFloat(h)) / 2
            for (r, line) in rows.enumerated() {
                for (c, ch) in Array(line).enumerated() where ch == "#" {
                    let col = pointsRight ? c : (w - 1 - c)   // влево — зеркалим
                    ctx.fill(Path(CGRect(x: ox + CGFloat(col) * px + 0.5, y: oy + CGFloat(r) * px + 0.5,
                                         width: px - 1, height: px - 1)),
                             with: .color(color))
                }
            }
        }
        .contentShape(Rectangle())
    }
}
