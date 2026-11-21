import AppKit
import CoreGraphics

/// 用主動式 CGEventTap 擋下鍵盤事件 (C 面鎖鍵盤、全鎖)。
///
/// 設計重點：
/// 1. 攔截跑在「自己的執行緒」上，主執行緒 (畫面) 忙碌時也不會拖慢鍵盤事件，
///    回呼函式也盡量輕快，避免被系統判定逾時而停用。
/// 2. 多重自動解鎖保險，全部不依賴主執行緒：
///    - 回呼函式每次都檢查截止時間，過了就一律放行 (同時看時鐘與開機計時：
///      睡眠時開機計時會暫停、使用者把時鐘往回調時時鐘會倒退，兩者取先到的)；
///    - 背景計時器 (watchdog) 到時間直接關閉攔截；
///    - 長按 Esc 3 秒 (計時器判斷，不依賴系統的按鍵重複)；
///    - 「輔助使用」權限被撤銷時立刻停止。
/// 3. App 當掉或被強制結束時，攔截會跟著程序一起消失，鍵盤自動恢復；
///    這個類別不修改任何系統設定。
final class KeyboardLocker: @unchecked Sendable {

    /// 系統定義事件 (NX_SYSDEFINED)：亮度、音量、播放等功能鍵走這個類型。
    static let systemDefinedType: UInt32 = 14
    /// NX_SYSDEFINED 的子類型 7 是「滑鼠按鍵狀態」，不是鍵盤，所以放行。
    static let auxMouseButtonsSubtype: Int16 = 7
    /// 長按 Esc 解鎖後，手還按著 Esc：最多吞掉這麼久的 Esc 事件，避免打進前景 App
    static let drainSeconds: TimeInterval = 1.5

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var watchdog: DispatchSourceTimer?
    private var drainTimer: DispatchSourceTimer?
    private var deadline: Date = .distantPast
    private var deadlineUptime: TimeInterval = 0
    private var active = false
    /// 長按 Esc 已解鎖、正在等 Esc 放開：只擋 Esc，其他按鍵全部放行
    private var draining = false
    private var lastBlockedNotify: TimeInterval = 0
    /// 在 init 建立 (不用 lazy：攔截執行緒與主執行緒可能同時第一次存取)
    private var emergency: EmergencyGuard!

    init() {
        emergency = EmergencyGuard(
            onHoldCompleted: { [weak self] in self?.beginDrain() },
            onPermissionLost: { [weak self] in self?.permissionLost() },
            isTapHealthy: { [weak self] in self?.tapHealthy() ?? true })
    }

    /// 目前擋下的事件數量 (只用於顯示，不記錄內容)
    private(set) var blockedCount = 0

    // 回呼函式：主執行緒設定、攔截執行緒讀取，所以放在加鎖的盒子裡
    private let _onEmergencyExit = Locked<(() -> Void)?>(nil)
    private let _onEscapeHoldChanged = Locked<((Bool) -> Void)?>(nil)
    private let _onBlockedInput = Locked<(() -> Void)?>(nil)
    private let _onPermissionLost = Locked<(() -> Void)?>(nil)

    /// 長按 Esc 3 秒 (在主執行緒呼叫)；按鍵這時已經恢復 (只剩還按著的 Esc 會被吞掉)
    var onEmergencyExit: (() -> Void)? {
        get { _onEmergencyExit.get() } set { _onEmergencyExit.set(newValue) }
    }
    /// Esc 開始按住 (true)／放開 (false)，在主執行緒呼叫；用來在畫面上顯示 3 秒倒數
    var onEscapeHoldChanged: ((Bool) -> Void)? {
        get { _onEscapeHoldChanged.get() } set { _onEscapeHoldChanged.set(newValue) }
    }
    /// 有按鍵被擋下 (最多每 0.4 秒一次，在主執行緒呼叫)；全黑時用來讓畫面呼吸一下
    var onBlockedInput: (() -> Void)? {
        get { _onBlockedInput.get() } set { _onBlockedInput.set(newValue) }
    }
    /// 清潔中「輔助使用」權限被撤銷 (在主執行緒呼叫)；攔截已經停止
    var onPermissionLost: (() -> Void)? {
        get { _onPermissionLost.get() } set { _onPermissionLost.set(newValue) }
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    /// 開始鎖鍵盤，直到 `deadline` 為止。
    /// 回傳 false 代表系統不允許建立攔截 (通常是沒有「輔助使用」權限)。
    func start(until deadline: Date) -> Bool {
        stopNow()

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        mask |= CGEventMask(1) << Self.systemDefinedType

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,      // 主動攔截 (可以擋下事件)
                                          eventsOfInterest: mask,
                                          callback: keyboardLockerCallback,
                                          userInfo: refcon) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        let remaining = max(0, deadline.timeIntervalSinceNow)
        lock.lock()
        self.tap = tap
        self.source = source
        self.deadline = deadline
        self.deadlineUptime = ProcessInfo.processInfo.systemUptime + remaining
        self.active = true
        self.draining = false
        self.blockedCount = 0
        lock.unlock()

        // 專用執行緒：把攔截加到這條執行緒的 RunLoop 再開始跑。
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            self?.lock.lock()
            self?.runLoop = rl
            self?.lock.unlock()
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "拂拭.鍵盤攔截"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)

