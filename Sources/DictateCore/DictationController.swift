import Foundation

public enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    /// A short message for the user (error, or text left on the clipboard). The controller is idle again.
    case notice(String)
}

public protocol AudioRecorder: AnyObject {
    func start() throws
    /// Stop and return the recorded file, or nil if nothing was captured.
    func stop() -> URL?
}

public protocol StatusSink: AnyObject {
    func dictationState(_ state: DictationState)
}

/// Push-to-talk flow: key down starts recording (and warms the server), key up transcribes and pastes.
/// Events must be delivered in order. keyUp returns at once; `waitUntilIdle()` awaits the work (tests, shutdown).
/// A key press while a transcription runs is ignored.
public actor DictationController {
    private let recorder: AudioRecorder
    private let service: TranscriptionService
    private let inserter: TextInserter
    private weak var sink: StatusSink?
    private let minSeconds: Double
    private let postProcess: @Sendable (String) -> String
    private let saveAudioPath: String
    private var targetAppPID: pid_t?
    private var state: DictationState = .idle
    private var warm: Task<Void, Error>?
    private var work: Task<Void, Never>?

    public init(recorder: AudioRecorder, service: TranscriptionService, inserter: TextInserter,
                sink: StatusSink?, minSeconds: Double = 0.3, postProcess: @escaping @Sendable (String) -> String = { $0 },
                saveAudioPath: String = "") {
        self.recorder = recorder; self.service = service; self.inserter = inserter
        self.sink = sink; self.minSeconds = minSeconds; self.postProcess = postProcess
        self.saveAudioPath = saveAudioPath
    }

    public var isIdle: Bool { state == .idle }

    private func set(_ s: DictationState) {
        switch s { case .notice: state = .idle; default: state = s }
        sink?.dictationState(s)
    }

    public func keyDown(targetAppPID: pid_t? = nil) {
        guard state == .idle else { return }
        self.targetAppPID = targetAppPID
        do { try recorder.start() } catch {
            set(.notice("Microphone unavailable: \(error.localizedDescription)")); return
        }
        set(.recording)
        let svc = service
        warm = Task { try await svc.ensureReady() }
    }

    public func keyUp() {
        guard state == .recording else { return }
        let url = recorder.stop()
        set(.transcribing)
        work = Task { await self.process(url) }
    }

    public func waitUntilIdle() async {
        if let w = work { await w.value }
        work = nil
    }

    /// Toggle mode: one press starts recording, the next press stops and transcribes.
    public func toggle(targetAppPID: pid_t? = nil) {
        if state == .idle { keyDown(targetAppPID: targetAppPID) }
        else if state == .recording { keyUp() }
        // While transcribing, ignore presses.
    }

    public func discard() {
        guard state == .recording else { return }
        let url = recorder.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        set(.idle)
    }

    private func process(_ url: URL?) async {
        // The audio file is deleted as soon as its bytes are in memory, on every path.
        var data: Data?
        if let url {
            data = try? Data(contentsOf: url)
            // Save a copy for training if configured
            if !saveAudioPath.isEmpty {
                let expanded = (saveAudioPath as NSString).expandingTildeInPath
                let dir = URL(fileURLWithPath: expanded)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let dest = dir.appendingPathComponent("dictate-\(ts).wav")
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            try? FileManager.default.removeItem(at: url)
        }
        defer { warm = nil }
        guard let wav = data else { set(.notice("No audio was captured")); return }
        guard let info = WAVInfo.parse(wav) else { set(.notice("The recording was not valid audio")); return }
        if info.duration < minSeconds { set(.idle); return }   // accidental tap: do nothing
        let text: String
        do {
            try await warm?.value
            text = postProcess(try await service.transcribe(wav))
        } catch {
            set(.notice("Transcription failed: \(error)")); return
        }
        if text.isEmpty { set(.notice("No speech detected")); return }
        switch await inserter.insert(text, intoAppPID: targetAppPID) {
        case .pasted: set(.idle)
        case .copiedOnly(let why): set(.notice("Copied: \(why)"))
        }
    }
}
