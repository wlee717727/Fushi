import XCTest

/// 緊急退出 (長按 Esc 3 秒) 的判斷邏輯。
final class EscapeHoldTests: XCTestCase {
    func testHoldThreeSecondsTriggers() {
        var d = EscapeHoldDetector(threshold: 3)
        XCTAssertFalse(d.keyDown(isRepeat: false, at: 100))
        XCTAssertFalse(d.keyDown(isRepeat: true, at: 101))
        XCTAssertFalse(d.keyDown(isRepeat: true, at: 102.9))
        XCTAssertTrue(d.keyDown(isRepeat: true, at: 103.0))
        XCTAssertNil(d.pressedAt, "觸發後重新計算，不會連續觸發")
    }

    func testReleaseResets() {
        var d = EscapeHoldDetector(threshold: 3)
        _ = d.keyDown(isRepeat: false, at: 0)
        _ = d.keyDown(isRepeat: true, at: 2)
        d.keyUp()
        _ = d.keyDown(isRepeat: false, at: 2.5)
        XCTAssertFalse(d.keyDown(isRepeat: true, at: 5.0), "放開後重新算，只按了 2.5 秒")
        XCTAssertTrue(d.keyDown(isRepeat: true, at: 5.5))
    }

    func testShortTapsNeverTrigger() {
        var d = EscapeHoldDetector(threshold: 3)
        for i in 0..<20 {
            XCTAssertFalse(d.keyDown(isRepeat: false, at: Double(i)))
            d.keyUp()
        }
    }

    func testRepeatWithoutInitialPressStartsCounting() {
        // 鎖定開始前就按著 Esc：第一個收到的是重複事件，從這一刻開始算
        var d = EscapeHoldDetector(threshold: 3)
        XCTAssertFalse(d.keyDown(isRepeat: true, at: 10))
        XCTAssertFalse(d.keyDown(isRepeat: true, at: 12))
        XCTAssertTrue(d.keyDown(isRepeat: true, at: 13))
    }

    func testDefaultThresholdIsThreeSeconds() {
        XCTAssertEqual(EscapeHoldDetector().threshold, 3)
        XCTAssertEqual(SessionPolicy.emergencyEscapeSeconds, 3)
    }
}
