import AppKit
import SwiftUI

/// 視窗內的觸控測試區。
///
/// 開啟 `allowedTouchTypes = [.direct, .indirect]` 之後，這個區域會收到 NSTouch：
/// `.direct` 代表手指直接碰螢幕，`.indirect` 代表觸控板。這是分辨觸控螢幕最直接的證據。
final class TouchProbeNSView: NSView {
    var onRecord: ((String, [String: Any]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.direct, .indirect]
        wantsRestingTouches = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("不支援") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: NSTouch

    override func touchesBegan(with event: NSEvent) { touches(event, "began") }
    override func touchesMoved(with event: NSEvent) { touches(event, "moved") }
    override func touchesEnded(with event: NSEvent) { touches(event, "ended") }
    override func touchesCancelled(with event: NSEvent) { touches(event, "cancelled") }

    private func touches(_ event: NSEvent, _ phase: String) {
        let all = event.touches(matching: .any, in: self)
        let direct = all.filter { $0.type == .direct }.count
        let indirect = all.count - direct
        var list: [[String: Any]] = []
        for touch in all {
            var t: [String: Any] = ["type": touch.type == .direct ? "direct" : "indirect",
                                    "phase": Int(touch.phase.rawValue)]
            if let device = touch.device as AnyObject? {
                t["device"] = String(UInt(bitPattern: ObjectIdentifier(device).hashValue), radix: 16)
            }
            list.append(t)
        }
        var fields = baseFields(event)
        fields["kind"] = "touches"
        fields["phase"] = phase
        fields["count"] = all.count
        fields["direct"] = direct
        fields["indirect"] = indirect
        fields["touches"] = list
        let summary = "NSTouch \(phase)：共 \(all.count) 指 (直接 \(direct)、間接 \(indirect))"
        onRecord?(summary, fields)
    }

    // MARK: 一般滑鼠／手勢事件

    override func mouseDown(with event: NSEvent) { pointer(event) }
    override func mouseUp(with event: NSEvent) { pointer(event) }
    override func mouseDragged(with event: NSEvent) { pointer(event) }
    override func rightMouseDown(with event: NSEvent) { pointer(event) }
    override func scrollWheel(with event: NSEvent) { pointer(event) }
    override func magnify(with event: NSEvent) { pointer(event) }
    override func rotate(with event: NSEvent) { pointer(event) }
    override func swipe(with event: NSEvent) { pointer(event) }
    override func smartMagnify(with event: NSEvent) { pointer(event) }
    override func pressureChange(with event: NSEvent) { pointer(event) }

    private var lastMove = Date.distantPast
    override func mouseMoved(with event: NSEvent) {
        // 移動事件很多，視窗層只取樣每 0.1 秒一筆
        guard Date().timeIntervalSince(lastMove) > 0.1 else { return }
        lastMove = Date()
        pointer(event)
    }

    private func pointer(_ event: NSEvent) {
        var fields = baseFields(event)
        fields["kind"] = "event"
        var subtype: Any = NSNull()
        var pressure: Any = NSNull()
        var stage: Any = NSNull()
        _ = FPTry { subtype = Int(event.subtype.rawValue) }
        _ = FPTry { pressure = Double(event.pressure) }
        _ = FPTry { stage = event.stage }
        fields["subtype"] = subtype
        fields["pressure"] = pressure
        fields["stage"] = stage
        let summary = "視窗事件：\(EventTapProbe.typeName(UInt32(event.type.rawValue)))，subtype \(subtype)"
        onRecord?(summary, fields)
    }

    private func baseFields(_ event: NSEvent) -> [String: Any] {
        let p = convert(event.locationInWindow, from: nil)
        return ["ns_type": Int(event.type.rawValue),
                "ns_type_name": EventTapProbe.typeName(UInt32(event.type.rawValue)),
                "x": Double(p.x).rounded(toPlaces: 1), "y": Double(p.y).rounded(toPlaces: 1)]
    }
}

struct TouchPadRepresentable: NSViewRepresentable {
    let onRecord: (String, [String: Any]) -> Void

    func makeNSView(context: Context) -> TouchProbeNSView {
        let view = TouchProbeNSView(frame: .zero)
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: TouchProbeNSView, context: Context) {
        nsView.onRecord = onRecord
    }
}
