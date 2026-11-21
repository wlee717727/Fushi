import SwiftUI

/// 面板按鈕共用的尺寸：一樣高、一樣圓角，並排時平分寬度。
enum PanelButtonMetrics {
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 10
}

/// 面板按鈕的外觀：淡色底＋圖示＋文字，和「按住結束」完全同尺寸。
struct PanelButtonLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                // 長語言 (德文、法文) 文字放不下時自動縮小，兩顆按鈕仍維持同樣高度
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: PanelButtonMetrics.height)
    }
}

/// 一般面板按鈕 (例如「繼續清潔」)：中性灰底，按下時稍微變深。
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: PanelButtonMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09))
            )
            .contentShape(RoundedRectangle(cornerRadius: PanelButtonMetrics.cornerRadius, style: .continuous))
    }
}

/// 要「按住」才會生效的按鈕：按住時紅色由左往右填滿整顆按鈕，填滿就執行。
/// 為什麼要按住？清潔時手會碰到螢幕和觸控板，單純點一下太容易誤觸。
struct HoldToConfirmButton: View {
    let title: LocalizedStringKey
    var symbol: String = "hand.tap.fill"
    var holdSeconds: Double = SessionPolicy.holdToEndSeconds
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelButtonMetrics.cornerRadius, style: .continuous)
        PanelButtonLabel(title: title, symbol: symbol, tint: .red)
            .background(
                ZStack(alignment: .leading) {
                    shape.fill(Color.primary.opacity(0.09))
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.red.opacity(0.35))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .clipShape(shape)
            )
            .contentShape(shape)
            .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 60) {
                action()
            } onPressingChanged: { isPressing in
                setPressing(isPressing)
            }
            .help("Hold for \(Int(holdSeconds)) seconds")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityHint("Hold for \(Int(holdSeconds)) seconds")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func setPressing(_ isPressing: Bool) {
        if isPressing {
            withAnimation(.linear(duration: holdSeconds)) { progress = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
    }
}

/// 浮動面板共用的外框：品牌底色 (淺色白底、深色深藍夜空漸層)＋品牌細框，圓角 16。陰影交給系統視窗。
struct HUDCard<Content: View>: View {
    var width: CGFloat = 360
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(20)
            .frame(width: width)
            .background(shape.fill(LinearGradient(colors: [Brand.pageTop, Brand.pageBottom],
                                                  startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Brand.heroStroke, lineWidth: 1))
            .padding(12)   // 留空間給系統陰影
    }
}

/// 面板標頭：App 圖示＋標題＋副標，三個面板共用同一種。
struct HUDHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 開始前的 3 秒倒數：圓環一格一格減少，中間是大數字。
struct CountdownHUD: View {
    @ObservedObject var model: AppModel

    private var remaining: Int { model.state.countdownRemaining(at: model.now) ?? 0 }
    private var fraction: Double {
        guard case .countdown(_, let endsAt, _) = model.state.phase else { return 0 }
        return max(0, min(1, endsAt.timeIntervalSince(model.now) / SessionPolicy.countdownSeconds))
    }

    var body: some View {
        HUDCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Brand.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: fraction)
                    Text(verbatim: "\(remaining)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: remaining)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Starting soon")
                        .font(.headline)
                    Text(model.state.activeMode?.title ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { model.cancelCountdown() } label: {
                    PanelButtonLabel(title: "Cancel", symbol: "xmark")
                        .frame(width: 96)
                }
                .buttonStyle(PanelButtonStyle())
            }
        }
    }
}

/// 長按 Esc 時的回饋：紅色圓環 3 秒填滿，中間大數字 3 → 2 → 1，讓使用者在全黑時也確定「有在算」。
struct EscapeHoldProgress: View {
    let startedAt: Date
    var ringSize: CGFloat = 60

