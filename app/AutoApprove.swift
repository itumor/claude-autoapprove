// AutoApprove: menu bar control for Claude Code desktop auto-approval.
// - Writes ~/.config/claude-autoapprove/state.json (read by hook/autoapprove.py).
// - Clicker: presses allow-listed buttons in Claude.app via the Accessibility API.
// Build: ./build.sh   Debug: AutoApprove.app/Contents/MacOS/AutoApprove --dump
import AppKit
import ApplicationServices
import SwiftUI

let claudeBundleID = "com.anthropic.claudefordesktop"
let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/claude-autoapprove")
let stateURL = dir.appendingPathComponent("state.json")
let logURL = dir.appendingPathComponent("decisions.jsonl")

let defaultButtons = ["Allow", "Allow once", "Always allow", "Approve", "Accept", "Yes, proceed", "Publish", "Continue"]
struct State: Codable, Equatable {
    var enabled = false
    var hook = true
    var clicker = true
    var buttons = defaultButtons
    var until: Double?            // epoch seconds; nil = on until turned off
    var askRisky = false          // off by default: approve everything, as before
    var askPatterns: [String]?    // nil = the hook's built-in defaults (see hook/autoapprove.py)

    init() {}
    // Every key optional, so an older state.json keeps its values (synthesized Codable
    // would fail on a missing key and loadState() would reset everything).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        hook = try c.decodeIfPresent(Bool.self, forKey: .hook) ?? hook
        clicker = try c.decodeIfPresent(Bool.self, forKey: .clicker) ?? clicker
        buttons = try c.decodeIfPresent([String].self, forKey: .buttons) ?? buttons
        until = try c.decodeIfPresent(Double.self, forKey: .until)
        askRisky = try c.decodeIfPresent(Bool.self, forKey: .askRisky) ?? askRisky
        askPatterns = try c.decodeIfPresent([String].self, forKey: .askPatterns)
    }
}

func loadState() -> State {
    guard let d = try? Data(contentsOf: stateURL), let s = try? JSONDecoder().decode(State.self, from: d) else { return State() }
    return s
}

func saveState(_ s: State) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? enc.encode(s).write(to: stateURL, options: .atomic)
}

func appendLog(_ entry: [String: String]) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
    line.append(0x0A)
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line); try? h.close() }
    else { FileManager.default.createFile(atPath: logURL.path, contents: line, attributes: [.posixPermissions: 0o600]) }
}

func tailLog(_ n: Int) -> [String] {
    guard let h = try? FileHandle(forReadingFrom: logURL) else { return [] }
    defer { try? h.close() }
    let size = h.seekToEndOfFile()
    h.seek(toFileOffset: size > 8192 ? size - 8192 : 0)
    let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
    return text.split(separator: "\n").suffix(n).reversed().map { raw in
        guard let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return String(raw.prefix(80)) }
        let ts = (o["ts"] as? String).map { String($0.suffix(8)) } ?? ""
        let what = (o["summary"] as? String) ?? (o["tool"] as? String) ?? (o["button"] as? String) ?? ""
        return "\(ts)  \(o["src"] as? String ?? "")  \(o["decision"] as? String ?? "")  \(what.prefix(60))"
    }
}

/// "Today: 12 approved · 2 asked · 3 clicks" from the current log file.
// ponytail: reads the whole file every 3 s; fine because rotateLog() caps it at 1 MB.
func todaySummary() -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    let day = "\"ts\": \"" + f.string(from: Date()), day2 = "\"ts\":\"" + f.string(from: Date())
    var allowed = 0, asked = 0, clicks = 0
    for line in ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n")
    where line.contains(day) || line.contains(day2) {
        if line.contains("\"decision\": \"allow\"") { allowed += 1 }
        else if line.contains("\"decision\": \"ask\"") { asked += 1 }
        else if line.contains("\"decision\":\"pressed\"") { clicks += 1 }
    }
    return "Today: \(allowed) approved · \(asked) asked · \(clicks) clicks"
}

