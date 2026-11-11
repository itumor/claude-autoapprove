// Renders promo images into docs/promo/: swift app/make-promo.swift
//   social-preview.png 1280x640   (GitHub Settings > Social preview)
//   before-after.png   1600x900
//   how-it-works.png   1600x900
//   safety.png         1080x1080
//   auto-run.png       1600x900   (auto-run of "Run in terminal" blocks)
//   whats-new.png      1080x1080
import AppKit

// MARK: palette + helpers (top-left coordinates)

let bg0 = NSColor(red: 0.10, green: 0.08, blue: 0.09, alpha: 1)
let bg1 = NSColor(red: 0.24, green: 0.11, blue: 0.08, alpha: 1)
let orange = NSColor(red: 0.98, green: 0.60, blue: 0.38, alpha: 1)
let deep = NSColor(red: 0.80, green: 0.30, blue: 0.20, alpha: 1)
let green = NSColor(red: 0.36, green: 0.82, blue: 0.52, alpha: 1)
let red = NSColor(red: 0.95, green: 0.40, blue: 0.38, alpha: 1)
let white = NSColor.white
func dim(_ a: CGFloat) -> NSColor { white.withAlphaComponent(a) }

var H: CGFloat = 0
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H - y - h, width: w, height: h) }

func canvas(_ w: Int, _ h: Int, _ out: String, _ draw: () -> Void) {
    H = CGFloat(h)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [bg0, bg1])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -20)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/promo/\(out)"))
    print("docs/promo/\(out)")
}

@discardableResult
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = white, mono: Bool = false, width: CGFloat? = nil) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let w = width ?? 10_000
    let h = (s as NSString).boundingRect(with: NSSize(width: w, height: 10_000), options: [.usesLineFragmentOrigin], attributes: attrs).height
    (s as NSString).draw(with: R(x, y, w, h), options: [.usesLineFragmentOrigin], attributes: attrs)
    return h
}

func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
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

let icon = NSImage(contentsOfFile: "app/AppIcon.icns")!
func appIcon(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) { icon.draw(in: R(x, y, s, s)) }

func chip(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 22, color: NSColor = orange) -> CGFloat {
    let w = textWidth(s, size: size, weight: .semibold) + size * 1.4
    let h = size * 2
    box(R(x, y, w, h), radius: h / 2, fill: color.withAlphaComponent(0.14), stroke: color.withAlphaComponent(0.55))
    text(s, x + size * 0.7, y + size * 0.42, size: size, weight: .semibold, color: color)
    return w
}

func arrow(from a: NSPoint, to b: NSPoint, color: NSColor = dim(0.55)) {
    let pa = NSPoint(x: a.x, y: H - a.y), pb = NSPoint(x: b.x, y: H - b.y)
    let p = NSBezierPath(); p.move(to: pa); p.line(to: pb); p.lineWidth = 4; color.setStroke(); p.stroke()
    let ang = atan2(pb.y - pa.y, pb.x - pa.x), l: CGFloat = 18
    let head = NSBezierPath()
    head.move(to: pb)
    head.line(to: NSPoint(x: pb.x - l * cos(ang - .pi / 7), y: pb.y - l * sin(ang - .pi / 7)))
    head.line(to: NSPoint(x: pb.x - l * cos(ang + .pi / 7), y: pb.y - l * sin(ang + .pi / 7)))
    head.close(); color.setFill(); head.fill()
}

let unofficial = "Unofficial · not affiliated with Anthropic · MIT"
let repoURL = "github.com/itumor/claude-autoapprove"

try? FileManager.default.createDirectory(atPath: "docs/promo", withIntermediateDirectories: true)

// MARK: I2 social preview 1280x640

canvas(1280, 640, "social-preview.png") {
    appIcon(90, 170, 260)
    text("AutoApprove", 400, 170, size: 84, weight: .bold)
    text("Stop babysitting Claude Code prompts.", 404, 282, size: 34, color: dim(0.85))
    text("One toggle in your menu bar. Fails closed.", 404, 328, size: 34, color: orange)
    var x: CGFloat = 404
    for c in ["macOS", "Claude Code desktop", "Open source"] { x += chip(c, x, 400) + 14 }
    text(repoURL, 90, 560, size: 24, weight: .medium, color: dim(0.7))
    text(unofficial, 1190 - textWidth(unofficial, size: 18), 566, size: 18, color: dim(0.45))
}

