import Foundation

/// A suggested correction learned from the user editing pasted text.
public struct CorrectionSuggestion: Codable, Equatable, Identifiable {
    public let id: UUID
    public var from: String
    public var to: String
    public var status: Status
    public var createdAt: Date

    public enum Status: String, Codable {
        case pending, accepted, rejected
    }

    public init(from: String, to: String) {
        self.id = UUID()
        self.from = from
        self.to = to
        self.status = .pending
        self.createdAt = Date()
    }
}
public struct AppConfig: Codable, Equatable {
    public var serverURL: String = "http://127.0.0.1:8772"
    public var pythonPath: String = "~/Sandbox/experiments/moonshine-stt/.venv/bin/python"
    public var serverScript: String = "~/Projects/dictate-app/server/dictate_srv.py"
    public var idleSeconds: Int = 600
    /// Carbon virtual key code. 49 = Space.
    public var hotkeyKeyCode: UInt32 = 49
    /// Any of: control, option, command, shift.
    public var hotkeyModifiers: [String] = ["control", "option"]
    /// "rightOptionHold" = hold the right Option key; "combo" = hotkeyModifiers + hotkeyKeyCode (also the fallback).
    public var hotkeyMode: String = "rightOptionHold"
    /// How long the right Option key must be held before recording starts. A quick tap does nothing.
    public var holdSeconds: Double = 0.3
    /// Show a Dock icon. Also gives a way to open Settings when the menu bar is too full to show the Dictate icon.
    public var showInDock: Bool = true
    /// Extra words the model should expect (names, product terms). Sent to the server with every request.
    public var vocabulary: [String] = []
    /// Fixes applied to the finished text, after the built-in SAP fixes.
    public var replacements: [Replacement] = []
    /// Voice commands: say the trigger, get the value inserted. E.g. trigger "my email" → value "raj@example.com".
    public var commands: [VoiceCommand] = []
    /// Auto-detected correction suggestions (pending user approval).
    public var suggestedCorrections: [CorrectionSuggestion] = []
    public var minSeconds: Double = 0.3
    public var maxRecordSeconds: Double = 120
    public var clipboardRestoreMs: Int = 600
    public var transcribeTimeoutSeconds: Double = 120
    public var serverStartTimeoutSeconds: Double = 120
    /// Seconds of silence before auto-stopping a recording (0 = disabled).
    public var silenceStopSeconds: Double = 3.0
    /// Sound pack for recording feedback (1-9). 1 = gentle chime, 2-9 = futuristic.
    public var soundPack: Int = 1
    /// Show the floating waveform animation while recording.
    public var showRecordingAnimation: Bool = true
    /// Speech model backend: "whisper" or "whistle".
    public var modelBackend: String = "whisper"
    /// Press Enter after pasting dictated text.
    public var autoPressEnter: Bool = false
    /// Last selected settings tab.
    public var settingsTab: String = "general"
    /// Where to save recorded audio for training (empty = don't save).
    public var saveAudioPath: String = ""

    public init() {}

