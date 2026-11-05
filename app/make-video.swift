// Renders the animated scenes of the promo video as PNG frames:
//   swift app/make-video.swift            -> build/video/<scene>/0000.png ...
// tools/make-video.sh stitches them with ffmpeg; tools/make-audio.sh adds the sound.
import AppKit

let W: CGFloat = 1920, H: CGFloat = 1080, FPS = 30

let bg0 = NSColor(red: 0.10, green: 0.08, blue: 0.09, alpha: 1)
let bg1 = NSColor(red: 0.24, green: 0.11, blue: 0.08, alpha: 1)
let orange = NSColor(red: 0.98, green: 0.60, blue: 0.38, alpha: 1)
let deep = NSColor(red: 0.80, green: 0.30, blue: 0.20, alpha: 1)
let green = NSColor(red: 0.36, green: 0.82, blue: 0.52, alpha: 1)
let red = NSColor(red: 0.95, green: 0.40, blue: 0.38, alpha: 1)
func dim(_ a: CGFloat) -> NSColor { NSColor.white.withAlphaComponent(max(0, min(1, a))) }
let icon = NSImage(contentsOfFile: "app/AppIcon.icns")!

// MARK: helpers (top-left coordinates)

func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H - y - h, width: w, height: h) }
func clamp(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
/// 0..1 progress of t inside [a, b], eased out.
func ease(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { let p = clamp((t - a) / (b - a)); return 1 - pow(1 - p, 3) }

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .white, mono: Bool = false, center: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let sz = (s as NSString).size(withAttributes: attrs)
    let px = center ? x - sz.width / 2 : x
    (s as NSString).draw(at: NSPoint(x: px, y: H - y - sz.height), withAttributes: attrs)
}

func box(_ r: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, line: CGFloat = 2) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    fill.setFill(); p.fill()
    if let stroke { stroke.setStroke(); p.lineWidth = line; p.stroke() }
}

func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, colors: [NSColor]) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold).applying(.init(paletteColors: colors))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    img.draw(in: R(x, y, img.size.width, img.size.height))
}

func background() {
    NSGradient(colors: [bg0, bg1])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -20)
}

func promptCard(_ x: CGFloat, _ y: CGFloat, _ cmd: String, _ a: CGFloat) {
    box(R(x, y, 720, 110), radius: 20, fill: NSColor(white: 0.16, alpha: a), stroke: dim(0.2 * a))
    text("Allow this command?", x + 30, y + 18, size: 25, weight: .semibold, color: dim(0.92 * a))
    text(cmd, x + 30, y + 58, size: 24, color: orange.withAlphaComponent(a), mono: true)
    box(R(x + 490, y + 34, 96, 42), radius: 10, fill: dim(0.10 * a))
    text("Deny", x + 514, y + 42, size: 21, color: dim(0.7 * a))
    box(R(x + 600, y + 34, 96, 42), radius: 10, fill: deep.withAlphaComponent(a))
    text("Allow", x + 620, y + 42, size: 21, weight: .semibold, color: NSColor.white.withAlphaComponent(a))
}

func render(_ scene: String, seconds: CGFloat, _ draw: (CGFloat) -> Void) {
    let dir = "build/video/\(scene)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let n = Int(seconds * CGFloat(FPS))
    for f in 0..<n {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background()
        draw(CGFloat(f) / CGFloat(FPS))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/%04d.png", dir, f)))
    }
    print("\(scene): \(n) frames")
}

let only = CommandLine.arguments.dropFirst().first  // optional: render one scene

// MARK: 1 — the problem (4.5 s)

if only == nil || only == "s1" {
    render("s1", seconds: 4.5) { t in
        text("You came to build.", W / 2, 90, size: 64, weight: .bold, color: dim(ease(t, 0, 0.6)), center: true)
        let cmds = ["npm test", "git add -A", "python3 build.py", "sed -i '' 's/v1/v2/' app.ts", "rm -rf build/"]
        for (i, c) in cmds.enumerated() {
            let start = 0.5 + CGFloat(i) * 0.45
            let p = ease(t, start, start + 0.35)
            guard p > 0 else { continue }
            promptCard(600, 230 + CGFloat(i) * 128 - (1 - p) * 40, c, p * (0.55 + 0.45 * CGFloat(i) / 4))
        }
        let n = min(47, Int(max(0, t - 0.5) * 16))
        if n > 0 {
            text("\(n)", 1500, 470, size: 150, weight: .heavy, color: red.withAlphaComponent(ease(t, 0.5, 0.9)), center: true)
            text("prompts", 1500, 650, size: 40, weight: .semibold, color: dim(0.75 * ease(t, 0.5, 0.9)), center: true)
        }
        if t > 3.3 { text("Not to click Allow.", W / 2, 920, size: 56, weight: .bold, color: orange.withAlphaComponent(ease(t, 3.3, 3.8)), center: true) }
    }
}

