// GUI harness for the REAL Dictate app, in two parts (a bare binary cannot take focus; an app bundle cannot post keys
// without its own Accessibility grant, so the work is split):
//   target <timeoutSeconds>        window with a text view; sets a clipboard marker; prints JSON when text appears
//   driver <holdSeconds> <text> [voice]   presses Control+Option+Space, speaks through the speakers, releases
import AppKit
import Foundation

let mode = CommandLine.arguments.dropFirst().first ?? "target"
let args = Array(CommandLine.arguments.dropFirst(2))
func now() -> Double { Date().timeIntervalSince1970 }
func json(_ d: [String: Any]) { print(String(data: try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]), encoding: .utf8)!); fflush(stdout) }

if mode == "driver" {
    let hold = Double(args.first ?? "6") ?? 6
    let speak = args.count > 1 ? args[1] : "Post the goods receipt in MIGO and then check the invoice in MIRO."
    let voice = args.count > 2 ? args[2] : "Rishi"
    func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: key, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
    post(0x3B, down: true, flags: .maskControl)
    post(0x3A, down: true, flags: [.maskControl, .maskAlternate])
    post(0x31, down: true, flags: [.maskControl, .maskAlternate])
    let pressed = now()
    Thread.sleep(forTimeInterval: 0.6)   // let the recorder start before speaking
    let p = Process()
    if speak.hasPrefix("afplay:") {   // play an audio file instead of speech, e.g. a steady tone
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay"); p.arguments = [String(speak.dropFirst(7))]
    } else {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = ["-v", voice, speak]
    }
    try? p.run()
    Thread.sleep(forTimeInterval: max(0.5, hold - 0.6))
    post(0x31, down: false, flags: [.maskControl, .maskAlternate])
    post(0x3A, down: false, flags: [.maskControl])
    post(0x3B, down: false, flags: [])
    json(["pressedEpoch": pressed, "releasedEpoch": now(), "AXTrusted": AXIsProcessTrusted()])
    exit(0)
}

// optdriver <right|left> <holdSeconds> [letterAtSeconds]: silent. Posts real Option modifier events (no sound).
if mode == "optdriver" {
    let side = args.first ?? "right"
    let hold = Double(args.dropFirst().first ?? "1.5") ?? 1.5
    let letterAt = Double(args.dropFirst(2).first ?? "-1") ?? -1
    let code: Int64 = side == "right" ? 61 : 58
    let dev: UInt64 = side == "right" ? 0x40 : 0x20
    func mod(_ down: Bool) {
        let e = CGEvent(source: CGEventSource(stateID: .hidSystemState))!
        e.type = .flagsChanged
        e.setIntegerValueField(.keyboardEventKeycode, value: code)
        e.flags = down ? CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | dev) : []
        e.post(tap: .cghidEventTap)
    }
    func letter() {
        for d in [true, false] {
            let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 0, keyDown: d)!
            e.flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | dev)
            e.post(tap: .cghidEventTap)
        }
    }
    mod(true)
    let pressed = now()
    if letterAt >= 0 && letterAt < hold {
        Thread.sleep(forTimeInterval: letterAt); letter(); Thread.sleep(forTimeInterval: hold - letterAt)
    } else {
        Thread.sleep(forTimeInterval: hold)
    }
    mod(false)
    json(["side": side, "held": now() - pressed, "letterAt": letterAt])
    exit(0)
}

// target
let timeout = Double(args.first ?? "30") ?? 30
let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Cmd+V reaches a text view only through a menu item with that key equivalent, as in any real app.
let mainMenu = NSMenu()
mainMenu.addItem(NSMenuItem())
let editItem = NSMenuItem(); mainMenu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
app.mainMenu = mainMenu
let win = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
win.title = "Dictate paste target (test)"
let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
win.contentView?.addSubview(tv)
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
win.makeFirstResponder(tv)
let marker = "CLIPBOARD-MARKER-\(Int.random(in: 1000...9999))"
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(marker, forType: .string)
let started = now()
var frontAtStart = ""
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { frontAtStart = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?" }
Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
    let s = tv.string
    if !s.isEmpty || now() - started > timeout {
        t.invalidate()
        let appeared = now()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            json(["text": s, "textAppearedEpoch": appeared, "timedOut": s.isEmpty, "frontmostAtStart": frontAtStart,
                  "clipboardRestored": NSPasteboard.general.string(forType: .string) == marker,
                  "clipboardNow": NSPasteboard.general.string(forType: .string) ?? ""])
            exit(0)
        }
    }
}
app.run()
