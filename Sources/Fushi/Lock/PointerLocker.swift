import AppKit
import CoreGraphics

/// 鎖住內建觸控板 (以及全鎖時的觸控螢幕)，外接滑鼠照常可用。
///
/// 做法：在最底層的 HID 位置建立主動式事件攔截。每個指標事件先查「是哪個實體裝置送的」，
/// 是內建觸控板就擋下 (點按與手勢沒反應，移動會把游標拉回原位)，其他裝置放行。
/// 同時「只看不擋」地監看 Esc：長按 3 秒一定能退出 (只鎖觸控板、鍵盤沒鎖時也有效)。
///
/// 安全設計和鍵盤鎖相同：專用執行緒、回呼只做判斷、到期一律放行、獨立的保險計時器、
/// 權限被撤銷立刻停止、App 當掉時攔截隨程序消失，不修改任何系統設定。
final class PointerLocker: @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var watchdog: DispatchSourceTimer?
    private var drainTimer: DispatchSourceTimer?
    private var deadline: Date = .distantPast
    private var deadlineUptime: TimeInterval = 0
    private var active = false
    /// 長按 Esc 已解鎖、正在等 Esc 放開：只擋 Esc，指標全部放行
    private var draining = false
    private var policy = PointerBlockPolicy(blockBuiltInTrackpad: true, blockTouchScreen: false)
    private var recent = RecentPointerSource()
    private var lastExternalNotify: TimeInterval = 0
    private var lastBlockedNotify: TimeInterval = 0
    /// 游標最後一個「允許」的位置：觸控板的移動被擋下時，把游標拉回這裡 (避免系統已先移動游標)
    private var lastAllowedLocation: CGPoint = .zero
    /// 診斷統計：每種來源收到幾筆、擋下幾筆 (結束時寫進診斷紀錄)
    private var stats: [String: (seen: Int, blocked: Int)] = [:]
    private var loggedSources: Set<String> = []
    private var emergency: EmergencyGuard!

    // 回呼函式：主執行緒設定、攔截執行緒讀取，所以放在加鎖的盒子裡
    private let _onEmergencyExit = Locked<(() -> Void)?>(nil)
    private let _onEscapeHoldChanged = Locked<((Bool) -> Void)?>(nil)
    private let _onExternalActivity = Locked<(() -> Void)?>(nil)
    private let _onBlockedInput = Locked<(() -> Void)?>(nil)
    private let _onPermissionLost = Locked<(() -> Void)?>(nil)

    /// 長按 Esc 3 秒 (在主執行緒呼叫)
    var onEmergencyExit: (() -> Void)? {
        get { _onEmergencyExit.get() } set { _onEmergencyExit.set(newValue) }
    }
    /// Esc 開始按住 (true)／放開 (false)，在主執行緒呼叫
    var onEscapeHoldChanged: ((Bool) -> Void)? {
        get { _onEscapeHoldChanged.get() } set { _onEscapeHoldChanged.set(newValue) }
    }
    /// 外接滑鼠有動作 (最多每 0.2 秒一次，在主執行緒呼叫)；全鎖時用來叫出控制面板
    var onExternalActivity: (() -> Void)? {
        get { _onExternalActivity.get() } set { _onExternalActivity.set(newValue) }
    }
    /// 內建觸控板的動作被擋下 (最多每 0.4 秒一次，在主執行緒呼叫)
    var onBlockedInput: (() -> Void)? {
        get { _onBlockedInput.get() } set { _onBlockedInput.set(newValue) }
    }
    /// 清潔中「輔助使用」權限被撤銷 (在主執行緒呼叫)；攔截已經停止
    var onPermissionLost: (() -> Void)? {
        get { _onPermissionLost.get() } set { _onPermissionLost.set(newValue) }
    }

    init() {
        emergency = EmergencyGuard(
            onHoldCompleted: { [weak self] in self?.beginDrain() },
            onPermissionLost: { [weak self] in self?.permissionLost() },
            isTapHealthy: { [weak self] in self?.tapHealthy() ?? true })
    }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    /// 開始攔截。回傳 false 代表系統不允許 (通常是沒有「輔助使用」權限)。
    func start(policy: PointerBlockPolicy, until deadline: Date) -> Bool {
        stopNow()
        let pointerTypes: [UInt32] = [1, 2, 3, 4, 5, 6, 7,      // 左右鍵按下放開、移動、拖曳
                                      18, 19, 20,               // 旋轉、手勢開始／結束
                                      22, 23, 24,               // 捲動、數位板
                                      25, 26, 27,               // 其他按鍵、拖曳
                                      29, 30, 31, 32, 33, 34]   // 手勢、縮放、滑動、智慧縮放、查詢、壓力
        var mask = pointerTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        mask |= CGEventMask(1) << CGEventType.keyDown.rawValue
        mask |= CGEventMask(1) << CGEventType.keyUp.rawValue

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: pointerLockerCallback, userInfo: refcon)
        else { return false }
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
        self.policy = policy
        self.recent = RecentPointerSource()
        self.stats = [:]
        self.loggedSources = []
        self.lastAllowedLocation = CGEvent(source: nil)?.location ?? .zero
        self.active = true
        self.draining = false
        lock.unlock()
        Diagnostics.log("指標攔截啟動：擋觸控板=\(policy.blockBuiltInTrackpad)、擋觸控螢幕=\(policy.blockTouchScreen)、查來源函式可用=\(EventSourceLookup.isAvailable)")

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            self?.lock.lock(); self?.runLoop = rl; self?.lock.unlock()
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "拂拭.指標攔截"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + remaining + 0.25)
        timer.setEventHandler { [weak self] in self?.stopNow() }
        lock.lock(); watchdog = timer; lock.unlock()
        timer.resume()
        emergency.start()
        return true
    }

    /// 停止攔截 (一般結束清潔時呼叫)。長按 Esc 解鎖後正在等 Esc 放開時，等放開或最多 1.5 秒後自己結束。
    func stop() {
        lock.lock()
        let drain = draining
        lock.unlock()
        if drain { return }
        stopNow()
    }

    private func stopNow() {
        lock.lock()
        let tap = self.tap, source = self.source, runLoop = self.runLoop
        let watchdog = self.watchdog, drainTimer = self.drainTimer
        let wasActive = active, summary = stats
        self.tap = nil; self.source = nil; self.runLoop = nil
        self.watchdog = nil; self.drainTimer = nil
        self.active = false
        self.draining = false
        lock.unlock()
        if wasActive {
            let text = summary.sorted { $0.key < $1.key }
                .map { "\($0.key) seen \($0.value.seen), blocked \($0.value.blocked)" }
                .joined(separator: "; ")
            Diagnostics.log("指標攔截結束：\(text.isEmpty ? "沒有收到任何指標事件" : text)")
        }
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

    /// 長按 Esc 滿 3 秒 (背景佇列)：指標立刻恢復，只吞掉還按著的 Esc，再通知畫面結束清潔
    private func beginDrain() {
        lock.lock()
        guard active, !draining else { lock.unlock(); return }
        draining = true
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + KeyboardLocker.drainSeconds)
        timer.setEventHandler { [weak self] in self?.stopNow() }
        drainTimer = timer
        lock.unlock()
        timer.resume()
        emergency.stop()
        if let callback = onEmergencyExit { DispatchQueue.main.async { callback() } }
    }

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

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        lock.lock()
        let running = active && Date() < deadline && ProcessInfo.processInfo.systemUptime < deadlineUptime
        let drain = draining
        let tap = self.tap
        lock.unlock()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if running || drain, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        // 按鍵：只看 Esc，按鍵本身一律放行 (鍵盤是否鎖由鍵盤鎖負責)
        if type == .keyDown || type == .keyUp {
            let isEscape = event.getIntegerValueField(.keyboardEventKeycode) == EscapeKey.keyCode
            if drain {
                // 已經解鎖、只等 Esc 放開：吞掉還在重複的 Esc 按下，避免打進前景 App。
                // 放開照常放行：只鎖觸控板時前景 App 已經收到按下，要讓它也收到放開；
                // 全鎖時放開會繼續傳到下游的鍵盤鎖，讓它也知道 Esc 放開了
                if isEscape && type == .keyUp { stopNow(); return pass }
                return isEscape ? nil : pass
            }
            guard running, isEscape else { return pass }
            if type == .keyDown, emergency.escDown() { notifyHold(true) }
            if type == .keyUp, emergency.escUp() { notifyHold(false) }
            return pass
        }
        // 時間到、已停止、或已經解鎖：指標一律放行
        guard running, !drain else { return pass }

        // 指標事件：查來源 → 判斷擋不擋
        let now = ProcessInfo.processInfo.systemUptime
        let sender = EventSourceLookup.sender(of: event)
        let observed = PointerSource.classify(sender)
        let isMove = [5, 6, 7, 27].contains(type.rawValue)   // 移動、拖曳
        lock.lock()
        let resolved = recent.resolve(observed, at: now)
        let block = policy.shouldBlock(resolved)
        var notify = false
        if resolved == .externalPointer && now - lastExternalNotify > 0.2 {
            lastExternalNotify = now
            notify = true
        }
        var blockedNotify = false
        if block && resolved == .builtInTrackpad && now - lastBlockedNotify > 0.4 {
            lastBlockedNotify = now
            blockedNotify = true
        }
        let key = "\(resolved)"
        var entry = stats[key] ?? (0, 0)
        entry.seen += 1
        if block { entry.blocked += 1 }
        stats[key] = entry
        let firstOfSource = loggedSources.insert("\(observed)").inserted
        if !block && isMove { lastAllowedLocation = event.location }
        let holdAt = lastAllowedLocation
        lock.unlock()

        if firstOfSource {
            Diagnostics.log("指標來源：\(observed)，事件類型 \(type.rawValue)，裝置 \(sender.map { "\($0.product) / \($0.className) / 內建=\(String(describing: $0.builtIn))" } ?? "查不到")")
        }
        if notify, let callback = onExternalActivity {
            DispatchQueue.main.async { callback() }
        }
        if blockedNotify, let callback = onBlockedInput {
            DispatchQueue.main.async { callback() }
        }
        if block && isMove {
            // 系統可能在攔截之前就已經移動游標；把游標拉回最後允許的位置，觸控板就推不動游標
            CGWarpMouseCursorPosition(holdAt)
            CGAssociateMouseAndMouseCursorPosition(1)   // 取消拉回後的短暫輸入凍結，外接滑鼠不受影響
        }
        return block ? nil : pass
    }

    private func notifyHold(_ holding: Bool) {
        if let callback = onEscapeHoldChanged { DispatchQueue.main.async { callback(holding) } }
    }

    deinit { stopNow() }
}

private func pointerLockerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                   userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<PointerLocker>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
