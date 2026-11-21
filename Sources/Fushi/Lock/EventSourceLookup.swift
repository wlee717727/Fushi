import CoreGraphics
import Darwin
import Foundation
import IOKit

/// 查出一個 CGEvent 是「哪一個實體裝置」送出的 (和偵測工具同一套做法，已在實機驗證)。
///
/// 1. `CGEventCopyIOHIDEvent`：取出事件底層的 HID 事件 (Apple 未公開的函式)。
/// 2. `IOHIDEventGetSenderID`：取得送出它的 HID 服務編號 (未公開)。
/// 3. 用公開的 IOKit 函式找到那個服務，往上找出它所屬裝置的名稱、是否內建、用途。
/// 未公開函式用 dlsym 動態載入：找不到時只是查不到來源 (一律放行)，App 不會壞掉。
/// 做法參考開源專案 LinearMouse (MIT) 的思路，程式為自行撰寫。
enum EventSourceLookup {
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

    static var isAvailable: Bool { copyHIDEvent != nil && getSenderID != nil }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [UInt64: SenderInfo] = [:]

    /// 事件的來源裝置；查不到時回傳 nil。
    static func sender(of event: CGEvent) -> SenderInfo? {
        guard let copy = copyHIDEvent, let get = getSenderID,
              let hid = copy(event)?.takeRetainedValue() else { return nil }
        let id = get(hid)
        guard id != 0 else { return nil }
        lock.lock()
        if let hit = cache[id] { lock.unlock(); return hit }
        lock.unlock()
        let info = describe(id)
        lock.lock(); cache[id] = info; lock.unlock()
        return info
    }

    private static func describe(_ id: UInt64) -> SenderInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        func search(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
        }
        let className = (IOObjectCopyClass(service)?.takeRetainedValue() as String?) ?? ""
        return SenderInfo(builtIn: (search("Built-In") as? NSNumber)?.boolValue,
                          className: className,
                          product: search("Product") as? String ?? "",
                          usagePage: (search("PrimaryUsagePage") as? NSNumber)?.intValue,
                          usage: (search("PrimaryUsage") as? NSNumber)?.intValue)
    }
}
