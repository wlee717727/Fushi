import SwiftUI

// MARK: - 模式的顯示資料

extension ModeKind {
    var title: LocalizedStringKey {
        switch self {
        case .screen: return "Screen Cleaning"
        case .keyboard: return "Keyboard Cleaning"
        case .trackpad: return "Trackpad Cleaning"
        case .all: return "Full Lock"
        }
    }

    /// 頁面上的一句話：講「效果」，細節留給下面的卡片
    var summary: LocalizedStringKey {
        switch self {
        case .screen: return TouchScreen.isPresent ? "The screen goes black and touch is off." : "The screen goes black and clicks do nothing."
        case .keyboard: return "Every key is paused."
        case .trackpad: return "The built-in trackpad is paused."
        case .all: return "The screen goes black. Only an external mouse works."
        }
    }

    var symbol: String {
        switch self {
        case .screen: return "sparkles.tv"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .all: return "lock.fill"
        }
    }

    /// 四張插畫同一個取景，只有拂塵移動：螢幕 → 鍵盤 → 觸控板 → 整台
    var heroImage: String {
        switch self {
        case .screen: return "HeroScreen"
        case .keyboard: return "HeroKeyboard"
        case .trackpad: return "HeroTrackpad"
        case .all: return "HeroAll"
        }
    }

    /// 這一頁需要「輔助使用」權限嗎 (螢幕清潔不需要)
    var needsAccessibility: Bool { self != .screen }
}

// MARK: - 依語言自動調整視窗大小

/// 主視窗打開時「依內容自動調整大小」：
/// - 側邊欄：量出目前語言最長的功能名稱，寬度剛好放得下 (任何語言都完整顯示)
/// - 內容區：固定用最舒服的寬度 (插畫最寬 560 點＋左右留白)
/// - 高度：880 點，不超過螢幕
@MainActor
enum MainLayout {
    /// 側邊欄要放得下的文字 (和 ModeKind.title、權限列、分組標題同樣的翻譯 key)
    private static var sidebarTitles: [String] {
        [String(localized: "Screen Cleaning"), String(localized: "Keyboard Cleaning"),
         String(localized: "Trackpad Cleaning"), String(localized: "Full Lock"),
         String(localized: "Permissions")]
    }

