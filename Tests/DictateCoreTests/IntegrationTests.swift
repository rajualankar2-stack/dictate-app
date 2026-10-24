import AppKit
import XCTest
@testable import DictateCore

/// Real controller + real supervisor + real Python server + real PasteStager.
/// Only the microphone (a recorded fixture) and the Cmd+V key press (a fake) are replaced.
/// Run:  DICTATE_INTEGRATION=1 swift test --filter IntegrationTests
final class FixtureRecorder: AudioRecorder {
    let fixture: URL
    init(_ f: URL) { fixture = f }
    func start() throws {}
    func stop() -> URL? {
        let u = URL(fileURLWithPath: NSTemporaryDirectory() + "fx-\(UUID().uuidString).wav")
        try? FileManager.default.copyItem(at: fixture, to: u)
        return u
    }
}

final class IntegrationTests: XCTestCase {
    static let data = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tests-data")

    func testColdStartOverlapsSpeechThenWarmDictation() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DICTATE_INTEGRATION"] == "1", "set DICTATE_INTEGRATION=1")
        var cfg = AppConfig(); cfg.serverStartTimeoutSeconds = 90
        let client = TranscribeClient(baseURL: URL(string: cfg.serverURL)!, timeout: 60)
        let alreadyUp = await client.healthy()
        try XCTSkipIf(alreadyUp, "a server already answers on \(cfg.serverURL); stop it first")
        let sup = ServerSupervisor(config: cfg, client: client)
        addTeardownBlock { await sup.stopServer() }

        let pb = NSPasteboard(name: NSPasteboard.Name("dictate-int-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("my clipboard before dictating", forType: .string)
        let poster = FakePoster()
        var pasted: [String] = []
        poster.onPost = { pasted.append(pb.string(forType: .string) ?? "<none>") }
        let sink = FakeSink()
        let c = DictationController(recorder: FixtureRecorder(Self.data.appendingPathComponent("sap1.wav")), service: sup,
                                    inserter: PasteStager(pasteboard: pb, poster: poster, restoreDelay: 0.1), sink: sink)

        // 1. Cold: the user "speaks" for 6 s while the server loads in the background.
        await c.keyDown()
        try await Task.sleep(nanoseconds: 6_000_000_000)
        let t0 = Date()
        await c.keyUp(); await c.waitUntilIdle()
        let coldAfterRelease = Date().timeIntervalSince(t0)
        XCTAssertEqual(pasted.count, 1)
        XCTAssertTrue(pasted.first?.contains("MIGO") == true && pasted.first?.contains("MIRO") == true, "got: \(pasted)")
        XCTAssertLessThan(coldAfterRelease, 3.0, "model loading should have finished while speaking; took \(coldAfterRelease)s after release")
        XCTAssertEqual(pb.string(forType: .string), "my clipboard before dictating")
        print("cold: \(String(format: "%.2f", coldAfterRelease)) s from key release to pasted")

        // 2. Warm, a different clip.
        let c2 = DictationController(recorder: FixtureRecorder(Self.data.appendingPathComponent("sap2.wav")), service: sup,
                                     inserter: PasteStager(pasteboard: pb, poster: poster, restoreDelay: 0.1), sink: sink)
        await c2.keyDown()
        let t1 = Date()
        await c2.keyUp(); await c2.waitUntilIdle()
        let warm = Date().timeIntervalSince(t1)
        XCTAssertEqual(pasted.count, 2)
        XCTAssertTrue(pasted.last?.contains("S/4HANA") == true && pasted.last?.contains("IDoc") == true, "got: \(pasted)")
        XCTAssertLessThan(warm, 3.0)
        print("warm: \(String(format: "%.2f", warm)) s from key release to pasted")
        XCTAssertEqual(pb.string(forType: .string), "my clipboard before dictating")
        XCTAssertEqual(sink.states.filter { if case .notice = $0 { return true } else { return false } }.count, 0, "\(sink.states)")
    }
}
