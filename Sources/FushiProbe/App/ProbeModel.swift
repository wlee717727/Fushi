import AppKit
import IOKit.hid
import SwiftUI

/// 偵測工具的畫面狀態。
@MainActor
final class ProbeModel: ObservableObject {
    static let shared = ProbeModel()

    @Published private(set) var label: ProbeLabel = .unlabeled
    @Published private(set) var devices: [HIDDeviceRow] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var tapRunning = false
    @Published private(set) var lastTouchSummary = "還沒有觸控事件"
    @Published private(set) var elapsedText = "0:00"
    @Published private(set) var lastSender = "還沒有指標事件"

    let recorder = ProbeRecorder.shared
    private lazy var hid = HIDProbe(recorder: recorder)
    private lazy var tap = EventTapProbe(recorder: recorder)
    private var timer: Timer?
    private let started = Date()
    private var triedTapOnce = false

    /// 啟動時沒有權限、之後才勾選：HID 層要重新開啟 App 才會生效
    private var startedWithoutPermission = false

    var needsRelaunch: Bool { startedWithoutPermission && inputMonitoringGranted }

    var statusText: String {
        if needsRelaunch { return "已取得「輸入監控」權限：請結束並重新打開偵測工具，讓權限完整生效" }
        if !inputMonitoringGranted {
            return tapRunning
                ? "缺少「輸入監控」權限：目前只收得到部分指標事件，鍵盤與 HID 層資料收不到"
                : "缺少「輸入監控」權限：事件層監聽無法啟動"
        }
        return tapRunning ? "監聽中 (只聽不擋)：事件層與 HID 層都在記錄" : "事件層監聽啟動失敗，請重新打開偵測工具"
    }

    var logPath: String { recorder.logURL.path }
    var logError: String? { recorder.openError }

    func start() {
        recorder.write("meta", Self.environmentInfo())
        hid.onDevicesChanged = { rows in
            Task { @MainActor in ProbeModel.shared.devices = rows }
        }
        hid.start()
        refreshPermissionAndTap()
        startedWithoutPermission = !inputMonitoringGranted

        // 每 0.5 秒更新一次畫面上的計數；權限剛勾選時自動啟動事件層監聽
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { ProbeModel.shared.periodic() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        recorder.write("meta", ["event": "quit"])
        recorder.flush()
    }

    func select(_ label: ProbeLabel) {
        self.label = label
        recorder.setLabel(label)
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([recorder.logURL])
    }

    func recordTouch(summary: String, fields: [String: Any]) {
        lastTouchSummary = summary
        recorder.write("touch", fields)
    }

    private func periodic() {
        counts = recorder.counts()
        if tap.isRunning { lastSender = tap.lastSender }
        let s = Int(Date().timeIntervalSince(started))
        elapsedText = String(format: "%d:%02d", s / 60, s % 60)
        refreshPermissionAndTap()
    }

    private func refreshPermissionAndTap() {
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        // 啟動時試一次；之後只在「已有權限但還沒啟動」時重試 (使用者一勾選就會開始)
        if !tap.isRunning && (inputMonitoringGranted || !triedTapOnce) {
            triedTapOnce = true
            tap.start()
        }
        tapRunning = tap.isRunning
    }

    private static func environmentInfo() -> [String: Any] {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            ["name": screen.localizedName,
             "frame": [screen.frame.origin.x, screen.frame.origin.y, screen.frame.width, screen.frame.height],
             "scale": screen.backingScaleFactor]
        }
        return [
            "event": "start",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "hw_model": String(cString: model),
            "probe_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "screens": screens,
            "input_monitoring": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
        ]
    }
}
