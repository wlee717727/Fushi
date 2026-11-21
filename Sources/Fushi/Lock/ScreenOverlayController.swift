import AppKit
import SwiftUI

/// 無邊框視窗預設不能成為焦點視窗；B 面需要它接收鍵盤，所以覆寫。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 第一下點擊就能操作 (不需要先點一下讓視窗取得焦點)。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// B 面清潔：用全黑視窗蓋住所有螢幕。
///
/// 為什麼這樣能「鎖住觸控螢幕」？觸控螢幕的點擊在 macOS 裡會變成一般滑鼠點擊，
/// 落在最上層的視窗上；我們的視窗什麼都不做，點擊就等於被吃掉了。
/// 這個做法只影響我們自己的視窗，App 結束時視窗消失，什麼都不會殘留。
@MainActor
final class ScreenOverlayController {
    private weak var model: AppModel?
    private var windows: [OverlayWindow] = []
    private var cursorHidden = false
    private var savedPresentation: NSApplication.PresentationOptions = []
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    /// 是否顯示中 (獨立記錄：螢幕清單短暫變成空的時，視窗數量會是 0，不能拿來判斷)
    private(set) var isShowing = false

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        if isShowing { buildWindows(model: model); return }
        isShowing = true
        NSApp.activate()
        buildWindows(model: model)

        // 隱藏 Dock 與選單列、停用 ⌘Tab 切換程式。
        // 這些「呈現選項」只對我們這個程式有效，App 結束時系統自動還原，不會殘留。
        savedPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing, let model = self.model else { return }
                self.buildWindows(model: model)   // 插拔外接螢幕時重新蓋滿
            }
        }
        // 全黑期間被別的程式 (Spotlight、系統對話框) 搶走前景：馬上搶回來，
        // 否則按鍵會打進後面看不到的 App，長按 Esc 也收不到
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reclaimFocus() }
        }
        // 從選單列開始時，系統有時不讓拂拭立刻到前景：稍後再確認一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if !NSApp.isActive { self?.reclaimFocus() }
        }
        setCursorHidden(true)
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        screenObserver = nil
        resignObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        // 只有真的顯示過全黑畫面才還原 (C 面沒動過這些設定，不要去重設)
        if isShowing { NSApp.presentationOptions = savedPresentation }
        isShowing = false
        setCursorHidden(false)
    }

    /// 確認拂拭在前景、全黑視窗是焦點視窗
    func reclaimFocus() {
        guard isShowing else { return }
        Diagnostics.log("全黑畫面失去前景，重新搶回")
        NSApp.activate()
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        (windows.first { $0.screen == mainScreen } ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    /// 全黑時隱藏游標；控制面板亮起時顯示游標，方便用觸控板按按鈕。
    func update(display: ScreenBDisplay) {
        if case .dark = display { setCursorHidden(true) } else { setCursorHidden(false) }
    }

    private func buildWindows(model: AppModel) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver               // 高於選單列、Dock、一般浮動視窗
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.animationBehavior = .none
            window.appearance = NSAppearance(named: .darkAqua)
            if screen == mainScreen {
                window.contentView = FirstMouseHostingView(rootView: OverlayRootView(model: model))
            } else {
                let black = NSView()
                black.wantsLayer = true
                black.layer?.backgroundColor = NSColor.black.cgColor
                window.contentView = black
            }
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        // 主螢幕的視窗設為焦點，鍵盤輸入只會送到這裡
        windows.first { $0.screen == mainScreen }?.makeKeyAndOrderFront(nil)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHidden else { return }   // hide/unhide 要成對呼叫
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
        cursorHidden = hidden
    }
}

/// 浮在最上層的小面板 (倒數、鍵盤已鎖定)。不會搶走其他 App 的焦點。
@MainActor
final class FloatingHUD {
    private var panel: NSPanel?

    func show<V: View>(_ view: V) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = FirstMouseHostingView(rootView: view)
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)
        // 卡片四周有 12 點的陰影留白 (HUDCard 的 padding)，對齊時要扣掉
        let shadowPad: CGFloat = 12
        let inset: CGFloat = 12
        if let hero = HeroAnchor.current,
           hero.frame.width >= size.width - 2 * shadowPad + 2 * inset {
            // 主視窗開著：對齊插畫框左上角，左邊與上面內縮一樣的距離
            panel.setFrameOrigin(NSPoint(x: (hero.frame.minX + inset - shadowPad).rounded(),
                                         y: (hero.frame.maxY - inset + shadowPad - size.height).rounded()))
        } else if let screen = HeroAnchor.current?.screen ?? NSScreen.main {
            // 沒有主視窗 (例如從選單列開始)：螢幕上方正中間。
            // 左右用整個螢幕寬度置中 (Dock 放在左右側時，visibleFrame 會少掉 Dock 寬度，中心會偏)；
            // 上下用 visibleFrame，避開選單列
            let full = screen.frame
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: (full.midX - size.width / 2).rounded(),
                                         y: visible.maxY - size.height - 48))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
