import AppKit
import AVFoundation
import Carbon.HIToolbox
import DictateCore

// MARK: - Hotkey (Carbon RegisterEventHotKey: reports key press AND release, needs no Accessibility permission)

enum HotkeyEvent { case down, up }

/// Carbon calls the handler on the main thread. The stream is the one ordered hand-off to the controller.
private let hotkeyStreamPair: (stream: AsyncStream<HotkeyEvent>, continuation: AsyncStream<HotkeyEvent>.Continuation) = {
    var cont: AsyncStream<HotkeyEvent>.Continuation!
    let s = AsyncStream<HotkeyEvent> { cont = $0 }
    return (s, cont)
}()

var hotkeyEvents: AsyncStream<HotkeyEvent> { hotkeyStreamPair.stream }

private func hotkeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed): hotkeyStreamPair.continuation.yield(.down)
    case UInt32(kEventHotKeyReleased): hotkeyStreamPair.continuation.yield(.up)
    default: return OSStatus(eventNotHandledErr)
    }
    return noErr
}

final class Hotkey {
    private var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?

    static func carbonModifiers(_ names: [String]) -> UInt32 {
        names.reduce(0) { acc, n in
            switch n.lowercased() {
            case "control", "ctrl": return acc | UInt32(controlKey)
            case "option", "alt": return acc | UInt32(optionKey)
            case "command", "cmd": return acc | UInt32(cmdKey)
            case "shift": return acc | UInt32(shiftKey)
            default: return acc
            }
        }
    }

    /// Returns noErr on success. eventHotKeyExistsErr (-9878) means another app owns this combination.
    func register(keyCode: UInt32, modifiers: [String]) -> OSStatus {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var st = InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 2, &specs, nil, &handler)
        guard st == noErr else { return st }
        let id = EventHotKeyID(signature: OSType(0x4449_4354), id: 1)   // 'DICT'
        st = RegisterEventHotKey(keyCode, Hotkey.carbonModifiers(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        return st
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}

// MARK: - Right Option long press (modifier-only keys cannot use Carbon hotkeys, so this watches events)

private func optionTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let info { Unmanaged<OptionHoldTap>.fromOpaque(info).takeUnretainedValue().handle(type, event) }
    return Unmanaged.passUnretained(event)   // never change or swallow an event
}

/// Watches the right Option key. Runs on the main run loop, so the detector is only touched from the main thread.
final class OptionHoldTap {
    static let rightOptionKeyCode: Int64 = 61
    static let rightOptionDeviceMask: UInt64 = 0x40   // NX_DEVICERALTKEYMASK: set only while the RIGHT Option key is down

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector: LongPressDetector?
    /// "listenOnly" (cannot delay typing, needs Input Monitoring) or "active" (needs Accessibility). Empty = not running.
    private(set) var mode = ""

    func start(holdSeconds: Double) -> Bool {
        detector = LongPressDetector(threshold: holdSeconds) { e in
            hotkeyStreamPair.continuation.yield(e == .begin ? .down : .up)
        }
        func bit(_ t: CGEventType) -> UInt64 { 1 << UInt64(t.rawValue) }
        let mask = CGEventMask(bit(.flagsChanged) | bit(.keyDown) | bit(.leftMouseDown) | bit(.rightMouseDown))
        let me = Unmanaged.passUnretained(self).toOpaque()
        for (options, name) in [(CGEventTapOptions.listenOnly, "listenOnly"), (CGEventTapOptions.defaultTap, "active")] {
            if let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                                         eventsOfInterest: mask, callback: optionTapCallback, userInfo: me) {
                let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
                CGEvent.tapEnable(tap: t, enable: true)
                tap = t; source = src; mode = name
                return true
            }
        }
        detector = nil
        return false
    }

    func stop() {
        detector?.reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; detector = nil; mode = ""
    }

