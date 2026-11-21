import Foundation
import ApplicationServices

/// 執行緒安全的小盒子：攔截執行緒讀、主執行緒寫的值 (例如回呼函式) 都放這裡。
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: Value) { lock.lock(); value = newValue; lock.unlock() }
}

/// 緊急退出守門員：鍵盤鎖與觸控板鎖共用，全部不經過主執行緒。
///
/// 1. 長按 Esc 3 秒：第一次按下就開始計時，放開就取消，時間到一定觸發。
///    不依賴系統的「按鍵重複」(使用者把按鍵重複關掉時，舊做法永遠不會觸發)。
/// 2. 每秒檢查「輔助使用」權限：清潔中被撤銷，就立刻通知攔截器停止，
///    避免 macOS 在權限消失後讓輸入整個卡住。
final class EmergencyGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var holdTimer: DispatchSourceTimer?
    private var permissionTimer: DispatchSourceTimer?
    private var holding = false
    /// 權限檢查連續失敗幾次 (連續 2 次才算權限消失：剛從睡眠醒來時攔截可能一瞬間還沒恢復)
    private var permissionFailures = 0
    private let holdSeconds: TimeInterval
    private let onHoldCompleted: @Sendable () -> Void
    private let onPermissionLost: @Sendable () -> Void
    private let isTapHealthy: @Sendable () -> Bool

    /// 回呼都在背景佇列呼叫。
    /// isTapHealthy：攔截是否還在作用 (被系統停用且重新啟用失敗就回傳 false)。
    /// 有些系統版本把 App 從權限清單移除後，AXIsProcessTrusted 仍回報已允許，所以兩個都看。
    init(holdSeconds: TimeInterval = SessionPolicy.emergencyEscapeSeconds,
         onHoldCompleted: @escaping @Sendable () -> Void,
         onPermissionLost: @escaping @Sendable () -> Void,
         isTapHealthy: @escaping @Sendable () -> Bool = { true }) {
        self.holdSeconds = holdSeconds
        self.onHoldCompleted = onHoldCompleted
        self.onPermissionLost = onPermissionLost
        self.isTapHealthy = isTapHealthy
    }

    /// 開始監看權限 (攔截開始時呼叫)
    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let ok = AXIsProcessTrusted() && self.isTapHealthy()
            self.lock.lock()
            self.permissionFailures = ok ? 0 : self.permissionFailures + 1
            let lost = self.permissionFailures >= 2
            self.lock.unlock()
            guard lost else { return }
            self.stop()
            self.onPermissionLost()
        }
        lock.lock(); permissionTimer = timer; permissionFailures = 0; lock.unlock()
        timer.resume()
    }

    /// 停止所有計時 (攔截結束時呼叫)。可以重複呼叫。
    func stop() {
        lock.lock()
        let hold = holdTimer, permission = permissionTimer
        holdTimer = nil; permissionTimer = nil; holding = false
        lock.unlock()
        hold?.cancel()
        permission?.cancel()
    }

    /// Esc 按下 (含重複)。回傳 true 代表「剛開始按住」，畫面要顯示倒數。
    func escDown() -> Bool {
        lock.lock()
        guard !holding else { lock.unlock(); return false }
        holding = true
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + holdSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let still = self.holding
            self.holding = false
            self.holdTimer = nil
            self.lock.unlock()
            if still { self.onHoldCompleted() }
        }
        holdTimer = timer
        lock.unlock()
        timer.resume()
        return true
    }

    /// Esc 放開。回傳 true 代表原本在按住 (畫面要取消倒數)。
    func escUp() -> Bool {
        lock.lock()
        let was = holding
        let timer = holdTimer
        holding = false
        holdTimer = nil
        lock.unlock()
        timer?.cancel()
        return was
    }
}