/// Keep one previous log file; start a new one past 1 MB.
func rotateLog() {
    let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
    guard size > 1_000_000 else { return }
    let old = dir.appendingPathComponent("decisions.1.jsonl")
    try? FileManager.default.removeItem(at: old)
    try? FileManager.default.moveItem(at: logURL, to: old)
}

/// nil when the hook is registered and its script exists, else what to fix.
func hookProblem() -> String? {
    let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    guard let d = try? Data(contentsOf: settings), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let groups = (o["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] else {
        return "Hook not installed: run ./install.sh"
    }
    let cmds = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    guard let cmd = cmds.first(where: { $0.contains("autoapprove.py") }) else { return "Hook not installed: run ./install.sh" }
    let script = cmd.split(separator: " ").map(String.init).first { $0.hasSuffix("autoapprove.py") } ?? ""
    guard FileManager.default.fileExists(atPath: (script as NSString).expandingTildeInPath) else {
        return "Hook script missing (repo moved?): re-run ./install.sh"
    }
    return nil
}

// MARK: Accessibility

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func webURL(_ e: AXUIElement) -> String? {
    if let u = attr(e, kAXURLAttribute) { return (u as? URL)?.absoluteString ?? (u as? String) }
    return attr(e, kAXDocumentAttribute) as? String
}

/// Claude's own UI: https://claude.ai/... or a file inside the running Claude.app's Resources.
/// Parsed, not prefix-matched (no "claude.ai.evil", no "/Claude.app/../../tmp").
func isTrustedOrigin(_ raw: String?, appBundle: URL?) -> Bool {
    guard let raw, let u = URL(string: raw) else { return false }
    if u.scheme == "https" { return u.host == "claude.ai" }
    if u.scheme == "file", let appBundle {
        let res = appBundle.appendingPathComponent("Contents/Resources").standardizedFileURL.path + "/"
        return u.standardizedFileURL.path.hasPrefix(res)
    }
    return false
}

func label(_ e: AXUIElement) -> String {
    for a in [kAXTitleAttribute, kAXDescriptionAttribute] {
        if let s = attr(e, a) as? String, !s.isEmpty { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    // Electron often puts button text in a child static text.
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        if let s = attr(c, kAXValueAttribute) as? String, !s.isEmpty { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return ""
}

/// Depth-first walk of all Claude windows; calls visit(button, label) for every AXButton.
// ponytail: full-tree poll, capped at maxNodes; switch to AXObserver if CPU shows up.
func walkButtons(maxNodes: Int = 30000, _ visit: (AXUIElement, String) -> Bool) {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        // Electron exposes web content to AX only when asked.
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // (element, inside a trusted web area?). A button counts only inside a top-level
        // AXWebArea (never nested in another) whose URL is Claude's own origin. Nested web
        // areas (embedded pages) and foreign-origin ones (browser pane) are skipped whole.
        // Pop-out session windows report their top-level page as about:blank. No signal the page
        // can't forge (window title is page-controlled) marks them as Claude's own, so they stay
        // untrusted: fail closed. The hook still answers tool prompts there.
        for window in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            var stack = [(window, false)]
            var seen = 0
            while let (e, parentTrusted) = stack.popLast(), seen < maxNodes {
                seen += 1
                let role = attr(e, kAXRoleAttribute) as? String
                var trusted = parentTrusted
                if role == "AXWebArea" {
                    guard !parentTrusted, isTrustedOrigin(webURL(e), appBundle: app.bundleURL) else { continue }
                    trusted = true
                }
                if trusted, role == kAXButtonRole as String, !visit(e, label(e)) { return }
                let kids = (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
                stack.append(contentsOf: kids.map { ($0, trusted) })
            }
        }
    }
}

// MARK: Model

let holdURL = dir.appendingPathComponent("hold.json")
let timestamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }()

final class Model: ObservableObject {
    @Published var state = loadState() { didSet { if state != oldValue { saveState(state) } } }
    @Published var recent: [String] = tailLog(10)
    @Published var today = todaySummary()
    @Published var trusted = AXIsProcessTrusted()
    @Published var hookIssue = hookProblem()
    @Published var claudeRunning = true
    @Published var now = Date()
    @Published var holding = false       // clicker paused for a risky prompt
    private var timer: Timer?
    private var ticks = 0
    private var lastMtime: Date?

    init() {
        saveState(state)
        if !trusted { requestTrust() }  // macOS shows "AutoApprove would like to control this computer"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setEnabled(false)  // quitting = brake on
        }
    }

    /// Master switch. minutes == nil: on until turned off (the default).
    func setEnabled(_ on: Bool, minutes: Double? = nil) {
        var s = state
        s.enabled = on
        s.until = on ? minutes.map { Date().timeIntervalSince1970 + $0 * 60 } : nil
        state = s
    }

    var title: String {
        guard state.enabled else { return "Auto-approve ON" }
        guard let u = state.until else { return "Auto-approve ON" }
        let left = max(0, Int((u - now.timeIntervalSince1970 + 59) / 60))
        return "Auto-approve ON · \(left) min left"
    }

    var setupOK: Bool { trusted && hookIssue == nil && claudeRunning }

    func tick() {
        ticks += 1
        now = Date()
        // Timed ON ran out. The hook checks `until` too, so this is only the visible half.
        if state.enabled, let u = state.until, now.timeIntervalSince1970 > u {
            setEnabled(false)
            appendLog(["ts": timestamp.string(from: now), "src": "app", "decision": "auto-off"])
        }
        if ticks % 3 == 0 {
            rotateLog()
            recent = tailLog(10); today = todaySummary(); trusted = AXIsProcessTrusted()
            hookIssue = hookProblem()
            claudeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).isEmpty
            // Pick up external edits to state.json (scripts, hand edits).
            let mtime = (try? FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate]) as? Date
            if let mtime, mtime != lastMtime { lastMtime = mtime; let s = loadState(); if s != state { state = s } }
            // Status for scripts/tests: is the app alive and trusted?
            let st = "{\"trusted\":\(trusted),\"pid\":\(getpid()),\"ts\":\(Int(Date().timeIntervalSince1970))}\n"
            try? st.write(to: dir.appendingPathComponent("status.json"), atomically: true, encoding: .utf8)
        }
        guard state.enabled, state.clicker, trusted else { return }
        let wanted = Set(state.buttons)
        // The hook sent a risky command back to the user: don't press "Allow" on that prompt.
        // Any hold.json (even unreadable) pauses the clicker until you press Resume.
        // A vanished button proves nothing (tab switch, other window), nor does turning ON.
        holding = FileManager.default.fileExists(atPath: holdURL.path)
        if holding { return }
        walkButtons { el, name in
            guard wanted.contains(name), (attr(el, kAXEnabledAttribute) as? Bool) ?? true else { return true }
            // The walk takes time: re-check the switch and timer right before pressing.
            guard state.enabled, state.until.map({ Date().timeIntervalSince1970 <= $0 }) ?? true,
                  !FileManager.default.fileExists(atPath: holdURL.path) else { return false }
            let ok = AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
            appendLog(["ts": timestamp.string(from: Date()), "src": "click", "button": name, "decision": ok ? "pressed" : "press-failed"])
            return false  // one press per tick; UI re-renders before next
        }
    }

    func resumeClicker() { try? FileManager.default.removeItem(at: holdURL); holding = false }

    func requestTrust() {
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
}