// MARK: 2 — logo reveal (3.5 s)

if only == nil || only == "s2" {
    render("s2", seconds: 3.5) { t in
        let p = ease(t, 0, 0.9)
        let s = 260 * (0.7 + 0.3 * p)
        icon.draw(in: R(W / 2 - s / 2, 260 + (260 - s) / 2, s, s), from: .zero, operation: .sourceOver, fraction: p)
        text("AutoApprove", W / 2, 580 + (1 - ease(t, 0.5, 1.3)) * 30, size: 110, weight: .bold, color: dim(ease(t, 0.5, 1.3)), center: true)
        text("Hands-free approvals for Claude Code desktop on macOS", W / 2, 730, size: 40,
             color: dim(0.85 * ease(t, 1.1, 1.9)), center: true)
    }
}

// MARK: 3 — one toggle (4.5 s): menu bar mock -> menu -> ON

if only == nil || only == "s3" {
    render("s3", seconds: 4.5) { t in
        text("One toggle in your menu bar.", W / 2, 820, size: 64, weight: .bold, color: dim(ease(t, 0.2, 0.8)), center: true)
        // Menu bar strip (generic).
        box(R(360, 120, 1200, 64), radius: 16, fill: NSColor(white: 0.12, alpha: 0.95), stroke: dim(0.12))
        symbol("wifi", 1300, 138, size: 26, colors: [dim(0.8)])
        symbol("battery.75percent", 1350, 140, size: 26, colors: [dim(0.8)])
        text("9:41", 1430, 136, size: 26, weight: .semibold, color: dim(0.85))
        let on = t > 2.4
        // Shield icon state.
        symbol(on ? "checkmark.shield.fill" : "shield.slash", 1232, 135, size: 28, colors: on ? [bg0, green] : [dim(0.8)])
        // Click highlight + menu.
        if t > 1.0 {
            let m = ease(t, 1.0, 1.3)
            box(R(1222, 126, 50, 52), radius: 10, fill: dim(0.12 * m))
            let r = R(1050, 200, 420, 300 * m)
            box(r, radius: 16, fill: NSColor(white: 0.17, alpha: 0.97 * m), stroke: dim(0.15 * m))
            if m > 0.9 {
                let rows: [(String, Bool)] = [("Auto-approve", on), ("Hook (tool prompts)", true), ("Clicker (app buttons)", true)]
                for (i, row) in rows.enumerated() {
                    let y = 228 + CGFloat(i) * 62
                    text(row.0, 1080, y, size: 27, weight: i == 0 ? .bold : .regular, color: dim(0.92))
                    // toggle
                    let tr = R(1370, y - 2, 66, 38)
                    box(tr, radius: 19, fill: row.1 ? green : dim(0.25))
                    let knobX: CGFloat = row.1 ? 1402 : 1374
                    box(R(knobX, y + 2, 30, 30), radius: 15, fill: .white)
                }
                text("Recent decisions · Open log · Quit", 1080, 430, size: 21, color: dim(0.5))
            }
        }
        // Cursor.
        let cp = ease(t, 0.2, 0.95)
        let cx = 900 + (1250 - 900) * cp, cy = 520 + (160 - 520) * cp
        let cx2 = t > 1.9 ? 1250 + (1400 - 1250) * ease(t, 1.9, 2.3) : cx
        let cy2 = t > 1.9 ? 160 + (248 - 160) * ease(t, 1.9, 2.3) : cy
        symbol("cursorarrow", cx2, cy2, size: 40, colors: [.white])
    }
}

// MARK: 4 — the tool at work (16 s): a session on the left, the AutoApprove menu on the right.
// Steps and log lines are the real ones from a recorded run (decisions.jsonl, --log-path task).

