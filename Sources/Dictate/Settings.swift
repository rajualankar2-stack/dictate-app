import AppKit
import AVFoundation
import DictateCore
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, words, dictation, status
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .words: return "Words"
        case .dictation: return "Dictation"
        case .status: return "Status"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .words: return "textformat.abc"
        case .dictation: return "mic"
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
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Spacer()
                Button("Revert") { model.revert() }.disabled(!model.hasChanges)
                Button("Save") { model.save() }.keyboardShortcut("s", modifiers: .command).disabled(!model.hasChanges)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            TabView(selection: $model.tab) {
                GeneralTab(model: model).tabItem { Label("General", systemImage: SettingsTab.general.icon) }.tag(SettingsTab.general)
                WordsTab(model: model).tabItem { Label("Words", systemImage: SettingsTab.words.icon) }.tag(SettingsTab.words)
                DictationTab(model: model).tabItem { Label("Dictation", systemImage: SettingsTab.dictation.icon) }.tag(SettingsTab.dictation)
                StatusTab(model: model).tabItem { Label("Status", systemImage: SettingsTab.status.icon) }.tag(SettingsTab.status)
            }
            .padding(.top, 6)
            Divider()
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Circle().fill(model.serverChecking ? Color.orange : (model.serverRunning ? Color.green : Color.gray)).frame(width: 8, height: 8)
                    Text(model.serverChecking ? "Checking…" : (model.serverRunning ? "Engine on" : "Engine off")).font(.caption).foregroundStyle(.secondary)
                    if let m = model.message {
                        Image(systemName: model.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(model.messageIsError ? .red : .green)
                        Text(m).font(.callout).lineLimit(2)
                    } else if model.hasChanges {
                        Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.orange)
                        Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Text("Shortcut:").font(.caption).foregroundStyle(.secondary)
                    Text(model.hotkeyActive).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    Spacer()
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 640, idealWidth: 680, maxWidth: 760, minHeight: 600, idealHeight: 760, maxHeight: 900)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
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

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Trigger key", selection: $model.draft.hotkeyMode) {
                    Text("Right Option key (long press)").tag("rightOptionHold")
                    Text("Key combination").tag("combo")
                }
                if model.draft.hotkeyMode == "rightOptionHold" {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Press duration")
                            Slider(value: $model.draft.holdSeconds, in: 0.15...1.0, step: 0.05)
                            Text(String(format: "%.2f s", model.draft.holdSeconds)).monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                        Text("Recording starts after this long. A shorter tap, or Option with another key, does nothing. Speak just after the recording starts: a longer hold time clips more of your first word.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 14) {
                        Toggle("\u{2303} Control", isOn: modifierBinding("control"))
                        Toggle("\u{2325} Option", isOn: modifierBinding("option"))
                        Toggle("\u{2318} Command", isOn: modifierBinding("command"))
                        Toggle("\u{21E7} Shift", isOn: modifierBinding("shift"))
                    }.toggleStyle(.checkbox)
                    Picker("Key", selection: $model.draft.hotkeyKeyCode) {
                        ForEach(comboKeyChoices, id: \.code) { Text($0.name).tag($0.code) }
                    }.frame(width: 240)
                    Text("Choose at least one modifier. Hold the combination, speak, release.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Active now: \(model.hotkeyActive)").font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Show Dictate in the Dock", isOn: $model.draft.showInDock)
                Text("Keep this on if the menu-bar icon is hidden: the Dock icon opens these settings.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open Dictate when I log in", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if let m = model.loginMessage { Text(m).font(.caption).foregroundStyle(.red) }
            }
            Section("Feedback") {
                Picker("Sound", selection: $model.draft.soundPack) {
                    Text("1 - Gentle chime").tag(1)
                    Text("2 - Digital blip").tag(2)
                    Text("3 - Synth sweep").tag(3)
                    Text("4 - Sci-fi chirp").tag(4)
                    Text("5 - Electronic ping").tag(5)
                    Text("6 - Tron-like").tag(6)
                    Text("7 - Cyber click").tag(7)
                    Text("8 - Hologram shimmer").tag(8)
                    Text("9 - Neon pulse").tag(9)
                }
                .onChange(of: model.draft.soundPack) { newPack in
                    if let url = Bundle.main.url(forResource: "sound_\(newPack)_start", withExtension: "wav"),
                       let sound = NSSound(contentsOf: url, byReference: true) {
                        sound.play()
                    }
                }
                Text("Played when recording starts and stops. Preview by recording.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show recording animation", isOn: $model.draft.showRecordingAnimation)
                Text("Floating waveform near the center of the screen while recording.").font(.caption).foregroundStyle(.secondary)
                Toggle("Press Enter after pasting", isOn: $model.draft.autoPressEnter)
                Text("Automatically press Return after dictating. Useful for chat and messaging apps.").font(.caption).foregroundStyle(.secondary)
                Toggle("Save audio for training", isOn: Binding(get: { !model.draft.saveAudioPath.isEmpty }, set: { model.draft.saveAudioPath = $0 ? "~/Projects/voice-log/audio" : "" }))
                Text("Saves each recording as a WAV file for future model fine-tuning. Off by default.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        Form {
            Section("Recording") {
                slider("Ignore recordings shorter than", value: $model.draft.minSeconds, range: 0.1...1.0, step: 0.05, unit: "s", format: "%.2f",
                       note: "Stops an accidental tap from pasting anything.")
                slider("Auto-stop after silence", value: $model.draft.silenceStopSeconds, range: 0...10, step: 0.5, unit: "s", format: "%.1f",
                       note: "Stop recording automatically when you stop speaking. Set to 0 to disable (press to stop manually).")
                Stepper(value: Binding(get: { Int(model.draft.maxRecordSeconds) }, set: { model.draft.maxRecordSeconds = Double($0) }), in: 10...600, step: 10) {
                    HStack { Text("Longest recording"); Spacer(); Text("\(Int(model.draft.maxRecordSeconds)) s").monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            Section("Pasting") {
                slider("Hold the text on the clipboard for", value: Binding(get: { Double(model.draft.clipboardRestoreMs) }, set: { model.draft.clipboardRestoreMs = Int($0) }),
                       range: 100...2000, step: 50, unit: "ms", format: "%.0f",
                       note: "While the paste happens, the dictated text sits on the clipboard. Then your earlier clipboard comes back. Raise it if a slow app (Terminal, Electron) pastes your old clipboard instead.")
            }
            Section("Speech engine") {
                Stepper(value: Binding(get: { max(1, model.draft.idleSeconds / 60) }, set: { model.draft.idleSeconds = $0 * 60 }), in: 1...240) {
                    HStack { Text("Stop the engine after being idle for"); Spacer(); Text("\(max(1, model.draft.idleSeconds / 60)) min").monospacedDigit().foregroundStyle(.secondary) }
                }
                Text("The engine holds about 1.7 GB of memory while it runs. It starts when you first dictate and stops by itself.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Circle().fill(model.serverRunning ? Color.green : Color.gray).frame(width: 9, height: 9)
                    Text(model.serverRunning ? "Engine running" : "Engine stopped")
                    Spacer()
                    Button("Stop engine now") { model.stopServerNow() }.disabled(!model.serverRunning)
                }
            }
            Section("Advanced") {
                Picker("Model", selection: $model.draft.modelBackend) {
                    Text("Parakeet (via HEX app, fast)").tag("parakeet")
                    Text("Whistle (16 MB, Cactus)").tag("whistle")
                }
                DisclosureGroup("Engine location") {
                    TextField("Python", text: $model.draft.pythonPath).textFieldStyle(.roundedBorder)
                    TextField("Server script", text: $model.draft.serverScript).textFieldStyle(.roundedBorder)
                    TextField("Address", text: $model.draft.serverURL).textFieldStyle(.roundedBorder)
                    Text("The address must be on this Mac (127.0.0.1 or localhost). Audio never leaves it.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, format: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.body)
                Spacer()
                Text(String(format: format, value.wrappedValue) + " " + unit)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }
            Slider(value: value, in: range, step: step)
                .tint(Color.accentColor)
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Status

struct StatusTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Permissions") {
                row("Microphone", ok: model.micAuthorized, detail: model.micDenied ? "Denied: turn it on in System Settings" : (model.micAuthorized ? "Allowed" : "Not asked yet"), pane: "Privacy_Microphone")
                row("Accessibility", ok: model.accessibilityOK, detail: model.accessibilityOK ? "Allowed (needed to paste)" : "Needed to paste text into other apps", pane: "Privacy_Accessibility")
                row("Input Monitoring", ok: model.inputMonitoringOK, detail: model.inputMonitoringOK ? "Allowed (needed for the right Option key)" : "Needed for the right Option key; the key combination works without it", pane: "Privacy_ListenEvent")
            }
            Section("Current state") {
                HStack { Text("Shortcut"); Spacer(); Text(model.hotkeyActive).foregroundStyle(.secondary) }
                HStack {
                    Text("Menu-bar icon"); Spacer()
                    Text(model.menuBarIconVisible ? "Visible" : "Hidden (menu bar is full)").foregroundStyle(model.menuBarIconVisible ? Color.secondary : Color.orange)
                }
                if !model.menuBarIconVisible {
                    Text("macOS hides menu-bar icons that do not fit. Hold Command and drag other icons out of the menu bar to make room, or use the Dock icon.").font(.caption).foregroundStyle(.secondary)
                }
                HStack { Text("Settings file"); Spacer(); Button("Show in Finder") { model.revealConfig() } }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ name: String, ok: Bool, detail: String, pane: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 1) { Text(name); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Open") { model.openPrivacy(pane) }
        }
    }
}