// MARK: I3 before / after 1600x900

// Compact prompt card (generic, not a copy of any real UI): title + command left, buttons right.
func promptCard(_ x: CGFloat, _ y: CGFloat, _ cmd: String, _ alpha: CGFloat) {
    box(R(x, y, 620, 96), radius: 18, fill: NSColor(white: 0.16, alpha: 0.4 + 0.6 * alpha), stroke: dim(0.18 * alpha))
    text("Allow this command?", x + 26, y + 16, size: 21, weight: .semibold, color: dim(0.9 * alpha))
    text(cmd, x + 26, y + 50, size: 20, color: orange.withAlphaComponent(alpha), mono: true)
    box(R(x + 418, y + 30, 84, 36), radius: 9, fill: dim(0.10 * alpha))
    text("Deny", x + 438, y + 37, size: 18, color: dim(0.7 * alpha))
    box(R(x + 514, y + 30, 84, 36), radius: 9, fill: deep.withAlphaComponent(alpha))
    text("Allow", x + 534, y + 37, size: 18, weight: .semibold, color: white.withAlphaComponent(alpha))
}

canvas(1600, 900, "before-after.png") {
    // Divider
    box(R(799, 60, 2, 780), radius: 1, fill: dim(0.12))

    // Before
    text("WITHOUT", 90, 70, size: 22, weight: .bold, color: red)
    text("You click Allow. Again.", 90, 104, size: 44, weight: .bold)
    let cmds = ["npm test", "git add -A", "sed -i '' 's/v1/v2/' x", "python3 build.py", "rm -rf build/"]
    for (i, c) in cmds.enumerated() {
        let a = 0.45 + CGFloat(i) * 0.1375  // older prompts fade, newest is brightest
        promptCard(90, 190 + CGFloat(i) * 112, c, a)
    }
    symbol("hand.tap.fill", 650, 676, size: 44, colors: [red])
    text("47 prompts this afternoon", 90, 790, size: 28, weight: .semibold, color: red)

    // After
    text("WITH AUTOAPPROVE", 880, 70, size: 22, weight: .bold, color: green)
    text("Claude keeps working.", 880, 104, size: 44, weight: .bold)
    box(R(880, 190, 630, 470), radius: 22, fill: NSColor(white: 0.07, alpha: 0.9), stroke: dim(0.14))
    text("decisions.jsonl", 908, 210, size: 20, weight: .semibold, color: dim(0.55), mono: true)
    let rows: [(String, String, String)] = [("16:39:27", "hook", "Bash  npm test"), ("16:39:29", "hook", "Bash  git add -A"),
                                            ("16:39:31", "hook", "Edit  src/app.ts"), ("16:39:34", "hook", "Bash  python3 build.py"),
                                            ("16:39:40", "hook", "MCP   jira.search"), ("16:48:55", "click", "Accept  plan approval")]
    for (i, r) in rows.enumerated() {
        let y = 262 + CGFloat(i) * 62
        symbol("checkmark.circle.fill", 908, y - 2, size: 26, colors: [.black, green])
        text(r.0, 952, y, size: 22, color: dim(0.5), mono: true)
        text(r.1, 1080, y, size: 22, weight: .semibold, color: r.1 == "click" ? orange : green, mono: true)
        text(r.2, 1170, y, size: 22, color: dim(0.9), mono: true)
    }
    appIcon(880, 700, 90)
    text("Auto-approve ON", 990, 712, size: 30, weight: .bold)
    text("0 clicks. Every decision logged.", 990, 752, size: 24, color: green)
    text(unofficial, 1510 - textWidth(unofficial, size: 16), 850, size: 16, color: dim(0.4))
}

// MARK: I4 how it works 1600x900