    func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            detector?.reset()   // a release may have been missed: end any hold so recording cannot get stuck
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            if event.getIntegerValueField(.keyboardEventKeycode) == OptionHoldTap.rightOptionKeyCode {
                detector?.keyChanged(isDown: event.flags.rawValue & OptionHoldTap.rightOptionDeviceMask != 0)
            } else {
                detector?.otherKeyPressed()
            }
        case .keyDown, .leftMouseDown, .rightMouseDown:
            detector?.otherKeyPressed()
        default:
            break
        }
    }
}

// MARK: - Recorder (16 kHz mono 16-bit WAV, the format the server wants; no audio-tap callback, so no actor trap)

enum RecorderError: Error, CustomStringConvertible {
    case micNotAuthorized(AVAuthorizationStatus)
    case couldNotStart

    var description: String {
        switch self {
        case .micNotAuthorized(let s): return "microphone permission is \(s == .notDetermined ? "not granted yet" : "denied")"
        case .couldNotStart: return "the recorder did not start"
        }
    }
}

final class WavRecorder: NSObject, AudioRecorder, AVAudioRecorderDelegate {
    static var directory: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.raj.dictate")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        var mu = u; try? mu.setResourceValues(v)   // leftover audio after a crash must not enter a backup
        return u
    }

    private var recorder: AVAudioRecorder?
    private var url: URL?
    private let maxSeconds: Double
    private var silenceTimer: Timer?
    private var silenceStart: Date?
    public var onSilenceDetected: (() -> Void)?
    public var onAudioLevel: ((Float) -> Void)?
    public var silenceThresholdDb: Double = -45
    public var silenceDuration: Double = 3.0

    init(maxSeconds: Double) { self.maxSeconds = maxSeconds }

    /// Remove audio left behind by a crash.
    static func cleanStale() {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix("dictate-") {
            try? fm.removeItem(at: f)
        }
    }

    func start() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else { throw RecorderError.micNotAuthorized(status) }
        let u = WavRecorder.directory.appendingPathComponent("dictate-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let r = try AVAudioRecorder(url: u, settings: settings)
        r.isMeteringEnabled = true
        r.delegate = self
        guard r.prepareToRecord(), r.record(forDuration: maxSeconds) else { throw RecorderError.couldNotStart }
        recorder = r; url = u
        startSilenceMonitoring()
    }

    private func startSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceStart = nil
        guard silenceDuration > 0 else { return }   // 0 means disabled
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let r = self.recorder, r.isRecording else { return }
            r.updateMeters()
            let power = r.averagePower(forChannel: 0)
            DispatchQueue.main.async { self.onAudioLevel?(power) }
            if Double(power) < self.silenceThresholdDb {
                if self.silenceStart == nil { self.silenceStart = Date() }
                if let start = self.silenceStart, Date().timeIntervalSince(start) >= self.silenceDuration {
                    self.stopSilenceMonitoring()
                    DispatchQueue.main.async { self.onSilenceDetected?() }
                }
            } else {
                self.silenceStart = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    private func stopSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceStart = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === self.recorder else { return }
        stopSilenceMonitoring()
        DispatchQueue.main.async { self.onSilenceDetected?() }
    }

    func stop() -> URL? {
        stopSilenceMonitoring()
        recorder?.stop()
        defer { recorder = nil; url = nil }
        return url
    }
}

/// Ask for microphone access. The completion runs on a system queue, so it lives in a plain function, not in an actor type.
func requestMicrophoneAccess() {
    AVCaptureDevice.requestAccess(for: .audio) { _ in }
}

// MARK: - Paste key

struct CGEventPoster: KeyPoster {
    func postCommandV() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        // Secure Event Input (set system-wide by any app with a password field or Secure Keyboard Entry) blocks
        // other apps from READING keys. It does not block posting Cmd+V, so it is not checked here: a guard
        // would switch dictation off whenever some unrelated app left it on.
        // The user may still hold Control and Option from the hotkey. Wait (up to 1 s) so they do not mix into Cmd+V.
        let deadline = Date().addingTimeInterval(1)
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        while Date() < deadline, !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: held) { usleep(10_000) }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    func postReturn() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false) else { return false }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
