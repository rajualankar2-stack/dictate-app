import AppKit
import XCTest
@testable import DictateCore

final class FakePoster: KeyPoster, @unchecked Sendable {
    var result = true
    var onPost: (() -> Void)?
    private(set) var posts = 0
    func postCommandV() -> Bool { posts += 1; onPost?(); return result }
    func postReturn() -> Bool { return result }
}

final class PasteStagerTests: XCTestCase {
    var pb: NSPasteboard!
    override func setUp() { pb = NSPasteboard(name: NSPasteboard.Name("dictate-test-\(UUID().uuidString)")) }
    override func tearDown() { pb.releaseGlobally() }

    private func stager(_ p: FakePoster, delay: TimeInterval = 0.05) -> PasteStager { PasteStager(pasteboard: pb, poster: p, restoreDelay: delay) }

    func testTextIsOnClipboardAtTheMomentOfPaste() async {
        let p = FakePoster(); var seen: String?; var types: [NSPasteboard.PasteboardType] = []
        p.onPost = { seen = self.pb.string(forType: .string); types = self.pb.types ?? [] }
        let r = await stager(p).paste("hello MIGO")
        XCTAssertEqual(r, .pasted); XCTAssertEqual(seen, "hello MIGO"); XCTAssertEqual(p.posts, 1)
        XCTAssertTrue(types.contains(PasteStager.transientType), "clipboard managers should skip it")
    }

    func testRestoresPreviousString() async {
        pb.clearContents(); pb.setString("my old clipboard", forType: .string)
        _ = await stager(FakePoster()).paste("dictated")
        XCTAssertEqual(pb.string(forType: .string), "my old clipboard")
        XCTAssertFalse((pb.types ?? []).contains(PasteStager.transientType))
    }

    func testRestoresMultipleTypesOnOneItem() async {
        pb.clearContents()
        let it = NSPasteboardItem()
        it.setString("plain", forType: .string)
        it.setData(Data("{\\rtf1 rich}".utf8), forType: .rtf)
        it.setData(Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]), forType: .png)
        pb.writeObjects([it])
        _ = await stager(FakePoster()).paste("dictated")
        XCTAssertEqual(pb.string(forType: .string), "plain")
        XCTAssertEqual(pb.data(forType: .rtf), Data("{\\rtf1 rich}".utf8))
        XCTAssertEqual(pb.data(forType: .png), Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]))
    }

    func testRestoresSeveralItems() async {
        pb.clearContents()
        let a = NSPasteboardItem(); a.setString("one", forType: .string)
        let b = NSPasteboardItem(); b.setString("two", forType: .string)
        pb.writeObjects([a, b])
        _ = await stager(FakePoster()).paste("dictated")
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["one", "two"])
    }

    func testEmptyClipboardStaysEmptyAfterwards() async {
        pb.clearContents()
        _ = await stager(FakePoster()).paste("dictated")
        XCTAssertNil(pb.string(forType: .string))
        XCTAssertEqual(pb.pasteboardItems?.count ?? 0, 0)
    }

    func testDoesNotOverwriteACopyMadeDuringTheDelay() async {
        pb.clearContents(); pb.setString("old", forType: .string)
        let s = stager(FakePoster(), delay: 0.3)
        async let r = s.paste("dictated")
        try? await Task.sleep(nanoseconds: 100_000_000)
        pb.clearContents(); pb.setString("user copied this just now", forType: .string)
        _ = await r
        XCTAssertEqual(pb.string(forType: .string), "user copied this just now")
    }

    func testCopyOnlyWhenPasteKeyCannotBeSent() async {
        pb.clearContents(); pb.setString("old", forType: .string)
        let p = FakePoster(); p.result = false
        let r = await stager(p).paste("dictated")
        guard case .copiedOnly = r else { return XCTFail("\(r)") }
        XCTAssertEqual(pb.string(forType: .string), "dictated", "text must stay so the user can paste it")
    }

    func testUnicodeAndLongTextSurvive() async {
        let p = FakePoster(); var seen: String?
        p.onPost = { seen = self.pb.string(forType: .string) }
        let text = String(repeating: "Zażółć gęślą jaźń — ₹1,200 ✓ ", count: 400)
        _ = await stager(p).paste(text)
        XCTAssertEqual(seen, text)
    }

    func testRepeatedPastesKeepOriginalClipboard() async {
        pb.clearContents(); pb.setString("original", forType: .string)
        let s = stager(FakePoster())
        for i in 0..<5 { _ = await s.paste("dictation \(i)") }
        XCTAssertEqual(pb.string(forType: .string), "original")
    }
}
