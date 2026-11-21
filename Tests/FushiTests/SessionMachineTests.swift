import XCTest

/// 狀態機與計時規則的單元測試：不需要真的鎖鍵盤，也能確認流程正確。
final class SessionMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// 開始 B 面清潔並跑完 3 秒倒數 (Release 規則，180 秒)。
    private func cleaningScreenB(seconds: Int = 180, debug: Bool = false) -> SessionState {
        var s = SessionState(isDebugBuild: debug)
        s.handle(.start(.screenB, requestedSeconds: seconds, now: t0))
        s.handle(.tick(now: at(3)))
        return s
    }

    // MARK: 模式

    func testDeckTargetRejectsNothingSelected() {
        XCTAssertNil(DeckTarget(keyboard: false, trackpad: false))
        XCTAssertEqual(DeckTarget(keyboard: true, trackpad: false), .keyboard)
        XCTAssertEqual(DeckTarget(keyboard: false, trackpad: true), .trackpad)
        XCTAssertEqual(DeckTarget(keyboard: true, trackpad: true), .keyboardAndTrackpad)
    }

    func testAllModesAvailable() {
        XCTAssertTrue(CleaningMode.screenB.isAvailableInPhase1)
        for target in DeckTarget.allCases { XCTAssertTrue(CleaningMode.deckC(target).isAvailableInPhase1) }
        XCTAssertTrue(CleaningMode.all.isAvailableInPhase1)
    }

    func testModeProperties() {
        XCTAssertTrue(CleaningMode.screenB.usesBlackScreen)
        XCTAssertTrue(CleaningMode.all.usesBlackScreen)
        XCTAssertFalse(CleaningMode.deckC(.keyboard).usesBlackScreen)
        XCTAssertFalse(CleaningMode.screenB.needsAccessibility, "B 面不需要任何權限")
        XCTAssertTrue(CleaningMode.deckC(.trackpad).needsAccessibility, "鎖觸控板也需要輔助使用")
        XCTAssertTrue(CleaningMode.deckC(.trackpad).locksTrackpad)
        XCTAssertFalse(CleaningMode.deckC(.trackpad).locksKeyboard)
        XCTAssertTrue(CleaningMode.all.locksKeyboard && CleaningMode.all.locksTrackpad)
    }

    func testFullLockWakesPanel() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.all, requestedSeconds: 120, now: t0))
        s.handle(.tick(now: at(3)))
        XCTAssertEqual(s.screenDisplay, .dark)
        s.handle(.keyPressed(now: at(10)))   // 全鎖：動外接滑鼠叫出面板
        XCTAssertTrue(s.isPanelVisible)
        s.handle(.tick(now: at(18)))
        XCTAssertEqual(s.screenDisplay, .dark, "8 秒沒操作回到全黑")
    }

    func testStorageRoundTrip() {
        let modes: [CleaningMode] = [.screenB, .all] + DeckTarget.allCases.map { .deckC($0) }
        for mode in modes {
            XCTAssertEqual(CleaningMode(storageValue: mode.storageValue), mode)
        }
        XCTAssertNil(CleaningMode(storageValue: "deckC.nothing"))
        XCTAssertNil(CleaningMode(storageValue: ""))
    }

    // MARK: 時間規則

    func testDurationClampAndDebugCap() {
        XCTAssertEqual(SessionPolicy.effectiveDuration(requested: 5, isDebug: false), 30)
        XCTAssertEqual(SessionPolicy.effectiveDuration(requested: 180, isDebug: false), 180)
        XCTAssertEqual(SessionPolicy.effectiveDuration(requested: 9999, isDebug: false), 600)
        XCTAssertEqual(SessionPolicy.effectiveDuration(requested: 180, isDebug: true), 30)
        XCTAssertEqual(SessionPolicy.effectiveDuration(requested: 600, isDebug: true), 30)
    }

    func testClockText() {
        XCTAssertEqual(SessionPolicy.clockText(seconds: 180), "3:00")
        XCTAssertEqual(SessionPolicy.clockText(seconds: 65), "1:05")
        XCTAssertEqual(SessionPolicy.clockText(seconds: -3), "0:00")
        XCTAssertEqual(SessionPolicy.durationText(seconds: 180), "3 分鐘")
        XCTAssertEqual(SessionPolicy.durationText(seconds: 90), "1 分 30 秒")
        XCTAssertEqual(SessionPolicy.durationText(seconds: 30), "30 秒")
    }

    // MARK: 倒數

    func testCountdownThenCleaning() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.screenB, requestedSeconds: 180, now: t0))
        XCTAssertTrue(s.isCountingDown)
        XCTAssertEqual(s.countdownRemaining(at: at(0.1)), 3)

        s.handle(.tick(now: at(2.9)))
        XCTAssertTrue(s.isCountingDown, "倒數還沒結束")

        s.handle(.tick(now: at(3.2)))   // 計時器晚了 0.2 秒
        XCTAssertTrue(s.isCleaning)
        XCTAssertEqual(s.screenDisplay, .dark)
        // 截止時間從倒數結束 (第 3 秒) 起算，不受計時器延遲影響
        XCTAssertEqual(s.deadline, at(183))
    }

    func testCancelCountdown() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.deckC(.keyboard), requestedSeconds: 180, now: t0))
        s.handle(.cancelCountdown)
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.lastEnd, .countdownCancelled)
        // 取消後再 tick 不會開始
        s.handle(.tick(now: at(10)))
        XCTAssertTrue(s.isIdle)
    }

    func testCannotStartTwice() {
        var s = cleaningScreenB()
        let before = s
        s.handle(.start(.deckC(.keyboard), requestedSeconds: 60, now: at(5)))
        XCTAssertEqual(s, before)
    }

    // MARK: 自動解鎖 (最高優先的安全機制)

    func testAutoUnlockAtDeadline() {
        var s = cleaningScreenB(seconds: 60)
        s.handle(.tick(now: at(62.9)))
        XCTAssertTrue(s.isCleaning)
        XCTAssertEqual(s.remainingSeconds(at: at(62.9)), 1)
        s.handle(.tick(now: at(63)))
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.lastEnd, .timeout)
    }

    func testAutoUnlockWinsEvenWhenPanelIsOpen() {
        var s = cleaningScreenB(seconds: 30)
        s.handle(.keyPressed(now: at(30)))
        XCTAssertTrue(s.isPanelVisible)
        s.handle(.tick(now: at(40)))   // 截止時間 33 秒早就過了
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.lastEnd, .timeout)
    }

    func testDebugBuildCapsAt30Seconds() {
        var s = cleaningScreenB(seconds: 600, debug: true)
        XCTAssertEqual(s.deadline, at(33))
        s.handle(.tick(now: at(33)))
        XCTAssertTrue(s.isIdle)
    }

    func testKeyboardLockAutoUnlock() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.deckC(.keyboard), requestedSeconds: 30, now: t0))
        s.handle(.tick(now: at(3)))
        XCTAssertTrue(s.isCleaning)
        XCTAssertNil(s.screenDisplay, "只鎖鍵盤沒有 B 面的全黑畫面")
        s.handle(.tick(now: at(33)))
        XCTAssertTrue(s.isIdle)
    }

    // MARK: B 面兩段式顯示

    func testKeyWakesPanelAndIdleReturnsToDark() {
        var s = cleaningScreenB()
        s.handle(.keyPressed(now: at(10)))
        XCTAssertEqual(s.screenDisplay, .panel(lastInteraction: at(10)))

        s.handle(.tick(now: at(17.9)))
        XCTAssertTrue(s.isPanelVisible, "還沒滿 8 秒")

        s.handle(.interaction(now: at(17)))   // 有操作 → 重新計時
        s.handle(.tick(now: at(24.9)))
        XCTAssertTrue(s.isPanelVisible)

        s.handle(.tick(now: at(25)))
        XCTAssertEqual(s.screenDisplay, .dark)
        XCTAssertTrue(s.isCleaning, "回到全黑但仍在清潔")
    }

    func testResumeDark() {
        var s = cleaningScreenB()
        s.handle(.keyPressed(now: at(10)))
        s.handle(.resumeDark)
        XCTAssertEqual(s.screenDisplay, .dark)
    }

    func testInteractionInDarkDoesNotWake() {
        // 擦螢幕時觸控會產生滑鼠事件，不能把畫面叫醒 (第 1 階段只用鍵盤喚醒)
        var s = cleaningScreenB()
        s.handle(.interaction(now: at(10)))
        XCTAssertEqual(s.screenDisplay, .dark)
    }

    func testKeyPressDoesNotAffectKeyboardLockMode() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.deckC(.keyboard), requestedSeconds: 60, now: t0))
        s.handle(.tick(now: at(3)))
        let before = s
        s.handle(.keyPressed(now: at(5)))
        XCTAssertEqual(s, before)
    }

    // MARK: 結束

    func testConfirmEnd() {
        var s = cleaningScreenB()
        s.handle(.confirmEnd)
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.lastEnd, .userConfirmed)
    }

    func testLockFailedReturnsToIdle() {
        var s = SessionState(isDebugBuild: false)
        s.handle(.start(.deckC(.keyboard), requestedSeconds: 60, now: t0))
        s.handle(.tick(now: at(3)))
        s.handle(.lockFailed("缺少輔助使用權限"))
        XCTAssertTrue(s.isIdle)
        XCTAssertEqual(s.lastEnd, .lockFailed("缺少輔助使用權限"))
    }

    func testIdleIgnoresStrayEvents() {
        var s = SessionState(isDebugBuild: false)
        for e: SessionEvent in [.tick(now: t0), .keyPressed(now: t0), .resumeDark, .confirmEnd, .cancelCountdown] {
            s.handle(e)
            XCTAssertTrue(s.isIdle)
        }
        XCTAssertNil(s.lastEnd)
    }
}
