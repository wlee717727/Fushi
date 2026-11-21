import CoreGraphics
import Darwin
import Foundation
import IOKit

/// 查出一個 CGEvent 是「哪一個實體裝置」送出的。
///
/// 做法 (參考開源專案 LinearMouse 的思路，程式為自行撰寫)：
/// 1. `CGEventCopyIOHIDEvent`：取出事件底層的 HID 事件 (Apple 未公開的函式)。
/// 2. `IOHIDEventGetSenderID`：取得送出它的 HID 服務在 IORegistry 的編號 (未公開)。
/// 3. 用公開的 IOKit 函式找到那個服務，往上找出它屬於哪個裝置 (名稱、是否內建、Usage)。
///
/// 未公開的函式用 dlsym 動態載入：找不到時只是記錄不到編號，App 不會壞掉。
enum EventSender {
    private typealias CopyHIDEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias GetSenderID = @convention(c) (CFTypeRef) -> UInt64

    private static let copyHIDEvent: CopyHIDEvent? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventCopyIOHIDEvent") else { return nil }
        return unsafeBitCast(sym, to: CopyHIDEvent.self)
    }()

    private static let getSenderID: GetSenderID? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventGetSenderID") else { return nil }
        return unsafeBitCast(sym, to: GetSenderID.self)
    }()

    /// 兩個未公開函式是否都找得到 (記在紀錄開頭，方便判斷新版系統還能不能用)。
    static var isAvailable: Bool { copyHIDEvent != nil && getSenderID != nil }

    /// 事件的來源編號；沒有底層 HID 事件 (例如程式產生的事件) 時回傳 nil。
    static func senderID(of event: CGEvent) -> UInt64? {
        guard let copy = copyHIDEvent, let get = getSenderID,
              let hid = copy(event)?.takeRetainedValue() else { return nil }
        let id = get(hid)
        return id == 0 ? nil : id
    }

    // MARK: 編號 → 裝置資訊 (有快取，同一個編號只查一次)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [UInt64: [String: Any]] = [:]

    static func describe(_ id: UInt64) -> [String: Any] {
        lock.lock()
        if let hit = cache[id] { lock.unlock(); return hit }
        lock.unlock()

        var info: [String: Any] = ["sender_id": id]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let cls = IOObjectCopyClass(service)?.takeRetainedValue() { info["sender_class"] = cls as String }
            // 往上 (parents) 搜尋：服務本身沒有的屬性，會從它所屬的裝置節點找到
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            for key in ["Product", "Built-In", "Transport", "PrimaryUsagePage", "PrimaryUsage", "VendorID", "ProductID"] {
                if let v = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options) {
                    info["sender_" + key] = JSONSafe.convert(v)
                }
            }
            // 往上找出第一個「HID 裝置節點」的編號，可以跟裝置清單的 registry_id 對照
            info["sender_device_registry_id"] = deviceAncestorID(of: service)
        } else {
            info["sender_missing"] = true
        }

        lock.lock(); cache[id] = info; lock.unlock()
        return info
    }

    /// 從服務往上找，回傳第一個有 "PrimaryUsagePage" 屬性的節點 (也就是 IOHIDDevice 那一層) 的編號。
    private static func deviceAncestorID(of service: io_registry_entry_t) -> UInt64 {
        var current = service
        IOObjectRetain(current)
        for _ in 0..<12 {
            if IORegistryEntryCreateCFProperty(current, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0) != nil {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(current, &id)
                IOObjectRelease(current)
                return id
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current)
            current = parent
        }
        IOObjectRelease(current)
        return 0
    }
}