if only == nil || only == "s4" {
    let card = NSColor(white: 0.13, alpha: 0.96), panel = NSColor(white: 0.17, alpha: 0.97)
    let tAccept: CGFloat = 3.0
    // (appear time, tool, detail, log line)
    let steps: [(CGFloat, String, String, String)] = [
        (3.9, "Edit", "hook/autoapprove.py", "20:32:28  hook   allow    Edit"),
        (5.0, "Bash", "python3 hook/autoapprove.py --log-path", "20:32:31  hook   allow    Bash"),
        (5.8, "Bash", "python3 hook/autoapprove.py --selftest", "20:32:33  hook   allow    Bash"),
        (6.9, "Bash", "git commit -m \"Add --log-path flag\"", "20:32:36  hook   allow    Bash"),
    ]
    render("s4", seconds: 16) { t in
        text("Watch it work", W / 2, 40, size: 52, weight: .bold, color: dim(ease(t, 0, 0.5)), center: true)
        text("Plan accepted by the clicker · tool prompts allowed by the hook", W / 2, 110, size: 28,
             color: orange.withAlphaComponent(ease(t, 0.2, 0.7)), center: true)

        // Left: a Claude Code session (generic look).
        box(R(110, 180, 1060, 840), radius: 22, fill: card, stroke: dim(0.12))
        for (i, c) in [red, orange, green].enumerated() { box(R(140 + CGFloat(i) * 30, 204, 16, 16), radius: 8, fill: c.withAlphaComponent(0.8)) }
        text("Claude Code · demo session", 250, 198, size: 22, color: dim(0.55))
        var y: CGFloat = 260
        let a0 = ease(t, 0.3, 0.7)
        box(R(560, y, 570, 64), radius: 16, fill: deep.withAlphaComponent(0.35 * a0))
        text("Add a --log-path flag to the hook", 585, y + 17, size: 25, color: dim(0.95 * a0))
        y += 96
        // Plan card -> accepted.
        let ap = ease(t, 1.2, 1.7)
        if ap > 0 {
            let accepted = t >= tAccept
            let h: CGFloat = accepted ? 70 : 250
            box(R(150, y + (1 - ap) * 20, 980, h), radius: 16, fill: NSColor(white: 0.2, alpha: ap), stroke: (accepted ? green : orange).withAlphaComponent(0.6 * ap))
            if accepted {
                symbol("checkmark.circle.fill", 175, y + 20, size: 28, colors: [NSColor(white: 0.19, alpha: 1), green])
                text("Plan accepted  ·  pressed by AutoApprove", 220, y + 20, size: 26, weight: .semibold, color: green)
            } else {
                text("Plan: --log-path flag", 180, y + 22, size: 30, weight: .bold, color: dim(ap))
                for (i, b) in ["Add --log-path: print the decisions log path, exit 0", "Run --log-path and --selftest", "Commit on the branch"].enumerated() {
                    text("•  " + b, 190, y + 76 + CGFloat(i) * 40, size: 23, color: dim(0.8 * ap))
                }
                box(R(820, y + 190, 130, 44), radius: 10, fill: dim(0.1 * ap))
                text("Reject", 852, y + 198, size: 22, color: dim(0.7 * ap))
                // Accept button with a press pulse just before tAccept.
                let press = ease(t, tAccept - 0.35, tAccept)
                box(R(965, y + 190, 140, 44), radius: 10, fill: deep.blended(withFraction: press, of: green)!.withAlphaComponent(ap))
                text("Accept", 998, y + 198, size: 22, weight: .semibold, color: NSColor.white.withAlphaComponent(ap))
                if press > 0 { box(R(965 - 10 * press, y + 190 - 10 * press, 140 + 20 * press, 44 + 20 * press), radius: 14, fill: .clear, stroke: green.withAlphaComponent(1 - press), line: 4) }
            }
            y += h + 26
        }
        // Tool prompts: shown as "Allow?" for 0.3 s, then approved.
        for s in steps where t >= s.0 {
            let p = ease(t, s.0, s.0 + 0.25), ok = t >= s.0 + 0.3
            box(R(150, y + (1 - p) * 16, 980, 78), radius: 14, fill: NSColor(white: 0.19, alpha: p), stroke: (ok ? green : orange).withAlphaComponent(0.45 * p))
            text(s.1, 175, y + 12, size: 22, weight: .bold, color: (s.1 == "Edit" ? orange : NSColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)).withAlphaComponent(p))
            text(s.2, 175, y + 42, size: 21, color: dim(0.85 * p), mono: true)
            if ok {
                symbol("checkmark.circle.fill", 960, y + 22, size: 26, colors: [NSColor(white: 0.19, alpha: 1), green])
                text("Allowed", 1000, y + 24, size: 23, weight: .semibold, color: green)
            } else {
                box(R(990, y + 18, 110, 42), radius: 10, fill: deep.withAlphaComponent(p))
                text("Allow", 1018, y + 26, size: 21, weight: .semibold, color: NSColor.white.withAlphaComponent(p))
            }
            y += 96
        }
        if t >= 8.6 {
            let p = ease(t, 8.6, 9.0)
            text("✓ Committed 124b8fd · selftest ok", 175, y + 6, size: 26, weight: .semibold, color: green.withAlphaComponent(p))
        }

        // Right: the AutoApprove menu, live.
        let mp = ease(t, 0.4, 0.9)
        box(R(1230, 180, 580, 840), radius: 22, fill: panel.withAlphaComponent(mp), stroke: dim(0.15 * mp))
        icon.draw(in: R(1260, 206, 56, 56), from: .zero, operation: .sourceOver, fraction: mp)
        text("AutoApprove", 1332, 214, size: 34, weight: .bold, color: dim(mp))
        for (i, row) in ["Auto-approve", "Hook (tool prompts)", "Clicker (app buttons)"].enumerated() {
            let ry = 300 + CGFloat(i) * 62
            text(row, 1265, ry, size: 26, weight: i == 0 ? .bold : .regular, color: dim(0.92 * mp))
            box(R(1700, ry - 2, 66, 38), radius: 19, fill: green.withAlphaComponent(mp))
            box(R(1732, ry + 2, 30, 30), radius: 15, fill: NSColor.white.withAlphaComponent(mp))
        }
        box(R(1260, 494, 520, 2), radius: 1, fill: dim(0.12 * mp))
        text("Recent", 1265, 512, size: 22, weight: .semibold, color: dim(0.55 * mp))
        var log: [String] = []
        if t >= tAccept { log.append("20:32:25  click  pressed  Accept") }
        for s in steps where t >= s.0 + 0.3 { log.append(s.3) }
        for (i, l) in log.reversed().enumerated() {  // newest first, like the app
            let fresh = i == 0 ? ease(t, t - 0.01, t) : 1  // newest line highlighted
            let ly = 556 + CGFloat(i) * 46
            if i == 0 { box(R(1252, ly - 6, 536, 40), radius: 8, fill: green.withAlphaComponent(0.12 * fresh)) }
            text(l, 1265, ly, size: 21, color: l.contains("click") ? orange : dim(0.85), mono: true)
        }
        // Score.
        if t >= 9.3 {
            let p = ease(t, 9.3, 9.9)
            text("5 approvals · 11 seconds · clicks by you: 0", W / 2, 1036 - (1 - p) * 10, size: 30, weight: .bold,
                 color: orange.withAlphaComponent(p), center: true)
        }
    }
}