func node(_ r: NSRect, _ title: String, _ sub: String, color: NSColor, sym: String, layered: Bool = false) {
    box(r, radius: 22, fill: color.withAlphaComponent(0.12), stroke: color.withAlphaComponent(0.6), line: 3)
    let top = H - r.maxY
    // Two-layer symbols take [inner glyph, fill]; single-layer ones use the first color.
    symbol(sym, r.minX + 26, top + 26, size: 34, colors: layered ? [bg0, color] : [color])
    text(title, r.minX + 82, top + 24, size: 28, weight: .bold)
    text(sub, r.minX + 26, top + 80, size: 21, color: dim(0.75), width: r.width - 52)
}

canvas(1600, 900, "how-it-works.png") {
    text("How AutoApprove works", 90, 60, size: 52, weight: .bold)
    text("Two approval paths, one toggle, one log.", 92, 128, size: 28, color: dim(0.7))

    node(R(90, 330, 360, 230), "Claude Code", "wants to run a tool or shows a plan / button", color: dim(0.9), sym: "terminal.fill")

    node(R(600, 220, 420, 200), "Hook", "Tool prompts: Bash, Edit, MCP, WebFetch. Native PermissionRequest hook.", color: orange, sym: "link")
    node(R(600, 480, 420, 200), "Clicker", "Plan approval and other buttons. Accessibility API, Claude's UI only.", color: orange, sym: "cursorarrow.click.2")

    node(R(1170, 220, 340, 200), "Allowed", "Hook returns allow. No prompt shown.", color: green, sym: "checkmark.seal.fill", layered: true)
    node(R(1170, 480, 340, 200), "Pressed", "Exact label match, e.g. \"Accept\".", color: green, sym: "checkmark.seal.fill", layered: true)

    arrow(from: NSPoint(x: 450, y: 410), to: NSPoint(x: 592, y: 320))
    arrow(from: NSPoint(x: 450, y: 480), to: NSPoint(x: 592, y: 580))
    arrow(from: NSPoint(x: 1020, y: 320), to: NSPoint(x: 1162, y: 320))
    arrow(from: NSPoint(x: 1020, y: 580), to: NSPoint(x: 1162, y: 580))

    box(R(90, 740, 1420, 90), radius: 18, fill: red.withAlphaComponent(0.10), stroke: red.withAlphaComponent(0.5))
    symbol("power.circle.fill", 118, 762, size: 40, colors: [white, red])
    text("Toggle OFF, app quit or crashed → no heartbeat → every prompt comes back to you.", 180, 768, size: 27, weight: .semibold)
}

// MARK: I5 safety card 1080x1080

canvas(1080, 1080, "safety.png") {
    appIcon(90, 90, 130)
    text("Built to fail safe", 250, 104, size: 60, weight: .bold)
    text("Approves only while you say so.", 254, 180, size: 28, color: orange)
    let items: [(String, String, String)] = [
        ("power.circle.fill", "Fails closed", "Hook needs a heartbeat under 10 s. App gone means prompts are back."),
        ("lock.shield.fill", "Claude's own UI only", "Clicker ignores the browser pane, embedded pages and other origins."),
        ("text.magnifyingglass", "Exact labels", "Presses listed buttons only. Never Deny or Cancel."),
        ("list.bullet.rectangle.portrait.fill", "Every decision logged", "decisions.jsonl: tool, input, time, allow or press."),
        ("questionmark.bubble.fill", "Questions stay yours", "When Claude asks you to choose, you choose."),
    ]
    for (i, it) in items.enumerated() {
        let y = 300 + CGFloat(i) * 136
        box(R(90, y, 900, 112), radius: 20, fill: dim(0.05), stroke: dim(0.12))
        symbol(it.0, 120, y + 30, size: 40, colors: [bg0, orange])
        text(it.1, 200, y + 18, size: 30, weight: .bold)
        text(it.2, 200, y + 60, size: 22, color: dim(0.72), width: 760)
    }
    text(repoURL, 90, 1000, size: 22, weight: .medium, color: dim(0.65))
}

// MARK: auto-run 1600x900

