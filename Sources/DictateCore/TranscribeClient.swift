import Foundation

public enum TranscribeError: Error, Equatable, CustomStringConvertible {
    case serverUnreachable
    case timeout
    case badAudio(String)
    case serverError(Int, String)

    public var description: String {
        switch self {
        case .serverUnreachable: return "server not reachable"
        case .timeout: return "server timed out"
        case .badAudio(let m): return "bad audio: \(m)"
        case .serverError(let c, let m): return "server error \(c): \(m)"
        }
    }
}

public protocol TranscriptionService: Sendable {
    /// Make sure the server is up and the model is loaded. Called when the key goes down so loading overlaps speech.
    func ensureReady() async throws
    func transcribe(_ wav: Data) async throws -> String
}

public struct TranscribeClient: Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval
    private let session: URLSession
    private let words: LiveWords?

    /// No disk cache, no cookies, no credential store: dictated text must never be written anywhere by the HTTP layer.
    public static func privateSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpCookieStorage = nil
        c.urlCredentialStorage = nil
        return URLSession(configuration: c)
    }

    public init(baseURL: URL, timeout: TimeInterval = 120, session: URLSession = TranscribeClient.privateSession(), words: LiveWords? = nil) {
        self.baseURL = baseURL; self.timeout = timeout; self.session = session; self.words = words
    }

    /// Terms travel in one header, each percent-encoded so a comma or accent inside a term cannot break the list.
    static func vocabularyHeader(_ terms: [String]) -> String? {
        let enc = terms.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) }.filter { !$0.isEmpty }
        return enc.isEmpty ? nil : enc.joined(separator: ",")
    }

    var sessionConfiguration: URLSessionConfiguration { session.configuration }

    public func healthy(touch: Bool = false) async -> Bool {
        var comps = URLComponents(url: baseURL.appendingPathComponent("health"), resolvingAgainstBaseURL: false)!
        if touch { comps.queryItems = [URLQueryItem(name: "touch", value: "1")] }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 2
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8) == "ok"
    }

    /// Raw WAV bytes in, text out. Empty string means silence or a clip the server judged too short.
    public func transcribe(wav: Data) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
        req.httpMethod = "POST"
        req.httpBody = wav
        req.timeoutInterval = timeout
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let v = words.flatMap({ TranscribeClient.vocabularyHeader($0.vocabulary) }) { req.setValue(v, forHTTPHeaderField: "X-Vocabulary") }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            switch code {
            case 200: return body.trimmingCharacters(in: .whitespacesAndNewlines)
            case 400: throw TranscribeError.badAudio(body)
            default: throw TranscribeError.serverError(code, body)
            }
        } catch let e as TranscribeError {
            throw e
        } catch let e as URLError {
            switch e.code {
            case .timedOut: throw TranscribeError.timeout
            default: throw TranscribeError.serverUnreachable
            }
        }
    }
}
