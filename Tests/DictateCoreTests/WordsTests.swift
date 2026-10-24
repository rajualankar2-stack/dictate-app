import XCTest
@testable import DictateCore

final class TextReplacerTests: XCTestCase {
    private func r(_ pairs: (String, String)...) -> [Replacement] { pairs.map { Replacement(from: $0.0, to: $0.1) } }

    func testBasicReplacement() {
        XCTAssertEqual(TextReplacer.apply("use cloud code today", r(("cloud code", "Claude Code"))), "use Claude Code today")
    }
    func testIgnoresCase() {
        XCTAssertEqual(TextReplacer.apply("Cloud CODE is fine", r(("cloud code", "Claude Code"))), "Claude Code is fine")
    }
    func testWholeWordsOnly() {
        XCTAssertEqual(TextReplacer.apply("the cat concatenates", r(("cat", "dog"))), "the dog concatenates")
        XCTAssertEqual(TextReplacer.apply("scatter", r(("cat", "dog"))), "scatter")
    }
    func testPunctuationNextToTheWordStillMatches() {
        XCTAssertEqual(TextReplacer.apply("call Bob, then Bob.", r(("bob", "Robert"))), "call Robert, then Robert.")
    }
    func testSpecialCharactersAreLiteral() {
        XCTAssertEqual(TextReplacer.apply("pay a.b now", r(("a.b", "X"))), "pay X now")
        XCTAssertEqual(TextReplacer.apply("pay axb now", r(("a.b", "X"))), "pay axb now", "the dot must not act as a wildcard")
        XCTAssertEqual(TextReplacer.apply("the S/4 system", r(("s/4", "S/4HANA"))), "the S/4HANA system")
    }
    func testReplacementTextIsLiteral() {
        XCTAssertEqual(TextReplacer.apply("price is cheap", r(("cheap", "$1 \\0 &"))), "price is $1 \\0 &")
    }
    func testRulesRunTopToBottom() {
        XCTAssertEqual(TextReplacer.apply("a", r(("a", "b"), ("b", "c"))), "c")
    }
    func testEmptyFromIsSkippedAndEmptyToDeletes() {
        XCTAssertEqual(TextReplacer.apply("hello there", r(("", "X"), ("   ", "Y"))), "hello there")
        XCTAssertEqual(TextReplacer.apply("um hello", r(("um", ""))), " hello")
    }
    func testUnicodeWords() {
        XCTAssertEqual(TextReplacer.apply("café là", r(("café", "cafe"))), "cafe là")
        XCTAssertEqual(TextReplacer.apply("cafés", r(("café", "cafe"))), "cafés")
    }
    func testNoRulesLeavesTextUnchanged() {
        XCTAssertEqual(TextReplacer.apply("anything at all", []), "anything at all")
    }
}

final class VocabularyAndSaveTests: XCTestCase {
    private func tmpPath() -> String { NSTemporaryDirectory() + "dictate-\(UUID().uuidString)/config.json" }

    func testCleanVocabulary() {
        let out = AppConfig.cleanVocabulary([" Novonesis ", "novonesis", "", "   ", "a,b", String(repeating: "x", count: 41), "Line\nbreak", "Kushi", "MIGO"])
        XCTAssertEqual(out, ["Novonesis", "Kushi", "MIGO"])
    }
    func testVocabularyIsCapped() {
        let many = (0..<80).map { "term\($0)" }
        XCTAssertEqual(AppConfig.cleanVocabulary(many).count, AppConfig.maxVocabulary)
    }
    func testValidatedTidiesWordListsAndReports() {
        var c = AppConfig()
        c.vocabulary = ["ok", "ok", ""]
        c.replacements = [Replacement(from: "", to: "x"), Replacement(from: "a", to: "b")]
        let v = c.validated()
        XCTAssertEqual(v.config.vocabulary, ["ok"]); XCTAssertEqual(v.config.replacements, [Replacement(from: "a", to: "b")])
        XCTAssertEqual(v.problems.count, 2)
    }
    func testSaveThenLoadRoundTripsEverything() throws {
        var c = AppConfig()
        c.hotkeyMode = "combo"; c.hotkeyModifiers = ["command", "shift"]; c.hotkeyKeyCode = 96; c.holdSeconds = 0.45
        c.showInDock = false; c.idleSeconds = 1800; c.clipboardRestoreMs = 900
        c.vocabulary = ["Novonesis", "Kushi"]
        c.replacements = [Replacement(from: "cloud code", to: "Claude Code"), Replacement(from: "e p i", to: "API")]
        let p = tmpPath()
        try c.save(path: p)
        let r = AppConfig.load(path: p)
        XCTAssertNil(r.warning); XCTAssertEqual(r.config, c)
    }
    func testSaveCreatesTheFolderAndWritesValidJSON() throws {
        let p = tmpPath()
        try AppConfig().save(path: p)
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: p))) as? [String: Any]
        XCTAssertEqual(obj?["hotkeyMode"] as? String, "rightOptionHold")
    }
    func testSaveNeverWritesInvalidValues() throws {
        var c = AppConfig(); c.serverURL = "http://example.com:1"; c.clipboardRestoreMs = -5
        let p = tmpPath()
        try c.save(path: p)
        let r = AppConfig.load(path: p)
        XCTAssertNil(r.warning, "what the app wrote must load cleanly")
        XCTAssertEqual(r.config.serverURL, AppConfig().serverURL); XCTAssertEqual(r.config.clipboardRestoreMs, 100)
    }
    func testSaveOverwritesAnExistingFile() throws {
        let p = tmpPath()
        var c = AppConfig(); c.idleSeconds = 60; try c.save(path: p)
        c.idleSeconds = 120; try c.save(path: p)
        XCTAssertEqual(AppConfig.load(path: p).config.idleSeconds, 120)
    }
    func testOldConfigWithoutNewKeysStillLoads() throws {
        let p = tmpPath()
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try #"{"idleSeconds": 300, "hotkeyModifiers": ["control","option"]}"#.write(toFile: p, atomically: true, encoding: .utf8)
        let r = AppConfig.load(path: p)
        XCTAssertNil(r.warning); XCTAssertEqual(r.config.vocabulary, []); XCTAssertTrue(r.config.showInDock)
    }
    func testVocabularyHeaderEncodingSurvivesAwkwardTerms() {
        let h = TranscribeClient.vocabularyHeader(["Zoë", "S/4HANA", "it's", "two words"])!
        XCTAssertFalse(h.contains(" ")); XCTAssertEqual(h.split(separator: ",").count, 4, "terms must not split on anything but our commas")
        XCTAssertNil(TranscribeClient.vocabularyHeader([]))
    }
}

