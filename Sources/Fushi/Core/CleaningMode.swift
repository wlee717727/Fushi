import Foundation

/// C 面清潔要鎖定的對象。
///
/// 為什麼不用 `deckC(keyboard: Bool, trackpad: Bool)`？
/// 因為 (false, false)「什麼都不鎖」是不合法的狀態，用兩個 Bool 還是寫得出來。
/// 改成三個 case 之後，不合法的組合在型別上就根本寫不出來。
enum DeckTarget: String, CaseIterable, Sendable {
    case keyboard
    case trackpad
    case keyboardAndTrackpad

    /// 從畫面上的兩個勾選框換算；兩個都沒勾時回傳 nil (不能開始)。
    init?(keyboard: Bool, trackpad: Bool) {
        switch (keyboard, trackpad) {
        case (true, true): self = .keyboardAndTrackpad
        case (true, false): self = .keyboard
        case (false, true): self = .trackpad
        case (false, false): return nil
        }
    }

    var locksKeyboard: Bool { self != .trackpad }
    var locksTrackpad: Bool { self != .keyboard }
}

/// 清潔模式。
enum CleaningMode: Hashable, Sendable {
    /// B 面：螢幕。用全黑視窗蓋住所有螢幕。
    case screenB
    /// C 面：鍵盤／觸控板。
    case deckC(DeckTarget)
    /// 全鎖：需要外接滑鼠 (第 2 階段才開放)。
    case all

    /// 所有模式都已開放。(「全鎖」另外需要外接滑鼠，由 App 在開始前檢查。)
    /// 鎖觸控板的依據：偵測工具在實機上證實「內建觸控板」和「外接滑鼠」的事件來源分得開。
    var isAvailableInPhase1: Bool { true }

    /// 不能開始時，給使用者看的原因 (目前沒有永久不能開始的模式)。
    var unavailableReason: String? { nil }

    /// 需要全黑畫面的模式：B 面與全鎖 (全鎖也要擦螢幕)。
    var usesBlackScreen: Bool {
        switch self {
        case .screenB, .all: return true
        case .deckC: return false
        }
    }

    /// 會鎖觸控板的模式
    var locksTrackpad: Bool {
        switch self {
        case .screenB: return false
        case .deckC(let target): return target.locksTrackpad
        case .all: return true
        }
    }

    /// 會鎖鍵盤的模式
    var locksKeyboard: Bool {
        switch self {
        case .screenB: return false
        case .deckC(let target): return target.locksKeyboard
        case .all: return true
        }
    }

    /// 需要「輔助使用」權限嗎？(主動攔截鍵盤事件才需要)
    var needsAccessibility: Bool {
        locksKeyboard || locksTrackpad
    }

    var title: String {
        switch self {
        case .screenB: return String(localized: "Screen Cleaning")
        case .deckC(.keyboard): return String(localized: "Keyboard Cleaning")
        case .deckC(.trackpad): return String(localized: "Trackpad Cleaning")
        case .deckC(.keyboardAndTrackpad): return String(localized: "Keyboard Cleaning")   // 和側邊欄一致，只用四個名稱
        case .all: return String(localized: "Full Lock")
        }
    }

    var symbolName: String {
        switch self {
        case .screenB: return "display"
        case .deckC(.keyboard): return "keyboard"
        case .deckC: return "rectangle.and.hand.point.up.left"
        case .all: return "lock.fill"
        }
    }

    // MARK: 存到 UserDefaults 用的字串 (用來記住「上次的模式」)

    var storageValue: String {
        switch self {
        case .screenB: return "screenB"
        case .deckC(let target): return "deckC.\(target.rawValue)"
        case .all: return "all"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "screenB": self = .screenB
        case "all": self = .all
        default:
            let prefix = "deckC."
            guard storageValue.hasPrefix(prefix),
                  let target = DeckTarget(rawValue: String(storageValue.dropFirst(prefix.count))) else { return nil }
            self = .deckC(target)
        }
    }
}

/// 主畫面側邊欄的四個模式，順序是從筆電上方往下：螢幕 → 鍵盤 → 觸控板 → 全部。
enum ModeKind: String, CaseIterable, Identifiable {
    case screen, keyboard, trackpad, all
    var id: String { rawValue }

    /// 讀取舊版存的值 (0.3.0 以前只有 screenB／deckC／all 三個)
    init?(storedValue: String) {
        switch storedValue {
        case "screenB": self = .screen
        case "deckC": self = .keyboard
        default: self.init(rawValue: storedValue)
        }
    }
}

extension ModeKind {
    /// 這一頁實際要鎖什麼。鍵盤清潔依「同時鎖住觸控板」決定要不要連觸控板一起鎖。
    func cleaningMode(keyboardAlsoLocksTrackpad: Bool) -> CleaningMode {
        switch self {
        case .screen: return .screenB
        case .keyboard: return .deckC(keyboardAlsoLocksTrackpad ? .keyboardAndTrackpad : .keyboard)
        case .trackpad: return .deckC(.trackpad)
        case .all: return .all
        }
    }

    /// 從 0.3.0 以前的設定換算：當時 C 面頁有「鍵盤」「觸控板」兩個開關。
    /// - 只開觸控板 → 觸控板清潔
    /// - 其他 → 鍵盤清潔，「同時鎖住觸控板」照舊版觸控板開關
    /// 回傳 nil 代表沒有舊設定可換算。
    static func migrate(storedKind: String?, deckKeyboard: Bool?, deckTrackpad: Bool?)
        -> (kind: ModeKind, alsoTrackpad: Bool)? {
        guard deckKeyboard != nil || deckTrackpad != nil else { return nil }
        let keyboard = deckKeyboard ?? true
        let trackpad = deckTrackpad ?? false
        let stored = storedKind.flatMap(ModeKind.init(storedValue:)) ?? .screen
        if storedKind == "deckC" && !keyboard && trackpad { return (.trackpad, true) }
        return (stored, keyboard ? trackpad : true)
    }
}
