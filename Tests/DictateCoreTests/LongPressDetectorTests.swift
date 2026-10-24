import XCTest
@testable import DictateCore

final class FakeScheduler: HoldScheduler, @unchecked Sendable {
    private let l = NSLock()
    private var items: [Int: (delay: TimeInterval, block: @Sendable () -> Void)] = [:]
    private var next = 0
    private(set) var scheduledDelays: [TimeInterval] = []
    var pendingCount: Int { l.lock(); defer { l.unlock() }; return items.count }

    func after(_ delay: TimeInterval, _ block: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        l.lock(); let id = next; next += 1; items[id] = (delay, block); scheduledDelays.append(delay); l.unlock()
        return { [weak self] in self?.l.lock(); self?.items[id] = nil; self?.l.unlock() }
    }
    /// Fire every timer that has not been cancelled, as the clock reaching the threshold would.
    func fireAll() {
        l.lock(); let due = items; items = [:]; l.unlock()
        due.values.forEach { $0.block() }
    }
    /// Fire one specific old timer even though it was cancelled: proves a stale callback is ignored.
    func captureForStaleTest() -> [@Sendable () -> Void] {
        l.lock(); defer { l.unlock() }; return items.values.map { $0.block }
    }
}

final class Events: @unchecked Sendable {
    private let l = NSLock(); private var v: [HoldEvent] = []
    func add(_ e: HoldEvent) { l.lock(); v.append(e); l.unlock() }
    var all: [HoldEvent] { l.lock(); defer { l.unlock() }; return v }
}

final class LongPressDetectorTests: XCTestCase {
    var sched: FakeScheduler!, ev: Events!, d: LongPressDetector!
    override func setUp() {
        sched = FakeScheduler(); ev = Events()
        d = LongPressDetector(threshold: 0.3, scheduler: sched) { [ev] in ev!.add($0) }
    }

    func testHoldPastThresholdBeginsAndReleaseEnds() {
        d.keyChanged(isDown: true)
        XCTAssertEqual(ev.all, [], "nothing before the threshold")
        sched.fireAll()
        XCTAssertEqual(ev.all, [.begin]); XCTAssertTrue(d.active)
        d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [.begin, .end]); XCTAssertFalse(d.active)
    }
    func testUsesTheConfiguredThreshold() {
        d.keyChanged(isDown: true)
        XCTAssertEqual(sched.scheduledDelays, [0.3])
    }
    func testQuickTapDoesNothingAndCancelsTheTimer() {
        d.keyChanged(isDown: true); d.keyChanged(isDown: false)
        XCTAssertEqual(sched.pendingCount, 0, "timer must be cancelled")
        sched.fireAll()
        XCTAssertEqual(ev.all, [])
    }
    func testOtherKeyBeforeThresholdMeansModifierUse() {
        d.keyChanged(isDown: true)
        d.otherKeyPressed()   // Option+E for an accent
        sched.fireAll()
        XCTAssertEqual(ev.all, [], "must not start recording")
        d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [])
    }
    func testOtherKeyAfterBeginDoesNotStopTheRecording() {
        d.keyChanged(isDown: true); sched.fireAll()
        d.otherKeyPressed()
        XCTAssertEqual(ev.all, [.begin]); XCTAssertTrue(d.active)
        d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [.begin, .end])
    }
    func testDuplicateDownEventsScheduleOnlyOneTimer() {
        for _ in 0..<5 { d.keyChanged(isDown: true) }
        XCTAssertEqual(sched.scheduledDelays.count, 1)
        sched.fireAll()
        XCTAssertEqual(ev.all, [.begin])
    }
    func testReleaseWithoutPressIsIgnored() {
        d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [])
    }
    func testStaleTimerFromAnEarlierPressIsIgnored() {
        d.keyChanged(isDown: true)
        let stale = sched.captureForStaleTest()
        d.keyChanged(isDown: false)
        d.keyChanged(isDown: true)       // a new press; the old timer fires "late"
        stale.forEach { $0() }
        XCTAssertEqual(ev.all, [], "an old timer must not start the new press early")
        sched.fireAll()
        XCTAssertEqual(ev.all, [.begin])
    }
    func testResetEndsAnActiveHoldSoRecordingCannotGetStuck() {
        d.keyChanged(isDown: true); sched.fireAll()
        d.reset()
        XCTAssertEqual(ev.all, [.begin, .end])
        d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [.begin, .end], "the late real release must not end twice")
    }
    func testResetWhenIdleEmitsNothing() {
        d.reset(); XCTAssertEqual(ev.all, [])
    }
    func testTenHoldsInARow() {
        for _ in 0..<10 { d.keyChanged(isDown: true); sched.fireAll(); d.keyChanged(isDown: false) }
        XCTAssertEqual(ev.all.filter { $0 == .begin }.count, 10); XCTAssertEqual(ev.all.filter { $0 == .end }.count, 10)
    }
    func testAfterAModifierUseTheNextCleanHoldWorks() {
        d.keyChanged(isDown: true); d.otherKeyPressed(); d.keyChanged(isDown: false)
        d.keyChanged(isDown: true); sched.fireAll(); d.keyChanged(isDown: false)
        XCTAssertEqual(ev.all, [.begin, .end])
    }
    func testRealMainQueueSchedulerFiresAndCancels() {
        let fired = Events()
        let s = MainQueueScheduler()
        let exp = expectation(description: "fires"); exp.expectedFulfillmentCount = 1
        _ = s.after(0.05) { fired.add(.begin); exp.fulfill() }
        let cancel = s.after(0.05) { fired.add(.end) }
        cancel()
        wait(for: [exp], timeout: 2)
        Thread.sleep(forTimeInterval: 0.15)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(fired.all, [.begin], "the cancelled timer must not fire")
    }
}
