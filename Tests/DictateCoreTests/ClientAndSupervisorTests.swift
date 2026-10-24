import XCTest
@testable import DictateCore

/// Serves canned HTTP responses to a URLSession so the client can be tested without a server.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.requests.append(request)
        switch StubProtocol.handler?(request) ?? .failure(URLError(.cannotConnectToHost)) {
        case .success(let (code, data)):
            let r = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let e):
            client?.urlProtocol(self, didFailWithError: e)
        }
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }
}

final class TranscribeClientTests: XCTestCase {
    let base = URL(string: "http://127.0.0.1:9")!
    override func setUp() { StubProtocol.handler = nil; StubProtocol.requests = [] }
    private func client() -> TranscribeClient { TranscribeClient(baseURL: base, timeout: 5, session: StubProtocol.session()) }

    func testDefaultSessionNeverCachesOrStoresAnything() {
        let c = TranscribeClient(baseURL: base).sessionConfiguration
        XCTAssertNil(c.urlCache, "responses hold the dictated text")
        XCTAssertNil(c.httpCookieStorage); XCTAssertNil(c.urlCredentialStorage)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testHealthyTouchAddsQueryOnlyWhenAsked() async {
        StubProtocol.handler = { _ in .success((200, Data("ok".utf8))) }
        _ = await client().healthy()
        XCTAssertNil(StubProtocol.requests.last?.url?.query, "a plain health check must not count as activity")
        _ = await client().healthy(touch: true)
        XCTAssertEqual(StubProtocol.requests.last?.url?.query, "touch=1")
        XCTAssertEqual(StubProtocol.requests.last?.url?.path, "/health")
    }

    func testOKTrimsText() async throws {
        StubProtocol.handler = { _ in .success((200, Data("  Hello MIGO.\n".utf8))) }
        let t = try await client().transcribe(wav: Data([1, 2, 3]))
        XCTAssertEqual(t, "Hello MIGO.")
        let r = StubProtocol.requests.last!
        XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.url?.path, "/transcribe")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
    }
    func testEmptyBodyIsEmptyString() async throws {
        StubProtocol.handler = { _ in .success((200, Data())) }
        let t = try await client().transcribe(wav: Data([1]))
        XCTAssertEqual(t, "")
    }
    func testBadAudio400() async {
        StubProtocol.handler = { _ in .success((400, Data("unreadable audio".utf8))) }
        do { _ = try await client().transcribe(wav: Data([1])); XCTFail() }
        catch { XCTAssertEqual(error as? TranscribeError, .badAudio("unreadable audio")) }
    }
    func testServerError500() async {
        StubProtocol.handler = { _ in .success((500, Data("model error".utf8))) }
        do { _ = try await client().transcribe(wav: Data([1])); XCTFail() }
        catch { XCTAssertEqual(error as? TranscribeError, .serverError(500, "model error")) }
    }
    func testConnectionRefusedIsUnreachable() async {
        StubProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        do { _ = try await client().transcribe(wav: Data([1])); XCTFail() }
        catch { XCTAssertEqual(error as? TranscribeError, .serverUnreachable) }
    }
    func testTimeoutMapped() async {
        StubProtocol.handler = { _ in .failure(URLError(.timedOut)) }
        do { _ = try await client().transcribe(wav: Data([1])); XCTFail() }
        catch { XCTAssertEqual(error as? TranscribeError, .timeout) }
    }
    func testHealthyOnlyForOk() async {
        StubProtocol.handler = { _ in .success((200, Data("ok".utf8))) }
        let a = await client().healthy(); XCTAssertTrue(a)
        StubProtocol.handler = { _ in .success((200, Data("?".utf8))) }
        let b = await client().healthy(); XCTAssertFalse(b)
        StubProtocol.handler = { _ in .success((503, Data("ok".utf8))) }
        let c = await client().healthy(); XCTAssertFalse(c)
        StubProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        let d = await client().healthy(); XCTAssertFalse(d)
    }
}

final class Counter: @unchecked Sendable {
    private let l = NSLock(); private var n = 0
    func inc() { l.lock(); n += 1; l.unlock() }
    var value: Int { l.lock(); defer { l.unlock() }; return n }
}

final class ServerSupervisorTests: XCTestCase {
    let base = URL(string: "http://127.0.0.1:9")!
    override func setUp() { StubProtocol.handler = nil; StubProtocol.requests = [] }

    private func make(startTimeout: Double = 5, launcher: @escaping ServerSupervisor.Launcher) -> ServerSupervisor {
        var cfg = AppConfig(); cfg.serverStartTimeoutSeconds = startTimeout
        return ServerSupervisor(config: cfg, client: TranscribeClient(baseURL: base, timeout: 5, session: StubProtocol.session()), launcher: launcher)
    }

    func testEnsureReadyTouchesTheServerOnEveryKeyPress() async throws {
        StubProtocol.handler = { _ in .success((200, Data("ok".utf8))) }
        let s = make { _ in }
        try await s.ensureReady()
        XCTAssertEqual(StubProtocol.requests.last?.url?.query, "touch=1", "idle timer must not expire while the user speaks")
    }

