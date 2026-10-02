import AppKit

// Иконка приложения (1024×1024 PNG): тёмный squircle, внутри логотип —
// wifi-дуги с «глазом»-перехватчиком в центре и неоновым свечением.
// Переосмысление классического wifi-знака под MITM-инструмент.
// Использование: swift make-icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/nk-icon-1024.png"
let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let orange = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.0, alpha: 1.0)
let darkEye = NSColor(srgbRed: 0.03, green: 0.035, blue: 0.045, alpha: 1.0)

// --- Фон: тёмный градиентный squircle ---
let inset: CGFloat = 92
let bgRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
if let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1),
    NSColor(srgbRed: 0.015, green: 0.02, blue: 0.028, alpha: 1),
]) {
    grad.draw(in: squircle, angle: -90)
}

// Неоновое свечение для элементов логотипа
let glow = NSShadow()
glow.shadowColor = orange.withAlphaComponent(0.75)
glow.shadowBlurRadius = 30
glow.shadowOffset = .zero
glow.set()

func disc(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)).fill()
}

// --- WiFi-дуги, расходящиеся вверх от точки O ---
let O = NSPoint(x: size / 2, y: 452)
for radius in [CGFloat(150), 238, 326] {
    let p = NSBezierPath()
    p.appendArc(withCenter: O, radius: radius, startAngle: 42, endAngle: 138)
    p.lineWidth = 42
    p.lineCapStyle = .round
    orange.setStroke()
    p.stroke()
}

// --- Глаз-перехватчик в точке схода ---
let ew: CGFloat = 100   // полуширина
let eh: CGFloat = 62    // полувысота (управляет «раскрытием» века)
let eyeL = NSPoint(x: O.x - ew, y: O.y)
let eyeR = NSPoint(x: O.x + ew, y: O.y)
let eye = NSBezierPath()
eye.move(to: eyeL)
eye.curve(to: eyeR,
          controlPoint1: NSPoint(x: O.x - ew * 0.35, y: O.y + eh * 1.7),
          controlPoint2: NSPoint(x: O.x + ew * 0.35, y: O.y + eh * 1.7))
eye.curve(to: eyeL,
          controlPoint1: NSPoint(x: O.x + ew * 0.35, y: O.y - eh * 1.7),
          controlPoint2: NSPoint(x: O.x - ew * 0.35, y: O.y - eh * 1.7))
eye.close()
darkEye.setFill(); eye.fill()           // тёмная глазница
orange.setStroke(); eye.lineWidth = 22; eye.stroke()

// зрачок
disc(O, 36, orange)
disc(O, 13, darkEye)                     // блик-центр

// нижняя точка сигнала
disc(NSPoint(x: O.x, y: O.y - 168), 30, orange)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("иконка: \(outPath)")
} catch {
    FileHandle.standardError.write(Data("ошибка записи иконки: \(error)\n".utf8))
    exit(1)
}
