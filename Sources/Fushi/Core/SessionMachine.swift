import Foundation

/// B 面清潔時，主螢幕現在顯示什麼。
enum ScreenBDisplay: Equatable, Sendable {
    /// 全黑：OLED 不發光、游標隱藏、觸控沒反應。
    case dark
    /// 控制面板亮起；記錄最後一次操作的時間，用來判斷 8 秒沒操作就回到全黑。
    case panel(lastInteraction: Date)
}

/// 清潔為什麼結束。
enum EndReason: Equatable, Sendable {
    case userConfirmed        // 使用者按住 2 秒結束
    case timeout              // 自動解鎖時間到
    case countdownCancelled   // 倒數時取消
    case lockFailed(String)   // 鎖定失敗 (例如缺少權限)
}

/// 外部送進狀態機的事件。
enum SessionEvent: Equatable, Sendable {
    case start(CleaningMode, requestedSeconds: Int, now: Date)
    case cancelCountdown
    case tick(now: Date)
    case keyPressed(now: Date)      // 全黑畫面：按任意鍵 (全鎖是動外接滑鼠) 喚醒／重置閒置計時
    case interaction(now: Date)     // B 面：在控制面板上的其他操作
    case resumeDark                 // B 面：按【繼續清潔】
    case confirmEnd                 // 按住 2 秒、長按 Esc 3 秒、或從選單列結束
    case lockFailed(String)
}

/// 清潔流程的狀態機。
///
/// 這裡是「純邏輯」：沒有計時器、沒有視窗，只根據事件和時間決定下一個狀態。
/// 真正開視窗、攔截事件的工作 (副作用) 交給 AppModel 根據狀態變化去做。
/// 好處是所有規則都能用單元測試驗證，不必真的去鎖鍵盤。
struct SessionState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case countdown(mode: CleaningMode, endsAt: Date, durationSeconds: Int)
        case cleaning(mode: CleaningMode, deadline: Date, screen: ScreenBDisplay)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastEnd: EndReason?
    let isDebugBuild: Bool

    init(isDebugBuild: Bool = SessionPolicy.isDebugBuild) {
        self.isDebugBuild = isDebugBuild
    }

    // MARK: 查詢

    var isIdle: Bool { phase == .idle }

    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    var isCountingDown: Bool {
        if case .countdown = phase { return true }
        return false
    }

    /// 倒數或清潔中的模式。
    var activeMode: CleaningMode? {
        switch phase {
        case .idle: return nil
        case .countdown(let mode, _, _), .cleaning(let mode, _, _): return mode
        }
    }

    var screenDisplay: ScreenBDisplay? {
        if case .cleaning(let mode, _, let screen) = phase, mode.usesBlackScreen { return screen }
        return nil
    }

    var isPanelVisible: Bool {
        if case .panel = screenDisplay { return true }
        return false
    }

    /// 自動解鎖剩餘秒數 (無條件進位，例如剩 2.1 秒顯示 3)。
    func remainingSeconds(at now: Date) -> Int? {
        guard case .cleaning(_, let deadline, _) = phase else { return nil }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    /// 倒數剩餘秒數。
    func countdownRemaining(at now: Date) -> Int? {
        guard case .countdown(_, let endsAt, _) = phase else { return nil }
        return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    var deadline: Date? {
        if case .cleaning(_, let deadline, _) = phase { return deadline }
        return nil
    }

    // MARK: 狀態轉換

    mutating func handle(_ event: SessionEvent) {
        switch (phase, event) {

        // 閒置 → 倒數 (只有第 1 階段開放的模式能開始)
        case (.idle, .start(let mode, let requested, let now)):
            guard mode.isAvailableInPhase1 else { return }
            let seconds = SessionPolicy.effectiveDuration(requested: requested, isDebug: isDebugBuild)
            phase = .countdown(mode: mode,
                               endsAt: now.addingTimeInterval(SessionPolicy.countdownSeconds),
                               durationSeconds: seconds)
            lastEnd = nil

        case (.countdown, .cancelCountdown):
            phase = .idle
            lastEnd = .countdownCancelled

        // 倒數中電腦睡著，醒來時連清潔時間都已經過了 → 直接回到待命 (不要先上鎖再立刻解鎖)
        case (.countdown(_, let endsAt, let seconds), .tick(let now))
            where now >= endsAt.addingTimeInterval(TimeInterval(seconds)):
            phase = .idle
            lastEnd = .timeout

        // 倒數結束 → 開始清潔。截止時間從「倒數結束的那一刻」起算，不受計時器延遲影響。
        case (.countdown(let mode, let endsAt, let seconds), .tick(let now)) where now >= endsAt:
            phase = .cleaning(mode: mode,
                              deadline: endsAt.addingTimeInterval(TimeInterval(seconds)),
                              screen: .dark)

        // 時間到 → 自動解鎖。這條放在最前面，優先於其他清潔中的規則。
        case (.cleaning(_, let deadline, _), .tick(let now)) where now >= deadline:
            phase = .idle
            lastEnd = .timeout

        // 控制面板 8 秒沒操作 → 回到全黑
        case (.cleaning(let mode, let deadline, .panel(let last)), .tick(let now))
            where now.timeIntervalSince(last) >= SessionPolicy.panelIdleSeconds:
            phase = .cleaning(mode: mode, deadline: deadline, screen: .dark)

        // B 面：按任意鍵 → 亮起控制面板 (已亮起則重置閒置計時)
        case (.cleaning(let mode, let deadline, _), .keyPressed(let now)) where mode.usesBlackScreen:
            phase = .cleaning(mode: mode, deadline: deadline, screen: .panel(lastInteraction: now))

        case (.cleaning(let mode, let deadline, .panel), .interaction(let now)):
            phase = .cleaning(mode: mode, deadline: deadline, screen: .panel(lastInteraction: now))

        case (.cleaning(let mode, let deadline, .panel), .resumeDark):
            phase = .cleaning(mode: mode, deadline: deadline, screen: .dark)

        case (.cleaning, .confirmEnd), (.countdown, .confirmEnd):
            phase = .idle
            lastEnd = .userConfirmed

        case (.cleaning, .lockFailed(let message)), (.countdown, .lockFailed(let message)):
            phase = .idle
            lastEnd = .lockFailed(message)

        default:
            break   // 其他組合一律忽略，例如閒置時收到 tick
        }
    }
}