// MARK: UI

struct AutoApproveApp: App {
    @StateObject var m = Model()

    var body: some Scene {
        MenuBarExtra {
            // Setup checklist: one line when all is well, else what to fix.
            if m.setupOK {
                Text("Setup ✓").font(.caption)
            } else {
                if !m.trusted {
                    Text("✗ Accessibility not granted to this copy:").font(.caption)
                    Text(Bundle.main.bundlePath).font(.system(.caption2, design: .monospaced))
                    Button("Grant Accessibility…") { m.requestTrust() }
                    Button("Open Accessibility settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button("Reveal this app in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                }
                if let h = m.hookIssue { Text("✗ " + h).font(.caption) }
                if !m.claudeRunning { Text("✗ Claude desktop not running").font(.caption) }
            }
            Divider()
            Toggle(m.title, isOn: Binding(get: { m.state.enabled }, set: { m.setEnabled($0) }))
            if !m.state.enabled {
                Button("Turn ON for 15 min") { m.setEnabled(true, minutes: 15) }
                Button("Turn ON for 1 hour") { m.setEnabled(true, minutes: 60) }
            }
            Divider()
            Toggle("Hook (tool prompts)", isOn: $m.state.hook)
            Toggle("Clicker (app buttons)", isOn: $m.state.clicker)
            if m.holding {
                Text("⏸ Clicker paused: a risky command is waiting for you").font(.caption)
                Button("Resume clicker") { m.resumeClicker() }
            }
            Menu("Settings") {
                Toggle("Still ask me for risky commands", isOn: $m.state.askRisky)
                Button("Edit risky patterns and buttons…") { NSWorkspace.shared.open(stateURL) }
            }
            Divider()
            Text(m.today).font(.caption)
            Text("Recent").font(.caption)
            ForEach(Array(m.recent.enumerated()), id: \.offset) { Text($0.element).font(.system(.caption, design: .monospaced)) }
            Divider()
            Button("Open log") { NSWorkspace.shared.open(logURL) }
            Button("Edit settings (buttons list)…") { NSWorkspace.shared.open(stateURL) }
            Button("Reload settings") { m.state = loadState() }
            Button("Dump Claude button labels…") {
                var out = ""
                walkButtons { _, name in out += (name.isEmpty ? "<no label>" : name) + "\n"; return true }
                let url = dir.appendingPathComponent("buttons-seen.txt")
                try? out.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            }
            Divider()
            Button("Quit (turns auto-approve OFF)") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: !m.state.enabled ? "shield.slash" : m.holding ? "pause.circle" : m.state.until == nil ? "checkmark.shield.fill" : "timer")
        }
    }
}

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            // An older state.json (no new keys) must keep its values, not reset to defaults.
            let old = try! JSONDecoder().decode(State.self, from: Data(#"{"enabled":true,"buttons":["X"]}"#.utf8))
            precondition(old.enabled && old.buttons == ["X"] && old.hook && old.clicker && old.until == nil)
            precondition(!old.askRisky && old.askPatterns == nil)
            let t = try! JSONDecoder().decode(State.self, from: Data(#"{"until":123.5,"askRisky":true,"askPatterns":[]}"#.utf8))
            precondition(t.until == 123.5 && t.askRisky && t.askPatterns == [] && !t.enabled && t.buttons == defaultButtons)
            precondition(isTrustedOrigin("https://claude.ai/x", appBundle: nil) && !isTrustedOrigin("https://claude.ai.evil/x", appBundle: nil))
            print("selftest ok"); exit(0)
        }
        if CommandLine.arguments.contains("--dump") {
            guard AXIsProcessTrusted() else { print("not trusted: grant Accessibility to this binary"); exit(1) }
            walkButtons { _, name in print("AXButton: \(name.isEmpty ? "<no label>" : name)"); return true }
            if CommandLine.arguments.contains("--webareas") {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID) {
                    var stack = (attr(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement]) ?? []
                    var depth: [Int] = stack.map { _ in 0 }
                    while let e = stack.popLast(), let d = depth.popLast() {
                        if (attr(e, kAXRoleAttribute) as? String) == "AXWebArea" {
                            print("AXWebArea depth=\(d) trusted=\(isTrustedOrigin(webURL(e), appBundle: app.bundleURL)) url=\(webURL(e) ?? "nil")")
                        }
                        let kids = (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
                        stack += kids; depth += kids.map { _ in d + 1 }
                    }
                }
            }
            exit(0)
        }
        AutoApproveApp.main()
    }
}
