import Foundation

/// Minimal WAV header reader. Enough to reject clips that are too short or not audio.
public struct WAVInfo: Equatable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int
    public let frames: Int
    public var duration: Double { sampleRate > 0 ? Double(frames) / Double(sampleRate) : 0 }

    public static func parse(_ d: Data) -> WAVInfo? {
        let b = [UInt8](d)
        guard b.count >= 12, String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        var pos = 12
        var rate = 0, ch = 0, bits = 0
        var haveFmt = false
        while pos + 8 <= b.count {
            let id = String(bytes: b[pos..<pos + 4], encoding: .ascii) ?? ""
            let size = u32(pos + 4)
            let body = pos + 8
            if id == "fmt " {
                guard body + 16 <= b.count else { return nil }
                ch = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                haveFmt = true
            } else if id == "data" {
                guard haveFmt, ch > 0, bits >= 8 else { return nil }
                // A recorder that crashed or a streaming writer can leave size 0 or too large: trust the bytes present.
                let available = b.count - body
                let n = (size == 0 || size > available) ? available : size
                return WAVInfo(sampleRate: rate, channels: ch, bitsPerSample: bits, frames: n / (ch * (bits / 8)))
            }
            pos = body + size + (size % 2)
        }
        return nil
    }
}
