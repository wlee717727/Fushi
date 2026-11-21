import Foundation

/// 偵測測試標籤：使用者按下哪一個，之後的每筆紀錄都會帶上它。
enum ProbeLabel: String, CaseIterable, Identifiable, Sendable {
    case keyboard = "keyboard"
    case builtinTrackpad = "builtin_trackpad"
    case touchscreen = "touchscreen"
    case externalMouse = "external_mouse"
    case externalTrackpad = "external_trackpad"
    case idle = "idle"
    case unlabeled = "unlabeled"

    var id: String { rawValue }

    static var selectable: [ProbeLabel] { allCases.filter { $0 != .unlabeled } }

    var title: String {
        switch self {
        case .keyboard: return "鍵盤"
        case .builtinTrackpad: return "內建觸控板"
        case .touchscreen: return "觸控螢幕"
        case .externalMouse: return "外接滑鼠"
        case .externalTrackpad: return "外接觸控板"
        case .idle: return "閒置"
        case .unlabeled: return "尚未選擇"
        }
    }

    var symbol: String {
        switch self {
        case .keyboard: return "keyboard"
        case .builtinTrackpad: return "rectangle.and.hand.point.up.left"
        case .touchscreen: return "hand.point.up.left"
        case .externalMouse: return "computermouse"
        case .externalTrackpad: return "rectangle.and.hand.point.up.left.filled"
        case .idle: return "pause.circle"
        case .unlabeled: return "questionmark.circle"
        }
    }

    /// 選單快速鍵 ⌘1～⌘6：用鍵盤切換標籤，就不會在別的裝置的標籤期間留下多餘的點擊。
    var shortcutDigit: Character? {
        switch self {
        case .keyboard: return "1"
        case .builtinTrackpad: return "2"
        case .touchscreen: return "3"
        case .externalMouse: return "4"
        case .externalTrackpad: return "5"
        case .idle: return "6"
        case .unlabeled: return nil
        }
    }
}

/// 把紀錄寫成 JSON Lines (每行一筆 JSON)。
///
/// 所有來源 (HID 層、事件層、視窗觸控) 都從不同執行緒呼叫 `write`，
/// 這裡用一條「序列佇列」依序寫檔，避免多執行緒同時寫同一個檔案而交錯。
final class ProbeRecorder: @unchecked Sendable {
    static let shared = ProbeRecorder()

    let stamp: String
    let logDirectory: URL
    let logURL: URL
    let devicesURL: URL
    private(set) var openError: String?

    private let queue = DispatchQueue(label: "拂拭偵測.寫檔", qos: .utility)
    private var handle: FileHandle?
    private let lock = NSLock()
    private var _label: ProbeLabel = .unlabeled
    private var _labelChangedNs: UInt64 = 0
    private var _counts: [String: Int] = [:]
    let startNs: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

    private init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        stamp = formatter.string(from: Date())

        logDirectory = Self.chooseLogDirectory()
        logURL = logDirectory.appendingPathComponent("probe-\(stamp).jsonl")
        devicesURL = logDirectory.appendingPathComponent("devices-\(stamp).json")

        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: logURL)
        } catch {
            openError = "無法建立紀錄檔：\(error.localizedDescription)"
        }
    }

    /// 紀錄資料夾：App 放在專案根目錄時，就是旁邊的 probe-logs；否則用桌面上的 Fushi 專案資料夾。
    private static func chooseLogDirectory() -> URL {
        let besideApp = Bundle.main.bundleURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: besideApp.appendingPathComponent("project.yml").path) {
            return besideApp.appendingPathComponent("probe-logs", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Fushi/probe-logs", isDirectory: true)
    }

    // MARK: 標籤

    var label: ProbeLabel {
        lock.lock(); defer { lock.unlock() }
        return _label
    }

    func setLabel(_ label: ProbeLabel) {
        lock.lock()
        let old = _label
        _label = label
        _labelChangedNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        lock.unlock()
        write("label", ["from": old.rawValue, "to": label.rawValue])
    }

    // MARK: 計數 (給畫面顯示)

    func counts() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return _counts
    }

    // MARK: 寫檔

    /// 寫入一筆紀錄。共同欄位：src (來源)、label (當下標籤)、t_ms (啟動後毫秒)、
    /// uptime_ns (系統開機後奈秒，用來對照 HID 層與事件層的時間)、since_label_ms (切換標籤後多久)。
    func write(_ source: String, _ fields: [String: Any], uptimeNs: UInt64? = nil) {
        let now = uptimeNs ?? clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        lock.lock()
        let label = _label
        let sinceLabel = _labelChangedNs == 0 ? -1 : (Double(Int64(now) - Int64(_labelChangedNs)) / 1_000_000)
        _counts[source, default: 0] += 1
        lock.unlock()

        var record = fields
        record["src"] = source
        record["label"] = label.rawValue
        record["uptime_ns"] = now
        record["t_ms"] = (Double(Int64(now) - Int64(startNs)) / 1_000_000).rounded(toPlaces: 3)
        record["since_label_ms"] = sinceLabel.rounded(toPlaces: 1)

        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            let safe = JSONSafe.convert(record)
            guard JSONSerialization.isValidJSONObject(safe),
                  var data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys, .withoutEscapingSlashes])
            else { return }
            data.append(0x0A)
            handle.write(data)
        }
    }

    /// 裝置清單另存一份 (插拔時覆寫成最新狀態)。
    func writeDevices(_ devices: [[String: Any]]) {
        let payload: [String: Any] = [
            "generated": ISO8601DateFormatter().string(from: Date()),
            "probe_log": logURL.lastPathComponent,
            "devices": devices,
        ]
        let url = devicesURL
        queue.async {
            let safe = JSONSafe.convert(payload)
            if let data = try? JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func flush() {
        queue.sync { try? handle?.synchronize() }
    }
}

/// 把 CoreFoundation 物件 (CFNumber、CFData…) 轉成 JSON 能接受的型別。
enum JSONSafe {
    static func convert(_ value: Any) -> Any {
        switch value {
        case is NSNull: return NSNull()   // 空值要寫成 JSON 的 null，不是文字 "<null>"
        case let v as String: return v
        case let v as NSNumber:
            // 注意：數字 1 也能轉成 Bool，所以先用 CF 型別判斷「真的是布林」才當布林
            if CFGetTypeID(v) == CFBooleanGetTypeID() { return v.boolValue }
            let d = v.doubleValue
            return d.isFinite ? v : String(describing: d)
        case let v as Data: return v.map { String(format: "%02x", $0) }.joined()
        case let v as [Any]: return v.map(convert)
        case let v as [String: Any]: return v.mapValues(convert)
        case let v as NSDictionary:
            var out: [String: Any] = [:]
            for (k, val) in v { out[String(describing: k)] = convert(val) }
            return out
        case let v as NSArray: return v.map(convert)
        default: return String(describing: value)
        }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10, Double(places))
        return (self * p).rounded() / p
    }
}
