import Foundation
import IOKit
import IOKit.hid

/// 這台 Mac 有沒有觸控螢幕。
///
/// 做法：找 HID 裝置裡「數位板／觸控螢幕」(UsagePage 0x0D、Usage 0x04)。
/// 只讀裝置清單，不需要任何權限。沒有觸控螢幕的 Mac 會把介面上「觸控停用」這類說法換掉。
enum TouchScreen {
    static let isPresent: Bool = {
        // 開發者用：啟動參數 -FushiTouchScreen YES/NO 可以強制指定 (方便截圖檢查兩種文字)
        if let forced = UserDefaults.standard.object(forKey: "FushiTouchScreen") as? Bool { return forced }

        // 用 IOHIDManager 列出「觸控螢幕」類的 HID 裝置 (和偵測工具同一個方法)；只列清單，不需要開啟裝置或任何權限
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDPrimaryUsagePageKey: 0x0D, kIOHIDPrimaryUsageKey: 0x04]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        return !devices.isEmpty
    }()

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.intValue
    }
}
