import SwiftUI

// MARK: - 模式的顯示資料

extension ModeKind {
    var title: String {
        switch self {
        case .screenB: return "B 面清潔"
        case .deckC: return "C 面清潔"
        case .all: return "全鎖"
        }
    }

    var sidebarSubtitle: String {
        switch self {
        case .screenB: return "螢幕"
        case .deckC: return "鍵盤與觸控板"
        case .all: return "需要外接滑鼠"
        }
    }

    /// 頁面上的一句話：講「效果」，細節留給下面的卡片
    var summary: String {
        switch self {
        case .screenB: return TouchScreen.isPresent
            ? "螢幕全黑、觸控停用，灰塵與指紋一目了然。"
            : "螢幕全黑、點擊不會按到東西，灰塵與指紋一目了然。"
        case .deckC: return "鍵盤、觸控板各自選擇要不要鎖，螢幕照常顯示。"
        case .all: return "螢幕全黑、全部輸入鎖住，只留外接滑鼠。"
        }
    }

    var symbol: String {
        switch self {
        case .screenB: return "sparkles.tv"
        case .deckC: return "keyboard"
        case .all: return "lock.fill"
        }
    }

    var heroImage: String {
        self == .screenB ? "HeroScreen" : "HeroKeyboard"
    }
}

// MARK: - 主視窗

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var permissions = AppModel.shared.permissions
    @Environment(\.openWindow) private var openWindow
    /// 每次打開都顯示側邊欄 (不沿用上次收起的狀態)；視窗太窄時系統會自己收起
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        // RWD 交給系統原生的分割視窗處理：內容區有最小寬度，視窗太窄時系統會自動收起側邊欄，
        // 而且不會改變視窗大小。(自己用程式收起側邊欄會連帶把視窗縮窄，之前就是這樣出錯。)
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 400, ideal: 560)
        }
        .frame(minWidth: 420, minHeight: 680)
        .alert("無法開始", isPresented: Binding(get: { model.alertMessage != nil },
                                              set: { if !$0 { model.alertMessage = nil } })) {
            Button("好") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            permissions.refresh()
        }
    }

    // MARK: 側邊欄

    private var sidebar: some View {
        List(selection: Binding(get: { Optional(model.sidebar) },
                                set: { if let v = $0 { model.sidebar = v } })) {
            Section("清潔模式") {
                ForEach(ModeKind.allCases) { kind in
                    SidebarRow(symbol: kind.symbol, title: kind.title, subtitle: kind.sidebarSubtitle)
                        .tag(SidebarItem.mode(kind))
                }
            }
            Section("設定") {
                SidebarRow(symbol: "hand.raised.fill", title: "權限",
                           subtitle: permissions.accessibility ? "已允許" : "需要設定",
                           warning: !permissions.accessibility)
                    .tag(SidebarItem.permissions)
            }
        }
        .listStyle(.sidebar)
        .modifier(DarkSidebarBackground())
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    // MARK: 內容區

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .mode(let kind):
            ModePage(kind: kind)
        case .permissions:
            PermissionsPane()
        }
    }
}

/// 側邊欄的一列：品牌色淡底小方塊＋名稱＋一行小字。
private struct SidebarRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var warning = false

    var body: some View {
        HStack(spacing: 10) {
            BrandTile(symbol: symbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(warning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.vertical, 2)
    }
}

/// 深色模式：側邊欄改成深藍底色，和品牌背景連成一體；淺色模式維持系統原生側邊欄。
private struct DarkSidebarBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if scheme == .dark {
            content.scrollContentBackground(.hidden).background(Color(nsColor: Brand.sidebarDark))
        } else {
            content
        }
    }
}

// MARK: - 模式頁 (B 面、C 面、全鎖共用同一個版型)

/// 內容欄寬度：插畫、標題、卡片三者同寬、左右切齊。
/// 只跟視窗大小有關，跟頁面內容無關，所以切換 B 面／C 面／全鎖時尺寸完全一樣。
enum ContentColumn {
    static func width(visibleWidth: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        let byWidth = visibleWidth - 56                          // 左右各留 28
        let reservedHeight: CGFloat = 450                        // 標題、說明、兩組卡片 (最多四張) 與上下留白的高度
        let byHeight = (visibleHeight - reservedHeight) * 1.6    // 插畫是 16:10，寬 = 高 × 1.6
        return max(340, min(560, byWidth, byHeight))
    }
}

