import AppKit
import CoreGraphics

/// 事件層監聽：建立「只監聽」(listenOnly) 的 CGEventTap，絕不擋下任何事件。
///
/// 同時在兩個位置監聽：
/// - hid：事件剛從硬體進入系統的位置 (最原始)
/// - session：事件送進使用者工作階段的位置 (一般 App 看到的)
/// 兩者欄位可能不同，一起記錄方便比較。
final class EventTapProbe: @unchecked Sendable {
    /// 高頻事件 (移動、拖曳、捲動、手勢) 每種類型每秒最多記 30 筆
    static let maxHighFrequencyPerSecond = 30

    private let recorder: ProbeRecorder
    private var contexts: [TapContext] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let lock = NSLock()
    private var rate: [String: (second: UInt64, count: Int, dropped: Int)] = [:]
    private var _lastSender = "還沒有指標事件"

    /// 最近一個指標事件來自哪個裝置 (給畫面即時顯示)
    var lastSender: String {
        lock.lock(); defer { lock.unlock() }
        return _lastSender
    }

    init(recorder: ProbeRecorder) {
        self.recorder = recorder
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return !contexts.isEmpty
    }

    /// 建立監聽。回傳每個位置是否成功；失敗通常代表沒有「輸入監控」權限。
    @discardableResult
    func start() -> [String: Bool] {
        lock.lock()
        let running = !contexts.isEmpty
        lock.unlock()
        if running { return ["hid": true, "session": true] }

        var result: [String: Bool] = [:]
        var created: [TapContext] = []
        let mask = CGEventMask.max   // 所有事件類型 (含未公開的類型)
        for (name, location) in [("hid", CGEventTapLocation.cghidEventTap), ("session", .cgSessionEventTap)] {
            let context = TapContext(name: name, probe: self)
            let refcon = Unmanaged.passUnretained(context).toOpaque()
            if let port = CGEvent.tapCreate(tap: location, place: .tailAppendEventTap, options: .listenOnly,
                                            eventsOfInterest: mask, callback: probeTapCallback, userInfo: refcon) {
                context.port = port
                created.append(context)
                result[name] = true
            } else {
                result[name] = false
            }
        }
        recorder.write("meta", ["event": "event_tap_start", "result": result,
                                "sender_api_available": EventSender.isAvailable])
        guard !created.isEmpty else { return result }

        lock.lock(); contexts = created; lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            for ctx in created {
                guard let port = ctx.port, let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { continue }
                CFRunLoopAddSource(rl, src, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            self?.lock.lock(); self?.runLoop = rl; self?.lock.unlock()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "拂拭偵測.事件層"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return result
    }

    // MARK: 處理單一事件 (在監聽執行緒上)

    fileprivate func handle(_ context: TapContext, type: CGEventType, event: CGEvent) {
        let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
            recorder.write("meta", ["event": "tap_reenabled", "tap": context.name, "reason": type.rawValue], uptimeNs: nowNs)
            return
        }

        let raw = type.rawValue
        var droppedBefore = 0
        if Self.highFrequencyTypes.contains(raw) {
            let key = "\(context.name).\(raw)"
            let second = nowNs / 1_000_000_000
            lock.lock()
            var entry = rate[key] ?? (second, 0, 0)
            if entry.second != second { entry = (second, 0, entry.dropped) }
            let allowed = entry.count < Self.maxHighFrequencyPerSecond
            if allowed { entry.count += 1; droppedBefore = entry.dropped; entry.dropped = 0 } else { entry.dropped += 1 }
            rate[key] = entry
            lock.unlock()
            guard allowed else { return }
        }

        let isKey = Self.keyTypes.contains(raw)
        var r: [String: Any] = [
            "tap": context.name,
            "type": raw,
            "type_name": Self.typeName(raw),
            "event_ts": event.timestamp,
            "x": Double(event.location.x).rounded(toPlaces: 1),
            "y": Double(event.location.y).rounded(toPlaces: 1),
            "flags": event.flags.rawValue,
            "dropped_before": droppedBefore,
        ]

        // 已知欄位
        var known: [String: Any] = [:]
        for (name, field) in Self.knownIntegerFields {
            known[name] = event.getIntegerValueField(field)
        }
        for (name, field) in Self.knownDoubleFields {
            known[name] = event.getDoubleValueField(field).rounded(toPlaces: 4)
        }
        r["fields"] = known

        // 原始欄位掃描：編號 0～255 逐一讀出，只記非零值。
        // 未公開的欄位 (沒有名稱的編號) 可能正是分辨裝置的關鍵。
        var rawInt: [String: Int64] = [:]
        var rawDouble: [String: Double] = [:]
        var nonzero: [Int] = []
        for i in 0..<256 {
            let field = Self.field(i)
            let iv = event.getIntegerValueField(field)
            let dv = event.getDoubleValueField(field)
            guard iv != 0 || dv != 0 else { continue }
            if isKey {
                // 隱私：鍵盤事件只記「哪些欄位非零」，數值只記白名單 (不含按鍵代碼)
                nonzero.append(i)
                if Self.keyAllowedFields.contains(i) {
                    rawInt[String(i)] = iv
                    if dv != 0 { rawDouble[String(i)] = dv.rounded(toPlaces: 4) }
                }
            } else {
                if iv != 0 { rawInt[String(i)] = iv }
                if dv != 0 && dv.isFinite { rawDouble[String(i)] = dv.rounded(toPlaces: 4) }
            }
        }
        r["raw_int"] = rawInt
        r["raw_double"] = rawDouble
        if isKey {
            r["raw_nonzero_fields"] = nonzero
            r["fields"] = known.filter { $0.key != "keyboardEventKeycode" }
        }

        // 事件來源裝置：這個事件是哪一個實體裝置送出的 (分辨觸控板／觸控螢幕／外接滑鼠的關鍵)
        if let sid = EventSender.senderID(of: event) {
            let sender = EventSender.describe(sid)
            r["sender"] = sender
            if !isKey {
                let name = sender["sender_Product"] as? String ?? (sender["sender_class"] as? String ?? "未知裝置")
                lock.lock(); _lastSender = name; lock.unlock()
            }
        } else {
            r["sender"] = NSNull()
        }

        // 轉成 NSEvent 後的資訊 (每個屬性都用 FPTry 保護，不支援的屬性回傳 null 而不是當掉)
        r["nsevent"] = Self.nsEventInfo(event, isKey: isKey)

        recorder.write("tap", r, uptimeNs: nowNs)
    }

    private static func nsEventInfo(_ cgEvent: CGEvent, isKey: Bool) -> [String: Any] {
        var info: [String: Any] = [:]
        var ns: NSEvent?
        guard FPTry({ ns = NSEvent(cgEvent: cgEvent) }), let event = ns else {
            info["available"] = false
            return info
        }
        func grab(_ name: String, _ block: () -> Any) {
            var value: Any = NSNull()
            if FPTry({ value = block() }) { info[name] = value } else { info[name] = NSNull() }
        }
        grab("type") { Int(event.type.rawValue) }
        grab("subtype") { Int(event.subtype.rawValue) }
        if isKey { return info }    // 隱私：鍵盤事件不讀其他屬性 (characters、keyCode 都不碰)
        grab("pressure") { Double(event.pressure) }
        grab("stage") { event.stage }
        grab("deviceID") { event.deviceID }
        grab("phase") { Int(event.phase.rawValue) }
        grab("momentumPhase") { Int(event.momentumPhase.rawValue) }
        grab("hasPreciseScrollingDeltas") { event.hasPreciseScrollingDeltas }
        grab("isDirectionInvertedFromDevice") { event.isDirectionInvertedFromDevice }
        grab("buttonNumber") { event.buttonNumber }
        grab("clickCount") { event.clickCount }
        grab("tabletPointingDeviceID") { event.pointingDeviceID }
        // 手勢事件裡的每一根手指：type 0 = 直接觸碰螢幕 (direct)，1 = 間接 (觸控板)
        var touches: [[String: Any]] = []
        _ = FPTry {
            for touch in event.allTouches() {
                var t: [String: Any] = ["type": Int(touch.type.rawValue), "phase": Int(touch.phase.rawValue)]
                if let device = touch.device as AnyObject? {
                    t["device"] = String(UInt(bitPattern: ObjectIdentifier(device).hashValue), radix: 16)
                }
                touches.append(t)
            }
        }
        if !touches.isEmpty { info["touches"] = touches }
        return info
    }

    // MARK: 常數

    static let keyTypes: Set<UInt32> = [10, 11, 12]   // keyDown、keyUp、flagsChanged
    /// 鍵盤事件允許記錄數值的欄位：自動重複、鍵盤類型、事件來源 (不含按鍵代碼 9)
    static let keyAllowedFields: Set<Int> = [8, 10, 39, 40, 41, 42, 45]
    static let highFrequencyTypes: Set<UInt32> = [5, 6, 7, 22, 23, 27, 29, 30, 31, 34]

    static func field(_ i: Int) -> CGEventField {
        // C 的列舉匯入 Swift 後，未命名的編號也能建立 (rawValue 不檢查)；保險起見再用 unsafeBitCast
        CGEventField(rawValue: UInt32(i)) ?? unsafeBitCast(UInt32(i), to: CGEventField.self)
    }

    static let knownIntegerFields: [(String, CGEventField)] = [
        ("mouseEventNumber", .mouseEventNumber),
        ("mouseEventClickState", .mouseEventClickState),
        ("mouseEventButtonNumber", .mouseEventButtonNumber),
        ("mouseEventSubtype", .mouseEventSubtype),
        ("mouseEventDeltaX", .mouseEventDeltaX),
        ("mouseEventDeltaY", .mouseEventDeltaY),
        ("mouseEventInstantMouser", .mouseEventInstantMouser),
        ("eventSourceStateID", .eventSourceStateID),
        ("eventSourceUnixProcessID", .eventSourceUnixProcessID),
        ("eventSourceUserData", .eventSourceUserData),
        ("eventTargetUnixProcessID", .eventTargetUnixProcessID),
        ("keyboardEventKeyboardType", .keyboardEventKeyboardType),
        ("keyboardEventAutorepeat", .keyboardEventAutorepeat),
        ("keyboardEventKeycode", .keyboardEventKeycode),
        ("scrollWheelEventIsContinuous", .scrollWheelEventIsContinuous),
        ("scrollWheelEventScrollPhase", .scrollWheelEventScrollPhase),
        ("scrollWheelEventMomentumPhase", .scrollWheelEventMomentumPhase),
        ("scrollWheelEventDeltaAxis1", .scrollWheelEventDeltaAxis1),
        ("scrollWheelEventDeltaAxis2", .scrollWheelEventDeltaAxis2),
        ("tabletEventDeviceID", .tabletEventDeviceID),
        ("tabletProximityEventPointerType", .tabletProximityEventPointerType),
    ]

    static let knownDoubleFields: [(String, CGEventField)] = [
        ("mouseEventPressure", .mouseEventPressure),
        ("mouseEventDeltaX_double", .mouseEventDeltaX),
        ("mouseEventDeltaY_double", .mouseEventDeltaY),
        ("scrollWheelEventPointDeltaAxis1", .scrollWheelEventPointDeltaAxis1),
        ("scrollWheelEventPointDeltaAxis2", .scrollWheelEventPointDeltaAxis2),
    ]

    static func typeName(_ raw: UInt32) -> String {
        switch raw {
        case 0: return "null"
        case 1: return "leftMouseDown"
        case 2: return "leftMouseUp"
        case 3: return "rightMouseDown"
        case 4: return "rightMouseUp"
        case 5: return "mouseMoved"
        case 6: return "leftMouseDragged"
        case 7: return "rightMouseDragged"
        case 8: return "mouseEntered"
        case 9: return "mouseExited"
        case 10: return "keyDown"
        case 11: return "keyUp"
        case 12: return "flagsChanged"
        case 13: return "appKitDefined"
        case 14: return "systemDefined"
        case 15: return "applicationDefined"
        case 16: return "periodic"
        case 17: return "cursorUpdate"
        case 18: return "rotate"
        case 19: return "beginGesture"
        case 20: return "endGesture"
        case 22: return "scrollWheel"
        case 23: return "tabletPointer"
        case 24: return "tabletProximity"
        case 25: return "otherMouseDown"
        case 26: return "otherMouseUp"
        case 27: return "otherMouseDragged"
        case 29: return "gesture"
        case 30: return "magnify"
        case 31: return "swipe"
        case 32: return "smartMagnify"
        case 33: return "quickLook"
        case 34: return "pressure"
        case 37: return "directTouch"
        case 38: return "changeMode"
        default: return "type\(raw)"
        }
    }
}

/// 每個監聽位置一個 context，回呼時用來知道是哪一個 tap。
final class TapContext {
    let name: String
    weak var probe: EventTapProbe?
    var port: CFMachPort?
    init(name: String, probe: EventTapProbe) {
        self.name = name
        self.probe = probe
    }
}

private func probeTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
        context.probe?.handle(context, type: type, event: event)
    }
    // 只監聽：事件一律原封不動放行
    return Unmanaged.passUnretained(event)
}
