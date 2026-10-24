import AppKit
import Carbon.HIToolbox
import Foundation

public enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly(reason: String)
}

public protocol KeyPoster: Sendable {
    /// Send Cmd+V to the focused app. Returns false when it could not (for example, Accessibility not granted).
    func postCommandV() -> Bool
    /// Send a Return key press.
    func postReturn() -> Bool
}

public protocol TextInserter {
    func insert(_ text: String, intoAppPID: pid_t?) async -> PasteResult
}

/// Puts text on the clipboard, sends Cmd+V, then puts the old clipboard back.
/// The old clipboard is restored only if nobody changed it in between, so a copy the user makes in that
/// window is never overwritten. If the paste key could not be sent, the text stays on the clipboard.
public final class PasteStager: TextInserter, @unchecked Sendable {
    /// Clipboard managers that follow nspasteboard.org skip items that carry this type.
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private let poster: KeyPoster
    private let restoreDelay: TimeInterval
    public var autoPressEnter: Bool = false
    /// Called ~5s after pasting with (pastedText, currentFieldText). Return suggestions.
    public var onCorrectionCheck: ((String, String) -> Void)?

    public init(pasteboard: NSPasteboard = .general, poster: KeyPoster, restoreDelay: TimeInterval = 0.6) {
        self.pasteboard = pasteboard; self.poster = poster; self.restoreDelay = max(0, restoreDelay)
    }

    private typealias Snapshot = [[(type: NSPasteboard.PasteboardType, data: Data)]]

    private func snapshot() -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in
                t.rawValue.hasPrefix("dyn.") ? nil : item.data(forType: t).map { (t, $0) }
            }
        }
    }

    private func restore(_ snap: Snapshot) {
        pasteboard.clearContents()
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let items: [NSPasteboardItem] = snap.compactMap { entries in
            guard !entries.isEmpty else { return nil }
            let it = NSPasteboardItem()
            for e in entries { it.setData(e.data, forType: e.type) }
            return it
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    public func insert(_ text: String, intoAppPID: pid_t?) async -> PasteResult { await paste(text, intoAppPID: intoAppPID) }

    public func paste(_ text: String, intoAppPID: pid_t? = nil) async -> PasteResult {
        // If the frontmost app changed since recording started, copy to clipboard only
        if let target = intoAppPID, target != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            pasteboard.prepareForNewContents(with: .currentHostOnly)
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            pasteboard.writeObjects([item])
            return .copiedOnly(reason: "app changed; text copied to clipboard")
        }
        let saved = snapshot()
        // currentHostOnly: dictated text must not sync to other Apple devices through Universal Clipboard.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: PasteStager.transientType)
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount

        guard poster.postCommandV() else {
            return .copiedOnly(reason: "paste is not permitted; press Cmd+V yourself")
        }
        try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        if pasteboard.changeCount == ours { restore(saved) }
        // Delay Enter to let the paste land in slow apps (Electron, browsers, Citrix/SAP GUI)
        if autoPressEnter {
            try? await Task.sleep(nanoseconds: 100_000_000)
            _ = poster.postReturn()
        }
        // Schedule correction check after 5s
        let pastedText = text
        let cb = onCorrectionCheck
        if cb != nil {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                // Abort if secure input is enabled (password fields) to avoid capturing sensitive data
                guard !IsSecureEventInputEnabled() else { return }
                // Check if at least the first word of pasted text is still in the field
                let firstWord = pastedText.split(separator: " ").first.map(String.init) ?? pastedText
                if let current = AccessibilityTextReader.readFocusedText(), current.contains(firstWord) {
                    cb?(pastedText, current)
                }
            }
        }
        return .pasted
    }
}
