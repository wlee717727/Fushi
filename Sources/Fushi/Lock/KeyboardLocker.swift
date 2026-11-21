import AppKit
import CoreGraphics

/// 用主動式 CGEventTap 擋下鍵盤事件 (C 面「只鎖鍵盤」)。
///
/// 設計重點：
/// 1. 攔截跑在「自己的執行緒」上，主執行緒 (畫面) 忙碌時也不會拖慢鍵盤事件，
///    回呼函式也盡量輕快，避免被系統判定逾時而停用。
/// 2. 雙重自動解鎖保險：
///    - 回呼函式每次都檢查「截止時間過了沒」，過了就一律放行；
///    - 另有一個背景計時器 (watchdog) 到時間直接關閉攔截。
///    兩者都不依賴主執行緒，就算畫面卡住，時間到鍵盤也會恢復。
/// 3. App 當掉或被強制結束時，攔截會跟著程序一起消失，鍵盤自動恢復；
///    這個類別不修改任何系統設定。
final class KeyboardLocker: @unchecked Sendable {

    /// 系統定義事件 (NX_SYSDEFINED)：亮度、音量、播放等功能鍵走這個類型。
    static let systemDefinedType: UInt32 = 14
    /// NX_SYSDEFINED 的子類型 7 是「滑鼠按鍵狀態」，不是鍵盤，所以放行。
    static let auxMouseButtonsSubtype: Int16 = 7

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var watchdog: DispatchSourceTimer?
    private var deadline: Date = .distantPast
    private var active = false

    /// 目前擋下的事件數量 (只用於顯示，不記錄內容)
    private(set) var blockedCount = 0
    /// 緊急退出：長按 Esc 3 秒。按鍵本身照樣擋下，但這裡看得到它被按住多久。
    private var escape = EscapeHoldDetector()
    /// 偵測到長按 Esc 3 秒時呼叫 (在主執行緒)；攔截會先自己關閉，保證鍵盤立刻恢復
    var onEmergencyExit: (() -> Void)?
    /// Esc 開始按住 (true)／放開 (false)，在主執行緒呼叫；用來在畫面上顯示 3 秒倒數
    var onEscapeHoldChanged: ((Bool) -> Void)?
    /// 有按鍵被擋下 (最多每 0.4 秒一次，在主執行緒呼叫)；全黑時用來讓畫面呼吸一下
    var onBlockedInput: (() -> Void)?
    private var lastBlockedNotify: TimeInterval = 0

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

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    /// 開始鎖鍵盤，直到 `deadline` 為止。
    /// 回傳 false 代表系統不允許建立攔截 (通常是沒有「輔助使用」權限)。
    func start(until deadline: Date) -> Bool {
        stop()

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

        lock.lock()
        self.tap = tap
        self.source = source
        self.deadline = deadline
        self.active = true
        self.blockedCount = 0
        self.escape = EscapeHoldDetector()
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
        self.thread = thread
        thread.start()
        _ = ready.wait(timeout: .now() + 2)

        // Watchdog：到截止時間就關掉攔截，完全不經過主執行緒。
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow) + 0.25)
        timer.setEventHandler { [weak self] in self?.stop() }
        lock.lock(); watchdog = timer; lock.unlock()
        timer.resume()
        return true
    }

    /// 停止攔截。可以重複呼叫，也可以從任何執行緒呼叫。
    func stop() {
        lock.lock()
        let tap = self.tap, source = self.source, runLoop = self.runLoop, watchdog = self.watchdog
        self.tap = nil; self.source = nil; self.runLoop = nil; self.watchdog = nil
        self.thread = nil
        self.active = false
        lock.unlock()

        watchdog?.cancel()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
    }

    /// 在攔截執行緒上被呼叫。要快：只做判斷，不做任何耗時工作。
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系統因為逾時或使用者輸入把攔截停掉了 → 立刻重新啟用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = self.tap, stillActive = active && Date() < deadline
            lock.unlock()
            if stillActive, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let shouldBlock = active && Date() < deadline
        lock.unlock()
        // 安全第一：時間到或已停止，一律放行
        guard shouldBlock else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            if event.getIntegerValueField(.keyboardEventKeycode) == EscapeHoldDetector.escapeKeyCode {
                if type == .keyDown {
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    let now = ProcessInfo.processInfo.systemUptime
                    lock.lock()
                    let wasHolding = escape.pressedAt != nil
                    let trigger = escape.keyDown(isRepeat: isRepeat, at: now)
                    let startedHolding = !wasHolding && escape.pressedAt != nil
                    lock.unlock()
                    if startedHolding, let callback = onEscapeHoldChanged {
                        DispatchQueue.main.async { callback(true) }
                    }
                    if trigger {
                        // 先在這條執行緒直接關掉攔截 (不依賴主執行緒)，再通知畫面結束清潔
                        stop()
                        let callback = onEmergencyExit
                        DispatchQueue.main.async { callback?() }
                        return Unmanaged.passUnretained(event)
                    }
                } else if type == .keyUp {
                    lock.lock(); escape.keyUp(); lock.unlock()
                    if let callback = onEscapeHoldChanged {
                        DispatchQueue.main.async { callback(false) }
                    }
                }
            }
            blockedCount &+= 1
            notifyBlocked(type)
            return nil
        default:
            if type.rawValue == Self.systemDefinedType {
                // 功能鍵 (亮度、音量、媒體) 擋下；滑鼠按鍵狀態 (子類型 7) 放行
                let subtype = NSEvent(cgEvent: event)?.subtype.rawValue ?? 0
                if subtype == Self.auxMouseButtonsSubtype { return Unmanaged.passUnretained(event) }
                blockedCount &+= 1
                notifyBlocked(type)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
    }

    deinit { stop() }
}

/// C 函式指標形式的回呼，不能捕捉變數，所以透過 userInfo 找回 KeyboardLocker。
private func keyboardLockerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let locker = Unmanaged<KeyboardLocker>.fromOpaque(userInfo).takeUnretainedValue()
    return locker.handle(type: type, event: event)
}
