// Renders docs/img/banner.png (README hero): swift app/make-banner.swift
import AppKit

let W = 1600, H = 560
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let full = NSRect(x: 0, y: 0, width: W, height: H)

// Background: deep warm gradient.
NSGradient(colors: [NSColor(red: 0.10, green: 0.08, blue: 0.09, alpha: 1),
                    NSColor(red: 0.24, green: 0.11, blue: 0.08, alpha: 1)])!.draw(in: full, angle: -20)

// App icon from the bundle source.
if let icon = NSImage(contentsOfFile: "app/AppIcon.icns") {
    icon.draw(in: NSRect(x: 110, y: (H - 300) / 2, width: 300, height: 300))
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: NSPoint) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let orange = NSColor(red: 0.98, green: 0.60, blue: 0.38, alpha: 1)
text("AutoApprove", 92, .bold, .white, at: NSPoint(x: 470, y: 300))
text("Hands-free approvals for Claude Code desktop on macOS", 34, .regular,
     NSColor.white.withAlphaComponent(0.82), at: NSPoint(x: 474, y: 245))

// Feature chips.
var x: CGFloat = 474
for chip in ["Permission hook", "Accessibility clicker", "Menu bar toggle", "Fails closed"] {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: orange]
    let sz = (chip as NSString).size(withAttributes: attrs)
    let r = NSRect(x: x, y: 150, width: sz.width + 36, height: 50)
    orange.withAlphaComponent(0.14).setFill(); NSBezierPath(roundedRect: r, xRadius: 25, yRadius: 25).fill()
    orange.withAlphaComponent(0.55).setStroke(); let b = NSBezierPath(roundedRect: r, xRadius: 25, yRadius: 25); b.lineWidth = 2; b.stroke()
    (chip as NSString).draw(at: NSPoint(x: x + 18, y: 162), withAttributes: attrs)
    x += r.width + 18
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/img/banner.png"))
print("docs/img/banner.png written")
