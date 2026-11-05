// Renders app/AppIcon.icns: swift app/make-icon.swift  (called by build.sh when icns missing)
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS squircle tile with 10% margin.
    let m = s * 0.1, tile = NSRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.30, alpha: 1),
                        NSColor(red: 0.80, green: 0.30, blue: 0.20, alpha: 1)])!.draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Subtle top highlight.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: path, angle: -90)

    // White shield + checkmark (SF Symbol), centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: tile.width * 0.52, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(red: 0.85, green: 0.35, blue: 0.22, alpha: 1), .white]))
    if let sym = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = sym.size
        sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("iconset written")
