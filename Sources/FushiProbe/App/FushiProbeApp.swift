import AppKit
import SwiftUI

@main
struct FushiProbeApp: App {
    @NSApplicationDelegateAdaptor(ProbeAppDelegate.self) private var appDelegate
    @StateObject private var model = ProbeModel.shared

    var body: some Scene {
        Window("拂拭偵測工具", id: "main") {
            ProbeView(model: model)
        }
        .defaultSize(width: 980, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("測試標籤") {
                ForEach(ProbeLabel.selectable) { item in
                    Button(item.title) { model.select(item) }
                        .keyboardShortcut(KeyEquivalent(item.shortcutDigit ?? "0"), modifiers: .command)
                }
                Divider()
                Button("在 Finder 中顯示紀錄檔") { model.revealLogs() }
            }
            CommandGroup(replacing: .help) {
                ProbeHelpMenuButton()
            }
        }

        Window("拂拭偵測工具 使用說明", id: "help") {
            ProbeHelpView()
        }
        .defaultSize(width: 620, height: 560)
    }
}

struct ProbeHelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("拂拭偵測工具 使用說明") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            ProbeModel.shared.start()
            // 測鍵盤時視窗會收到按鍵；沒有 ⌘ 的按鍵在這裡吃掉，避免一直發出「嗶」聲。
            // (事件層的監聽在這之前就已經記錄到了，不受影響)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                event.modifierFlags.contains(.command) ? event : nil
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { ProbeModel.shared.stop() }
    }
}
