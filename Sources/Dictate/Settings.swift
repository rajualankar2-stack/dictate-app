import AppKit
import AVFoundation
import DictateCore
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, text, words, dictation, status
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .text: return "Text"
        case .words: return "Words"
        case .dictation: return "Dictation"
        case .status: return "Permissions"
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .text: return "textformat"
        case .words: return "text.book.closed"
        case .dictation: return "waveform"
        case .status: return "checkmark.shield"
        }
    }
}

/// Keys offered for the key-combination hotkey (macOS virtual key codes).
let comboKeyChoices: [(name: String, code: UInt32)] = [
    ("Space", 49), ("Tab", 48), ("Return", 36), ("` (grave)", 50),
    ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97),
    ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
]

@MainActor
final class SettingsModel: ObservableObject {
    @Published var draft: AppConfig
    @Published private(set) var saved: AppConfig
    @Published var tab: SettingsTab
    @Published var message: String?
    @Published var messageIsError = false

    @Published var micAuthorized = false
    @Published var micDenied = false
    @Published var accessibilityOK = false
    @Published var inputMonitoringOK = false
    @Published var serverRunning = false
    @Published var serverChecking = false
    @Published var menuBarIconVisible = true
    @Published var hotkeyActive = ""
    @Published var loginEnabled = false
    @Published var loginMessage: String?
    var showTour: (() -> Void)?

    /// Short text for a keycap, from the draft so it follows what the person picks.
    var shortcutLabel: String {
        if draft.hotkeyMode == "rightOptionHold" { return "Right \u{2325}" }
        let sym = ["control": "\u{2303}", "ctrl": "\u{2303}", "option": "\u{2325}", "alt": "\u{2325}", "command": "\u{2318}", "cmd": "\u{2318}", "shift": "\u{21E7}"]
        let mods = draft.hotkeyModifiers.map { sym[$0.lowercased()] ?? $0 }.joined()
        let key = comboKeyChoices.first { $0.code == draft.hotkeyKeyCode }?.name ?? "?"
        return mods + " " + key
    }

    private let applyConfig: (AppConfig) -> String?     // returns an error message, or nil
    private let stopServer: () -> Void
    private let checkServer: () async -> Bool
    private let iconVisible: () -> Bool
    private let hotkeyDescription: () -> String
    private var timer: Timer?

    init(config: AppConfig, apply: @escaping (AppConfig) -> String?, stopServer: @escaping () -> Void,
         checkServer: @escaping () async -> Bool, iconVisible: @escaping () -> Bool, hotkeyDescription: @escaping () -> String) {
        draft = config; saved = config
        tab = SettingsTab(rawValue: config.settingsTab) ?? .general
        applyConfig = apply; self.stopServer = stopServer; self.checkServer = checkServer
        self.iconVisible = iconVisible; self.hotkeyDescription = hotkeyDescription
        refresh()
    }

    var hasChanges: Bool { draft != saved }

