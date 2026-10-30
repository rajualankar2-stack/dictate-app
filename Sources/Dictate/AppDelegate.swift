import AppKit
import Carbon
private var escapeDelegateRef: AppDelegate?
import AVFoundation
import DictateCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusSink, NSWindowDelegate {
    private var item: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
    private let hotkey = Hotkey()
    private let optionTap = OptionHoldTap()
    private var controller: DictationController?
    private var stager: PasteStager?
    private var supervisor: ServerSupervisor?
    private var config = AppConfig()
    private let words = LiveWords()
    private var resetTimer: Timer?
    private var startupNote: String?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var onboardingModel: OnboardingModel?
    var settingsModel: SettingsModel?
    private var carbonActive = false
    private var escapeHandler: EventHandlerRef?
    private var escapeRef: EventHotKeyRef?
    private let overlay = RecordingOverlay()
    private var startSound: NSSound?
    private var stopSound: NSSound?

    nonisolated func dictationState(_ state: DictationState) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.show(state) } }
    }

    // MARK: menu-bar look

    private func show(_ s: DictationState) {
        resetTimer?.invalidate()
        switch s {
        case .idle:
            setIcon(.idle, "Ready. Hold \(hotkeyLabel()) to dictate" + (startupNote.map { " (\($0))" } ?? ""))
            overlay.hide()
        case .recording:
            setIcon(.recording, "Recording... press \(hotkeyLabel()) again to stop")
            startSound?.play()
            if config.showRecordingAnimation { overlay.show() }
        case .transcribing:
            setIcon(.transcribing, "Transcribing...")
            stopSound?.play()
            if config.showRecordingAnimation { overlay.show(state: "Transcribing...") }
        case .notice(let m):
            setIcon(.notice, m)
            overlay.hide()
            resetTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.show(.idle) } }
            }
        }

        // Register/unregister Escape hotkey based on recording state
        switch s {
        case .recording: registerEscape()
        default: unregisterEscape()
        }
    }

    private func registerEscape() {
        guard escapeRef == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        var handler: EventHandlerRef?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (next, event, userData) -> OSStatus in
            if let userData {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    if let c = delegate.controller {
                        Task { @MainActor in
                            let idle = await c.isIdle
                            if !idle { await c.discard(); delegate.show(.idle) }
                        }
                    }
                }
            }
            return noErr
        }, 1, &specs, selfPtr, &handler)
        escapeHandler = handler
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4553_4350), id: 2)
        RegisterEventHotKey(53, 0, id, GetApplicationEventTarget(), 0, &ref)
        escapeRef = ref
    }

    private func unregisterEscape() {
        if let r = escapeRef { UnregisterEventHotKey(r) }
        if let h = escapeHandler { RemoveEventHandler(h) }
        escapeRef = nil; escapeHandler = nil
    }

    private enum Look { case idle, recording, transcribing, notice }

    /// Idle follows the menu-bar theme (template image). The other states are coloured so they are visible at a glance.
    private func setIcon(_ look: Look, _ text: String) {
        let (symbol, color): (String, NSColor?) = {
            switch look {
            case .idle: return ("mic", nil)
            case .recording: return ("mic.fill", .systemRed)
            case .transcribing: return ("waveform", .systemOrange)
            case .notice: return ("exclamationmark.triangle.fill", .systemYellow)
            }
        }()
        var img = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        if let color {
            img = img?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            img?.isTemplate = false
        } else {
            img?.isTemplate = true
        }
        item.button?.image = img
        item.button?.toolTip = text
        statusLine.title = text
    }

    private func comboLabel() -> String {
        let m = config.hotkeyModifiers.map { ["control": "\u{2303}", "ctrl": "\u{2303}", "option": "\u{2325}", "alt": "\u{2325}", "command": "\u{2318}", "cmd": "\u{2318}", "shift": "\u{21E7}"][$0.lowercased()] ?? $0 }.joined()
        let key = comboKeyChoices.first { $0.code == config.hotkeyKeyCode }?.name ?? "key \(config.hotkeyKeyCode)"
        return m + key
    }

    private func hotkeyLabel() -> String { optionTap.mode.isEmpty ? comboLabel() : "right \u{2325}" }

    private func hotkeyDescription() -> String {
        if !optionTap.mode.isEmpty { return "Hold the right Option key (\(String(format: "%.2f", config.holdSeconds)) s)" }
        if carbonActive { return "Hold \(comboLabel())" + (config.hotkeyMode == "rightOptionHold" ? " (fallback: right Option needs Input Monitoring)" : "") }
        return "None active"
    }

    // MARK: launch

    func applicationDidFinishLaunching(_ n: Notification) {
        // One copy only: a second launch would fight over the hotkey. Skipped when run as a bare binary (no bundle id).
        let me = NSRunningApplication.current
        if let bid = me.bundleIdentifier,
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bid && $0 != me }) {
            NSApp.terminate(nil); return
        }
        let loaded = AppConfig.load()
        config = loaded.config
        words.update(from: config)
        WavRecorder.cleanStale()
        NSApp.setActivationPolicy(config.showInDock ? .regular : .accessory)
        installMainMenu()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Welcome tour...", action: #selector(showOnboarding), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Microphone settings...", action: #selector(openMic), keyEquivalent: "")
        menu.addItem(withTitle: "Accessibility settings...", action: #selector(openAX), keyEquivalent: "")
        menu.addItem(withTitle: "Input Monitoring settings...", action: #selector(openInput), keyEquivalent: "")
        menu.addItem(withTitle: "Stop server now", action: #selector(stopServer), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dictate", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu

        buildPipeline()

        loadSounds()

        // Permissions: ask once at launch so the prompts do not appear mid-dictation.
        // The first-run tour asks for them instead, one at a time, with an explanation.
        if config.onboardingDone {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { requestMicrophoneAccess() }
            if !AXIsProcessTrusted() {
                let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self.showOnboarding() } }
        }

        runSnapshotsIfRequested()
        let ok = setupHotkey()
        if ok { if let w = loaded.warning { setIcon(.notice, w) } else { show(.idle) } }

        // Escape hotkey is registered only while recording (see registerEscape/unregisterEscape)

        Task {
            for await e in hotkeyEvents {
                switch e {
                case .down: await self.controller?.toggle(targetAppPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
                case .up: break   // toggle mode: release is ignored
                }
            }
        }

        // If the menu bar has no room, macOS silently hides our icon. Open Settings once so the user can find the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                if !self.iconVisible() && !UserDefaults.standard.bool(forKey: "shownHiddenIconHint") {
                    UserDefaults.standard.set(true, forKey: "shownHiddenIconHint")
                    UserDefaults.standard.set(SettingsTab.status.rawValue, forKey: "settingsTab")
                    self.openSettings()
                }
            }
        }
    }

    /// Client, supervisor and controller are built from the config; rebuilt when a saved setting needs it.
    private func buildPipeline() {
        let client = TranscribeClient(baseURL: URL(string: config.serverURL) ?? URL(string: AppConfig().serverURL)!,
                                      timeout: config.transcribeTimeoutSeconds, words: words)
        supervisor = ServerSupervisor(config: config, client: client)
        let w = words
        let recorder = WavRecorder(maxSeconds: config.maxRecordSeconds)
        recorder.silenceDuration = config.silenceStopSeconds
        let stager = PasteStager(poster: CGEventPoster(), restoreDelay: Double(config.clipboardRestoreMs) / 1000)
        self.stager = stager
        stager.autoPressEnter = config.autoPressEnter
        stager.onCorrectionCheck = { [weak self] pasted, current in
            guard let self else { return }
            let pairs = CorrectionExtractor.extract(original: pasted, corrected: current)
            guard !pairs.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (from, to) in pairs {
                        if self.config.replacements.contains(where: { $0.from.lowercased() == from.lowercased() }) { continue }
                        if self.config.suggestedCorrections.contains(where: { $0.from.lowercased() == from.lowercased() }) { continue }
                        self.config.suggestedCorrections.append(CorrectionSuggestion(from: from, to: to))
                    }
                    try? self.config.save()
                }
            }
        }
        recorder.onSilenceDetected = { [weak self] in
            Task { @MainActor in
                await self?.controller?.keyUp()
            }
        }
        recorder.onAudioLevel = { [weak self] power in
            guard let self, self.config.showRecordingAnimation else { return }
            self.overlay.updateLevel(power)
        }
        controller = DictationController(recorder: recorder, service: supervisor!,
                                         inserter: stager,
                                         sink: self, minSeconds: config.minSeconds, postProcess: { w.process($0) },
                                         saveAudioPath: config.saveAudioPath)
    }

    private func loadSounds() {
        let pack = config.soundPack
        if let url = Bundle.main.url(forResource: "sound_\(pack)_start", withExtension: "wav") { startSound = NSSound(contentsOf: url, byReference: true) }
        if let url = Bundle.main.url(forResource: "sound_\(pack)_stop", withExtension: "wav") { stopSound = NSSound(contentsOf: url, byReference: true) }
    }

    /// Right Option long press, or the key combination (also the fallback). Returns false if nothing could be registered.
    @discardableResult
    private func setupHotkey() -> Bool {
        startupNote = nil
        var ok = false
        if config.hotkeyMode == "rightOptionHold" {
            if optionTap.start(holdSeconds: config.holdSeconds) { ok = true }
            else { startupNote = "right \u{2325} needs Input Monitoring; using \(comboLabel()) meanwhile" }
        }
        if !ok {
            let st = hotkey.register(keyCode: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
            if st != noErr {
                setIcon(.notice, st == -9878 ? "Hotkey \(comboLabel()) is taken by another app" : "Hotkey failed (\(st))")
            } else { ok = true; carbonActive = true }
        }
        return ok
    }

    private func teardownHotkey() {
        hotkey.unregister(); carbonActive = false
        optionTap.stop()
        if let r = escapeRef { UnregisterEventHotKey(r) }
        if let h = escapeHandler { RemoveEventHandler(h) }
        escapeRef = nil; escapeHandler = nil
    }

    // MARK: settings

    private func iconVisible() -> Bool {
        guard let w = item?.button?.window else { return false }
        return w.occlusionState.contains(.visible) && NSScreen.screens.contains { $0.frame.intersects(w.frame) }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let model = SettingsModel(config: config,
                // applySettings returns nil on success and an error message on failure. A plain `??` would
                // turn the success nil into "App is closing", so the guard is explicit.
                apply: { [weak self] new in
                    guard let self else { return "App is closing" }
                    return self.applySettings(new)
                },
                stopServer: { [weak self] in self?.stopServer() },
                checkServer: { [weak self] in
                    guard let c = self?.config, let url = URL(string: c.serverURL) else { return false }
                    return await TranscribeClient(baseURL: url).healthy()
                },
                iconVisible: { [weak self] in self?.iconVisible() ?? false },
                hotkeyDescription: { [weak self] in self?.hotkeyDescription() ?? "" })
            model.showTour = { [weak self] in self?.showOnboarding() }
            settingsModel = model
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Dictate Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        // Opening again (Dock click, Spotlight, menu) shows the tab saved in defaults, then refreshes the live status.
        if let t = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settingsTab") ?? "") { settingsModel?.tab = t }
        settingsModel?.refresh()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        if let w = onboardingWindow { NSApp.activate(); w.makeKeyAndOrderFront(nil); return }
        let model = OnboardingModel(
            hotkey: { [weak self] in self?.hotkeyLabel() ?? "" },
            needsInputMonitoring: { [weak self] in self?.config.hotkeyMode == "rightOptionHold" },
            startEngine: { [weak self] in
                guard let s = self?.supervisor else { return }
                Task { try? await s.ensureReady() }
            },
            checkEngine: { [weak self] in
                guard let c = self?.config, let url = URL(string: c.serverURL) else { return false }
                return await TranscribeClient(baseURL: url).healthy()
            },
            finish: { [weak self] in self?.finishOnboarding() })
        onboardingModel = model
        let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
        w.title = "Welcome to Dictate"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        onboardingWindow = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        if !config.onboardingDone {
            config.onboardingDone = true
            try? config.save()
            // Ask for anything the tour skipped, the way a normal launch does.
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { requestMicrophoneAccess() }
        }
        onboardingWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            onboardingModel?.stop(); onboardingWindow = nil; onboardingModel = nil
            if !config.onboardingDone { config.onboardingDone = true; try? config.save() }
            return
        }
        if let t = settingsModel?.tab {
            config.settingsTab = t.rawValue
            try? config.save()
        }
        settingsModel?.stopRefreshing()
    }

    /// Dock click, or opening Dictate again from Finder or Spotlight: show the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    /// Save to disk, then make the change live. Returns an error message or nil.
    private func applySettings(_ requested: AppConfig) -> String? {
        let new = requested.validated().config
        // Preserve correction suggestions that arrived while the settings window was open.
        let existingSuggestions = config.suggestedCorrections
        var merged = new
        merged.onboardingDone = merged.onboardingDone || config.onboardingDone
        for s in existingSuggestions where !merged.suggestedCorrections.contains(where: { $0.id == s.id }) {
            merged.suggestedCorrections.append(s)
        }
        if merged.hotkeyMode == "combo" && new.hotkeyModifiers.isEmpty { return "Choose at least one modifier for the key combination." }
        do { try merged.save() } catch { return "Could not save the settings file: \(error.localizedDescription)" }
        let old = config
        config = merged
        words.update(from: merged)
        if let s = self.stager { s.autoPressEnter = merged.autoPressEnter }
        // Switch server script based on model backend (persist to disk)
        // Each backend has its own script and default port; a custom address is left alone.
        // An old "whisper" setting (removed) falls back to Parakeet.
        let backends = ["whistle": ("whistle_srv.py", "http://127.0.0.1:8773"),
                        "parakeet": ("parakeet_srv.py", "http://127.0.0.1:8774")]
        if backends[merged.modelBackend] == nil { merged.modelBackend = "parakeet" }
        let (script, url) = backends[merged.modelBackend]!
        merged.serverScript = (merged.serverScript as NSString).deletingLastPathComponent + "/" + script
        let defaultURLs = Set(backends.values.map { $0.1 } + ["http://127.0.0.1:8772"])
        if defaultURLs.contains(merged.serverURL) { merged.serverURL = url }
        // Re-save with the corrected paths
        try? merged.save()

        let hotkeyChanged = (old.hotkeyMode, old.holdSeconds, old.hotkeyKeyCode, old.hotkeyModifiers) != (merged.hotkeyMode, merged.holdSeconds, merged.hotkeyKeyCode, merged.hotkeyModifiers)
        if hotkeyChanged {
            teardownHotkey()
            if setupHotkey() { show(.idle) }
        }
        NSApp.setActivationPolicy(merged.showInDock ? .regular : .accessory)

        let engineChanged = (old.serverURL, old.pythonPath, old.serverScript, old.idleSeconds) != (merged.serverURL, merged.pythonPath, merged.serverScript, merged.idleSeconds)
        let pipelineChanged = engineChanged || old.silenceStopSeconds != new.silenceStopSeconds || old.saveAudioPath != new.saveAudioPath || (old.minSeconds, old.maxRecordSeconds, old.clipboardRestoreMs, old.transcribeTimeoutSeconds, old.serverStartTimeoutSeconds)
            != (new.minSeconds, new.maxRecordSeconds, new.clipboardRestoreMs, new.transcribeTimeoutSeconds, new.serverStartTimeoutSeconds)
        if pipelineChanged {
            let oldSupervisor = supervisor
            if engineChanged { Task { await oldSupervisor?.stopServer() } }   // restarts with the new settings on the next dictation
            buildPipeline()
        }
        if old.soundPack != new.soundPack { loadSounds() }
        if !hotkeyChanged { show(.idle) }
        return nil
    }

    // MARK: menus

    /// A real main menu: Cmd+Q, Cmd+, and the text-field shortcuts (Cut, Copy, Paste, Select All) the Settings window needs.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dictate", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    @objc private func openMic() { open("Privacy_Microphone") }
    @objc private func openAX() { open("Privacy_Accessibility") }
    @objc private func openInput() { open("Privacy_ListenEvent") }
    private func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
    @objc private func stopServer() { let s = supervisor; Task { await s?.stopServer() } }
    @objc private func quit() {
        teardownHotkey()
        let sup = supervisor
        Task {
            // Stop the server only if this app started it.
            if let sup, await sup.launchCount > 0 { await sup.stopServer() }
            await MainActor.run { NSApp.terminate(nil) }
        }
    }
}
