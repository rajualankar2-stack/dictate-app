import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Optional clean-up steps that run on the transcript before replacements and text style.
public enum TextCleanup {
    private static let fillerRE = try! NSRegularExpression(
        pattern: "(?<!\\w)(?:um+|uh+|uhm+|erm|er|ah|hmm+|mm+)(?!\\w)(?:[ \\t]*,)?", options: [.caseInsensitive])

    /// Removes um, uh, uhm, er, erm, ah, hmm and the comma after them. Keeps a leading capital letter.
    public static func removeFillers(_ text: String) -> String {
        let startsUpper = text.first?.isUppercase ?? false
        var out = fillerRE.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        guard out != text else { return text }
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "[ \\t]+([,.;:!?])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "^[ \\t,]+", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        if startsUpper, let f = out.first, f.isLowercase { out = f.uppercased() + out.dropFirst() }
        return out
    }

    /// "new paragraph" becomes a blank line and "new line" becomes a line break.
    /// Takes the comma or space before, and one comma or full stop after, the phrase.
    public static func spokenFormat(_ text: String) -> String {
        var out = text
        for (phrase, rep) in [("new paragraph", "\n\n"), ("new line", "\n")] {
            let pattern = "[ \\t]*,?[ \\t]*(?<!\\w)" + phrase.replacingOccurrences(of: " ", with: "[ \\t]+") + "(?!\\w)[,.]?[ \\t]*"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: rep))
        }
        return out
    }
}

/// Smart spacing: adds one leading space when the dictation lands right after a word.
public enum SmartSpacing {
    private static let after: Set<Character> = [".", ",", ";", ":", "!", "?", "\u{2026}", ")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}"]

    /// `before` is the character left of the cursor (nil = unknown, start of field, or a selection).
    public static func needsLeadingSpace(before: Character?, text: String) -> Bool {
        guard let b = before, let first = text.first else { return false }
        if first.isWhitespace || ".,;:!?\u{2026})]}\u{201D}\u{2019}\u{00BB}".contains(first) { return false }
        return b.isLetter || b.isNumber || after.contains(b)
    }

    public static func apply(_ text: String, before: Character?) -> String {
        needsLeadingSpace(before: before, text: text) ? " " + text : text
    }
}

public enum CaretReader {
    /// The character just left of the cursor in the focused field, or nil when there is a selection,
    /// the cursor is at the start, or the app does not expose its text. Each call is bounded to 250 ms.
    public static func charBeforeCaret() -> Character? {
        guard !IsSecureEventInputEnabled() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        let element = el as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rv = rangeRef, CFGetTypeID(rv) == AXValueGetTypeID() else { return nil }
        var sel = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &sel), sel.length == 0, sel.location > 0 else { return nil }
        // Read up to two UTF-16 units so a surrogate pair is not cut in half.
        let n = min(2, sel.location)
        var want = CFRange(location: sel.location - n, length: n)
        guard let param = AXValueCreate(.cfRange, &want) else { return nil }
        var textRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &textRef) == .success,
              let s = textRef as? String else { return nil }
        return s.last
    }
}
