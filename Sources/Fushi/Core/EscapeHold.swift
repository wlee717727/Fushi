import Foundation

/// 緊急退出：任何模式下「長按 Esc 3 秒」一定能結束清潔。
///
/// 按住一個鍵時，鍵盤會先送一次「按下」，之後每隔一小段時間送「重複按下」(autorepeat)。
/// 這裡記錄第一次按下的時間，之後每次收到重複按下就檢查「是否已經按住滿 3 秒」。
/// 放開 (keyUp) 就重新計算。純邏輯，方便單元測試。
struct EscapeHoldDetector: Equatable, Sendable {
    static let escapeKeyCode: Int64 = 53
    let threshold: TimeInterval
    private(set) var pressedAt: TimeInterval?

    init(threshold: TimeInterval = SessionPolicy.emergencyEscapeSeconds) {
        self.threshold = threshold
    }

    /// 收到 Esc 按下 (含重複)。回傳 true 代表已經按住滿門檻，應該立刻退出。
    mutating func keyDown(isRepeat: Bool, at time: TimeInterval) -> Bool {
        // 第一次按下 (不是重複)，或中間漏掉了放開事件：都從這一刻重新起算
        guard isRepeat, let start = pressedAt else {
            pressedAt = time
            return false
        }
        if time - start >= threshold {
            pressedAt = nil
            return true
        }
        return false
    }

    mutating func keyUp() {
        pressedAt = nil
    }
}