    func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
    }
    func stopRefreshing() { timer?.invalidate(); timer = nil }

    func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        micAuthorized = mic == .authorized
        micDenied = mic == .denied || mic == .restricted
        accessibilityOK = AXIsProcessTrusted()
        inputMonitoringOK = CGPreflightListenEventAccess()
        menuBarIconVisible = iconVisible()
        hotkeyActive = hotkeyDescription()
        loginEnabled = SMAppService.mainApp.status == .enabled
        serverChecking = true
        Task { serverRunning = await checkServer(); serverChecking = false }
    }

    func save() {
        let problem = applyConfig(draft)
        if let problem { message = problem; messageIsError = true; return }
        let cleaned = draft.validated().config
        draft = cleaned; saved = cleaned
        message = "Saved. Changes are active now."; messageIsError = false
    }

    func revert() { draft = saved; message = nil }

    func stopServerNow() { stopServer(); message = "Server stopped. It starts again the next time you dictate."; messageIsError = false
        Task { try? await Task.sleep(nanoseconds: 800_000_000); serverRunning = await checkServer() } }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            loginMessage = "Could not change Login Items: \(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func openPrivacy(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
    func revealConfig() {
        let p = AppConfig.defaultPath
        if FileManager.default.fileExists(atPath: p) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        else { message = "No config file yet. Save once to create it."; messageIsError = false }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            panel
        }
        .background(DS.sidebarBG)
        .frame(minWidth: 760, idealWidth: 820, maxWidth: 980, minHeight: 600, idealHeight: 720, maxHeight: 900)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { t in
                Button { model.tab = t } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.icon).font(.system(size: 13)).frame(width: 20)
                            .foregroundStyle(model.tab == t ? Color.primary : DS.faint)
                        Text(t.title).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.tab == t ? Color.primary.opacity(0.08) : Color.clear))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(model.serverChecking ? Color.orange : (model.serverRunning ? Color.green : Color.gray)).frame(width: 7, height: 7)
                    Text(model.serverChecking ? "Checking…" : (model.serverRunning ? "Speech engine on" : "Speech engine off"))
                        .font(.system(size: 11)).foregroundStyle(DS.muted)
                }
                Button("Welcome tour…") { model.showTour?() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(DS.muted)
            }.padding(.horizontal, 10).padding(.bottom, 4)
        }
        .padding(.top, 16).padding(.horizontal, 10).padding(.bottom, 12)
        .frame(width: 200)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Group {
                switch model.tab {
                case .general: GeneralTab(model: model)
                case .text: TextTab(model: model)
                case .words: WordsTab(model: model)
                case .dictation: DictationTab(model: model)
                case .status: StatusTab(model: model)
                }
            }
            if model.hasChanges || model.message != nil {
                Rectangle().fill(DS.hairline).frame(height: 1)
                HStack(spacing: 10) {
                    if let m = model.message, !model.hasChanges {
                        Image(systemName: model.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(model.messageIsError ? .red : .green)
                        Text(m).font(.system(size: 12)).lineLimit(2)
                    } else {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text(model.message ?? "Unsaved changes").font(.system(size: 12)).foregroundStyle(DS.muted)
                    }
                    Spacer()
                    if model.hasChanges {
                        ActionButton(title: "Revert") { model.revert() }
                        ActionButton(title: "Save", primary: true) { model.save() }.keyboardShortcut("s", modifiers: .command)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .background(DS.panelBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.hairline, lineWidth: 1))
        .padding(.vertical, 8).padding(.trailing, 8)
    }
}

/// Scrolling page with a title and cards at a fixed reading width.
struct Page<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageTitle(text: title)
                content
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    private func modifierBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { model.draft.hotkeyModifiers.map { $0.lowercased() }.contains(name) },
                set: { on in
                    var m = model.draft.hotkeyModifiers.map { $0.lowercased() }.filter { $0 != name }
                    if on { m.append(name) }
                    model.draft.hotkeyModifiers = m
                })
    }

    private func toggle(_ b: Binding<Bool>) -> some View { Toggle("", isOn: b).labelsHidden().toggleStyle(.switch) }

    var body: some View {
        Page(title: "General") {
            Card {
                SettingRow(icon: "keyboard", title: "Shortcut", detail: "Press once to start, press again to stop") {
                    Keycap(label: model.shortcutLabel)
                }
                SettingRow(icon: "hand.tap", title: "Trigger", divider: false) {
                    Picker("", selection: $model.draft.hotkeyMode) {
                        Text("Right Option (long press)").tag("rightOptionHold")
                        Text("Key combination").tag("combo")
                    }.labelsHidden().frame(width: 220)
                }
            }
            if model.draft.hotkeyMode == "rightOptionHold" {
                Card {
                    SettingRow(icon: "timer", title: "Press duration", detail: "Shorter taps do nothing", divider: false) {
                        HStack(spacing: 8) {
                            Slider(value: $model.draft.holdSeconds, in: 0.15...1.0, step: 0.05).frame(width: 140)
                            Text(String(format: "%.2f s", model.draft.holdSeconds)).monospacedDigit().font(.system(size: 12)).frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            } else {
                Card {
                    SettingRow(icon: "command", title: "Modifiers", detail: "Choose at least one. Hold them, press the key, speak") {
                        HStack(spacing: 10) {
                            Toggle("\u{2303}", isOn: modifierBinding("control"))
                            Toggle("\u{2325}", isOn: modifierBinding("option"))
                            Toggle("\u{2318}", isOn: modifierBinding("command"))
                            Toggle("\u{21E7}", isOn: modifierBinding("shift"))
                        }.toggleStyle(.checkbox)
                    }
                    SettingRow(icon: "return", title: "Key", divider: false) {
                        Picker("", selection: $model.draft.hotkeyKeyCode) {
                            ForEach(comboKeyChoices, id: \.code) { Text($0.name).tag($0.code) }
                        }.labelsHidden().frame(width: 140)
                    }
                }
            }
            Card(title: "App") {
                SettingRow(icon: "power", title: "Open Dictate at login") {
                    toggle(Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                }
                SettingRow(icon: "dock.rectangle", title: "Show in the Dock", detail: "Keep it on if the menu-bar icon is hidden: the Dock icon opens settings", divider: false) {
                    toggle($model.draft.showInDock)
                }
                if let m = model.loginMessage { Text(m).font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 8) }
            }
            Card(title: "Feedback") {
                SettingRow(icon: "speaker.wave.2", title: "Sound") {
                    Picker("", selection: $model.draft.soundPack) {
                        Text("Gentle chime").tag(1); Text("Digital blip").tag(2); Text("Synth sweep").tag(3)
                        Text("Sci-fi chirp").tag(4); Text("Electronic ping").tag(5); Text("Tron-like").tag(6)
                        Text("Cyber click").tag(7); Text("Hologram shimmer").tag(8); Text("Neon pulse").tag(9)
                    }.labelsHidden().frame(width: 180)
                    .onChange(of: model.draft.soundPack) { newPack in
                        if let url = Bundle.main.url(forResource: "sound_\(newPack)_start", withExtension: "wav"),
                           let sound = NSSound(contentsOf: url, byReference: true) { sound.play() }
                    }
                }
                SettingRow(icon: "waveform.path", title: "Recording animation", detail: "A floating waveform while you record") {
                    toggle($model.draft.showRecordingAnimation)
                }
                SettingRow(icon: "return", title: "Press Enter after pasting", detail: "Useful in chat and messaging apps") {
                    toggle($model.draft.autoPressEnter)
                }
                SettingRow(icon: "externaldrive", title: "Save audio for training", detail: "Keeps each recording as a WAV file. Off by default", divider: false) {
                    toggle(Binding(get: { !model.draft.saveAudioPath.isEmpty }, set: { model.draft.saveAudioPath = $0 ? "~/Projects/voice-log/audio" : "" }))
                }
            }
        }
    }
}

// MARK: Text

struct TextTab: View {
    @ObservedObject var model: SettingsModel

    private struct Fixed: RandomNumberGenerator {   // a fixed seed keeps the preview from flickering
        var n: UInt64 = 7
        mutating func next() -> UInt64 { n &+= 0x9E3779B97F4A7C15; var z = n; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; return z ^ (z >> 27) }
    }

    private var sample: String {
        var g = Fixed()
        return TextStyler.apply("Please send me the report by Friday afternoon.",
                                textCase: TextCase(rawValue: model.draft.textCase) ?? .normal,
                                noTrailingPunctuation: model.draft.noTrailingPunctuation, using: &g)
    }

    var body: some View {
        Page(title: "Text") {
            Card {
                SettingRow(icon: "textformat", title: "Letter case", detail: "Applied to every dictation after transcribing", divider: false) {
                    Picker("", selection: $model.draft.textCase) {
                        Text("Normal").tag("normal")
                        Text("lowercase").tag("lowercase")
                        Text("UPPERCASE").tag("uppercase")
                        Text("rAnDoM").tag("random")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }
            }
            Card {
                SettingRow(icon: "period", title: "No trailing punctuation", detail: "Removes . , ; : from the end. Keeps ? and !", divider: false) {
                    Toggle("", isOn: $model.draft.noTrailingPunctuation).labelsHidden().toggleStyle(.switch)
                }
            }
            Card(title: "Preview") {
                Text(sample)
                    .font(.system(size: 14)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}

// MARK: Words

struct WordsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var newTerm = ""
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var newTrigger = ""
    @State private var newValue = ""

    var body: some View {
        // A plain VStack instead of a grouped Form: the grouped style adds ~30 pt of
        // padding per row, which pushed a long replacement list off the bottom of the
        // window. Rows are now compact, so the whole list stays visible.
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vocabulary (\(model.draft.vocabulary.count) of \(AppConfig.maxVocabulary))")
                    .font(.headline)
                HStack {
                    TextField("Add a word or name", text: $newTerm).textFieldStyle(.roundedBorder).onSubmit(addTerm)
                    Button("Add", action: addTerm).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.draft.vocabulary.isEmpty {
                    note("No extra words. The built-in list is always on, so common technical terms still land correctly.")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.draft.vocabulary.indices, id: \.self) { i in
                            HStack(spacing: 8) {
                                TextField("", text: $model.draft.vocabulary[i]).textFieldStyle(.roundedBorder)
                                Spacer(minLength: 0)
                                Button { if i < model.draft.vocabulary.count { model.draft.vocabulary.remove(at: i) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                note("Names and terms you say often. They hint the model before it listens, which helps rare words. This does not force a spelling: use a replacement for that.")

                Divider().padding(.top, 6)

                Text("Replacements (\(model.draft.replacements.count))")
                    .font(.headline)
                HStack {
                    TextField("When it hears", text: $newFrom).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("write", text: $newTo).textFieldStyle(.roundedBorder).onSubmit(addRule)
                    Button("Add", action: addRule).disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.draft.replacements.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                                TextField("", text: $model.draft.replacements[i].from).textFieldStyle(.roundedBorder)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                TextField("", text: $model.draft.replacements[i].to).textFieldStyle(.roundedBorder)
                            Spacer(minLength: 0)
                            Button { if i < model.draft.replacements.count { model.draft.replacements.remove(at: i) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                note("Applied to the finished text, whole words only, ignoring capitals. Rules run top to bottom.")

                Divider().padding(.top, 6)

                Text("Voice commands (\(model.draft.commands.count))")
                    .font(.headline)
                HStack {
                    TextField("Say this", text: $newTrigger).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("insert this", text: $newValue).textFieldStyle(.roundedBorder).onSubmit(addCommand)
                    Button("Add", action: addCommand).disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.draft.commands.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            TextField("", text: $model.draft.commands[i].trigger).textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("", text: $model.draft.commands[i].value).textFieldStyle(.roundedBorder)
                            Spacer(minLength: 0)
                            Button { if i < model.draft.commands.count { model.draft.commands.remove(at: i) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                note("Say the trigger phrase and nothing else — it is replaced with the value. E.g. trigger \"my email\" inserts your email address.")

                let pending = model.draft.suggestedCorrections.filter { $0.status == .pending }
                if !pending.isEmpty {
                    Divider().padding(.top, 6)
                    Text("Suggested corrections (\(pending.count))")
                        .font(.headline)
                    note("Detected from your edits after pasting. Accept to add as a replacement rule.")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.draft.suggestedCorrections.indices, id: \.self) { i in
                            if model.draft.suggestedCorrections[i].status == .pending {
                                HStack(spacing: 8) {
                                    Text(model.draft.suggestedCorrections[i].from)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        .frame(width: 168, alignment: .leading)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                    Text(model.draft.suggestedCorrections[i].to)
                                        .font(.caption).fontWeight(.medium).foregroundStyle(Color.accentColor).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button("Accept") {
                                        let s = model.draft.suggestedCorrections[i]
                                        model.draft.replacements.append(Replacement(from: s.from, to: s.to))
                                        model.draft.suggestedCorrections[i].status = .accepted
                                    }.buttonStyle(.borderless).font(.caption)
                                    Button("Reject") {
                                        model.draft.suggestedCorrections[i].status = .rejected
                                    }.buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addTerm() {
        let t = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.draft.vocabulary.append(t); newTerm = ""
    }
    private func addRule() {
        let f = newFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return }
        model.draft.replacements.append(Replacement(from: f, to: newTo)); newFrom = ""; newTo = ""
    }

    private func addCommand() {
        let t = newTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.draft.commands.append(VoiceCommand(trigger: t, value: newValue)); newTrigger = ""; newValue = ""
    }
}

// MARK: Dictation

struct DictationTab: View {
    @ObservedObject var model: SettingsModel

    private func sliderRow(icon: String, _ title: String, _ detail: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, unit: String, format: String, divider: Bool = true) -> some View {
        SettingRow(icon: icon, title: title, detail: detail, divider: divider) {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step).frame(width: 150)
                Text(String(format: format, value.wrappedValue) + " " + unit).monospacedDigit()
                    .font(.system(size: 12)).frame(width: 64, alignment: .trailing)
            }
        }
    }

    var body: some View {
        Page(title: "Dictation") {
            Card(title: "Recording") {
                sliderRow(icon: "scissors", "Ignore short recordings", "Stops an accidental tap from pasting anything",
                          value: $model.draft.minSeconds, range: 0.1...1.0, step: 0.05, unit: "s", format: "%.2f")
                sliderRow(icon: "speaker.slash", "Stop after silence", "Set to 0 to stop by hand only",
                          value: $model.draft.silenceStopSeconds, range: 0...10, step: 0.5, unit: "s", format: "%.1f")
                SettingRow(icon: "clock", title: "Longest recording", divider: false) {
                    Stepper(value: Binding(get: { Int(model.draft.maxRecordSeconds) }, set: { model.draft.maxRecordSeconds = Double($0) }), in: 10...600, step: 10) {
                        Text("\(Int(model.draft.maxRecordSeconds)) s").monospacedDigit().font(.system(size: 12))
                    }
                }
            }
            Card(title: "Pasting") {
                sliderRow(icon: "doc.on.clipboard", "Hold text on the clipboard",
                          "Raise it if a slow app (Terminal, Electron) pastes your old clipboard",
                          value: Binding(get: { Double(model.draft.clipboardRestoreMs) }, set: { model.draft.clipboardRestoreMs = Int($0) }),
                          range: 100...2000, step: 50, unit: "ms", format: "%.0f", divider: false)
            }
            Card(title: "Speech engine") {
                SettingRow(icon: "cpu", title: "Model", detail: "Runs on this Mac. Audio never leaves it") {
                    Picker("", selection: $model.draft.modelBackend) {
                        Text("Parakeet (731 MB)").tag("parakeet")
                        Text("Whistle (16 MB)").tag("whistle")
                    }.labelsHidden().frame(width: 180)
                }
                SettingRow(icon: "moon.zzz", title: "Stop when idle", detail: "The engine uses about 1 GB while it runs and stops by itself") {
                    Stepper(value: Binding(get: { max(1, model.draft.idleSeconds / 60) }, set: { model.draft.idleSeconds = $0 * 60 }), in: 1...240) {
                        Text("\(max(1, model.draft.idleSeconds / 60)) min").monospacedDigit().font(.system(size: 12))
                    }
                }
                SettingRow(icon: "circle.fill", title: model.serverRunning ? "Engine running" : "Engine stopped", divider: false) {
                    SmallButton(title: "Stop now") { model.stopServerNow() }.opacity(model.serverRunning ? 1 : 0.4).disabled(!model.serverRunning)
                }
            }
            DisclosureGroup("Advanced") {
                Card {
                    SettingRow(title: "Python", divider: true) { TextField("", text: $model.draft.pythonPath).textFieldStyle(.roundedBorder).frame(width: 320) }
                    SettingRow(title: "Server script", divider: true) { TextField("", text: $model.draft.serverScript).textFieldStyle(.roundedBorder).frame(width: 320) }
                    SettingRow(title: "Address", detail: "Must be on this Mac (127.0.0.1)", divider: false) { TextField("", text: $model.draft.serverURL).textFieldStyle(.roundedBorder).frame(width: 320) }
                }.padding(.top, 8)
            }
            .font(.system(size: 12)).foregroundStyle(DS.muted)
        }
    }
}

// MARK: Permissions

struct StatusTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Page(title: "Permissions") {
            Card {
                permission("mic", "Microphone", ok: model.micAuthorized,
                           detail: model.micDenied ? "Denied: turn it on in System Settings" : "Hears you only while you record", pane: "Privacy_Microphone")
                permission("character.cursor.ibeam", "Accessibility", ok: model.accessibilityOK,
                           detail: "Pastes your words into any app", pane: "Privacy_Accessibility")
                permission("keyboard", "Input Monitoring", ok: model.inputMonitoringOK,
                           detail: "Needed for the right Option key. The key combination works without it", pane: "Privacy_ListenEvent", divider: false)
            }
            Card(title: "Current state") {
                SettingRow(icon: "keyboard", title: "Shortcut") { Keycap(label: model.shortcutLabel) }
                SettingRow(icon: "menubar.rectangle", title: "Menu-bar icon",
                           detail: model.menuBarIconVisible ? nil : "macOS hides icons that do not fit. Use the Dock icon, or drag other icons out of the menu bar") {
                    Text(model.menuBarIconVisible ? "Visible" : "Hidden").font(.system(size: 12))
                        .foregroundStyle(model.menuBarIconVisible ? DS.muted : Color.orange)
                }
                SettingRow(icon: "doc.text", title: "Settings file", divider: false) { SmallButton(title: "Show in Finder") { model.revealConfig() } }
            }
        }
    }

    private func permission(_ icon: String, _ name: String, ok: Bool, detail: String, pane: String, divider: Bool = true) -> some View {
        SettingRow(icon: icon, title: name, detail: detail, divider: divider) {
            if ok {
                HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Allowed").font(.system(size: 12)).foregroundStyle(DS.muted) }
            } else {
                SmallButton(title: "Allow") { model.openPrivacy(pane) }
            }
        }
    }
}
