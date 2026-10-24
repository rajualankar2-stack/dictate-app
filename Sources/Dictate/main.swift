import AppKit
import AVFoundation
import Carbon.HIToolbox
import DictateCore

// Self-test modes run without a GUI, a microphone or any permission prompt:
//   Dictate --selftest-status
//   Dictate --selftest-transcribe <file.wav> [--stop]
//   Dictate --selftest-paste <text>
// With no flag the menu-bar app starts.

func printJSON(_ obj: [String: Any]) {
    let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    print(String(data: d ?? Data(), encoding: .utf8) ?? "{}")
}

func runSelfTest(_ args: [String]) -> Int32 {
    let loaded = AppConfig.load()
    let cfg = loaded.config
    switch args[0] {
    case "--selftest-status":
        let hk = Hotkey()
        let st = hk.register(keyCode: cfg.hotkeyKeyCode, modifiers: cfg.hotkeyModifiers)
        hk.unregister()
        let ot = OptionHoldTap()
        let tapOK = ot.start(holdSeconds: cfg.holdSeconds)
        let tapMode = ot.mode
        ot.stop()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        printJSON([
            "hotkeyRegisterStatus": Int(st),
            "rightOptionTap": tapOK ? tapMode : "FAILED (Input Monitoring / Accessibility missing)",
            "hotkeyMode": cfg.hotkeyMode,
            "microphone": ["notDetermined", "restricted", "denied", "authorized"][mic.rawValue],
            "accessibilityTrusted": AXIsProcessTrusted(),
            "secureInput": IsSecureEventInputEnabled(),
            "configWarning": loaded.warning ?? "",
            "pythonExists": FileManager.default.isExecutableFile(atPath: cfg.expandedPython),
            "scriptExists": FileManager.default.fileExists(atPath: cfg.expandedScript),
            "serverURL": cfg.serverURL,
        ])
        return 0
    case "--selftest-transcribe":
        guard args.count >= 2, let wav = FileManager.default.contents(atPath: args[1]) else { print("usage: --selftest-transcribe file.wav [--stop]"); return 2 }
        let words = LiveWords(config: cfg)
        let client = TranscribeClient(baseURL: URL(string: cfg.serverURL)!, timeout: cfg.transcribeTimeoutSeconds, words: words)
        let sup = ServerSupervisor(config: cfg, client: client)
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]
        Task {
            let t0 = Date()
            do {
                try await sup.ensureReady()
                let ready = Date().timeIntervalSince(t0)
                let raw = try await sup.transcribe(wav)
                let text = words.process(raw)   // same steps the app takes: server text, then the user's replacements
                out = ["text": text, "rawFromServer": raw, "vocabularySent": words.vocabulary.count, "readySeconds": ready, "totalSeconds": Date().timeIntervalSince(t0), "launched": await sup.launchCount]
            } catch { out = ["error": "\(error)"] }
            if args.contains("--stop"), await sup.launchCount > 0 { await sup.stopServer(); out["stopped"] = true }
            sem.signal()
        }
        sem.wait()
        printJSON(out)
        return out["error"] == nil ? 0 : 1
    case "--selftest-paste":
        // Usage: --selftest-paste "text" [seconds]. The wait lets you click into a text field first.
        let text = args.count >= 2 ? args[1] : "dictate selftest"
        let wait = args.count >= 3 ? (Double(args[2]) ?? 0) : 0
        if wait > 0 { print("pasting in \(Int(wait)) s: click into a text field now"); Thread.sleep(forTimeInterval: wait) }
        let stager = PasteStager(poster: CGEventPoster(), restoreDelay: Double(cfg.clipboardRestoreMs) / 1000)
        let sem = DispatchSemaphore(value: 0)
        var result = ""
        Task { result = "\(await stager.paste(text))"; sem.signal() }
        sem.wait()
        printJSON(["result": result, "clipboardNow": NSPasteboard.general.string(forType: .string) ?? ""])
        return 0
    case "--selftest-record":
        // Usage: --selftest-record <seconds> [tone.wav]. Records with the app's own recorder, optionally playing a file
        // meanwhile, and prints the level per 0.5 s. Run through `open -n -W --stdout f build/Dictate.app --args ...`
        // so the microphone permission is the app's. The audio is deleted; only levels are printed.
        let secs = args.count >= 2 ? (Double(args[1]) ?? 5) : 5
        let rec = WavRecorder(maxSeconds: 60)
        do { try rec.start() } catch { printJSON(["error": "\(error)"]); return 1 }
        var player: Process?
        if args.count >= 3 {
            Thread.sleep(forTimeInterval: 1.0)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay"); p.arguments = [args[2]]
            try? p.run(); player = p
        }
        Thread.sleep(forTimeInterval: secs)
        guard let url = rec.stop(), let data = FileManager.default.contents(atPath: url.path) else { printJSON(["error": "no file"]); return 1 }
        try? FileManager.default.removeItem(at: url)
        player?.terminate()
        guard let info = WAVInfo.parse(data) else { printJSON(["error": "invalid wav"]); return 1 }
        let samples = data.dropFirst(44)   // AVAudioRecorder writes a canonical 44-byte header
        let per = Int(0.5 * Double(info.sampleRate))
        var levels: [Int] = []
        samples.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            var i = 0
            while i + per <= s.count {
                var acc = 0.0
                for k in i..<(i + per) { let v = Double(s[k]) / 32768; acc += v * v }
                levels.append(Int(20 * log10(max(1e-9, (acc / Double(per)).squareRoot()))))
                i += per
            }
        }
        printJSON(["seconds": info.duration, "sampleRate": info.sampleRate, "channels": info.channels, "bits": info.bitsPerSample, "dbPerHalfSecond": levels])
        return 0
    default:
        print("unknown self-test"); return 2
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, first.hasPrefix("--selftest") {
    exit(runSelfTest(args))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