// Generic command block (not a copy of any real UI): lead-in line, code, a round Run button.
func commandBlock(_ y: CGFloat, _ lead: String, _ cmd: String, _ color: NSColor, _ verdict: String, _ why: String, sym: String) {
    text(lead, 90, y, size: 24, color: dim(0.8))
    box(R(90, y + 42, 820, 78), radius: 16, fill: NSColor(white: 0.07, alpha: 0.9), stroke: dim(0.14))
    text(cmd, 118, y + 67, size: 23, color: orange, mono: true)
    box(R(836, y + 57, 48, 48), radius: 24, fill: color.withAlphaComponent(0.18), stroke: color.withAlphaComponent(0.7))
    symbol("play.fill", 851, y + 69, size: 20, colors: [color])
    arrow(from: NSPoint(x: 930, y: y + 81), to: NSPoint(x: 1010, y: y + 81), color: color.withAlphaComponent(0.7))
    symbol(sym, 1030, y + 58, size: 40, colors: sym == "clock.fill" ? [color] : [bg0, color])
    text(verdict, 1096, y + 50, size: 28, weight: .bold, color: color)
    text(why, 1096, y + 88, size: 20, color: dim(0.7), width: 430)
}

canvas(1600, 900, "auto-run.png") {
    text("NEW", 90, 60, size: 22, weight: .bold, color: green)
    text("Auto-run terminal commands", 90, 92, size: 52, weight: .bold)
    text("Claude hands you a command to run. AutoApprove presses Run, and the output goes back to Claude.", 92, 162, size: 26, color: dim(0.7))

    commandBlock(250, "Run the tests and send me the output:", "npm test -- --watch=false", green,
                 "Pressed for you", "Written this turn, in the session you are watching. Run once.", sym: "checkmark.circle.fill")
    commandBlock(420, "Rollback, only if needed:", "kubectl rollout undo deploy/web", orange,
                 "Left for you", "Rollback, revert, undo, \"only if needed\": never auto-run.", sym: "hand.raised.circle.fill")
    commandBlock(590, "From yesterday, further up the chat:", "git push origin release", dim(0.6),
                 "Never touched", "History and other sessions are not run again.", sym: "clock.fill")

    box(R(90, 770, 1420, 70), radius: 18, fill: dim(0.05), stroke: dim(0.12))
    text("Off by default  ·  Waits until Claude stops  ·  One command at a time  ·  Every press logged", 118, 790, size: 25, weight: .semibold)
    text(unofficial, 1510 - textWidth(unofficial, size: 16), 856, size: 16, color: dim(0.4))
}

// MARK: what's new 1080x1080

canvas(1080, 1080, "whats-new.png") {
    appIcon(90, 90, 130)
    text("What's new", 250, 104, size: 60, weight: .bold)
    text("More hands-off, with more brakes.", 254, 180, size: 28, color: orange)
    let items: [(String, String, String)] = [
        ("play.circle.fill", "Auto-run terminal commands", "Presses Run on the command blocks Claude hands you. Opt-in."),
        ("arrow.uturn.backward.circle.fill", "Rollbacks stay yours", "Rollback, revert, undo and \"only if needed\" blocks are never run."),
        ("timer.circle.fill", "Timed ON", "Turn on for 15 minutes or 1 hour. It switches itself off."),
        ("exclamationmark.shield.fill", "Still ask me for risky commands", "Force push, push to main, rm -rf, sudo: back to you."),
        ("checklist", "Setup checklist", "The menu tells you what is missing: Accessibility, hook, Claude."),
    ]
    for (i, it) in items.enumerated() {
        let y = 300 + CGFloat(i) * 136
        box(R(90, y, 900, 112), radius: 20, fill: dim(0.05), stroke: dim(0.12))
        symbol(it.0, 120, y + 30, size: 40, colors: it.0 == "checklist" ? [orange] : [bg0, orange])
        text(it.1, 200, y + 18, size: 30, weight: .bold)
        text(it.2, 200, y + 60, size: 22, color: dim(0.72), width: 760)
    }
    text(repoURL, 90, 1000, size: 22, weight: .medium, color: dim(0.65))
    text(unofficial, 990 - textWidth(unofficial, size: 16), 1004, size: 16, color: dim(0.4))
}
