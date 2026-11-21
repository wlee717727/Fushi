import Foundation
import IOKit.hid

/// 監看外接滑鼠／外接觸控板有沒有接上。
/// 全鎖需要外接滑鼠才能開始；全鎖期間外接滑鼠全部拔掉 (或沒電、藍牙斷線) 就立刻全部解鎖。
/// 只讀裝置清單與插拔通知，不需要開啟裝置或任何權限。
@MainActor
final class ExternalMouseMonitor: ObservableObject {
    @Published private(set) var names: [String] = []
    var isConnected: Bool { !names.isEmpty }
    /// 外接滑鼠全部斷線時呼叫
    var onAllDisconnected: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [IOHIDDevice] = []

    init() {
        // 用「任何一個用途」比對，不只看主要用途：
        // 羅技 MX Master 之類的滑鼠，主要用途登記成「鍵盤」(為了送快捷鍵)，滑鼠是次要用途。
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x02],   // 滑鼠
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x01],   // 指標裝置
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            let monitor = Unmanaged<ExternalMouseMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            guard let ctx else { return }
            let monitor = Unmanaged<ExternalMouseMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)
        // 用通用模式：選單打開、正在拖曳時也收得到斷線通知
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        refresh()
    }

    func refresh() {
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var found: [String] = []
        for device in all {
            let builtIn = (IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? NSNumber)?.boolValue ?? false
            var product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            // 排除內建裝置與虛擬裝置 (例如 Karabiner 的虛擬裝置)
            if builtIn || product.localizedCaseInsensitiveContains("karabiner")
                || product.localizedCaseInsensitiveContains("virtual") { continue }
            if product.isEmpty {
                // 沒有產品名稱：只有實體連線 (USB、藍牙) 才算，名稱用通用說法
                let physical = ["USB", "Bluetooth", "Bluetooth Low Energy"].contains { transport.localizedCaseInsensitiveContains($0) }
                guard physical else { continue }
                product = String(localized: "External mouse")
            }
            if !found.contains(product) { found.append(product) }
        }
        found.sort()
        let wasConnected = isConnected
        if found != names { names = found }
        if wasConnected && found.isEmpty { onAllDisconnected?() }
    }
}
