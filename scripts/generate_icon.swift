import Foundation
import AppKit

let masterSize = 1024
let image = NSImage(size: NSSize(width: masterSize, height: masterSize))

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Failed to obtain CGContext")
}

// 1. Dark Rounded Squircle Background with Deep Purple/Blue Gradient
let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
let outerPath = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: NSColor.black.withAlphaComponent(0.65).cgColor)
NSColor(red: 0.07, green: 0.08, blue: 0.14, alpha: 1.0).setFill()
outerPath.fill()
ctx.restoreGState()

// Inner Gradient Surface
let bgGradient = NSGradient(
    colors: [
        NSColor(red: 0.16, green: 0.14, blue: 0.28, alpha: 1.0),
        NSColor(red: 0.08, green: 0.07, blue: 0.16, alpha: 1.0)
    ]
)
bgGradient?.draw(in: outerPath, angle: -45)

// Outer Border Glow
let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 197, yRadius: 197)
NSColor(red: 0.5, green: 0.4, blue: 0.95, alpha: 0.35).setStroke()
borderPath.lineWidth = 6
borderPath.stroke()

// 2. Glowing Ambient Audio Wave Circles
ctx.saveGState()
let center = CGPoint(x: 512, y: 560)
for radius: CGFloat in [220, 290, 360] {
    let circlePath = NSBezierPath()
    circlePath.appendArc(withCenter: center, radius: radius, startAngle: 15, endAngle: 165)
    NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: (380 - radius) / 1000.0).setStroke()
    circlePath.lineWidth = 10
    circlePath.lineCapStyle = .round
    circlePath.stroke()
}
ctx.restoreGState()

// 3. Central Microphone Capsule Body
let micWidth: CGFloat = 160
let micHeight: CGFloat = 280
let micX = center.x - (micWidth / 2)
let micY = center.y - (micHeight / 2) + 20
let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
let micPath = NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.5).cgColor)
let micGradient = NSGradient(
    colors: [
        NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1.0)
    ]
)
micGradient?.draw(in: micPath, angle: -60)
ctx.restoreGState()

// 4. Microphone Grille Lines
ctx.saveGState()
NSColor.white.withAlphaComponent(0.25).setStroke()
for yOffset: CGFloat in [-40, -10, 20, 50, 80] {
    let line = NSBezierPath()
    line.move(to: CGPoint(x: micX + 24, y: center.y + yOffset))
    line.line(to: CGPoint(x: micX + micWidth - 24, y: center.y + yOffset))
    line.lineWidth = 4
    line.lineCapStyle = .round
    line.stroke()
}
ctx.restoreGState()

// 5. Microphone Cradle / Arc
let cradleRadius: CGFloat = 120
let cradlePath = NSBezierPath()
cradlePath.appendArc(withCenter: CGPoint(x: center.x, y: micY + 80), radius: cradleRadius, startAngle: 180, endAngle: 0, clockwise: true)
NSColor.white.withAlphaComponent(0.85).setStroke()
cradlePath.lineWidth = 14
cradlePath.lineCapStyle = .round
cradlePath.stroke()

// 6. Microphone Stand Neck & Base
let stemPath = NSBezierPath()
stemPath.move(to: CGPoint(x: center.x, y: micY + 80 - cradleRadius))
stemPath.line(to: CGPoint(x: center.x, y: 230))
NSColor.white.withAlphaComponent(0.85).setStroke()
stemPath.lineWidth = 14
stemPath.lineCapStyle = .round
stemPath.stroke()

let basePath = NSBezierPath()
basePath.move(to: CGPoint(x: center.x - 90, y: 230))
basePath.line(to: CGPoint(x: center.x + 90, y: 230))
NSColor.white.withAlphaComponent(0.85).setStroke()
basePath.lineWidth = 16
basePath.lineCapStyle = .round
basePath.stroke()

image.unlockFocus()

// Save PNG & ICNS
let fileManager = FileManager.default
let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let projectDir = (scriptDir as NSString).deletingLastPathComponent
let resourcesDir = (projectDir as NSString).appendingPathComponent("Resources")
let iconsetDir = (projectDir as NSString).appendingPathComponent("HardyFlow.iconset")

try? fileManager.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true, attributes: nil)
try? fileManager.removeItem(atPath: iconsetDir)
try? fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert image to PNG")
}

let logoPath = (resourcesDir as NSString).appendingPathComponent("app_logo.png")
try? pngData.write(to: URL(fileURLWithPath: logoPath))

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let resized = NSImage(size: NSSize(width: s, height: s))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: NSRect(x: 0, y: 0, width: masterSize, height: masterSize), operation: .copy, fraction: 1.0)
    resized.unlockFocus()
    
    if let data = resized.tiffRepresentation,
       let rep = NSBitmapImageRep(data: data),
       let pData = rep.representation(using: .png, properties: [:]) {
        let path1x = (iconsetDir as NSString).appendingPathComponent("icon_\(s)x\(s).png")
        try? pData.write(to: URL(fileURLWithPath: path1x))
        if s <= 512 {
            let path2x = (iconsetDir as NSString).appendingPathComponent("icon_\(s/2)x\(s/2)@2x.png")
            try? pData.write(to: URL(fileURLWithPath: path2x))
        }
    }
}

let icnsPath = (resourcesDir as NSString).appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try? process.run()
process.waitUntilExit()

try? fileManager.removeItem(atPath: iconsetDir)
print("✅ [generate_icon] AppIcon.icns successfully created at \(icnsPath)")