    /// DICTATE_CONFIG overrides the location (used by tests so they never touch the real config).
    public static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["DICTATE_CONFIG"], !p.isEmpty { return p }
        return ("~/.config/dictate-app/config.json" as NSString).expandingTildeInPath
    }

    /// Missing file -> defaults. Unreadable or invalid JSON -> defaults too, with `warning` set so the app can say so.
    public static func load(path: String = AppConfig.defaultPath) -> (config: AppConfig, warning: String?) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return (AppConfig(), nil) }
        do {
            let data = try Data(contentsOf: url)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var merged = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig())) as? [String: Any]) ?? [:]
            for (k, v) in obj { merged[k] = v }
            // Try full decode first; if one bad key breaks it, drop bad keys one at a time.
            if let cfg = try? JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: merged)) {
                let v = cfg.validated()
                return (v.config, v.problems.isEmpty ? nil : "config.json: " + v.problems.joined(separator: "; "))
            }
            var problems: [String] = []
            for key in Array(merged.keys) {
                var trial = merged
                trial.removeValue(forKey: key)
                if let cfg = try? JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: trial)) {
                    problems.append("\(key) had an invalid value and was reset to default")
                    merged = trial
                    break
                }
            }
            // If still broken, fall back to defaults for the remaining bad keys.
            while (try? JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: merged))) == nil, !merged.isEmpty {
                let key = merged.keys.first!
                problems.append("\(key) had an invalid value and was reset to default")
                merged.removeValue(forKey: key)
            }
            let cfg = (try? JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: merged))) ?? AppConfig()
            let v = cfg.validated()
            let allProblems = problems + v.problems
            return (v.config, allProblems.isEmpty ? nil : "config.json: " + allProblems.joined(separator: "; "))
        } catch {
            return (AppConfig(), "config.json ignored: \(error.localizedDescription)")
        }
    }

    /// Replace values that would crash the app or send audio off this Mac. Returns what was changed.
    public func validated() -> (config: AppConfig, problems: [String]) {
        var c = self
        var problems: [String] = []
        let d = AppConfig()
        if let u = URL(string: c.serverURL), u.scheme == "http", let host = u.host,
           ["127.0.0.1", "localhost", "::1"].contains(host), u.port != nil {
        } else {
            problems.append("serverURL must be http://127.0.0.1:<port> (audio never leaves this Mac); using \(d.serverURL)")
            c.serverURL = d.serverURL
        }
        let known = Set(["control", "ctrl", "option", "alt", "command", "cmd", "shift"])
        if c.hotkeyModifiers.isEmpty || !c.hotkeyModifiers.allSatisfy({ known.contains($0.lowercased()) }) {
            problems.append("hotkeyModifiers needs one or more of control, option, command, shift; using \(d.hotkeyModifiers)")
            c.hotkeyModifiers = d.hotkeyModifiers
        }
        func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T, _ name: String) -> T {
            if v < lo || v > hi { problems.append("\(name) must be \(lo)...\(hi)"); return min(max(v, lo), hi) }
            return v
        }
        if !["rightOptionHold", "combo"].contains(c.hotkeyMode) {
            problems.append("hotkeyMode must be rightOptionHold or combo; using \(d.hotkeyMode)")
            c.hotkeyMode = d.hotkeyMode
        }
        c.holdSeconds = clamp(c.holdSeconds, 0.15, 2, "holdSeconds")
        let vocab = AppConfig.cleanVocabulary(c.vocabulary)
        if vocab != c.vocabulary { problems.append("vocabulary was tidied (empty, duplicate, long or comma terms removed; max \(AppConfig.maxVocabulary))") }
        c.vocabulary = vocab
        let reps = c.replacements.filter { !$0.from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(AppConfig.maxReplacements).map { Replacement(from: String($0.from.prefix(80)), to: String($0.to.prefix(200))) }
        if reps != c.replacements { problems.append("replacements were tidied (empty rules removed; max \(AppConfig.maxReplacements))") }
        c.replacements = Array(reps)
        let cmds = c.commands.filter { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(AppConfig.maxCommands).map { VoiceCommand(trigger: String($0.trigger.prefix(60)), value: String($0.value.prefix(500))) }
        if cmds != c.commands { problems.append("commands were tidied (empty triggers removed; max \(AppConfig.maxCommands))") }
        c.commands = Array(cmds)
        c.idleSeconds = clamp(c.idleSeconds, 0, 86_400, "idleSeconds")
        c.minSeconds = clamp(c.minSeconds, 0.05, 5, "minSeconds")
        c.maxRecordSeconds = clamp(c.maxRecordSeconds, 5, 600, "maxRecordSeconds")
        c.clipboardRestoreMs = clamp(c.clipboardRestoreMs, 100, 5_000, "clipboardRestoreMs")
        c.transcribeTimeoutSeconds = clamp(c.transcribeTimeoutSeconds, 5, 600, "transcribeTimeoutSeconds")
        c.serverStartTimeoutSeconds = clamp(c.serverStartTimeoutSeconds, 10, 600, "serverStartTimeoutSeconds")
        c.silenceStopSeconds = clamp(c.silenceStopSeconds, 0, 10, "silenceStopSeconds")
        c.soundPack = clamp(c.soundPack, 1, 9, "soundPack")
        // H1: validate pythonPath and serverScript point to expected files
        let allowedScripts = ["dictate_srv.py", "whistle_srv.py"]
        let scriptName = (c.serverScript as NSString).lastPathComponent
        if !allowedScripts.contains(scriptName) {
            problems.append("serverScript must be dictate_srv.py or whistle_srv.py; using default")
            c.serverScript = d.serverScript
        }
        let pythonName = (c.pythonPath as NSString).lastPathComponent.lowercased()
        if !pythonName.hasPrefix("python") {
            problems.append("pythonPath must be a python executable; using default")
            c.pythonPath = d.pythonPath
        }
        return (c, problems)
    }

    public var expandedPython: String { (pythonPath as NSString).expandingTildeInPath }
    public var expandedScript: String { (serverScript as NSString).expandingTildeInPath }

    public static let maxVocabulary = 30
    public static let maxReplacements = 100
    public static let maxCommands = 50

    /// Trim, drop empties, drop terms with commas or line breaks or over 40 characters, drop duplicates (any case), cap the count.
    public static func cleanVocabulary(_ terms: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for t in terms {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty || s.count > 40 || s.contains(",") || s.rangeOfCharacter(from: .newlines) != nil { continue }
            if seen.insert(s.lowercased()).inserted { out.append(s) }
            if out.count == maxVocabulary { break }
        }
        return out
    }

    /// Write the config file (atomic). Values are validated first, so the file never holds something the app would reject.
    public func save(path: String = AppConfig.defaultPath) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(validated().config)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // Restrict permissions: only owner can read/write
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
