import Foundation
import IOKit
import IOKit.hid

/// 一個 HID 裝置的摘要 (給畫面顯示)。
struct HIDDeviceRow: Identifiable, Equatable, Sendable {
    let id: UInt64          // IORegistry entry ID
    let product: String
    let manufacturer: String
    let vendorID: Int
    let productID: Int
    let transport: String
    let usagePage: Int
    let usage: Int
    let builtIn: Bool?
    let className: String
    let locationID: Int

    var kindText: String {
        switch (usagePage, usage) {
        case (0x01, 0x06): return "鍵盤"
        case (0x01, 0x02): return "滑鼠／指標"
        case (0x01, 0x01): return "指標"
        case (0x0D, _): return "數位板／觸控 (Digitizer)"
        case (0x0C, _): return "媒體鍵 (Consumer)"
        case (0xFF00..., _): return "廠商自訂"
        default: return String(format: "UsagePage 0x%02X／Usage 0x%02X", usagePage, usage)
        }
    }
}

/// HID 層監聽：用 IOHIDManager 列出所有裝置，並「只聽不擋」地記錄每個裝置送出的資料。
///
/// 為什麼要這一層？事件層 (CGEvent) 看到的是系統整理過的事件，可能分不出來源；
/// HID 層看得到「哪一個實體裝置」在送資料，可以用時間點對照，找出事件真正的來源。
final class HIDProbe: @unchecked Sendable {
    static let maxRecordsPerSecondPerDevice = 30

    private let recorder: ProbeRecorder
    private var manager: IOHIDManager?
    private var thread: Thread?
    private let lock = NSLock()
    private var devices: [UInt64: [String: Any]] = [:]
    private var rate: [UInt64: (second: UInt64, count: Int, dropped: Int)] = [:]

    /// 裝置清單變動時呼叫 (在背景執行緒)
    var onDevicesChanged: (([HIDDeviceRow]) -> Void)?
    private(set) var openResult: IOReturn = kIOReturnSuccess