    func testLauncherPassesServerPortToThePythonServer() throws {
        // runScript is the real launcher path: run a throwaway script that prints DICTATE_PORT.
        let dir = NSTemporaryDirectory() + "port-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "import os\nprint(os.environ.get('DICTATE_PORT'))\n".write(toFile: dir + "/dictate_srv.py", atomically: true, encoding: .utf8)
        var cfg = AppConfig(); cfg.pythonPath = "/usr/bin/python3"; cfg.serverScript = dir + "/dictate_srv.py"; cfg.serverURL = "http://127.0.0.1:9123"
        XCTAssertEqual(try ServerSupervisor.runScript(cfg, args: []).trimmingCharacters(in: .whitespacesAndNewlines), "9123")
    }

    func testAlreadyHealthyDoesNotLaunch() async throws {
        StubProtocol.handler = { _ in .success((200, Data("ok".utf8))) }
        let launches = Counter()
        let s = make { _ in launches.inc() }
        try await s.ensureReady()
        XCTAssertEqual(launches.value, 0)
    }

    func testLaunchesOnceThenWaitsForHealth() async throws {
        let launched = Counter(); let polls = Counter()
        StubProtocol.handler = { _ in
            polls.inc()
            return launched.value > 0 && polls.value > 4 ? .success((200, Data("ok".utf8))) : .failure(URLError(.cannotConnectToHost))
        }
        let s = make { _ in launched.inc() }
        try await s.ensureReady()
        let c = await s.launchCount
        XCTAssertEqual(c, 1); XCTAssertEqual(launched.value, 1)
    }

    func testConcurrentCallsShareOneLaunch() async throws {
        let launched = Counter()
        StubProtocol.handler = { _ in launched.value > 0 ? .success((200, Data("ok".utf8))) : .failure(URLError(.cannotConnectToHost)) }
        let s = make { _ in launched.inc(); Thread.sleep(forTimeInterval: 0.3) }
        try await withThrowingTaskGroup(of: Void.self) { g in
            for _ in 0..<6 { g.addTask { try await s.ensureReady() } }
            try await g.waitForAll()
        }
        XCTAssertEqual(launched.value, 1)
    }

    func testLauncherFailurePropagatesAndNextCallRetries() async {
        StubProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        let launched = Counter()
        let s = make { _ in launched.inc(); throw ServerStartError.launchFailed("no python") }
        for _ in 0..<2 {
            do { try await s.ensureReady(); XCTFail("should throw") }
            catch { XCTAssertEqual(error as? ServerStartError, .launchFailed("no python")) }
        }
        XCTAssertEqual(launched.value, 2)
    }

    func testStartTimeout() async {
        StubProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        let s = make(startTimeout: 1) { _ in }
        let t0 = Date()
        do { try await s.ensureReady(); XCTFail() }
        catch { XCTAssertEqual(error as? ServerStartError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3)
    }

    func testTranscribeRetriesOnceAfterIdleShutdown() async throws {
        let phase = Counter()   // 0 = server gone, 1 = restarted
        let launched = Counter()
        StubProtocol.handler = { req in
            if launched.value == 0 { return .failure(URLError(.cannotConnectToHost)) }
            return req.url!.path == "/health" ? .success((200, Data("ok".utf8))) : .success((200, Data("hello".utf8)))
        }
        _ = phase
        let s = make { _ in launched.inc() }
        let t = try await s.transcribe(Data([1]))
        XCTAssertEqual(t, "hello"); XCTAssertEqual(launched.value, 1)
    }

    func testTranscribeDoesNotRetryOnBadAudio() async {
        StubProtocol.handler = { _ in .success((400, Data("bad".utf8))) }
        let launched = Counter()
        let s = make { _ in launched.inc() }
        do { _ = try await s.transcribe(Data([1])); XCTFail() }
        catch { XCTAssertEqual(error as? TranscribeError, .badAudio("bad")) }
        XCTAssertEqual(launched.value, 0)
    }

    func testFailsFastWhenServerProcessDiesDuringStartup() async throws {
        // A pid file that names a dead process, as left by a server that exited on "port busy".
        let dir = NSTemporaryDirectory() + "srv-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dead = Process(); dead.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try dead.run(); dead.waitUntilExit()
        try "\(dead.processIdentifier)".write(toFile: dir + "/dictate_srv.pid", atomically: true, encoding: .utf8)
        StubProtocol.handler = { _ in .failure(URLError(.cannotConnectToHost)) }
        var cfg = AppConfig(); cfg.serverScript = dir + "/dictate_srv.py"; cfg.serverStartTimeoutSeconds = 60
        let s = ServerSupervisor(config: cfg, client: TranscribeClient(baseURL: base, timeout: 5, session: StubProtocol.session()), launcher: { _ in })
        let t0 = Date()
        do { try await s.ensureReady(); XCTFail("should throw") }
        catch {
            guard case ServerStartError.launchFailed(let m)? = error as? ServerStartError else { return XCTFail("\(error)") }
            XCTAssertTrue(m.contains("exited while starting"), m)
        }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 6, "must not wait out the 60 s timeout")
    }

    func testRunScriptReportsMissingPython() {
        var cfg = AppConfig(); cfg.pythonPath = "/nonexistent/python"
        XCTAssertThrowsError(try ServerSupervisor.runScript(cfg, args: ["status"])) { e in
            XCTAssertTrue("\(e)".contains("python not found"))
        }
    }
    func testRunScriptReportsMissingScript() {
        var cfg = AppConfig(); cfg.pythonPath = "/usr/bin/python3"; cfg.serverScript = "/nonexistent/srv.py"
        XCTAssertThrowsError(try ServerSupervisor.runScript(cfg, args: ["status"])) { e in
            XCTAssertTrue("\(e)".contains("server script not found"))
        }
    }
}