// MARK: 5 — fails closed (4.5 s)

if only == nil || only == "s5" {
    render("s5", seconds: 4.5) { t in
        text("It fails closed.", W / 2, 110, size: 72, weight: .bold, color: dim(ease(t, 0, 0.5)), center: true)
        // Heartbeat line drawn progressively; flatlines at 55%.
        let prog = ease(t, 0.3, 2.6)
        // Green while beating, red once flat.
        let live = NSBezierPath(), flat = NSBezierPath()
        live.lineWidth = 6; flat.lineWidth = 6
        let x0: CGFloat = 260, x1: CGFloat = 1660, mid: CGFloat = 470
        let flatAt: CGFloat = 0.55
        var x = x0
        while x <= x0 + (x1 - x0) * prog {
            let u = (x - x0) / (x1 - x0)
            var y = mid
            if u < flatAt {
                let k = (u * 9).truncatingRemainder(dividingBy: 1)
                if k > 0.40 && k < 0.47 { y = mid - 120 } else if k > 0.47 && k < 0.53 { y = mid + 70 }
            }
            let path = u < flatAt ? live : flat
            let p = NSPoint(x: x, y: H - y)
            if path.isEmpty { path.move(to: p) } else { path.line(to: p) }
            if u < flatAt && x + 4 > x0 + (x1 - x0) * flatAt { flat.move(to: p) }  // join the two segments
            x += 4
        }
        green.setStroke(); live.stroke()
        red.setStroke(); flat.stroke()
        if prog > flatAt {
            icon.draw(in: R(W / 2 - 60, 600, 120, 120), from: .zero, operation: .sourceOver, fraction: 0.35)
            text("App quit or crashed  →  no heartbeat  →  approvals stop", W / 2, 760, size: 38, weight: .semibold,
                 color: dim(ease(t, 1.7, 2.2)), center: true)
        }
        if t > 2.9 {
            let p = ease(t, 2.9, 3.4)
            promptCard(600, 850 - (1 - p) * 30, "git push --force", p)
        }
    }
}
