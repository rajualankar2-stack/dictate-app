import XCTest
@testable import DictateCore

final class FakeRecorder: AudioRecorder {
    var startError: Error?
    var seconds: Double = 1.0
    var returnNil = false
    var garbage = false
    private(set) var starts = 0
    private(set) var files: [URL] = []
    func start() throws { starts += 1; if let startError { throw startError } }
    func stop() -> URL? {
        if returnNil { return nil }
        let u = URL(fileURLWithPath: NSTemporaryDirectory() + "fake-\(UUID().uuidString).wav")
        try? (garbage ? Data("garbage".utf8) : makeWAV(seconds: seconds)).write(to: u)
        files.append(u)
        return u
    }
}

final class FakeService: TranscriptionService, @unchecked Sendable {
    private let l = NSLock()
    private var _ready = 0, _tx = 0
    var readyError: Error?
    var readyDelay: UInt64 = 0
    var transcribeDelay: UInt64 = 0
    var result: Result<String, Error> = .success("hello world")
    var readyCalls: Int { l.lock(); defer { l.unlock() }; return _ready }
    var transcribeCalls: Int { l.lock(); defer { l.unlock() }; return _tx }
    func ensureReady() async throws {
        l.lock(); _ready += 1; l.unlock()
        if readyDelay > 0 { try await Task.sleep(nanoseconds: readyDelay) }
        if let readyError { throw readyError }
    }
    func transcribe(_ wav: Data) async throws -> String {
        l.lock(); _tx += 1; l.unlock()
        if transcribeDelay > 0 { try await Task.sleep(nanoseconds: transcribeDelay) }
        return try result.get()
    }
}

final class FakeInserter: TextInserter, @unchecked Sendable {
    var result: PasteResult = .pasted
    private(set) var texts: [String] = []
    func insert(_ text: String, intoAppPID: pid_t?) async -> PasteResult { texts.append(text); return result }
}

final class FakeSink: StatusSink {
    private(set) var states: [DictationState] = []
    func dictationState(_ state: DictationState) { states.append(state) }
}

struct Boom: Error, CustomStringConvertible { var description = "boom" }

final class DictationControllerTests: XCTestCase {
    var rec: FakeRecorder!, svc: FakeService!, ins: FakeInserter!, sink: FakeSink!, c: DictationController!

    override func setUp() {
        rec = FakeRecorder(); svc = FakeService(); ins = FakeInserter(); sink = FakeSink()
        c = DictationController(recorder: rec, service: svc, inserter: ins, sink: sink, minSeconds: 0.3)
    }

    private func cycle() async { await c.keyDown(); await c.keyUp(); await c.waitUntilIdle() }
    private func noFilesLeft() -> Bool { rec.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }

    func testNormalFlow() async {
        await cycle()
        XCTAssertEqual(sink.states, [.recording, .transcribing, .idle])
        XCTAssertEqual(ins.texts, ["hello world"]); XCTAssertEqual(svc.transcribeCalls, 1)
        XCTAssertTrue(noFilesLeft(), "audio must be deleted")
    }

    func testServerWarmsAtKeyDownNotKeyUp() async {
        await c.keyDown()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(svc.readyCalls, 1, "loading must overlap speaking")
        XCTAssertEqual(svc.transcribeCalls, 0)
        await c.keyUp(); await c.waitUntilIdle()
        XCTAssertEqual(svc.readyCalls, 1)
    }

    func testSlowWarmupIsAwaitedBeforeTranscribing() async {
        svc.readyDelay = 300_000_000
        await c.keyDown(); await c.keyUp()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(svc.transcribeCalls, 0, "must not transcribe before the server is ready")
        await c.waitUntilIdle()
        XCTAssertEqual(svc.transcribeCalls, 1); XCTAssertEqual(ins.texts, ["hello world"])
    }

    func testShortTapDoesNothing() async {
        rec.seconds = 0.1
        await cycle()
        XCTAssertEqual(svc.transcribeCalls, 0); XCTAssertTrue(ins.texts.isEmpty)
        XCTAssertEqual(sink.states.last, .idle); XCTAssertTrue(noFilesLeft())
    }

