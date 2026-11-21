import AppKit
import SwiftUI

/// 拂拭的品牌配色：全部從 App 圖示取色。
/// 淺色模式：白底＋薄荷／天藍柔光，重點色是青綠；深色模式：深藍夜空，重點色是拂塵握把的金色。
/// 每個顏色都會跟著系統外觀自動切換。
enum Brand {
    /// 主要按鈕與重點顏色
    static let accent = dynamic(light: rgb(0x1A948A), dark: rgb(0xE8C27A))
    /// 主要按鈕上的文字
    static let onAccent = dynamic(light: .white, dark: rgb(0x07090F))
    /// 頁面背景：上、下兩色漸層
    static let pageTop = dynamic(light: .white, dark: rgb(0x1B2233))
    static let pageBottom = dynamic(light: rgb(0xFBFCFC), dark: rgb(0x07090F))
    /// 深色模式的側邊欄底色 (淺色模式用系統原生側邊欄)
    static let sidebarDark = rgb(0x0C1018)
    /// 卡片
    static let card = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.06))
    static let cardStroke = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    /// 插畫卡片的外框
    static let heroStroke = dynamic(light: rgb(0x9EE6D6).withAlphaComponent(0.8), dark: rgb(0xE8C27A).withAlphaComponent(0.35))
    /// 淺色模式插畫背後的柔光
    static let glowMint = Color(nsColor: rgb(0x9EE6D6))
    static let glowSky = Color(nsColor: rgb(0xADD1FF))

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// 頁面背景：深色是深藍夜空漸層；淺色是白底，插畫後方加柔和光暈。
/// 深色模式不放模糊光暈 (會變成灰色汙漬)。
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Brand.pageTop, Brand.pageBottom], startPoint: .top, endPoint: .bottom)
            if scheme == .light {
                ZStack {
                    Circle().fill(Brand.glowMint.opacity(0.7)).frame(width: 380).blur(radius: 90).offset(x: -140, y: 110)
                    Circle().fill(Brand.glowSky.opacity(0.7)).frame(width: 340).blur(radius: 90).offset(x: 150, y: 130)
                }
                .frame(height: 420)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// 主視覺插畫卡片：固定 16:10 (和螢幕同比例)，撐滿內容欄寬度，圖片完整顯示、不裁切。
struct HeroArt: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brand.heroStroke, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
            .background(HeroAnchorView())
            .accessibilityHidden(true)
    }
}

/// 記住主畫面插畫框在螢幕上的位置：浮動面板 (倒數、C 面鎖定) 會對齊插畫框的左上角，
/// 左邊與上面內縮相同距離，不會凸出插畫框外。
@MainActor
enum HeroAnchor {
    static weak var view: NSView?

    /// 插畫框目前在螢幕上的位置與所在螢幕；主視窗沒顯示或插畫不在畫面上時回傳 nil
    static var current: (frame: CGRect, screen: NSScreen)? {
        guard let view, let window = view.window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible), let screen = window.screen else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard frame.width > 100, frame.height > 60 else { return nil }
        return (frame, screen)
    }
}

private struct HeroAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        HeroAnchor.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        HeroAnchor.view = nsView
    }
}

/// 品牌小方塊：淡色品牌底＋品牌色符號 (側邊欄、面板標頭共用)。
struct BrandTile: View {
    let symbol: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Brand.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Brand.accent.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// 品牌卡片：步驟、說明用。帶圖示圓點、標題、一行說明。
struct BrandStepCard: View {
    enum Trailing { case none, locked }
    let symbol: String
    let title: String
    let detail: String
    var trailing: Trailing = .none

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Brand.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if trailing == .locked {
                Label("會鎖住", systemImage: "checkmark.circle.fill")
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

/// 品牌色的膠囊主按鈕。
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Brand.onAccent)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(Capsule().fill(Brand.accent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次要膠囊按鈕 (例如「取消」)：中性底色，和主按鈕同尺寸。
struct BrandSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09)))
    }
}

/// 頁面已有大標題時，隱藏工具列上重複的小標題 (macOS 15 起才支援；macOS 14 維持原樣)。
struct HideToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