final class WordsWiringTests: XCTestCase {
    override func setUp() { StubProtocol.handler = nil; StubProtocol.requests = [] }

    func testClientSendsTheCurrentVocabularyAndSeesUpdates() async throws {
        let words = LiveWords(vocabulary: ["Novonesis"])
        let client = TranscribeClient(baseURL: URL(string: "http://127.0.0.1:9")!, timeout: 5, session: StubProtocol.session(), words: words)
        StubProtocol.handler = { _ in .success((200, Data("ok".utf8))) }
        _ = try await client.transcribe(wav: Data([1]))
        XCTAssertEqual(StubProtocol.requests.last?.value(forHTTPHeaderField: "X-Vocabulary"), "Novonesis")
        words.update(from: { var c = AppConfig(); c.vocabulary = []; return c }())
        _ = try await client.transcribe(wav: Data([1]))
        XCTAssertNil(StubProtocol.requests.last?.value(forHTTPHeaderField: "X-Vocabulary"), "an empty list sends no header")
    }

    func testControllerAppliesReplacementsBeforePasting() async {
        let rec = FakeRecorder(), svc = FakeService(), ins = FakeInserter(), sink = FakeSink()
        svc.result = .success("please open cloud code now")
        let words = LiveWords(replacements: [Replacement(from: "cloud code", to: "Claude Code")])
        let c = DictationController(recorder: rec, service: svc, inserter: ins, sink: sink, postProcess: { words.process($0) })
        await c.keyDown(); await c.keyUp(); await c.waitUntilIdle()
        XCTAssertEqual(ins.texts, ["please open Claude Code now"])
    }

    func testReplacementsEditedLaterApplyToTheNextDictation() async {
        let rec = FakeRecorder(), svc = FakeService(), ins = FakeInserter(), sink = FakeSink()
        svc.result = .success("alpha beta")
        let words = LiveWords()
        let c = DictationController(recorder: rec, service: svc, inserter: ins, sink: sink, postProcess: { words.process($0) })
        await c.keyDown(); await c.keyUp(); await c.waitUntilIdle()
        words.update(from: { var x = AppConfig(); x.replacements = [Replacement(from: "beta", to: "BETA")]; return x }())
        await c.keyDown(); await c.keyUp(); await c.waitUntilIdle()
        XCTAssertEqual(ins.texts, ["alpha beta", "alpha BETA"])
    }

    func testReplacementThatEmptiesTheTextIsReportedAsNoSpeech() async {
        let rec = FakeRecorder(), svc = FakeService(), ins = FakeInserter(), sink = FakeSink()
        svc.result = .success("um")
        let words = LiveWords(replacements: [Replacement(from: "um", to: "")])
        let c = DictationController(recorder: rec, service: svc, inserter: ins, sink: sink, postProcess: { words.process($0) })
        await c.keyDown(); await c.keyUp(); await c.waitUntilIdle()
        XCTAssertTrue(ins.texts.isEmpty); XCTAssertEqual(sink.states.last, .notice("No speech detected"))
    }
}