    var body: some View {
        TimelineView(.animation) { context in
            let total = SessionPolicy.emergencyEscapeSeconds
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let fraction = min(1, elapsed / total)
            let remaining = max(1, Int((total - elapsed).rounded(.up)))
            let done = fraction >= 1
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Group {
                        if done {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: ringSize * 0.36, weight: .semibold))
                        } else {
                            Text(verbatim: "\(remaining)")
                                .font(.system(size: ringSize * 0.43, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                    .animation(.snappy, value: remaining)
                }
                .frame(width: ringSize, height: ringSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(done ? "Unlocking…" : "Keep holding Esc")
                        .font(.headline)
                    Text(done ? "Cleaning finished" : "Ends in \(remaining) s · release to cancel")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keep holding Esc to end cleaning")
    }
}

/// 全黑時碰到鍵盤／觸控板／滑鼠的回饋：螢幕四周的金色光暈呼吸兩下，中央淡淡浮出「長按 Esc 3 秒結束」，
/// 停手 6 秒後緩慢淡出 (持續碰觸會一直亮著)。讓使用者知道電腦還開著、拂拭正在保護畫面。
struct NudgeHint: View {
    let startedAt: Date
    let endsAt: Date
    let isFullLock: Bool
    let remainingText: String

    private static let gold = Color(red: 0xE8 / 255, green: 0xC2 / 255, blue: 0x7A / 255)

    /// 緩慢淡入 1 秒 → 停留並以 3 秒為週期緩慢呼吸 → 最後 2 秒緩慢淡出。
    /// t：從開始算起的秒數；left：距離結束還剩幾秒 (持續碰觸會一直延長)
    static func intensity(t: TimeInterval, left: TimeInterval) -> Double {
        guard t >= 0, left > 0 else { return 0 }
        let fadeIn = smooth(min(1, t / 1.0))
        let fadeOut = smooth(min(1, left / 2.0))
        let breath = 0.65 + 0.35 * (0.5 + 0.5 * cos(2 * .pi * t / 3.0))
        return fadeIn * fadeOut * breath
    }

    /// 平滑曲線 (開頭與結尾都放慢)，讓淡入淡出更柔和
    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    var body: some View {
        TimelineView(.animation) { context in
            let a = Self.intensity(t: context.date.timeIntervalSince(startedAt),
                                    left: endsAt.timeIntervalSince(context.date))
            ZStack {
                // 四周光暈：只在邊緣，不在畫面中間留下灰色汙漬
                Rectangle()
                    .strokeBorder(Self.gold, lineWidth: 28)
                    .blur(radius: 36)
                    .opacity(0.85 * a)
                    .ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: Self.gold.opacity(0.45 * a), radius: 18)
                    VStack(spacing: 5) {
                        Text(isFullLock ? "Everything locked · cleaning" : "Screen locked · cleaning")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(isFullLock ? "Hold Esc for 3 s to end · or move the external mouse" : "Hold Esc for 3 s to end cleaning")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Unlocks in \(remainingText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .monospacedDigit()
                    }
                }
                .opacity(min(1, a * 1.25))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// C 面清潔期間浮在畫面上方的面板 (鎖鍵盤、鎖觸控板或兩者)。
struct DeckLockHUD: View {
    @ObservedObject var model: AppModel
    let target: DeckTarget

    private var title: LocalizedStringKey {
        switch target {
        case .keyboard: return "Keyboard locked"
        case .trackpad: return "Trackpad locked"
        case .keyboardAndTrackpad: return "Keyboard & trackpad locked"
        }
    }

    /// 怎麼結束：依「還剩哪些輸入能用」說明
    private var hint: LocalizedStringKey {
        let touch = TouchScreen.isPresent
        switch target {
        case .keyboard:
            return touch ? "Hold the button with the trackpad, a mouse, or the touch screen — or hold Esc for 3 s." : "Hold the button with the trackpad or a mouse — or hold Esc for 3 s."
        case .trackpad:
            return touch ? "Hold the button with the touch screen or an external mouse — or hold Esc for 3 s." : "Hold the button with an external mouse — or hold Esc for 3 s."
        case .keyboardAndTrackpad:
            return touch ? "Hold the button with the touch screen or an external mouse — or hold Esc for 3 s." : "Hold the button with an external mouse — or hold Esc for 3 s."
        }
    }

    var body: some View {
        HUDCard {
            ZStack {
                VStack(alignment: .leading, spacing: 14) {
                    HUDHeader(title: title, subtitle: "Unlocks in \(model.remainingText)")
                    HoldToConfirmButton(title: "Hold 2 s to end cleaning") { model.confirmEnd() }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(model.escHoldStartedAt == nil ? 1 : 0)
                if let start = model.escHoldStartedAt {
                    EscapeHoldProgress(startedAt: start)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.escHoldStartedAt)
        }
    }
}

/// B 面全黑視窗裡的內容：全黑，或亮起的控制面板。
struct OverlayRootView: View {
    @ObservedObject var model: AppModel
    private var isFullLock: Bool { model.state.activeMode == .all }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let start = model.escHoldStartedAt {
                HUDCard(width: 340) {
                    EscapeHoldProgress(startedAt: start, ringSize: 72)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if model.state.isPanelVisible {
                controlPanel
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if let nudge = model.nudgeAt, let end = model.nudgeEndsAt {
                NudgeHint(startedAt: nudge, endsAt: end, isFullLock: isFullLock, remainingText: model.remainingText)
                    .id(nudge)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.state.isPanelVisible)
        .animation(.easeInOut(duration: 0.15), value: model.escHoldStartedAt)
        .environment(\.colorScheme, .dark)
    }

    /// 和其他浮動面板同一套外框 (HUDCard)、同一種「方塊圖示＋標題＋副標」靠左標頭。
    private var controlPanel: some View {
        HUDCard(width: 440) {
            VStack(alignment: .leading, spacing: 16) {
                HUDHeader(title: isFullLock ? "Everything locked" : (TouchScreen.isPresent ? "Screen & touch locked" : "Screen locked"),
                          subtitle: "Unlocks in \(model.remainingText)")
                // 兩顆按鈕同高、同圓角、平分寬度；用顏色區分「繼續」與「結束」
                HStack(spacing: 12) {
                    Button {
                        model.resumeDark()
                    } label: {
                        PanelButtonLabel(title: "Keep cleaning", symbol: "moon.fill")
                    }
                    .buttonStyle(PanelButtonStyle())

                    HoldToConfirmButton(title: "Hold 2 s to end cleaning") {
                        model.confirmEnd()
                    }
                }
                Text(isFullLock
                     ? "Hold the button with the external mouse. Unplugging the mouse or holding Esc for 3 s also unlocks right away. After 8 s without activity the screen goes black again; move the mouse to bring this back."
                     : "You can also hold Esc for 3 s to end. After 8 s without activity the screen goes black again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
