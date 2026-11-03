import Foundation

/// Small timestamped file log at ~/Library/Logs/Dictate/dictate.log (override: DICTATE_LOG).
/// Never writes dictated text, only states, timings, sizes and errors. Rotates at 1 MB, keeps one old file.
public enum AppLog {
    private static let queue = DispatchQueue(label: "dictate.applog")
    private static let maxBytes = 1_000_000
    private static let path: String = {
        if let p = ProcessInfo.processInfo.environment["DICTATE_LOG"], !p.isEmpty { return (p as NSString).expandingTildeInPath }
        return ("~/Library/Logs/Dictate/dictate.log" as NSString).expandingTildeInPath
    }()
    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static var filePath: String { path }

    /// Unit tests would fill the real log, so they log only when DICTATE_LOG is set.
    private static let enabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] == nil || !(env["DICTATE_LOG"] ?? "").isEmpty
    }()

    public static func log(_ message: String) {
        guard enabled else { return }
        let line = "\(fmt.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            let dir = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > maxBytes {
                try? fm.removeItem(atPath: path + ".1")
                try? fm.moveItem(atPath: path, toPath: path + ".1")
            }
            if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
            guard let h = FileHandle(forWritingAtPath: path) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        }
    }
}
