import Foundation

/// App 內的語言選擇。
///
/// macOS 的介面語言在 App 啟動時決定：選了某個語言，就把它寫進「這個 App 自己的」AppleLanguages 設定
/// (和「系統設定 › 一般 › 語言與地區 › App」完全同一個地方)，重新開啟 App 後生效。
/// 選「跟隨系統」就把這個設定刪掉，回到系統的偏好語言。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"
    case ja
    case ko
    case es

    var id: String { rawValue }

    /// 寫進 AppleLanguages 的語言代碼；跟隨系統是 nil
    var code: String? { self == .system ? nil : rawValue }

    /// 語言自己的名稱 (慣例：用該語言書寫，不翻譯，讓看不懂目前語言的人也找得到)
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .en: return "English"
        case .zhHant: return "繁體中文"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .es: return "Español"
        }
    }

    /// 從 App 自己的 AppleLanguages 設定判斷目前的選擇 (沒有設定 → 跟隨系統)
    static func from(appleLanguages: [String]?) -> AppLanguage {
        guard let first = appleLanguages?.first else { return .system }
        if first.hasPrefix("zh-Hant") || first == "zh-TW" || first == "zh-HK" { return .zhHant }
        if first.hasPrefix("zh-Hans") || first == "zh-CN" || first == "zh" { return .zhHans }
        let base = String(first.prefix { $0 != "-" && $0 != "_" })
        return AppLanguage(rawValue: base) ?? .system
    }
}
