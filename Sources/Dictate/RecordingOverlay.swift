import AppKit
import QuartzCore

/// A floating waveform overlay that appears near the cursor while recording.
/// Shows 9 vertical bars (tallest in center) that pulse like a live audio
/// waveform. Disappears on release.
final class RecordingOverlay {
    private var window: NSPanel?
    private var bars: [CALayer] = []
    private var originalHeights: [CGFloat] = []
    private let size: CGFloat = 80

    private var stateLabel: NSTextField?
    private var currentState: String = "Recording"

    func show(state: String = "Recording") {
        currentState = state
        // Rebuild window each time to ensure it appears on the current space (including full-screen spaces)
        if window != nil {
            window?.orderOut(nil)
            window = nil
            bars = []
            originalHeights = []
        }
        build()
        stateLabel?.stringValue = state
        // Reset bar heights to original (updateLevel may have shrunk them)
        for (i, bar) in bars.enumerated() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.bounds.size.height = originalHeights[i]
            CATransaction.commit()
        }
        refreshColors()
        positionNearCursor()
        // Regardless: we're an accessory app and must not steal focus from the paste target.
        window?.orderFrontRegardless()
        startAnimation()
    }

    func updateLevel(_ power: Float) {
        // Map dB (-60..0) to a 0..1 scale; clamp
        let normalized = max(0, min(1, (power + 60) / 60))
        for (i, bar) in bars.enumerated() {
            let baseH = originalHeights[i]
            let scale = 0.3 + normalized * 0.7
            let newH = baseH * CGFloat(scale)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.bounds.size.height = newH
            bar.position.y = (window?.contentView?.bounds.height ?? 80) / 2 + 6
            CATransaction.commit()
        }
    }

    func hide() {
        stopAnimation()
        window?.orderOut(nil)
    }

    private func build() {
        // Only a non-activating panel is allowed onto another app's full-screen Space.
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.hidesOnDeactivate = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        let layer = v.layer!

        // No container box, no glow circle — just the waveform bars.

        // 9 waveform bars (heights: short -> tall -> short)
        let heights: [CGFloat] = [0.25, 0.45, 0.65, 0.85, 1.0, 0.85, 0.65, 0.45, 0.25]
        let barW: CGFloat = 4
        let gap: CGFloat = 4
        let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
        let startX = (size - totalW) / 2
        let maxH = size * 0.55
        for (i, h) in heights.enumerated() {
            let bar = CALayer()
            let bh = maxH * h
            bar.bounds = CGRect(x: 0, y: 0, width: barW, height: bh)
            bar.position = CGPoint(x: startX + CGFloat(i) * (barW + gap) + barW / 2,
                                   y: size / 2 + 6)
            bar.cornerRadius = barW / 2
            // Adapt opacity to dark/light mode: brighter in dark mode, dimmer in light mode
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            bar.backgroundColor = NSColor.systemRed.withAlphaComponent(isDark ? 0.9 : 0.75).cgColor
            // Add shadow in light mode for contrast
            if !isDark {
                bar.shadowColor = NSColor.black.cgColor
                bar.shadowRadius = 4
                bar.shadowOpacity = 0.3
                bar.shadowOffset = .zero
            }
            layer.addSublayer(bar)
            bars.append(bar)
            originalHeights.append(bh)
        }

        // State label beneath the bars
        let label = NSTextField(labelWithString: currentState)
        label.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 4, width: size, height: 12)
        v.addSubview(label)
        stateLabel = label
        w.contentView = v
        self.window = w
    }

    private func positionNearCursor() {
        guard let w = window else { return }
        let mouseLoc = NSEvent.mouseLocation
        let x = mouseLoc.x - size / 2
        let y = mouseLoc.y - size / 2
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refreshColors() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for bar in bars {
            bar.backgroundColor = NSColor.systemRed.withAlphaComponent(isDark ? 0.9 : 0.75).cgColor
            if !isDark {
                bar.shadowColor = NSColor.black.cgColor
                bar.shadowRadius = 4
                bar.shadowOpacity = 0.3
                bar.shadowOffset = .zero
            } else {
                bar.shadowOpacity = 0
            }
        }
    }

    private func startAnimation() {
        for (i, bar) in bars.enumerated() {
            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = 0.4
            anim.toValue = 1.3
            anim.duration = 0.45 + Double(i) * 0.04
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(anim, forKey: "pulse")

            let op = CABasicAnimation(keyPath: "opacity")
            op.fromValue = 0.7
            op.toValue = 1.0
            op.duration = 0.45 + Double(i) * 0.04
            op.autoreverses = true
            op.repeatCount = .infinity
            bar.add(op, forKey: "op")
        }
    }

    private func stopAnimation() {
        for bar in bars { bar.removeAllAnimations() }
    }
}