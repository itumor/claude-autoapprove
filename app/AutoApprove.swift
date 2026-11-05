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

struct State: Codable {
    var enabled = false
    var hook = true
    var clicker = true
    var buttons = ["Allow", "Allow once", "Always allow", "Approve", "Accept", "Yes, proceed", "Publish", "Continue"]
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
    else { try? line.write(to: logURL) }
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
        let what = (o["tool"] as? String) ?? (o["button"] as? String) ?? "?"
        return "\(ts)  \(o["src"] as? String ?? "")  \(o["decision"] as? String ?? "")  \(what)"
    }
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

final class Model: ObservableObject {
    @Published var state = loadState() { didSet { saveState(state) } }
    @Published var recent: [String] = tailLog(10)
    @Published var trusted = AXIsProcessTrusted()
    private var timer: Timer?
    private var ticks = 0
    private var lastMtime: Date?

    init() {
        saveState(state)
        if !trusted { requestTrust() }  // macOS shows "AutoApprove would like to control this computer"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state.enabled = false  // quitting = brake on
        }
    }

    func tick() {
        ticks += 1
        if ticks % 3 == 0 {
            recent = tailLog(10); trusted = AXIsProcessTrusted()
            // Pick up external edits to state.json (scripts, hand edits).
            let mtime = (try? FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate]) as? Date
            if let mtime, mtime != lastMtime { lastMtime = mtime; let s = loadState(); if s.enabled != state.enabled || s.hook != state.hook || s.clicker != state.clicker || s.buttons != state.buttons { state = s } }
            // Status for scripts/tests: is the app alive and trusted?
            let st = "{\"trusted\":\(trusted),\"pid\":\(getpid()),\"ts\":\(Int(Date().timeIntervalSince1970))}\n"
            try? st.write(to: dir.appendingPathComponent("status.json"), atomically: true, encoding: .utf8)
        }
        guard state.enabled, state.clicker, trusted else { return }
        let wanted = Set(state.buttons)
        walkButtons { el, name in
            guard wanted.contains(name), (attr(el, kAXEnabledAttribute) as? Bool) ?? true else { return true }
            let ok = AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            appendLog(["ts": f.string(from: Date()), "src": "click", "button": name, "decision": ok ? "pressed" : "press-failed"])
            return false  // one press per tick; UI re-renders before next
        }
    }

    func requestTrust() {
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
}

// MARK: UI

struct AutoApproveApp: App {
    @StateObject var m = Model()

    var body: some Scene {
        MenuBarExtra {
            Toggle("Auto-approve ON", isOn: $m.state.enabled)
            Divider()
            Toggle("Hook (tool prompts)", isOn: $m.state.hook)
            Toggle("Clicker (app buttons)", isOn: $m.state.clicker)
            if !m.trusted { Button("⚠︎ Grant Accessibility…") { m.requestTrust() } }
            Divider()
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
            Image(systemName: m.state.enabled ? "checkmark.shield.fill" : "shield.slash")
        }
    }
}

@main
enum Entry {
    static func main() {
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