    static let sidebarWidth: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let longest = sidebarTitles
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 120
        // 列表左右內距、品牌小方塊 26、間距 10、右側狀態圖示 20、捲軸與餘裕
        return max(200, ceil(longest + 112))
    }()

    static let detailWidth: CGFloat = 640
    static let preferredHeight: CGFloat = 880

    /// 把主視窗調成這個語言最舒服的大小 (主視窗每次出現時呼叫)
    static func fit(_ window: NSWindow) {
        // 等系統還原完上次的視窗位置後再調整，否則會被蓋掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let size = NSSize(width: min(sidebarWidth + detailWidth, visible.width - 40),
                              height: min(preferredHeight, visible.height - 40))
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            // 以目前視窗中心為準調整，並確保整個視窗在螢幕內
            frame.origin.x = min(max(window.frame.midX - frame.width / 2, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(window.frame.midY - frame.height / 2, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

/// 放在主視窗畫面背後：視窗真正出現時，回報是哪一個視窗並調整大小
private struct WindowFitter: NSViewRepresentable {
    final class Probe: NSView {
        private weak var fitted: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== fitted else { return }
            fitted = window
            MainLayout.fit(window)
        }
    }
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        .background(WindowFitter())
        .alert("Can’t start", isPresented: Binding(get: { model.alertMessage != nil },
                                              set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
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
            Section("Cleaning modes") {
                ForEach(ModeKind.allCases) { kind in
                    SidebarRow(symbol: kind.symbol, title: kind.title)
                        .tag(SidebarItem.mode(kind))
                }
            }
            Section("Settings") {
                SidebarRow(symbol: "hand.raised.fill", title: "Permissions",
                           status: permissions.accessibility ? .ok : .warning)
                    .tag(SidebarItem.permissions)
            }
        }
        .listStyle(.sidebar)
        .modifier(DarkSidebarBackground())
        // 寬度依目前語言最長的名稱計算：任何語言都完整顯示，不用拖拉
        .navigationSplitViewColumnWidth(min: MainLayout.sidebarWidth, ideal: MainLayout.sidebarWidth,
                                        max: MainLayout.sidebarWidth + 60)
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

/// 側邊欄的一列：品牌色淡底小方塊＋名稱；需要時右側顯示狀態小圖示 (和系統設定的做法一樣，不加說明小字)。
private struct SidebarRow: View {
    enum Status { case none, ok, warning }
    let symbol: String
    let title: LocalizedStringKey
    var status: Status = .none

    var body: some View {
        HStack(spacing: 10) {
            BrandTile(symbol: symbol, size: 26)
            Text(title)
            Spacer(minLength: 4)
            switch status {
            case .none: EmptyView()
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Brand.accent)
                    .accessibilityLabel("Allowed")
            case .warning:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs setup")
            }
        }
        .padding(.vertical, 3)
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
        let reservedHeight: CGFloat = 520                        // 標題、摘要、兩區共四張卡片與上下留白的高度 (四頁都是這個結構)
        let byHeight = (visibleHeight - reservedHeight) * 1.6    // 插畫是 16:10，寬 = 高 × 1.6
        return max(280, min(560, byWidth, byHeight))   // 視窗矮時插畫縮小，四張卡片一定看得到
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
                        // 窄視窗＋長英文時，標題縮小而不是換行或截斷；狀態標籤維持原大小
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if kind == .all && !model.externalMouse.isConnected {
                        StatusBadge(text: "Needs an external mouse", color: .orange)
                    } else if kind.needsAccessibility && !permissions.accessibility {
                        StatusBadge(text: "Needs permission", color: .orange)
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
        case .screen:
            // 四頁同樣的結構：「會鎖住」＋「怎麼結束」，切換時對齊、不會有一頁特別空
            SectionTitle("What gets locked")
            BrandStepCard(symbol: "hand.point.up.left", title: TouchScreen.isPresent ? "Screen touch" : "Screen clicks",
                          trailing: .locked)
            SectionTitle("How to finish")
            BrandStepCard(symbol: "escape", title: "Hold Esc for 3 s")
        case .keyboard:
            SectionTitle("What gets locked")
            VStack(spacing: 8) {
                BrandStepCard(symbol: "keyboard", title: "Keyboard", trailing: .locked)
                BrandToggleCard(symbol: "rectangle.and.hand.point.up.left", title: "Also lock the trackpad",
                                isOn: $model.keyboardAlsoLocksTrackpad)
            }
            finishCards
        case .trackpad:
            SectionTitle("What gets locked")
            BrandStepCard(symbol: "rectangle.and.hand.point.up.left", title: "Built-in trackpad", trailing: .locked)
            finishCards
        case .all:
            SectionTitle("What gets locked")
            BrandStepCard(symbol: "lock.fill",
                          title: TouchScreen.isPresent ? "Keyboard, trackpad, and touch screen" : "Keyboard and trackpad",
                          trailing: .locked)
            // 和鍵盤頁一樣「兩區、四張卡片」：外接滑鼠就是用來結束的工具，所以放在「怎麼結束」第一張
            SectionTitle("How to finish")
            VStack(spacing: 8) {
                ExternalMouseCard(monitor: model.externalMouse)
                BrandStepCard(symbol: "hand.tap", title: "Move the mouse, then hold the red button for 2 s")
                BrandStepCard(symbol: "bolt.horizontal.circle", title: "Unplug the mouse to unlock instantly")
            }
        }
    }

    /// 鍵盤、觸控板頁共用的「怎麼結束」：標題直接寫出用什麼按，不另外解釋
    @ViewBuilder
    private var finishCards: some View {
        SectionTitle("How to finish")
        VStack(spacing: 8) {
            BrandStepCard(symbol: "hand.tap", title: endButtonTitle)
            BrandStepCard(symbol: "escape", title: "Hold Esc for 3 s")
        }
    }

    /// 依照「這一頁會不會鎖觸控板、這台有沒有觸控螢幕」寫出用什麼按「結束清潔」
    private var endButtonTitle: LocalizedStringKey {
        let touch = TouchScreen.isPresent
        let trackpadLocked = kind == .trackpad || (kind == .keyboard && model.keyboardAlsoLocksTrackpad)
        if trackpadLocked {
            return touch ? "Hold the red button for 2 s with the touch screen or a mouse" : "Hold the red button for 2 s with an external mouse"
        }
        return "Hold the red button on the panel for 2 s"
    }
}

/// 可以開關的品牌卡片 (C 面要鎖哪些)。
private struct BrandToggleCard: View {
    let symbol: String
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
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
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Group {
                    // 裝置名稱照原樣顯示；沒接滑鼠時的說明要翻譯
                    if monitor.isConnected {
                        Text(verbatim: monitor.names.joined(separator: ", "))
                    } else {
                        Text("No external mouse detected")
                    }
                }
                .font(.body.weight(.medium))
                if !monitor.isConnected {
                    Text("Connect a mouse to start")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if monitor.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
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
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

struct StatusBadge: View {
    let text: LocalizedStringKey
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .fixedSize()
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
            // 放得下就左右排；長語言或窄視窗放不下時，按鈕換到說明下方 (不會把說明擠成一條)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusText.fixedSize()
                    Spacer(minLength: 12)
                    button
                }
                VStack(alignment: .leading, spacing: 10) {
                    statusText.fixedSize(horizontal: false, vertical: true)
                    button
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: column)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.pageBottom)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primaryLine)
                .font(.callout.weight(.medium))
            secondaryLine
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 按鈕永遠一行、不被壓縮
    private var button: some View {
        actionButton
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.state.isCountingDown {
            Button("Cancel") { model.cancelCountdown() }
                .buttonStyle(BrandSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        } else if model.state.isCleaning {
            Button("Cleaning…") {}
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(true)
        } else if model.selectedModeNeedsPermission {
            Button("Grant Permission…") { model.presentPermissionGuide() }
                .buttonStyle(BrandPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Start Cleaning") { model.startSelected() }
                .buttonStyle(BrandPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.startBlockedReason != nil)
        }
    }

    private var primaryLine: String {
        if let n = model.state.countdownRemaining(at: model.now) { return String(localized: "Starting in \(n) s") }
        if model.state.isCleaning { return String(localized: "Cleaning · unlocks in \(model.remainingText)") }
        if model.selectedModeNeedsPermission { return String(localized: "Locking requires Accessibility permission") }
        return model.startBlockedReason ?? String(localized: "Locks after a 3-second countdown")
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if model.state.isCountingDown {
            Text("Press Esc or Cancel to stop")
        } else if model.selectedModeNeedsPermission {
            Text("Allow it once and you’re set")
        } else {
            HStack(spacing: 6) {
                Text("Unlocks automatically after \(SessionPolicy.durationText(seconds: model.effectiveDuration))")
                SettingsLink {
                    Text("Change Time").font(.caption.weight(.medium)).foregroundStyle(Brand.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
