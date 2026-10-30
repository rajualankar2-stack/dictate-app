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
