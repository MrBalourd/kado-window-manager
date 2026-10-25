import AppKit
import Foundation

let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let iconset = project.appendingPathComponent("Resources/Kado.iconset", isDirectory: true)
let fileManager = FileManager.default

if fileManager.fileExists(atPath: iconset.path) {
    try fileManager.removeItem(at: iconset)
}
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func render(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "KadoIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap."])
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.setShouldAntialias(true)
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let unit = CGFloat(size)
    let background = NSBezierPath(
        roundedRect: CGRect(x: unit * 0.035, y: unit * 0.035, width: unit * 0.93, height: unit * 0.93),
        xRadius: unit * 0.22,
        yRadius: unit * 0.22
    )
    NSGradient(colors: [color(0xf4f0e7), color(0xe0d8c8)])!.draw(in: background, angle: 90)
    color(0xffffff, alpha: 0.60).setStroke()
    background.lineWidth = max(1, unit * 0.009)
    background.stroke()

    let panels: [(CGRect, UInt32)] = [
        (CGRect(x: unit * 0.225, y: unit * 0.205, width: unit * 0.235, height: unit * 0.59), 0x222b38),
        (CGRect(x: unit * 0.535, y: unit * 0.515, width: unit * 0.24, height: unit * 0.28), 0x2583ff),
        (CGRect(x: unit * 0.535, y: unit * 0.205, width: unit * 0.24, height: unit * 0.28), 0x687687)
    ]

    for (rect, fill) in panels {
        let panel = NSBezierPath(roundedRect: rect, xRadius: unit * 0.065, yRadius: unit * 0.065)
        let shadow = NSShadow()
        shadow.shadowColor = color(0x101722, alpha: 0.22)
        shadow.shadowBlurRadius = unit * 0.018
        shadow.shadowOffset = NSSize(width: 0, height: -unit * 0.012)
        shadow.set()
        color(fill).setFill()
        panel.fill()
        NSShadow().set()
        color(0xffffff, alpha: 0.16).setStroke()
        panel.lineWidth = max(1, unit * 0.006)
        panel.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KadoIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG."])
    }
    return data
}

for (name, size) in outputs {
    let url = iconset.appendingPathComponent(name)
    try render(size: size).write(to: url, options: .atomic)
}
