import XCTest
@testable import DictateCore

private struct Fixed: RandomNumberGenerator {
    var n: UInt64 = 0
    mutating func next() -> UInt64 { n &+= 0x9E3779B97F4A7C15; return n }
}

final class TextStyleTests: XCTestCase {
    let s = "Please send me the report, by Friday afternoon."

    func testNormalKeepsText() { XCTAssertEqual(TextStyler.apply(s, textCase: .normal, noTrailingPunctuation: false), s) }
    func testLowercase() { XCTAssertEqual(TextStyler.apply(s, textCase: .lowercase, noTrailingPunctuation: false), s.lowercased()) }
    func testUppercase() { XCTAssertEqual(TextStyler.apply(s, textCase: .uppercase, noTrailingPunctuation: false), s.uppercased()) }
    func testNoTrailingPunctuation() {
        XCTAssertEqual(TextStyler.apply(s, textCase: .normal, noTrailingPunctuation: true), "Please send me the report, by Friday afternoon")
        XCTAssertEqual(TextStyler.apply("Is it ready?", textCase: .normal, noTrailingPunctuation: true), "Is it ready?")
    }
    func testRandomMixesCaseAndKeepsLetters() {
        var g = Fixed()
        let r = TextStyler.apply(s, textCase: .random, noTrailingPunctuation: false, using: &g)
        XCTAssertEqual(r.lowercased(), s.lowercased())
        XCTAssertTrue(r.contains(where: { $0.isUppercase }) && r.contains(where: { $0.isLowercase }))
    }
    func testConfigRejectsUnknownCase() {
        var c = AppConfig(); c.textCase = "shouting"
        XCTAssertEqual(c.validated().config.textCase, "normal")
    }
}

final class TextCleanupTests: XCTestCase {
    func testFillersRemoved() {
        XCTAssertEqual(TextCleanup.removeFillers("Um, I think, uh, we should go."), "I think, we should go.")
        XCTAssertEqual(TextCleanup.removeFillers("um so the report is ready"), "so the report is ready")
        XCTAssertEqual(TextCleanup.removeFillers("Um, so it works"), "So it works")
    }
    func testFillerLookalikesKept() {
        XCTAssertEqual(TextCleanup.removeFillers("The umbrella is here, ask Herman"), "The umbrella is here, ask Herman")
    }
    func testSpokenFormat() {
        XCTAssertEqual(TextCleanup.spokenFormat("Hello, new line, how are you"), "Hello\nhow are you")
        XCTAssertEqual(TextCleanup.spokenFormat("Done. New paragraph. Next topic"), "Done.\n\nNext topic")
        XCTAssertEqual(TextCleanup.spokenFormat("a newline in code"), "a newline in code")
    }
    func testLiveWordsOrder() {
        var c = AppConfig(); c.removeFillerWords = true; c.spokenFormatting = true
        XCTAssertEqual(LiveWords(config: c).process("Uh, first point, new line, second point"), "First point\nsecond point")
    }
    func testSmartSpacingRules() {
        XCTAssertTrue(SmartSpacing.needsLeadingSpace(before: "d", text: "next"))
        XCTAssertTrue(SmartSpacing.needsLeadingSpace(before: ".", text: "Next"))
        XCTAssertTrue(SmartSpacing.needsLeadingSpace(before: ")", text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: " ", text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: "(", text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: "@", text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: "\"", text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: nil, text: "next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: "d", text: ", next"))
        XCTAssertFalse(SmartSpacing.needsLeadingSpace(before: "d", text: " next"))
    }
}
