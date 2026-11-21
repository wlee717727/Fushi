import XCTest

/// 緊急退出守門員：長按 Esc 用計時器判斷，不依賴系統的「按鍵重複」。
final class EmergencyGuardTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// 只按一次、完全沒有重複按鍵 (使用者把按鍵重複關掉)，按住滿時間也要觸發
    func testHoldTriggersWithoutKeyRepeat() {
        let fired = expectation(description: "長按觸發")
        let guardian = EmergencyGuard(holdSeconds: 0.3, onHoldCompleted: { fired.fulfill() }, onPermissionLost: {})
        XCTAssertTrue(guardian.escDown(), "第一次按下要回報「開始按住」")
        wait(for: [fired], timeout: 2)
    }

    /// 時間還沒到就放開：不可以觸發
    func testReleaseBeforeThresholdCancels() {
        let counter = Counter()
        let guardian = EmergencyGuard(holdSeconds: 0.3, onHoldCompleted: { counter.add() }, onPermissionLost: {})
        XCTAssertTrue(guardian.escDown())
        XCTAssertTrue(guardian.escUp(), "放開要回報「原本在按住」")
        let done = expectation(description: "等超過門檻")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(counter.count, 0)
    }

    /// 按住期間的重複按鍵不會重新起算，也只觸發一次
    func testRepeatsDoNotRestartTimer() {
        let counter = Counter()
        let fired = expectation(description: "長按觸發")
        let guardian = EmergencyGuard(holdSeconds: 0.3, onHoldCompleted: { counter.add(); fired.fulfill() },
                                      onPermissionLost: {})
        XCTAssertTrue(guardian.escDown())
        XCTAssertFalse(guardian.escDown(), "重複按下不是新的按住")
        XCTAssertFalse(guardian.escDown())
        wait(for: [fired], timeout: 2)
        XCTAssertEqual(counter.count, 1)
    }

    /// 沒有在按住時放開 (例如鎖定前就按著 Esc)：不算取消
    func testReleaseWithoutHoldIsIgnored() {
        let guardian = EmergencyGuard(holdSeconds: 0.3, onHoldCompleted: {}, onPermissionLost: {})
        XCTAssertFalse(guardian.escUp())
    }

    /// 停止後計時取消，不會再觸發
    func testStopCancelsPendingHold() {
        let counter = Counter()
        let guardian = EmergencyGuard(holdSeconds: 0.3, onHoldCompleted: { counter.add() }, onPermissionLost: {})
        _ = guardian.escDown()
        guardian.stop()
        let done = expectation(description: "等超過門檻")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(counter.count, 0)
    }

    /// 緊急退出固定 3 秒、Esc 按鍵代碼 53 (所有模式一致，說明文字也寫 3 秒)
    func testEscapeConstants() {
        XCTAssertEqual(SessionPolicy.emergencyEscapeSeconds, 3)
        XCTAssertEqual(EscapeKey.keyCode, 53)
    }

    /// 攔截失效 (權限被移除但系統仍回報已允許) 也要算權限消失
    func testUnhealthyTapCountsAsPermissionLost() {
        let lost = expectation(description: "判定權限消失")
        let guardian = EmergencyGuard(holdSeconds: 3, onHoldCompleted: {}, onPermissionLost: { lost.fulfill() },
                                      isTapHealthy: { false })
        guardian.start()
        wait(for: [lost], timeout: 4)   // 連續 2 次 (約 2 秒) 才判定
        guardian.stop()
    }

    func testLockedBox() {
        let box = Locked(1)
        box.set(2)
        XCTAssertEqual(box.get(), 2)
    }
}