    func testClipAtThresholdIsTranscribed() async {
        rec.seconds = 0.31
        await cycle()
        XCTAssertEqual(svc.transcribeCalls, 1)
    }

    func testKeyUpWithoutKeyDownIsIgnored() async {
        await c.keyUp(); await c.waitUntilIdle()
        XCTAssertTrue(sink.states.isEmpty); XCTAssertEqual(rec.starts, 0)
    }

    func testDoubleKeyDownStartsRecorderOnce() async {
        await c.keyDown(); await c.keyDown()
        XCTAssertEqual(rec.starts, 1)
        await c.keyUp(); await c.waitUntilIdle()
        XCTAssertEqual(svc.transcribeCalls, 1)
    }

    func testKeyDownWhileTranscribingIsIgnoredThenNextCycleWorks() async {
        svc.transcribeDelay = 300_000_000
        await c.keyDown(); await c.keyUp()
        await c.keyDown()   // pressed again while transcribing
        XCTAssertEqual(rec.starts, 1)
        await c.keyUp()     // ignored too
        await c.waitUntilIdle()
        XCTAssertEqual(ins.texts.count, 1)
        svc.transcribeDelay = 0
        await cycle()
        XCTAssertEqual(rec.starts, 2); XCTAssertEqual(ins.texts.count, 2)
    }

    func testMicFailureShowsNoticeAndRecovers() async {
        rec.startError = Boom()
        await c.keyDown()
        guard case .notice(let m)? = sink.states.last else { return XCTFail("\(sink.states)") }
        XCTAssertTrue(m.contains("Microphone unavailable"))
        let idle = await c.isIdle; XCTAssertTrue(idle)
        rec.startError = nil
        await cycle()
        XCTAssertEqual(ins.texts, ["hello world"])
    }

    func testTranscriptionErrorShowsNoticeDeletesAudioAndRecovers() async {
        svc.result = .failure(TranscribeError.serverError(500, "model error"))
        await cycle()
        guard case .notice(let m)? = sink.states.last else { return XCTFail("\(sink.states)") }
        XCTAssertTrue(m.contains("Transcription failed")); XCTAssertTrue(ins.texts.isEmpty); XCTAssertTrue(noFilesLeft())
        svc.result = .success("again")
        await cycle()
        XCTAssertEqual(ins.texts, ["again"])
    }

    func testWarmupFailureShowsNoticeAndInsertsNothing() async {
        svc.readyError = ServerStartError.launchFailed("no python")
        await cycle()
        guard case .notice(let m)? = sink.states.last else { return XCTFail("\(sink.states)") }
        XCTAssertTrue(m.contains("no python")); XCTAssertTrue(ins.texts.isEmpty); XCTAssertEqual(svc.transcribeCalls, 0)
    }

    func testEmptyTextIsNoticeNotPaste() async {
        svc.result = .success("")
        await cycle()
        XCTAssertEqual(sink.states.last, .notice("No speech detected")); XCTAssertTrue(ins.texts.isEmpty)
    }

    func testCopiedOnlyIsReportedToUser() async {
        ins.result = .copiedOnly(reason: "paste is not permitted")
        await cycle()
        guard case .notice(let m)? = sink.states.last else { return XCTFail("\(sink.states)") }
        XCTAssertTrue(m.contains("Copied"))
    }

    func testRecorderReturningNothing() async {
        rec.returnNil = true
        await cycle()
        XCTAssertEqual(sink.states.last, .notice("No audio was captured")); XCTAssertEqual(svc.transcribeCalls, 0)
    }

    func testInvalidAudioFileIsRejectedAndDeleted() async {
        rec.garbage = true
        await cycle()
        XCTAssertEqual(sink.states.last, .notice("The recording was not valid audio"))
        XCTAssertEqual(svc.transcribeCalls, 0); XCTAssertTrue(noFilesLeft())
    }

    func testTwentyRapidCyclesAllSucceed() async {
        for _ in 0..<20 { await cycle() }
        XCTAssertEqual(rec.starts, 20); XCTAssertEqual(ins.texts.count, 20); XCTAssertTrue(noFilesLeft())
        let idle = await c.isIdle; XCTAssertTrue(idle)
    }
}