    init(recorder: ProbeRecorder) {
        self.recorder = recorder
    }

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, nil)   // nil = 所有 HID 裝置

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDProbe>.fromOpaque(ctx).takeUnretainedValue().deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDProbe>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<HIDProbe>.fromOpaque(ctx).takeUnretainedValue().inputValue(value)
        }, context)

        // 放在自己的執行緒上跑，不影響畫面
        let thread = Thread { [weak self] in
            guard let self else { return }
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            // kIOHIDOptionsTypeNone：一般開啟，「不」獨占裝置 (seize)，其他程式照常收到輸入
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.openResult = result
            self.recorder.write("meta", ["event": "hid_manager_open",
                                         "result": String(format: "0x%08X", UInt32(bitPattern: result)),
                                         "ok": result == kIOReturnSuccess])
            CFRunLoopRun()
        }
        thread.name = "拂拭偵測.HID"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    // MARK: 裝置

    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString).map { JSONSafe.convert($0) }
    }

    private func describe(_ device: IOHIDDevice) -> [String: Any] {
        let service = IOHIDDeviceGetService(device)
        var info: [String: Any] = ["registry_id": registryID(device)]
        let keys = [kIOHIDProductKey, kIOHIDManufacturerKey, kIOHIDVendorIDKey, kIOHIDProductIDKey,
                    kIOHIDTransportKey, kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey,
                    kIOHIDDeviceUsagePairsKey, "Built-In", kIOHIDLocationIDKey,
                    kIOHIDVersionNumberKey, kIOHIDCountryCodeKey, "DeviceTypeHint", "IOClass"]
        for key in keys {
            if let value = property(device, key) { info[key] = value }
        }
        if let cls = IOObjectCopyClass(service)?.takeRetainedValue() {
            info["ClassName"] = cls as String
        }
        return info
    }

    private func row(from info: [String: Any]) -> HIDDeviceRow {
        func int(_ k: String) -> Int { (info[k] as? NSNumber)?.intValue ?? (info[k] as? Int) ?? 0 }
        let builtIn: Bool? = (info["Built-In"] as? NSNumber).map { $0.boolValue } ?? (info["Built-In"] as? Bool)
        return HIDDeviceRow(id: info["registry_id"] as? UInt64 ?? 0,
                            product: info[kIOHIDProductKey] as? String ?? "(沒有名稱)",
                            manufacturer: info[kIOHIDManufacturerKey] as? String ?? "",
                            vendorID: int(kIOHIDVendorIDKey), productID: int(kIOHIDProductIDKey),
                            transport: info[kIOHIDTransportKey] as? String ?? "",
                            usagePage: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey),
                            builtIn: builtIn, className: info["ClassName"] as? String ?? "",
                            locationID: int(kIOHIDLocationIDKey))
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        let info = describe(device)
        let id = registryID(device)
        lock.lock(); devices[id] = info; lock.unlock()
        recorder.write("device", ["event": "added", "device": info])
        publish()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = registryID(device)
        lock.lock(); let info = devices.removeValue(forKey: id); lock.unlock()
        recorder.write("device", ["event": "removed", "registry_id": id,
                                  "product": info?[kIOHIDProductKey] as? String ?? ""])
        publish()
    }

    private func publish() {
        lock.lock()
        let all = Array(devices.values)
        lock.unlock()
        recorder.writeDevices(all.sorted { ($0["registry_id"] as? UInt64 ?? 0) < ($1["registry_id"] as? UInt64 ?? 0) })
        // 排序：觸控 (Digitizer) → 指標 → 鍵盤 → 媒體鍵 → 其他 (感測器、廠商自訂)，同類再依名稱
        func rank(_ r: HIDDeviceRow) -> Int {
            switch (r.usagePage, r.usage) {
            case (0x0D, _): return 0
            case (0x01, 0x02), (0x01, 0x01): return 1
            case (0x01, 0x06): return 2
            case (0x0C, _): return 3
            default: return 4
            }
        }
        let rows = all.map(row(from:)).sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            return $0.product < $1.product
        }
        onDevicesChanged?(rows)
    }

    // MARK: 輸入資料

    private func inputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let id = registryID(device)
        let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let second = nowNs / 1_000_000_000

        // 每個裝置每秒最多記 30 筆，避免檔案爆量；被略過的數量記在下一筆
        lock.lock()
        var entry = rate[id] ?? (second, 0, 0)
        if entry.second != second { entry = (second, 0, entry.dropped) }
        let allowed = entry.count < Self.maxRecordsPerSecondPerDevice
        var droppedBefore = 0
        if allowed {
            entry.count += 1
            droppedBefore = entry.dropped
            entry.dropped = 0
        } else {
            entry.dropped += 1
        }
        rate[id] = entry
        let product = devices[id]?[kIOHIDProductKey] as? String ?? ""
        let pageOfDevice = devices[id]?[kIOHIDPrimaryUsagePageKey] as? NSNumber
        let usageOfDevice = devices[id]?[kIOHIDPrimaryUsageKey] as? NSNumber
        lock.unlock()
        guard allowed else { return }

        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        var fields: [String: Any] = [
            "registry_id": id,
            "product": product,
            "usage_page": page,
            "hid_ts": IOHIDValueGetTimeStamp(value),
            "dropped_before": droppedBefore,
        ]
        if let pageOfDevice { fields["device_primary_usage_page"] = pageOfDevice }
        if let usageOfDevice { fields["device_primary_usage"] = usageOfDevice }
        // 隱私：鍵盤頁 (0x07) 的 usage 就是「哪一個鍵」，不記錄
        if page == 0x07 {
            fields["usage"] = NSNull()
            fields["redacted"] = true
        } else {
            fields["usage"] = usage
        }
        recorder.write("hid", fields, uptimeNs: nowNs)
    }
}
