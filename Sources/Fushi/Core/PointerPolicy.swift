import Foundation

/// 一個指標事件的來源裝置資訊 (由系統查出來，這裡只做判斷)。
struct SenderInfo: Equatable, Sendable {
    var builtIn: Bool?
    var className: String
    var product: String
    var usagePage: Int?
    var usage: Int?
}

/// 指標事件是哪一種裝置送的。
///
/// 判斷依據來自偵測工具在實機上的紀錄：
/// - 內建觸控板：Built-In＝是、類別含 Multitouch (產品名 "Apple Internal Keyboard / Trackpad")
/// - 外接滑鼠：不是內建 (例如 MX Master 3 走藍牙)
/// - 觸控螢幕：HID 用途是「數位板／觸控螢幕」(UsagePage 0x0D、Usage 0x04)
enum PointerSource: Equatable, Sendable {
    case builtInTrackpad
    case touchScreen
    case externalPointer
    case unknown

    static func classify(_ info: SenderInfo?) -> PointerSource {
        guard let info else { return .unknown }
        if info.usagePage == 0x0D && info.usage == 0x04 { return .touchScreen }
        if info.builtIn == true {
            if info.className.localizedCaseInsensitiveContains("multitouch")
                || info.product.localizedCaseInsensitiveContains("trackpad") {
                return .builtInTrackpad
            }
            return .unknown
        }
        return .externalPointer
    }
}

/// 要擋哪些指標來源。外接滑鼠永遠放行 (它是解鎖用的手段)。
struct PointerBlockPolicy: Equatable, Sendable {
    var blockBuiltInTrackpad: Bool
    var blockTouchScreen: Bool

    func shouldBlock(_ source: PointerSource) -> Bool {
        switch source {
        case .builtInTrackpad: return blockBuiltInTrackpad
        case .touchScreen: return blockTouchScreen
        case .externalPointer, .unknown: return false   // 查不到來源一律放行：寧可漏擋，不可鎖死
        }
    }
}

/// 有些事件 (例如拖曳) 查不到來源。這時沿用「最近 0.5 秒內」有來源的那一筆。
struct RecentPointerSource: Equatable, Sendable {
    static let window: TimeInterval = 0.5
    private(set) var source: PointerSource = .unknown
    private(set) var time: TimeInterval = -.infinity

    mutating func resolve(_ observed: PointerSource, at now: TimeInterval) -> PointerSource {
        if observed != .unknown {
            source = observed
            time = now
            return observed
        }
        return now - time <= Self.window ? source : .unknown
    }
}
