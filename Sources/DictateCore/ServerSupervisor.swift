import Foundation

public enum ServerStartError: Error, Equatable, CustomStringConvertible {
    case launchFailed(String)
    case timeout

    public var description: String {
        switch self {
        case .launchFailed(let m): return "could not start server: \(m)"
        case .timeout: return "server did not become ready in time"
        }
    }
}

/// Starts the Python server on demand and keeps it from being started twice at once.
/// The server stops itself after `idleSeconds` without a request, so the 2 GB of RAM is freed.
public actor ServerSupervisor: TranscriptionService {
    public typealias Launcher = @Sendable (AppConfig) throws -> Void

    private let config: AppConfig
    private let client: TranscribeClient
    private let launcher: Launcher
    private var starting: Task<Void, Error>?
    public private(set) var launchCount = 0

    public init(config: AppConfig, client: TranscribeClient, launcher: @escaping Launcher = ServerSupervisor.defaultLauncher) {
        self.config = config; self.client = client; self.launcher = launcher
    }

    public func ensureReady() async throws {
        // touch: a key press counts as activity, so the idle timer cannot expire while the user is speaking.
        if await client.healthy(touch: true) { return }
        if let t = starting { return try await t.value }
        let t = Task<Void, Error> { try await self.launchAndWait() }
        starting = t
        do { try await t.value; starting = nil } catch { starting = nil; throw error }
    }

    private func launchAndWait() async throws {
        launchCount += 1
        try launcher(config)
        let started = Date()
        let deadline = started.addingTimeInterval(config.serverStartTimeoutSeconds)
        while Date() < deadline {
            if await client.healthy() { return }
            // If the server process died while loading (port busy, missing adapter), say so now instead of waiting out the timeout.
            if Date().timeIntervalSince(started) > 2, let reason = serverDiedReason() { throw ServerStartError.launchFailed(reason) }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw ServerStartError.timeout
    }

    /// Non-nil only when the server's pid file exists and that process is gone. No pid file (tests, foreign launcher) = no opinion.
    private func serverDiedReason() -> String? {
        let scriptName = (config.expandedScript as NSString).lastPathComponent
        let pidFileName = scriptName.replacingOccurrences(of: ".py", with: ".pid")
        let logFileName = scriptName.replacingOccurrences(of: ".py", with: ".log")
        let pidPath = ((config.expandedScript as NSString).deletingLastPathComponent as NSString).appendingPathComponent(pidFileName)
        guard let s = try? String(contentsOfFile: pidPath, encoding: .utf8), let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if kill(pid, 0) == 0 { return nil }
        return "the server exited while starting (see \((config.expandedScript as NSString).deletingLastPathComponent)/\(logFileName))"
    }

    public func transcribe(_ wav: Data) async throws -> String {
        do {
            return try await client.transcribe(wav: wav)
        } catch TranscribeError.serverUnreachable {
            // The server may have just stopped for being idle. Start it once and retry once.
            try await ensureReady()
            return try await client.transcribe(wav: wav)
        }
    }

    public func stopServer() {
        _ = try? ServerSupervisor.runScript(config, args: ["stop"])
    }

    // MARK: launching

    public static let defaultLauncher: Launcher = { cfg in
        _ = try runScript(cfg, args: ["start", "--idle", String(cfg.idleSeconds)])
    }

    @discardableResult
    static func runScript(_ cfg: AppConfig, args: [String]) throws -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: cfg.expandedPython) else {
            throw ServerStartError.launchFailed("python not found at \(cfg.expandedPython)")
        }
        guard fm.fileExists(atPath: cfg.expandedScript) else {
            throw ServerStartError.launchFailed("server script not found at \(cfg.expandedScript)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cfg.expandedPython)
        p.arguments = [cfg.expandedScript] + args
        var env = ProcessInfo.processInfo.environment
        for k in ["PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV"] { env.removeValue(forKey: k) }
        // One source of truth for the port: the server listens where the app is looking.
        if let port = URL(string: cfg.serverURL)?.port { env["DICTATE_PORT"] = String(port) }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { throw ServerStartError.launchFailed(error.localizedDescription) }
        // Read pipe in background to avoid deadlock on large output
        let readHandle = out.fileHandleForReading
        var data = Data()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = readHandle.readDataToEndOfFile()
            sem.signal()
        }
        p.waitUntilExit()
        sem.wait()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw ServerStartError.launchFailed(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return text
    }
}
