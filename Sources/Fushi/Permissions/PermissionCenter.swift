import AppKit
import ApplicationServices
import IOKit.hid

/// 「輔助使用」與「輸入監控」權限的檢查與引導。
///
/// - 輔助使用 (Accessibility)：主動攔截 (擋下) 鍵盤事件需要。
/// - 輸入監控 (Input Monitoring)：只監聽 (不擋) 鍵盤與指標事件需要；
///   第 2 階段分辨裝置時會用到，偵測工具 FushiProbe 也需要。
///
/// 權限綁定在 App 的「簽章身分」上。Release 版用 signing/Fushi.req 把身分固定成 Bundle ID，
/// 重新建置後權限不會失效；Debug 版沒有固定，每次重新建置都要到系統設定重新勾選。
@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    private var pollTimer: Timer?

    init() { refresh() }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let im = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if ax != accessibility { accessibility = ax }
        if im != inputMonitoring { inputMonitoring = im }
    }

    /// 引導畫面開著時每秒檢查一次，使用者在系統設定勾選後畫面會立刻更新。
    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccessibility() {
        // 讓系統把「拂拭」加進清單 (會跳出系統提示)，再打開對應的設定頁
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
