import AppKit
import AVFoundation
import SwiftUI

enum TourStep: Int, CaseIterable { case welcome, setup, tryIt, done }

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: TourStep = .welcome
    @Published var micOK = false
    @Published var micDenied = false
    @Published var axOK = false
    @Published var inputOK = false
    @Published var engineReady = false
    @Published var practiceText = ""

    let hotkey: () -> String
    let needsInputMonitoring: () -> Bool
    let startEngine: () -> Void
    let checkEngine: () async -> Bool
    let finish: () -> Void
    private var timer: Timer?

    init(hotkey: @escaping () -> String, needsInputMonitoring: @escaping () -> Bool, startEngine: @escaping () -> Void,
         checkEngine: @escaping () async -> Bool, finish: @escaping () -> Void) {
        self.hotkey = hotkey; self.needsInputMonitoring = needsInputMonitoring
        self.startEngine = startEngine; self.checkEngine = checkEngine; self.finish = finish
        refresh()
    }

    var permissionsReady: Bool { micOK && axOK && (!needsInputMonitoring() || inputOK) }
    var landed: Bool { !practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start() {
        startEngine()   // load the model while the person reads, so the practice step is instant
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        micOK = mic == .authorized; micDenied = mic == .denied || mic == .restricted
        axOK = AXIsProcessTrusted()
        inputOK = CGPreflightListenEventAccess()
        Task { engineReady = await checkEngine() }
    }

    func allowMic() {
        if micDenied { open("Privacy_Microphone") } else { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
    }
    func allowAccessibility() { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
    func allowInput() { _ = CGRequestListenEventAccess(); open("Privacy_ListenEvent") }
    private func open(_ pane: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!) }

    func next() { if let s = TourStep(rawValue: step.rawValue + 1) { step = s } else { finish() } }
    func back() { if let s = TourStep(rawValue: step.rawValue - 1) { step = s } }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); engineStatus }.padding(.horizontal, 24).padding(.top, 14).frame(height: 40)
            Spacer(minLength: 0)
            Group {
                switch model.step {
                case .welcome: welcome
                case .setup: setup
                case .tryIt: tryIt
                case .done: done
                }
            }
            .frame(width: 440)
            .transition(.opacity)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 640, height: 500)
        .background(DS.panelBG)
        .animation(.easeOut(duration: 0.15), value: model.step)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var engineStatus: some View {
        HStack(spacing: 6) {
            if model.engineReady {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                Text("Speech model ready").font(.system(size: 12)).foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Starting speech model…").font(.system(size: 12)).foregroundStyle(DS.muted)
            }
        }
    }

    private func titleBlock(_ title: String, _ body: String?) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
            if let body { Text(body).font(.system(size: 14)).foregroundStyle(DS.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private var welcome: some View {
        titleBlock("Welcome to Dictate",
                   "Press a key, say what you mean, and Dictate types it wherever your cursor is. Your voice is transcribed on this Mac.")
    }

    private var setup: some View {
        VStack(spacing: 22) {
            titleBlock("Let Dictate hear you and type for you", nil)
            Card {
                permissionRow("mic", "Microphone", "Hears you only while you record", ok: model.micOK,
                              primary: !model.micOK, divider: true, action: model.allowMic)
                permissionRow("character.cursor.ibeam", "Accessibility", "Pastes your words in any app",
                              ok: model.axOK, primary: model.micOK && !model.axOK, divider: model.needsInputMonitoring(), action: model.allowAccessibility)
                if model.needsInputMonitoring() {
                    permissionRow("keyboard", "Input Monitoring", "Lets the right Option key start a recording",
                                  ok: model.inputOK, primary: model.micOK && model.axOK && !model.inputOK, divider: false, action: model.allowInput)
                }
            }
            if model.micDenied { Text("Microphone is off. Switch Dictate on in System Settings, then come back.").font(.system(size: 11)).foregroundStyle(.orange) }
        }
    }

    private func permissionRow(_ icon: String, _ title: String, _ detail: String, ok: Bool, primary: Bool, divider: Bool,
                               action: @escaping () -> Void) -> some View {
        SettingRow(icon: icon, title: title, detail: detail, divider: divider) {
            if ok {
                HStack(spacing: 5) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Allowed").font(.system(size: 12)).foregroundStyle(DS.muted) }
            } else {
                ActionButton(title: "Allow", primary: primary, action: action)
            }
        }
    }

    private var tryIt: some View {
        VStack(spacing: 18) {
            titleBlock("Give it a try", nil)
            HStack(spacing: 6) {
                Text("Press").foregroundStyle(DS.muted)
                Keycap(label: model.hotkey())
                Text("say a sentence, then press it again.").foregroundStyle(DS.muted)
            }.font(.system(size: 14))
            PracticeField(text: $model.practiceText)
                .frame(height: 96)
                .background(DS.cardBG, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.landed ? Color.green.opacity(0.6) : DS.hairline, lineWidth: 1))
            if model.landed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("That's it. Dictate pastes wherever your cursor is, in any app.").foregroundStyle(.green)
                }.font(.system(size: 13))
            } else {
                Text("Your words appear in the box.").font(.system(size: 12)).foregroundStyle(DS.faint)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            titleBlock("You're all set", "Dictate lives in the menu bar. Open its settings there to change the shortcut, the letter case and your word lists.")
            HStack(spacing: 6) { Keycap(label: model.hotkey()); Text("starts and stops a recording").font(.system(size: 13)).foregroundStyle(DS.muted) }
        }
    }

    private var footer: some View {
        HStack {
            HStack {
                if model.step != .welcome { ActionButton(title: "Back") { model.back() } }
            }.frame(width: 230, alignment: .leading)
            Spacer()
            StepDots(count: TourStep.allCases.count, current: model.step.rawValue)
            Spacer()
            HStack(spacing: 10) {
                if model.step == .setup || model.step == .tryIt { Button("Skip") { model.finish() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DS.muted) }
                switch model.step {
                case .welcome: ActionButton(title: "Get started", primary: true, trailingArrow: true) { model.next() }
                case .setup: ActionButton(title: "Continue", primary: model.permissionsReady, disabled: !model.permissionsReady, trailingArrow: true) { model.next() }
                case .tryIt: ActionButton(title: "Continue", primary: model.landed, trailingArrow: true) { model.next() }
                case .done: ActionButton(title: "Start using Dictate", primary: true) { model.finish() }
                }
            }.frame(width: 230, alignment: .trailing)
        }
        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 10)
    }
}

/// A plain multi-line text view that takes focus, so a dictation can paste into it.
struct PracticeField: NSViewRepresentable {
    @Binding var text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 14)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.isRichText = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tv = nsView.documentView as? NSTextView, tv.string != text { tv.string = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PracticeField
        init(_ p: PracticeField) { parent = p }
        func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { parent.text = tv.string } }
    }
}
