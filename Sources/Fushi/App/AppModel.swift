import AppKit
import Carbon.HIToolbox   // IsSecureEventInputEnabled：偵測密碼欄位的安全輸入
import SwiftUI

/// 主畫面上選的是哪一類模式。
enum ModeKind: String, CaseIterable, Identifiable {
    case screenB, deckC, all
    var id: String { rawValue }
}

/// 主視窗側邊欄的項目。
enum SidebarItem: Hashable {
    case mode(ModeKind)
    case permissions
}

/// App 的中樞：保存設定、驅動狀態機，並依照狀態變化執行「副作用」
/// (開關全黑視窗、開關鍵盤攔截、顯示浮動面板)。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: 狀態

    @Published private(set) var state = SessionState()
    @Published private(set) var now = Date()
    @Published private(set) var escHolding = false
    /// 開始按住 Esc 的時間 (畫面用來畫 3 秒倒數)
    @Published private(set) var escHoldStartedAt: Date?
    /// 全黑時碰到鍵盤／觸控板／滑鼠的時間：畫面呼吸一下並提示「長按 Esc 3 秒結束」
    @Published private(set) var nudgeAt: Date?
    /// 呼吸提示預計淡出完畢的時間；持續碰觸會一直往後延
    @Published private(set) var nudgeEndsAt: Date?
    static let nudgeSeconds: TimeInterval = 6
    /// 側邊欄目前選的頁面；選到模式時同步更新 kind。
    @Published var sidebar: SidebarItem {
        didSet {
            if sidebar != oldValue { Diagnostics.log("側邊欄：\(oldValue) → \(sidebar)") }
            if case .mode(let k) = sidebar, k != kind { kind = k }
        }
    }
    @Published var alertMessage: String?

    // MARK: 設定 (存在 UserDefaults)

    @Published var kind: ModeKind {
        didSet {
            defaults.set(kind.rawValue, forKey: Keys.kind)
            if case .mode(let k) = sidebar, k != kind { sidebar = .mode(kind) }
        }
    }
    @Published var deckKeyboard: Bool { didSet { defaults.set(deckKeyboard, forKey: Keys.deckKeyboard) } }
    @Published var deckTrackpad: Bool { didSet { defaults.set(deckTrackpad, forKey: Keys.deckTrackpad) } }
    @Published var durationSeconds: Int { didSet { defaults.set(durationSeconds, forKey: Keys.duration) } }
    @Published var autoStartLastMode: Bool { didSet { defaults.set(autoStartLastMode, forKey: Keys.autoStart) } }
    @Published private(set) var lastMode: CleaningMode?

    let permissions = PermissionCenter()
    /// 由畫面設定，用來在需要時把主視窗叫出來。
    var openMainWindow: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let locker = KeyboardLocker()
    private let pointerLocker = PointerLocker()
    /// 外接滑鼠 (全鎖需要)
    let externalMouse = ExternalMouseMonitor()
    private lazy var overlay = ScreenOverlayController(model: self)
    private let hud = FloatingHUD()
    private var ticker: Timer?
    private var escTimer: Timer?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var safetyTimer: DispatchSourceTimer?
    /// 最後防線：主程式卡死、超過解鎖時間 5 秒還沒收掉畫面，就直接結束拂拭 (不經過主執行緒)
    private var lastResortTimer: DispatchSourceTimer?
    /// 「清潔中」旗標：背景的最後防線要讀，所以放在加鎖的盒子裡
    private let cleaningFlag = Locked(false)
    /// 上鎖失敗時是否要帶到權限頁 (外接滑鼠中斷、安全輸入這類失敗不需要)
    private var failureNeedsPermissionGuide = true

    private enum Keys {
        static let kind = "mode.kind"
        static let deckKeyboard = "mode.deck.keyboard"
        static let deckTrackpad = "mode.deck.trackpad"
        static let duration = "duration.seconds"
        static let autoStart = "launch.autoStartLastMode"
        static let lastMode = "mode.last"
        static let seenGuide = "permissions.seenGuide"
    }

    private init() {
        let savedKind = ModeKind(rawValue: defaults.string(forKey: Keys.kind) ?? "") ?? .screenB
        kind = savedKind
        sidebar = .mode(savedKind)
        deckKeyboard = defaults.object(forKey: Keys.deckKeyboard) as? Bool ?? true
        deckTrackpad = defaults.object(forKey: Keys.deckTrackpad) as? Bool ?? false
        let saved = defaults.integer(forKey: Keys.duration)
        durationSeconds = saved == 0 ? SessionPolicy.defaultSeconds
            : min(max(saved, SessionPolicy.minimumSeconds), SessionPolicy.maximumSeconds)
        autoStartLastMode = defaults.bool(forKey: Keys.autoStart)
        lastMode = defaults.string(forKey: Keys.lastMode).flatMap(CleaningMode.init(storageValue:))
    }

    // MARK: 給畫面用的衍生資料

    /// 目前畫面上的選擇換算成模式；C 面兩個都沒勾時是 nil。
    var selectedMode: CleaningMode? {
        switch kind {
        case .screenB: return .screenB
        case .deckC: return DeckTarget(keyboard: deckKeyboard, trackpad: deckTrackpad).map { .deckC($0) }
        case .all: return .all
        }
    }

    /// 不能按【開始清潔】的原因；nil 代表可以開始。
    var startBlockedReason: String? {
        guard let mode = selectedMode else { return "請至少選擇鍵盤或觸控板" }
        if mode == .all && !externalMouse.isConnected { return "請先連接外接滑鼠" }
        return mode.unavailableReason
    }

    var effectiveDuration: Int {
        SessionPolicy.effectiveDuration(requested: durationSeconds, isDebug: SessionPolicy.isDebugBuild)
    }

    var remainingText: String {
        SessionPolicy.clockText(seconds: state.remainingSeconds(at: now) ?? 0)
    }

    var menuBarSymbol: String {
        if state.isCleaning { return "lock.fill" }
        if state.isCountingDown { return "timer" }
        return "sparkles"
    }

    var needsFirstRunGuide: Bool { !defaults.bool(forKey: Keys.seenGuide) }

    func markGuideSeen() { defaults.set(true, forKey: Keys.seenGuide) }

    // MARK: 使用者操作

    func startSelected() {
        guard let mode = selectedMode else { return }
        start(mode)
    }

    func start(_ mode: CleaningMode) {
        guard state.isIdle else { return }
        if mode == .all && !externalMouse.isConnected {
            alertMessage = "全鎖需要先接上外接滑鼠 (藍牙或 USB 都可以)，結束時要用它來操作。"
            return
        }
        if let reason = mode.unavailableReason {
            alertMessage = reason
            return
        }
        // 缺少權限就不進入鎖定，直接帶到權限引導畫面
        permissions.refresh()
        if mode.needsAccessibility && !permissions.accessibility {
            presentPermissionGuide()
            return
        }
        // 有 App 正在用「安全輸入」(例如游標停在密碼欄位)：macOS 不讓任何 App 攔截鍵盤，鎖了也沒用
        if mode.locksKeyboard && IsSecureEventInputEnabled() {
            alertMessage = Self.secureInputMessage
            return
        }
        Diagnostics.log("開始倒數：\(mode.storageValue)，設定 \(durationSeconds) 秒")
        send(.start(mode, requestedSeconds: durationSeconds, now: Date()))
    }

    static let secureInputMessage = "目前有 App 正在使用「安全輸入」(例如游標停在密碼欄位，或終端機開了安全鍵盤輸入)，macOS 不允許任何 App 鎖住鍵盤。請先點一下別的地方離開密碼欄位，再開始清潔。"

    func startLastMode() {
        if let lastMode { start(lastMode) }
    }

    func cancelCountdown() { send(.cancelCountdown) }
    func confirmEnd() { send(.confirmEnd) }
    func resumeDark() { send(.resumeDark) }
    func panelInteraction() { send(.interaction(now: Date())) }

    func presentPermissionGuide() {
        Diagnostics.log("打開權限頁")
        openMainWindow?()
        NSApp.activate()
        sidebar = .permissions
    }

    /// 目前選的模式缺少權限時，開始按鈕會改成「先允許權限」。
    var selectedModeNeedsPermission: Bool {
        guard let mode = selectedMode, mode.unavailableReason == nil else { return false }
        return mode.needsAccessibility && !permissions.accessibility
    }

    /// App 啟動後呼叫：需要的話自動開始上次的模式 (一樣有 3 秒倒數可以取消)。
    func handleLaunch() {
        // 只有「真的還沒允許」時才主動帶到權限頁；已經允許就直接停在模式頁
        permissions.refresh()
        if needsFirstRunGuide && !permissions.accessibility {
            presentPermissionGuide()
            return
        }
        if autoStartLastMode, let lastMode, lastMode.isAvailableInPhase1 {
            start(lastMode)
        }
    }

    /// App 結束前：保證所有鎖定都解除。
    func emergencyStop() {
        locker.stop()
        pointerLocker.stop()
        overlay.hide()
        hud.hide()
        removeMonitors()
    }

    #if DEBUG
    /// 開發用：直接設定狀態，讓面板截圖工具畫出指定的畫面 (不會真的鎖定)。
    func debugPreview(state: SessionState, now: Date, escHoldStartedAt: Date? = nil, nudgeAt: Date? = nil) {
        self.state = state
        self.now = now
        self.nudgeAt = nudgeAt
        self.nudgeEndsAt = nudgeAt?.addingTimeInterval(Self.nudgeSeconds)
        self.escHoldStartedAt = escHoldStartedAt
        self.escHolding = escHoldStartedAt != nil
    }
    #endif

    // MARK: 狀態機與副作用

    private func send(_ event: SessionEvent) {
        let old = state
        var new = old
        new.handle(event)
        guard new != old else { return }
        Diagnostics.log("狀態：\(Diagnostics.describe(old)) → \(Diagnostics.describe(new))")
        state = new
        now = Date()
        applyEffects(from: old, to: new)
    }

    private func applyEffects(from old: SessionState, to new: SessionState) {
        // 倒數開始／結束
        if new.isCountingDown && !old.isCountingDown {
            startTicker()
            showCountdownHUD()
        }
        if old.isCountingDown && !new.isCountingDown {
            hud.hide()
        }

        // 進入清潔
        if new.isCleaning && !old.isCleaning, let mode = new.activeMode, let deadline = new.deadline {
            beginCleaning(mode: mode, deadline: deadline)
            // 上鎖途中失敗 (已經收拾完、回到待命)：後面用舊狀態的步驟一律不做，免得又把游標藏起來
            guard state == new else { return }
        }
        // B 面全黑／控制面板切換
        if let display = new.screenDisplay, display != old.screenDisplay {
            overlay.update(display: display)
        }
        // 離開清潔
        if old.isCleaning && !new.isCleaning {
            endCleaning()
        }

        if new.isIdle {
            stopTicker()
            if case .lockFailed(let message)? = new.lastEnd {
                alertMessage = message
                // 主視窗可能是關著的 (從選單列開始)：一定打開並帶到前景，提示才看得到；權限問題再切到權限頁
                if failureNeedsPermissionGuide {
                    presentPermissionGuide()
                } else {
                    openMainWindow?()
                    NSApp.activate()
                }
                failureNeedsPermissionGuide = true
            }
        }
    }

    private func beginCleaning(mode: CleaningMode, deadline: Date) {
        lastMode = mode
        defaults.set(mode.storageValue, forKey: Keys.lastMode)
        armSafetyTimer(deadline: deadline)

        let failMessage = "無法鎖定：請確認已在「系統設定 › 隱私權與安全性 › 輔助使用」勾選「拂拭」。"

        // 倒數的 3 秒內情況可能變了，真正上鎖前再檢查一次
        if mode == .all && !externalMouse.isConnected {
            failureNeedsPermissionGuide = false
            send(.lockFailed("外接滑鼠已經中斷，沒有辦法安全地全鎖。請確認滑鼠有電、已連線後再開始。")); return
        }
        if mode.locksKeyboard && IsSecureEventInputEnabled() {
            failureNeedsPermissionGuide = false
            send(.lockFailed(Self.secureInputMessage)); return
        }
        cleaningFlag.set(true)
        armLastResort(deadline: deadline)
        // 清潔中「輔助使用」被關掉：攔截已經自己停了，這裡結束清潔並說明
        let lost: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.isCleaning else { return }
                Diagnostics.log("清潔中輔助使用權限被撤銷，自動解除")
                self.send(.lockFailed("「輔助使用」權限在清潔中被關閉，已經自動解除鎖定。"))
            }
        }
        locker.onPermissionLost = lost
        pointerLocker.onPermissionLost = lost
        let emergency: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                Diagnostics.log("緊急退出：長按 Esc 3 秒")
                self?.confirmEnd()
            }
        }
        locker.onEmergencyExit = emergency
        pointerLocker.onEmergencyExit = emergency
        // 鍵盤或觸控板鎖住時，Esc 由攔截器偵測；畫面只負責顯示倒數 (時間到由攔截器結束)
        let escapeChanged: (Bool) -> Void = { [weak self] holding in
            MainActor.assumeIsolated { self?.setEscHold(holding) }
        }
        locker.onEscapeHoldChanged = escapeChanged
        pointerLocker.onEscapeHoldChanged = escapeChanged
        let blocked: () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.nudge() }
        }
        locker.onBlockedInput = blocked
        pointerLocker.onBlockedInput = blocked

        // 1. 鍵盤
        if mode.locksKeyboard && !locker.start(until: deadline) {
            send(.lockFailed(failMessage)); return
        }
        // 2. 指標：鎖觸控板 (全鎖時連觸控螢幕一起擋)。它也同時監看長按 Esc 3 秒 (只鎖觸控板時鍵盤沒鎖，靠它退出)
        if mode.locksTrackpad {
            let policy = PointerBlockPolicy(blockBuiltInTrackpad: true, blockTouchScreen: mode == .all)
            if !pointerLocker.start(policy: policy, until: deadline) {
                locker.stop()
                send(.lockFailed(failMessage)); return
            }
        }
        // 3. 畫面
        switch mode {
        case .screenB:
            overlay.show()
            installOverlayMonitors()
        case .deckC(let target):
            hud.show(DeckLockHUD(model: self, target: target))
        case .all:
            overlay.show()
            installOverlayMonitors()
            // 動外接滑鼠 → 叫出控制面板 (鍵盤已鎖，觸控螢幕被全黑畫面擋住)
            pointerLocker.onExternalActivity = { [weak self] in
                MainActor.assumeIsolated { self?.send(.keyPressed(now: Date())) }
            }
            // 外接滑鼠全部斷線 → 立刻全部解鎖
            externalMouse.onAllDisconnected = { [weak self] in
                MainActor.assumeIsolated {
                    Diagnostics.log("全鎖：外接滑鼠斷線，立刻解鎖")
                    self?.confirmEnd()
                }
            }
        }
    }

    private func endCleaning() {
        cleaningFlag.set(false)
        safetyTimer?.cancel()
        safetyTimer = nil
        lastResortTimer?.cancel()
        lastResortTimer = nil
        locker.stop()
        pointerLocker.stop()
        pointerLocker.onExternalActivity = nil
        externalMouse.onAllDisconnected = nil
        overlay.hide()
        removeMonitors()
        cancelEscHold()
        locker.onBlockedInput = nil
        pointerLocker.onBlockedInput = nil
        nudgeAt = nil
        nudgeEndsAt = nil
        hud.hide()
    }

    /// 獨立於主計時器的保險：用背景佇列的計時器在截止時間送出 tick。
    private func armSafetyTimer(deadline: Date) {
        safetyTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow) + 0.1)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.send(.tick(now: Date()))
                // 時鐘被往回調時 tick 不會判定到期；保險計時器到了就一定結束
                if self.state.isCleaning {
                    Diagnostics.log("保險計時器到期，強制結束清潔")
                    self.confirmEnd()
                }
            }
        }
        timer.resume()
        safetyTimer = timer
    }

    /// 最後防線：超過解鎖時間 5 秒，主程式還沒結束清潔 (例如主執行緒卡死)，就直接結束拂拭。
    /// 程式結束時全黑視窗與所有攔截都會跟著消失。完全不經過主執行緒。
    private func armLastResort(deadline: Date) {
        lastResortTimer?.cancel()
        let flag = cleaningFlag
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow) + 5)
        timer.setEventHandler {
            guard flag.get() else { return }
            Diagnostics.log("最後防線：超過解鎖時間仍未結束，直接結束拂拭")
            // 用 _exit 不用 exit：exit 會先跑收尾程序，主執行緒卡死時收尾也可能卡在同一個鎖上
            _exit(0)
        }
        timer.resume()
        lastResortTimer = timer
    }

    private func startTicker() {
        guard ticker == nil else { return }
        // 加到 .common 模式：選單打開或拖曳時計時器也照常跑
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.send(.tick(now: self.now))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func showCountdownHUD() {
        hud.show(CountdownHUD(model: self))
    }

    // MARK: B 面的鍵盤處理

    /// B 面期間，App 收到的鍵盤事件全部在這裡處理後吃掉，不會打進任何地方 (包含 ⌘Q)。
    private func installOverlayMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleOverlayKey(event) }
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state.isPanelVisible {
                    self.panelInteraction()
                } else if let cg = event.cgEvent {
                    // 全黑時：觸控板或滑鼠 → 畫面呼吸一下；觸控螢幕 (擦螢幕) 不反應
                    let source = PointerSource.classify(EventSourceLookup.sender(of: cg))
                    if source == .builtInTrackpad || source == .externalPointer { self.nudge() }
                }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    private func handleOverlayKey(_ event: NSEvent) {
        let escape: UInt16 = 53
        switch event.type {
        case .keyDown:
            // B 面：按鍵不叫出控制面板 (面板一出現，觸控螢幕就能按到東西，擦螢幕時會誤觸)。
            // 只讓畫面呼吸一下提示「長按 Esc 3 秒結束」；按住 Esc 則顯示倒數。
            if event.keyCode == escape && !event.isARepeat { beginEscHold() }
            nudge()
        case .keyUp:
            if event.keyCode == escape { cancelEscHold() }
        case .flagsChanged:
            nudge()
        default:
            break
        }
    }

    /// 全黑時有人碰到鍵盤、觸控板或滑鼠：畫面呼吸一下，提示怎麼結束 (控制面板亮著時不需要)。
    private func nudge() {
        guard state.isCleaning, state.activeMode?.usesBlackScreen == true,
              !state.isPanelVisible, escHoldStartedAt == nil else { return }
        let now = Date()
        let end = now.addingTimeInterval(Self.nudgeSeconds)
        // 已經在顯示：只把結束時間往後延，畫面維持亮著、繼續緩慢呼吸
        if nudgeAt == nil || (nudgeEndsAt ?? .distantPast) <= now {
            nudgeAt = now
        }
        nudgeEndsAt = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.nudgeSeconds + 0.1) { [weak self] in
            guard let self, let e = self.nudgeEndsAt, e <= Date() else { return }
            self.nudgeAt = nil
            self.nudgeEndsAt = nil
        }
    }

    /// 攔截器回報 Esc 按住／放開：只更新畫面狀態。
    private func setEscHold(_ holding: Bool) {
        guard state.isCleaning else { return }
        if holding {
            if !escHolding {
                let start = Date()
                escHolding = true
                escHoldStartedAt = start
                // 放開事件萬一漏掉：4.5 秒後還在清潔中，就把倒數收掉，讓結束按鈕回來
                DispatchQueue.main.asyncAfter(deadline: .now() + SessionPolicy.emergencyEscapeSeconds + 1.5) { [weak self] in
                    guard let self, self.escHoldStartedAt == start, self.state.isCleaning else { return }
                    self.cancelEscHold()
                }
            }
        } else {
            cancelEscHold()
        }
    }

    /// 長按 Esc 3 秒結束清潔 (B 面：鍵盤沒鎖，由畫面自己計時)。
    private func beginEscHold() {
        cancelEscHold()
        escHolding = true
        escHoldStartedAt = Date()
        let timer = Timer(timeInterval: SessionPolicy.emergencyEscapeSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.escHolding else { return }
                self.escHolding = false
                self.confirmEnd()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        escTimer = timer
    }

    private func cancelEscHold() {
        escTimer?.invalidate()
        escTimer = nil
        if escHolding { escHolding = false }
        if escHoldStartedAt != nil { escHoldStartedAt = nil }
    }
}
