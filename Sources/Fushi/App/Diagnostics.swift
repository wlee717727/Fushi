import AppKit
import OSLog

/// 診斷紀錄：寫進 macOS 系統記錄 (不另外產生檔案)，需要時從「說明」選單拷貝出來。
///
/// 為什麼需要？像「按鈕點不動」這種問題，要先知道點擊到底有沒有送到 App、
/// 落在哪個視窗、當時是什麼狀態，才找得到原因，不必靠猜。
/// 只記錄位置與狀態，不記錄任何按鍵內容。
enum Diagnostics {
    static let subsystem = "com.wlee717727.Fushi"
    private static let logger = Logger(subsystem: subsystem, category: "診斷")
    nonisolated(unsafe) private static var clickMonitor: Any?

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func describe(_ state: SessionState) -> String {
        switch state.phase {
        case .idle: return "待命"
        case .countdown(let mode, _, let seconds): return "倒數 (\(mode.storageValue)，\(seconds) 秒)"
        case .cleaning(let mode, _, let screen):
            if case .panel = screen { return "清潔中 (\(mode.storageValue)，控制面板)" }
            return "清潔中 (\(mode.storageValue))"
        }
    }

    /// 記錄每一次滑鼠／觸控點擊落在哪個視窗、哪個位置 (不攔截，原封不動放行)。
    @MainActor
    static func startClickLogging() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let window = event.window
            let title = window?.title.isEmpty == false ? window!.title : String(describing: type(of: window as Any))
            let p = event.locationInWindow
            log(String(format: "點擊：視窗「%@」(主視窗=%@、焦點=%@) 位置 (%.0f, %.0f)、subtype %d",
                       title,
                       window?.isMainWindow == true ? "是" : "否",
                       window?.isKeyWindow == true ? "是" : "否",
                       p.x, p.y, Int(event.subtype.rawValue)))
            return event
        }
        log("診斷紀錄啟動：版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")，系統 \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// 讀出這次執行以來的診斷紀錄 (最多 400 行)。
    static func recentEntries() -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(timeIntervalSinceLatestBoot: 0)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let lines = try store.getEntries(at: start)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == subsystem }
                .map { "\(formatter.string(from: $0.date))  \($0.composedMessage)" }
            return lines.suffix(400).joined(separator: "\n")
        } catch {
            return "無法讀取診斷紀錄：\(error.localizedDescription)"
        }
    }

    /// 拷貝到剪貼簿，方便貼給開發者。
    @MainActor
    static func copyToPasteboard(permissions: PermissionCenter) {
        permissions.refresh()
        let header = """
        拂拭 診斷資訊
        版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        系統：\(ProcessInfo.processInfo.operatingSystemVersionString)
        輔助使用：\(permissions.accessibility ? "已允許" : "未允許")；輸入監控：\(permissions.inputMonitoring ? "已允許" : "未允許")
        ----
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(header + "\n" + recentEntries(), forType: .string)
    }
}
