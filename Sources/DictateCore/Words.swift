import Foundation

/// "When the transcript says `from`, write `to`." Whole words only, case-insensitive.
public struct Replacement: Codable, Equatable, Hashable, Sendable {
    public var from: String
    public var to: String
    public init(from: String = "", to: String = "") { self.from = from; self.to = to }
}

public struct VoiceCommand: Codable, Equatable, Hashable, Sendable {
    public var trigger: String
    public var value: String
    public init(trigger: String = "", value: String = "") { self.trigger = trigger; self.value = value }
}

public enum TextReplacer {
    public static func apply(_ text: String, _ rules: [Replacement]) -> String {
        var out = text
        for r in rules {
            let from = r.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }
            // Whole-word match: the characters on both sides must not be letters or digits.
            let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: from) + "(?!\\w)"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: r.to))
        }
        return out
    }
}

/// The user's word lists, readable from any thread. The settings window replaces them; dictation reads them.
public final class LiveWords: @unchecked Sendable {
    private let lock = NSLock()
    private var _vocabulary: [String] = []
    private var _replacements: [Replacement] = []
    private var _commands: [VoiceCommand] = []
    private var _textCase: TextCase = .normal
    private var _noTrailingPunctuation = false

    public init(vocabulary: [String] = [], replacements: [Replacement] = [], commands: [VoiceCommand] = []) {
        _vocabulary = vocabulary; _replacements = replacements; _commands = commands
    }
    public convenience init(config: AppConfig) { self.init(); update(from: config) }

    public func update(from c: AppConfig) {
        lock.lock(); _vocabulary = c.vocabulary; _replacements = c.replacements; _commands = c.commands
        _textCase = TextCase(rawValue: c.textCase) ?? .normal; _noTrailingPunctuation = c.noTrailingPunctuation; lock.unlock()
    }
    public var vocabulary: [String] { lock.lock(); defer { lock.unlock() }; return _vocabulary }
    public var replacements: [Replacement] { lock.lock(); defer { lock.unlock() }; return _replacements }
    public var commands: [VoiceCommand] { lock.lock(); defer { lock.unlock() }; return _commands }
    public func process(_ text: String) -> String {
        var result = text
        for cmd in commands {
            let trigger = cmd.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            result = result.replacingOccurrences(of: trigger, with: cmd.value, options: .caseInsensitive)
        }
        result = TextReplacer.apply(result, replacements)
        lock.lock(); let style = (_textCase, _noTrailingPunctuation); lock.unlock()
        return TextStyler.apply(result, textCase: style.0, noTrailingPunctuation: style.1)
    }
}
