import AppKit
import SwiftUI

@main
struct FushiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("拂拭", id: "main") {
            MainView()
                .environmentObject(model)
        }
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("清潔") {
                CleaningCommands().environmentObject(model)
            }
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }

        Window("拂拭 使用說明", id: "help") {
            HelpView()
        }
        .defaultSize(width: 640, height: 720)

        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("拂拭")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // 開發者用：啟動參數 -FushiAppearance light|dark 強制外觀，方便截圖檢查 (不改系統設定)
            switch UserDefaults.standard.string(forKey: "FushiAppearance") {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: break
            }
            Diagnostics.startClickLogging()
            #if DEBUG
            PanelSnapshots.runIfRequested()
            DirectionMockups.runIfRequested()
            #endif
        }
        // 稍微延後，讓主視窗先出現，再決定要不要顯示權限引導或自動開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated { AppModel.shared.handleLaunch() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.emergencyStop() }
    }
}

/// 「說明」選單：不能是空的。
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let help = Button("拂拭 使用說明") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
        if #available(macOS 15.0, *) {
            // 按住 ⌥ 時才出現的支援用項目 (一般使用者看不到)
            help.modifierKeyAlternate(.option) {
                Button("拷貝診斷資訊 (給開發者)") {
                    Diagnostics.copyToPasteboard(permissions: AppModel.shared.permissions)
                }
            }
        } else {
            help
        }
    }
}

/// 「清潔」選單。
struct CleaningCommands: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button("開始清潔") { model.startSelected() }
            .disabled(model.startBlockedReason != nil || !model.state.isIdle)
        Button("開始上次的模式") { model.startLastMode() }
            .disabled(model.lastMode == nil || !model.state.isIdle)
        Divider()
        Button("權限") { model.presentPermissionGuide() }
    }
}

/// 選單列圖示點開後的內容。
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.state.isCleaning {
                Text("清潔中：\(model.state.activeMode?.title ?? "")")
                Text("剩餘 \(model.remainingText)")
                Button("結束清潔") { model.confirmEnd() }
            } else if model.state.isCountingDown {
                Text("即將開始：\(model.state.activeMode?.title ?? "")")
                Button("取消倒數") { model.cancelCountdown() }
            } else {
                Text("拂拭：待命中")
                Button("開始 \(CleaningMode.screenB.title)") { model.start(.screenB) }
                Button("開始 \(CleaningMode.deckC(.keyboard).title)") { model.start(.deckC(.keyboard)) }
                Button("開始 \(CleaningMode.deckC(.keyboardAndTrackpad).title)") { model.start(.deckC(.keyboardAndTrackpad)) }
                Button("開始全鎖 (需要外接滑鼠)") { model.start(.all) }
                    .disabled(!model.externalMouse.isConnected)
                if let last = model.lastMode {
                    Button("開始上次的模式：\(last.title)") { model.start(last) }
                }
            }
            Divider()
            Button("打開拂拭主視窗") {
                openWindow(id: "main")
                NSApp.activate()
            }
            SettingsLink { Text("設定…") }
            Button("使用說明") {
                openWindow(id: "help")
                NSApp.activate()
            }
            Divider()
            Button("結束拂拭") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear {
            if model.openMainWindow == nil { model.openMainWindow = { openWindow(id: "main") } }
        }
    }
}