        // Watchdog：到截止時間就關掉攔截，完全不經過主執行緒。
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + remaining + 0.25)
        timer.setEventHandler { [weak self] in self?.stopNow() }
        lock.lock(); watchdog = timer; lock.unlock()
        timer.resume()
        emergency.start()
        return true
    }

    /// 停止攔截 (一般結束清潔時呼叫)。可以重複呼叫，也可以從任何執行緒呼叫。
    /// 長按 Esc 解鎖後正在等 Esc 放開時，不會立刻拆掉 (等放開或最多 1.5 秒後自己結束)。
    func stop() {
        lock.lock()
        let drain = draining
        lock.unlock()
        if drain { return }
        stopNow()
    }

    /// 立刻拆掉攔截，不等任何事。
    private func stopNow() {
        lock.lock()
        let tap = self.tap, source = self.source, runLoop = self.runLoop
        let watchdog = self.watchdog, drainTimer = self.drainTimer
        self.tap = nil; self.source = nil; self.runLoop = nil
        self.watchdog = nil; self.drainTimer = nil
        self.active = false
        self.draining = false
        lock.unlock()

        emergency.stop()
        watchdog?.cancel()
        drainTimer?.cancel()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
    }

    /// 長按 Esc 滿 3 秒 (背景佇列)：其他按鍵立刻恢復，只吞掉還按著的 Esc，再通知畫面結束清潔
    private func beginDrain() {
        lock.lock()
        guard active, !draining else { lock.unlock(); return }
        draining = true
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + Self.drainSeconds)
        timer.setEventHandler { [weak self] in self?.stopNow() }
        drainTimer = timer
        lock.unlock()
        timer.resume()
        emergency.stop()
        if let callback = onEmergencyExit { DispatchQueue.main.async { callback() } }
    }

    /// 權限被撤銷 (背景佇列)：立刻拆掉攔截，再通知畫面
    /// 攔截是否還在作用：被系統停用就試著重新啟用，還是不行代表權限已經消失
    private func tapHealthy() -> Bool {
        lock.lock()
        let tap = self.tap
        lock.unlock()
        guard let tap else { return true }
        if CGEvent.tapIsEnabled(tap: tap) { return true }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func permissionLost() {
        guard isActive else { return }
        stopNow()
        if let callback = onPermissionLost { DispatchQueue.main.async { callback() } }
    }

    /// 節流後通知「有按鍵被擋下」
    private func notifyBlocked(_ type: CGEventType) {
        guard type == .keyDown || type.rawValue == Self.systemDefinedType else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let fire = now - lastBlockedNotify > 0.4
        if fire { lastBlockedNotify = now }
        lock.unlock()
        if fire, let callback = onBlockedInput { DispatchQueue.main.async { callback() } }
    }

    private func notifyHold(_ holding: Bool) {
        if let callback = onEscapeHoldChanged { DispatchQueue.main.async { callback(holding) } }
    }

    /// 在攔截執行緒上被呼叫。要快：只做判斷，不做任何耗時工作。
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        lock.lock()
        let running = active && Date() < deadline && ProcessInfo.processInfo.systemUptime < deadlineUptime
        let drain = draining
        let tap = self.tap
        lock.unlock()

        // 系統因為逾時或使用者輸入把攔截停掉了 → 立刻重新啟用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if running || drain, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let isKey = type == .keyDown || type == .keyUp || type == .flagsChanged
        let isEscape = isKey && event.getIntegerValueField(.keyboardEventKeycode) == EscapeKey.keyCode

        // 已經解鎖、只等 Esc 放開：吞掉 Esc，其他全部放行
        if drain {
            if isEscape && type == .keyUp { stopNow() }
            return isEscape ? nil : pass
        }
        // 安全第一：時間到或已停止，一律放行
        guard running else { return pass }

        if isKey {
            if isEscape {
                if type == .keyDown, emergency.escDown() { notifyHold(true) }
                if type == .keyUp, emergency.escUp() { notifyHold(false) }
            }
            blockedCount &+= 1
            notifyBlocked(type)
            return nil
        }
        if type.rawValue == Self.systemDefinedType {
            // 功能鍵 (亮度、音量、媒體) 擋下；滑鼠按鍵狀態 (子類型 7) 放行
            let subtype = NSEvent(cgEvent: event)?.subtype.rawValue ?? 0
            if subtype == Self.auxMouseButtonsSubtype { return pass }
            blockedCount &+= 1
            notifyBlocked(type)
            return nil
        }
        return pass
    }

    deinit { stopNow() }
}

/// C 函式指標形式的回呼，不能捕捉變數，所以透過 userInfo 找回 KeyboardLocker。
private func keyboardLockerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let locker = Unmanaged<KeyboardLocker>.fromOpaque(userInfo).takeUnretainedValue()
    return locker.handle(type: type, event: event)
}
