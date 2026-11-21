#if DEBUG
import AppKit
import SwiftUI

/// 開發用：把各個面板畫成 PNG，方便檢查外觀而不必真的鎖定螢幕。
/// 用法 (只有 Debug 版有效)：Fushi -FushiSnapshot <輸出資料夾>
@MainActor
enum PanelSnapshots {
    static func runIfRequested() {
        guard let dir = UserDefaults.standard.string(forKey: "FushiSnapshot") else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = AppModel.shared
        let t0 = Date()

        // B 面：控制面板亮起，剩餘 2:43
        var b = SessionState(isDebugBuild: false)
        b.handle(.start(.screenB, requestedSeconds: 180, now: t0))
        b.handle(.tick(now: t0.addingTimeInterval(3)))
        b.handle(.keyPressed(now: t0.addingTimeInterval(20)))
        model.debugPreview(state: b, now: t0.addingTimeInterval(20))
        render(OverlayRootView(model: model).frame(width: 900, height: 560), "B面控制面板", out, dark: true)

        // 倒數：剩 2 秒
        var c = SessionState(isDebugBuild: false)
        c.handle(.start(.deckC(.keyboard), requestedSeconds: 180, now: t0))
        for dark in [false, true] {
            model.debugPreview(state: c, now: t0.addingTimeInterval(1.2))
            render(CountdownHUD(model: model), "倒數面板", out, dark: dark)
        }

        // 鍵盤已鎖定：剩 2:43
        var k = SessionState(isDebugBuild: false)
        k.handle(.start(.deckC(.keyboard), requestedSeconds: 180, now: t0))
        k.handle(.tick(now: t0.addingTimeInterval(3)))
        for dark in [false, true] {
            model.debugPreview(state: k, now: t0.addingTimeInterval(20))
            render(DeckLockHUD(model: model, target: .keyboardAndTrackpad), "鍵盤鎖定面板", out, dark: dark)
        }
        // 長按 Esc 倒數：已按住 1.2 秒 (顯示 2)
        model.debugPreview(state: b, now: t0.addingTimeInterval(20), escHoldStartedAt: Date().addingTimeInterval(-1.2))
        render(OverlayRootView(model: model).frame(width: 900, height: 560), "全黑長按Esc", out, dark: true)
        for dark in [false, true] {
            model.debugPreview(state: k, now: t0.addingTimeInterval(20), escHoldStartedAt: Date().addingTimeInterval(-1.2))
            render(DeckLockHUD(model: model, target: .keyboardAndTrackpad), "C面長按Esc", out, dark: dark)
        }
        // 全黑時碰到鍵盤：呼吸提示 (第 0.7 秒，接近最亮)
        var dark = SessionState(isDebugBuild: false)
        dark.handle(.start(.all, requestedSeconds: 180, now: t0))
        dark.handle(.tick(now: t0.addingTimeInterval(3)))
        model.debugPreview(state: dark, now: t0.addingTimeInterval(20), nudgeAt: Date().addingTimeInterval(-0.7))
        render(OverlayRootView(model: model).frame(width: 900, height: 560), "全黑呼吸提示", out, dark: true)
        model.debugPreview(state: k, now: t0.addingTimeInterval(20))
        print("面板截圖已輸出到 \(out.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, _ name: String, _ dir: URL, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(dark ? Color(white: 0.16) : Color(white: 0.92)))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            let file = dir.appendingPathComponent("\(name)-\(dark ? "深色" : "淺色").png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
#endif
