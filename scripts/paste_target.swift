// Paste-target harness for capturing a real Dictate paste.
// The window title is an honest, generic untitled document: the capture must not
// imply the paste landed in some named commercial app.
import AppKit
import Foundation

let timeout = Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let mainMenu = NSMenu()
mainMenu.addItem(NSMenuItem())
let editItem = NSMenuItem(); mainMenu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
app.mainMenu = mainMenu

let win = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 660, height: 240),
                   styleMask: [.titled], backing: .buffered, defer: false)
win.title = "Untitled"
let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 660, height: 240))
tv.isRichText = false
tv.font = NSFont.systemFont(ofSize: 15)
win.contentView?.addSubview(tv)
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
win.makeFirstResponder(tv)

let marker = "CLIPBOARD-MARKER-\(Int.random(in: 1000...9999))"
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(marker, forType: .string)

let started = Date().timeIntervalSince1970
Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
    let s = tv.string
    if !s.isEmpty || Date().timeIntervalSince1970 - started > timeout {
        t.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let out: [String: Any] = ["text": s, "timedOut": s.isEmpty,
                                      "clipboardRestored": NSPasteboard.general.string(forType: .string) == marker]
            print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
                         encoding: .utf8)!)
            exit(0)
        }
    }
}
app.run()
