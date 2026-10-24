import Foundation

public protocol HoldScheduler: Sendable {
    /// Run `block` after `delay`. The returned closure cancels it.
    func after(_ delay: TimeInterval, _ block: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}

public struct MainQueueScheduler: HoldScheduler {
    public init() {}
    public func after(_ delay: TimeInterval, _ block: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

public enum HoldEvent: Equatable, Sendable { case begin, end }

/// Turns "a modifier key held for `threshold` seconds" into begin/end events.
///  - Released before the threshold: nothing happens (a normal tap of the key).
///  - Another key or modifier pressed before the threshold: nothing happens (the key was used as a modifier, e.g. Option+E).
///  - Held past the threshold: `.begin`; releasing then sends `.end`. Other keys pressed after `.begin` do not stop it.
/// Not thread-safe: call every method from one thread (the main thread, where the event tap runs).
public final class LongPressDetector: @unchecked Sendable {
    private let threshold: TimeInterval
    private let scheduler: HoldScheduler
    private let emit: @Sendable (HoldEvent) -> Void
    private var isDown = false
    private var isActive = false
    private var generation = 0
    private var cancelTimer: (@Sendable () -> Void)?

    public init(threshold: TimeInterval, scheduler: HoldScheduler = MainQueueScheduler(), emit: @escaping @Sendable (HoldEvent) -> Void) {
        self.threshold = threshold; self.scheduler = scheduler; self.emit = emit
    }

    public var active: Bool { isActive }

    public func keyChanged(isDown down: Bool) {
        if down {
            guard !isDown else { return }   // key repeat or duplicate event
            isDown = true
            generation += 1
            let g = generation
            cancelTimer = scheduler.after(threshold) { [weak self] in self?.fire(g) }
        } else {
            guard isDown else { return }
            isDown = false
            generation += 1
            cancelTimer?(); cancelTimer = nil
            if isActive { isActive = false; emit(.end) }
        }
    }

    /// Any other key or modifier went down.
    public func otherKeyPressed() {
        guard isDown, !isActive else { return }
        generation += 1
        cancelTimer?(); cancelTimer = nil
    }

    /// The event source went away (tap disabled, app quitting). Ends an active hold so recording cannot get stuck.
    public func reset() {
        keyChanged(isDown: false)
    }

    private func fire(_ g: Int) {
        guard g == generation, isDown, !isActive else { return }
        isActive = true
        cancelTimer = nil
        emit(.begin)
    }
}
