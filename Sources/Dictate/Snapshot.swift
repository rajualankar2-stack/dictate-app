import AppKit

/// Developer aid: `DICTATE_SNAPSHOT_DIR=/path open -n Dictate.app` writes PNGs of the welcome tour and every
/// settings page, in light and dark, then quits. It draws the app's own views, so it needs no Screen Recording permission.
extension AppDelegate {
    func runSnapshotsIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["DICTATE_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                showOnboarding()
                if let w = onboardingWindow, let m = onboardingModel {
                    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    for step in TourStep.allCases {
                        m.step = step
                        if step == .tryIt { m.practiceText = "Let's move the standup to ten thirty tomorrow." }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        snap(w, "\(dir)/tour-\(step.rawValue)-\(suffix).png")
                    }
                    m.practiceText = ""
                    w.close()
                }
                openSettings()
                if let w = settingsWindow, let m = settingsModel {
                    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    w.setContentSize(NSSize(width: 820, height: 720))
                    for t in SettingsTab.allCases {
                        m.tab = t
                        if t == .text { m.draft.textCase = "random" }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        snap(w, "\(dir)/settings-\(t.rawValue)-\(suffix).png")
                    }
                    w.close()
                }
            }
            NSApp.terminate(nil)
        }
    }

    private func snap(_ w: NSWindow, _ path: String) {
        guard let v = w.contentView?.superview ?? w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