private struct ModePage: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var mouse = AppModel.shared.externalMouse
    @ObservedObject private var permissions = AppModel.shared.permissions
    let kind: ModeKind
    @State private var visible = CGSize(width: 560, height: 640)

    private var column: CGFloat {
        ContentColumn.width(visibleWidth: visible.width, visibleHeight: visible.height)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeroArt(imageName: kind.heroImage)

                HStack(spacing: 10) {
                    Text(kind.title).font(.largeTitle.weight(.bold))
                    if kind == .all && !model.externalMouse.isConnected {
                        StatusBadge(text: "需要外接滑鼠", color: .orange)
                    } else if kind != .screenB && !permissions.accessibility {
                        StatusBadge(text: "需要權限", color: .orange)
                    }
                }
                .padding(.top, 20)
                Text(kind.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                cards
            }
            .frame(width: column)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { visible = $0 }
        .background(BrandBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StartBar(kind: kind, column: column)
        }
        .navigationTitle(kind.title)
        .modifier(HideToolbarTitle())   // 頁面上已經有大標題，工具列不再重複
    }

    @ViewBuilder
    private var cards: some View {
        switch kind {
        case .screenB:
            SectionTitle("怎麼用")
            VStack(spacing: 8) {
                BrandStepCard(symbol: "moon.fill", title: "螢幕變成全黑",
                              detail: TouchScreen.isPresent ? "觸控螢幕怎麼碰都不會按到東西" : "游標隱藏，點擊不會按到東西")
                BrandStepCard(symbol: "sparkles", title: "碰到鍵盤或觸控板，畫面會呼吸",
                              detail: "四周亮起金光，提醒電腦還開著；不會跳出可以按的按鈕")
                BrandStepCard(symbol: "escape", title: "長按 Esc 3 秒結束",
                              detail: "按住時出現 3、2、1 倒數；時間到也會自動解鎖")
            }
        case .deckC:
            SectionTitle("要鎖住什麼")
            VStack(spacing: 8) {
                BrandToggleCard(symbol: "keyboard", title: "鍵盤",
                                detail: "所有按鍵與亮度、音量等功能鍵", isOn: $model.deckKeyboard)
                BrandToggleCard(symbol: "rectangle.and.hand.point.up.left", title: "觸控板",
                                detail: "內建觸控板；外接滑鼠照常可用", isOn: $model.deckTrackpad)
            }
            SectionTitle("怎麼結束")
            VStack(spacing: 8) {
                BrandStepCard(symbol: "hand.tap", title: "按住面板上的「結束清潔」2 秒",
                              detail: endHint)
                BrandStepCard(symbol: "escape", title: "長按 Esc 3 秒，一定能退出",
                              detail: "鍵盤鎖住時也有效；時間到也會自動解鎖")
            }
        case .all:
            SectionTitle("外接滑鼠")
            ExternalMouseCard(monitor: model.externalMouse)
            SectionTitle("怎麼結束")
            VStack(spacing: 8) {
                BrandStepCard(symbol: "computermouse", title: "動一下外接滑鼠叫出面板",
                              detail: "再用滑鼠按住「結束清潔」2 秒")
                BrandStepCard(symbol: "bolt.horizontal.circle", title: "拔掉外接滑鼠，立刻全部解鎖",
                              detail: "藍牙斷線、沒電也一樣；長按 Esc 3 秒也能解鎖")
            }
        }
    }

    /// 依照「鎖了哪些、這台有沒有觸控螢幕」說明可以用什麼結束
    private var endHint: String {
        let touch = TouchScreen.isPresent
        if model.deckTrackpad {
            return touch ? "觸控板鎖住時，用觸控螢幕或外接滑鼠按" : "觸控板鎖住時，用外接滑鼠按；沒有滑鼠就長按 Esc 3 秒"
        }
        return touch ? "用觸控板、滑鼠或觸控螢幕都可以" : "用觸控板或滑鼠都可以"
    }
}

/// 可以開關的品牌卡片 (C 面要鎖哪些)。
private struct BrandToggleCard: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Brand.accent : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill((isOn ? Brand.accent : Color.secondary).opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Brand.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.cardStroke))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// 全鎖頁：外接滑鼠的連線狀態 (插拔即時更新)。
private struct ExternalMouseCard: View {
    @ObservedObject var monitor: ExternalMouseMonitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(monitor.isConnected ? Brand.accent : Color.orange)
                .frame(width: 32, height: 32)
                .background(Circle().fill((monitor.isConnected ? Brand.accent : Color.orange).opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.isConnected ? monitor.names.joined(separator: "、") : "沒有偵測到外接滑鼠")
                    .font(.body.weight(.medium))
                Text(monitor.isConnected ? "全鎖期間只有它能操作" : "接上滑鼠或外接觸控板後就能開始 (藍牙或 USB 都可以)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if monitor.isConnected {
                Label("已連接", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.accent)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.cardStroke))
    }
}

/// 卡片群組的小標題
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// 底部固定的開始列：品牌色膠囊按鈕永遠最顯眼；內容左右對齊上方內容欄。
private struct StartBar: View {
    @EnvironmentObject var model: AppModel
    /// 滑鼠插拔時開始按鈕要立刻更新
    @ObservedObject private var mouse = AppModel.shared.externalMouse
    let kind: ModeKind
    let column: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Brand.cardStroke).frame(height: 1)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLine)
                        .font(.callout.weight(.medium))
                    secondaryLine
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                actionButton
            }
            .frame(width: column)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.pageBottom)
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.state.isCountingDown {
            Button("取消") { model.cancelCountdown() }
                .buttonStyle(BrandSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        } else if model.state.isCleaning {
            Button("清潔中…") {}
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(true)
        } else if model.selectedModeNeedsPermission {
            Button("先允許權限…") { model.presentPermissionGuide() }
                .buttonStyle(BrandPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        } else {
            Button("開始清潔") { model.startSelected() }
                .buttonStyle(BrandPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.startBlockedReason != nil)
        }
    }

    private var primaryLine: String {
        if let n = model.state.countdownRemaining(at: model.now) { return "\(n) 秒後開始" }
        if model.state.isCleaning { return "清潔中，\(model.remainingText) 後自動解鎖" }
        if model.selectedModeNeedsPermission { return "鎖鍵盤需要「輔助使用」權限" }
        return model.startBlockedReason ?? "倒數 3 秒後鎖定"
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if model.state.isCountingDown {
            Text("按 Esc 或「取消」可以停止")
        } else if model.selectedModeNeedsPermission {
            Text("允許一次之後就不用再設定")
        } else {
            HStack(spacing: 6) {
                Text("\(SessionPolicy.durationText(seconds: model.effectiveDuration))後自動解鎖")
                SettingsLink {
                    Text("更改時間").font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
