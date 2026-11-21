import AppKit
import SwiftUI

@main
struct FushiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Fushi", id: "main") {
            MainView()
                .environmentObject(model)
        }
        .defaultSize(width: 840, height: 880)   // 實際大小打開時由 MainLayout.fitMainWindow 依語言調整
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Cleaning") {
                CleaningCommands().environmentObject(model)
            }
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }

        Window("Fushi Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 640, height: 720)

        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Fushi")
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
        let help = Button("Fushi Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
        if #available(macOS 15.0, *) {
            // 按住 ⌥ 時才出現的支援用項目 (一般使用者看不到)
            help.modifierKeyAlternate(.option) {
                Button("Copy Diagnostics (for Developers)") {
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
        Button("Start Cleaning") { model.startSelected() }
            .disabled(model.startBlockedReason != nil || !model.state.isIdle)
        Button("Start Last Mode") { model.startLastMode() }
            .disabled(model.lastMode == nil || !model.state.isIdle)
        Divider()
        Button("Permissions") { model.presentPermissionGuide() }
    }
}

/// 選單列圖示點開後的內容。
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.state.isCleaning {
                Text("Cleaning: \(model.state.activeMode?.title ?? "")")
                Text("\(model.remainingText) left")
                Button("End Cleaning") { model.confirmEnd() }
            } else if model.state.isCountingDown {
                Text("Starting: \(model.state.activeMode?.title ?? "")")
                Button("Cancel Countdown") { model.cancelCountdown() }
            } else {
                Text("Fushi: Idle")
                // 和主視窗側邊欄同樣的四個選項、同樣的順序
                Button("Start Screen Cleaning") { model.start(model.mode(for: .screen)) }
                Button("Start Keyboard Cleaning") { model.start(model.mode(for: .keyboard)) }
                Button("Start Trackpad Cleaning") { model.start(model.mode(for: .trackpad)) }
                if model.externalMouse.isConnected {
                    Button("Start Full Lock") { model.start(model.mode(for: .all)) }
                } else {
                    // 不能按時寫出原因，不只是變灰
                    Button("Start Full Lock (Needs External Mouse)") {}
                        .disabled(true)
                }
                if let last = model.lastMode {
                    Button("Start Last Mode: \(last.title)") { model.start(last) }
                }
            }
            Divider()
            Button("Open Fushi Main Window") {
                openWindow(id: "main")
                NSApp.activate()
            }
            SettingsLink { Text("Settings…") }
            Button("Fushi Help") {
                openWindow(id: "help")
                NSApp.activate()
            }
            Divider()
            Button("Quit Fushi") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear {
            if model.openMainWindow == nil { model.openMainWindow = { openWindow(id: "main") } }
        }
    }
}
