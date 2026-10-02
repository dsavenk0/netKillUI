import AppKit

// Баннер для README (1280×360 PNG): тёмный фон, слева — логотип (wifi-дуги с
// «глазом»-перехватчиком и неоновым свечением), справа — вордмарк netKillUI и
// таглайн. Та же бренд-гамма, что у иконки.
// Использование: swift make-banner.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/nk-banner.png"
let W: CGFloat = 1280, H: CGFloat = 360

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let orange = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.0, alpha: 1.0)
let darkEye = NSColor(srgbRed: 0.03, green: 0.035, blue: 0.045, alpha: 1.0)
let fg = NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1.0)
let dim = NSColor(srgbRed: 0.52, green: 0.55, blue: 0.60, alpha: 1.0)

// --- Фон: тёмный диагональный градиент ---
let bg = NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H))
if let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1),
    NSColor(srgbRed: 0.015, green: 0.02, blue: 0.028, alpha: 1),
]) {
    grad.draw(in: bg, angle: -60)
}
// Тонкая оранжевая линия снизу — «терминальный» акцент.
orange.withAlphaComponent(0.85).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: 5)).fill()

func disc(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)).fill()
}

// --- Логотип слева (рисуем в координатах иконки 1024, через трансформацию) ---
NSGraphicsContext.saveGraphicsState()
let t = NSAffineTransform()
t.translateX(by: 215, yBy: H / 2)   // куда поместить центр логотипа на баннере
t.scale(by: 0.50)
t.translateX(by: -512, yBy: -520)   // центр содержимого логотипа в коорд. иконки
t.concat()

let glow = NSShadow()
glow.shadowColor = orange.withAlphaComponent(0.75)
glow.shadowBlurRadius = 26
glow.shadowOffset = .zero
glow.set()

let O = NSPoint(x: 512, y: 452)
for radius in [CGFloat(150), 238, 326] {
    let p = NSBezierPath()
    p.appendArc(withCenter: O, radius: radius, startAngle: 42, endAngle: 138)
    p.lineWidth = 42
    p.lineCapStyle = .round
    orange.setStroke()
    p.stroke()
}

let ew: CGFloat = 100, eh: CGFloat = 62
let eyeL = NSPoint(x: O.x - ew, y: O.y), eyeR = NSPoint(x: O.x + ew, y: O.y)
let eye = NSBezierPath()
eye.move(to: eyeL)
eye.curve(to: eyeR,
          controlPoint1: NSPoint(x: O.x - ew * 0.35, y: O.y + eh * 1.7),
          controlPoint2: NSPoint(x: O.x + ew * 0.35, y: O.y + eh * 1.7))
eye.curve(to: eyeL,
          controlPoint1: NSPoint(x: O.x + ew * 0.35, y: O.y - eh * 1.7),
          controlPoint2: NSPoint(x: O.x - ew * 0.35, y: O.y - eh * 1.7))
eye.close()
darkEye.setFill(); eye.fill()
orange.setStroke(); eye.lineWidth = 22; eye.stroke()
disc(O, 36, orange)
disc(O, 13, darkEye)
disc(NSPoint(x: O.x, y: O.y - 168), 30, orange)
NSGraphicsContext.restoreGraphicsState()

// --- Вордмарк netKillUI ---
func font(_ size: CGFloat, bold: Bool) -> NSFont {
    let name = bold ? "Menlo-Bold" : "Menlo-Regular"
    return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
}

let markFont = font(104, bold: true)
var x: CGFloat = 430
let markY: CGFloat = 180
func drawWord(_ s: String, _ color: NSColor) {
    let attr: [NSAttributedString.Key: Any] = [.font: markFont, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attr)
    str.draw(at: NSPoint(x: x, y: markY))
    x += str.size().width
}
drawWord("net", fg)
drawWord("Kill", orange)
drawWord("UI", fg)

// Мигающий курсор-акцент после вордмарка.
orange.setFill()
NSBezierPath(rect: NSRect(x: x + 12, y: markY + 6, width: 34, height: 96)).fill()

// --- Таглайн ---
let tagFont = font(31, bold: false)
let tag = NSAttributedString(string: "Native macOS ARP-spoofing toolkit · SwiftUI",
                             attributes: [.font: tagFont, .foregroundColor: dim])
tag.draw(at: NSPoint(x: 434, y: 118))

// Вторая строка таглайна — ключевые фичи.
let tag2 = NSAttributedString(string: "cut · ninja stealth · MAC-mask · spoof detection",
                              attributes: [.font: font(24, bold: false), .foregroundColor: orange.withAlphaComponent(0.85)])
tag2.draw(at: NSPoint(x: 434, y: 78))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("баннер: \(outPath)")
} catch {
    FileHandle.standardError.write(Data("ошибка записи баннера: \(error)\n".utf8))
    exit(1)
}
