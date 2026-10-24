import XCTest
@testable import DictateCore

func makeWAV(seconds: Double, rate: Int = 16000, channels: Int = 1, bits: Int = 16,
             dataSizeField: UInt32? = nil, extraChunkBeforeData: Bool = false) -> Data {
    let frames = Int(seconds * Double(rate))
    let dataBytes = frames * channels * (bits / 8)
    var d = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataBytes)); d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(UInt16(channels)); u32(UInt32(rate))
    u32(UInt32(rate * channels * bits / 8)); u16(UInt16(channels * bits / 8)); u16(UInt16(bits))
    if extraChunkBeforeData {
        d.append("LIST".data(using: .ascii)!); u32(5); d.append(Data([1, 2, 3, 4, 5])); d.append(0)   // odd size + pad byte
    }
    d.append("data".data(using: .ascii)!); u32(dataSizeField ?? UInt32(dataBytes))
    d.append(Data(count: dataBytes))
    return d
}

final class WAVInfoTests: XCTestCase {
    func testValidMono16k() {
        let i = WAVInfo.parse(makeWAV(seconds: 1.0))
        XCTAssertEqual(i?.sampleRate, 16000); XCTAssertEqual(i?.channels, 1); XCTAssertEqual(i?.bitsPerSample, 16)
        XCTAssertEqual(i?.duration ?? 0, 1.0, accuracy: 0.001)
    }
    func testStereo44k() {
        let i = WAVInfo.parse(makeWAV(seconds: 2.5, rate: 44100, channels: 2))
        XCTAssertEqual(i?.duration ?? 0, 2.5, accuracy: 0.001); XCTAssertEqual(i?.channels, 2)
    }
    func testSizeFieldZeroUsesBytesPresent() {
        XCTAssertEqual(WAVInfo.parse(makeWAV(seconds: 1.5, dataSizeField: 0))?.duration ?? 0, 1.5, accuracy: 0.001)
    }
    func testSizeFieldTooLargeUsesBytesPresent() {
        XCTAssertEqual(WAVInfo.parse(makeWAV(seconds: 1.0, dataSizeField: 0xFFFF_FFFF))?.duration ?? 0, 1.0, accuracy: 0.001)
    }
    func testOddSizedChunkBeforeData() {
        XCTAssertEqual(WAVInfo.parse(makeWAV(seconds: 1.0, extraChunkBeforeData: true))?.duration ?? 0, 1.0, accuracy: 0.001)
    }
    func testRejectsGarbage() {
        XCTAssertNil(WAVInfo.parse(Data("not a wav file".utf8)))
        XCTAssertNil(WAVInfo.parse(Data()))
        XCTAssertNil(WAVInfo.parse(Data("RIFF".utf8)))
    }
    func testRejectsMissingDataChunk() {
        XCTAssertNil(WAVInfo.parse(makeWAV(seconds: 1.0).prefix(40)))
    }
    func testZeroLengthAudioIsZeroDuration() {
        XCTAssertEqual(WAVInfo.parse(makeWAV(seconds: 0))?.duration, 0)
    }
}

