import Foundation

/// 所有和時間有關的規則集中在這裡，方便測試，也避免數字散落各處。
enum SessionPolicy {
    /// 自動解鎖時間的範圍 (秒)
    static let minimumSeconds = 30
    static let maximumSeconds = 600
    static let defaultSeconds = 180
    static let stepSeconds = 10

    /// Debug 版 (開發測試用) 的自動解鎖上限：30 秒。
    static let debugCapSeconds = 30

    /// 開始前的倒數 (秒)
    static let countdownSeconds: TimeInterval = 3
    /// B 面控制面板亮起後，多久沒操作就回到全黑 (秒)
    static let panelIdleSeconds: TimeInterval = 8
    /// 「結束清潔」要按住多久 (秒)
    static let holdToEndSeconds: TimeInterval = 2
    /// 緊急退出：任何模式下長按 Esc 幾秒一定能結束 (鍵盤鎖住時也有效)
    static let emergencyEscapeSeconds: TimeInterval = 3

    /// 目前是不是 Debug 版。
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// 把使用者設定的秒數換算成實際使用的秒數：
    /// 先夾在 30～600 之間；Debug 版再強制不超過 30 秒。
    static func effectiveDuration(requested: Int, isDebug: Bool) -> Int {
        let clamped = min(max(requested, minimumSeconds), maximumSeconds)
        return isDebug ? min(clamped, debugCapSeconds) : clamped
    }

    /// 把秒數格式化成「2:05」。
    static func clockText(seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 把秒數格式化成「3 分 0 秒」。
    static func durationText(seconds: Int) -> String {
        let s = max(seconds, 0)
        if s < 60 { return "\(s) 秒" }
        return s % 60 == 0 ? "\(s / 60) 分鐘" : "\(s / 60) 分 \(s % 60) 秒"
    }
}
