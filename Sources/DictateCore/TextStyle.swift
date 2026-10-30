import Foundation

/// How dictated text is written after transcription. Applied last, to the whole text.
public enum TextCase: String, Codable, CaseIterable, Sendable {
    case normal, lowercase, uppercase, random
}

public enum TextStyler {
    /// `rng` is a parameter so tests can fix the "random" case.
    public static func apply(_ text: String, textCase: TextCase, noTrailingPunctuation: Bool,
                             using rng: inout some RandomNumberGenerator) -> String {
        var out = text
        if noTrailingPunctuation { out = stripTrailingPunctuation(out) }
        switch textCase {
        case .normal: break
        case .lowercase: out = out.lowercased()
        case .uppercase: out = out.uppercased()
        case .random:
            // Each letter flips a coin: upper or lower. Other characters stay as they are.
            out = String(out.map { ch -> Character in
                guard ch.isLetter else { return ch }
                return Bool.random(using: &rng) ? Character(ch.uppercased()) : Character(ch.lowercased())
            })
        }
        return out
    }

    public static func apply(_ text: String, textCase: TextCase, noTrailingPunctuation: Bool) -> String {
        var rng = SystemRandomNumberGenerator()
        return apply(text, textCase: textCase, noTrailingPunctuation: noTrailingPunctuation, using: &rng)
    }

    /// Removes . , ; : and the ellipsis character at the end. Keeps ? and ! because they change the meaning.
    public static func stripTrailingPunctuation(_ text: String) -> String {
        var s = Substring(text)
        while let last = s.last, last.isWhitespace || ".,;:\u{2026}".contains(last) { s = s.dropLast() }
        // Keep a trailing newline or space the caller added only if the text had no other change.
        return String(s)
    }
}