final class AppConfigTests: XCTestCase {
    private func tmp(_ s: String?) -> String {
        let p = NSTemporaryDirectory() + "cfg-\(UUID().uuidString).json"
        if let s { try? s.write(toFile: p, atomically: true, encoding: .utf8) }
        return p
    }
    func testMissingFileGivesDefaultsWithoutWarning() {
        let r = AppConfig.load(path: tmp(nil))
        XCTAssertEqual(r.config, AppConfig()); XCTAssertNil(r.warning)
    }
    func testPartialFileMergesWithDefaults() {
        let r = AppConfig.load(path: tmp(#"{"idleSeconds": 30, "hotkeyModifiers": ["command","shift"]}"#))
        XCTAssertNil(r.warning); XCTAssertEqual(r.config.idleSeconds, 30)
        XCTAssertEqual(r.config.hotkeyModifiers, ["command", "shift"])
        XCTAssertEqual(r.config.serverURL, AppConfig().serverURL)
    }
    func testInvalidJSONFallsBackWithWarning() {
        let r = AppConfig.load(path: tmp("{not json"))
        XCTAssertEqual(r.config, AppConfig()); XCTAssertNotNil(r.warning)
    }
    func testWrongTypeFallsBackWithWarning() {
        let r = AppConfig.load(path: tmp(#"{"idleSeconds": "soon"}"#))
        XCTAssertEqual(r.config, AppConfig()); XCTAssertNotNil(r.warning)
    }
    func testRemoteOrMalformedServerURLIsRejected() {
        for bad in ["http://example.com:8772", "https://127.0.0.1:8772", "http://192.168.1.5:8772", "", "not a url", "http://127.0.0.1"] {
            let r = AppConfig.load(path: tmp(#"{"serverURL": "\#(bad)"}"#))
            XCTAssertEqual(r.config.serverURL, AppConfig().serverURL, "\(bad) must fall back")
            XCTAssertNotNil(r.warning, "\(bad)")
        }
    }
    func testLocalServerURLsAccepted() {
        for ok in ["http://127.0.0.1:9000", "http://localhost:8772"] {
            let r = AppConfig.load(path: tmp(#"{"serverURL": "\#(ok)"}"#))
            XCTAssertEqual(r.config.serverURL, ok); XCTAssertNil(r.warning)
        }
    }
    func testOutOfRangeNumbersAreClampedNotCrashing() {
        let r = AppConfig.load(path: tmp(#"{"clipboardRestoreMs": -50, "idleSeconds": -1, "maxRecordSeconds": 100000, "minSeconds": 0}"#))
        XCTAssertEqual(r.config.clipboardRestoreMs, 100); XCTAssertEqual(r.config.idleSeconds, 0)
        XCTAssertEqual(r.config.maxRecordSeconds, 600); XCTAssertEqual(r.config.minSeconds, 0.05, accuracy: 1e-9)
        XCTAssertNotNil(r.warning)
    }
    func testBadHotkeyModifiersFallBack() {
        for bad in ["[]", #"["hyper"]"#, #"["control", "banana"]"#] {
            let r = AppConfig.load(path: tmp(#"{"hotkeyModifiers": \#(bad)}"#))
            XCTAssertEqual(r.config.hotkeyModifiers, AppConfig().hotkeyModifiers, bad); XCTAssertNotNil(r.warning)
        }
    }
    func testDefaultsAreValid() {
        XCTAssertTrue(AppConfig().validated().problems.isEmpty)
    }
    func testDefaultHotkeyIsRightOptionHold() {
        XCTAssertEqual(AppConfig().hotkeyMode, "rightOptionHold"); XCTAssertEqual(AppConfig().holdSeconds, 0.3, accuracy: 1e-9)
    }
    func testHotkeyModeAndHoldSecondsAreValidated() {
        let a = AppConfig.load(path: tmp(#"{"hotkeyMode": "leftShift"}"#))
        XCTAssertEqual(a.config.hotkeyMode, "rightOptionHold"); XCTAssertNotNil(a.warning)
        let b = AppConfig.load(path: tmp(#"{"hotkeyMode": "combo", "holdSeconds": 0.01}"#))
        XCTAssertEqual(b.config.hotkeyMode, "combo"); XCTAssertEqual(b.config.holdSeconds, 0.15, accuracy: 1e-9); XCTAssertNotNil(b.warning)
        let c = AppConfig.load(path: tmp(#"{"holdSeconds": 0.5}"#))
        XCTAssertEqual(c.config.holdSeconds, 0.5, accuracy: 1e-9); XCTAssertNil(c.warning)
    }
    func testUnknownKeysAreIgnored() {
        let r = AppConfig.load(path: tmp(#"{"futureSetting": true, "idleSeconds": 5}"#))
        XCTAssertNil(r.warning); XCTAssertEqual(r.config.idleSeconds, 5)
    }
    func testTildeExpansion() {
        XCTAssertFalse(AppConfig().expandedPython.hasPrefix("~")); XCTAssertFalse(AppConfig().expandedScript.hasPrefix("~"))
    }
}
