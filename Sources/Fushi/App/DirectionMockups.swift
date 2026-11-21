#if DEBUG
import AppKit
import SwiftUI

/// 開發用：三個視覺方向的模擬畫面，輸出成 PNG 給使用者挑選。
/// 用法 (只有 Debug 版有效)：Fushi -FushiMockups <輸出資料夾> -FushiIconPath <AppIcon-1024.png>
@MainActor
enum DirectionMockups {
    static func runIfRequested() {
        guard let dir = UserDefaults.standard.string(forKey: "FushiMockups") else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let iconPath = UserDefaults.standard.string(forKey: "FushiIconPath") ?? ""
        let art = sceneArt(iconPath: iconPath)

        render(MockWindow(dark: true) { BrandIllustrationMock(art: art) }, "A-品牌插畫", out, dark: true)
        render(MockWindow(dark: false) { BrightFreshMock() }, "B-明亮清新", out, dark: false)
        render(MockWindow(dark: true) { PremiumToolMock() }, "C-精品工具", out, dark: true)
        // 混搭版改用重新構圖的 16:10 主視覺 (scripts/make-hero-art.py 產生)，不再裁圖示
        let hero = UserDefaults.standard.string(forKey: "FushiHeroPath").flatMap { NSImage(contentsOfFile: $0) } ?? art
        render(MockWindow(dark: false) { HybridMock(art: hero, dark: false) }, "混搭-淺色", out, dark: false)
        render(MockWindow(dark: true) { HybridMock(art: hero, dark: true) }, "混搭-深色", out, dark: true)
        print("視覺方向模擬圖已輸出到 \(out.path)")
        exit(0)
    }

    /// 從 App 圖示裁出「筆電＋拂塵」的場景，當作主視覺插畫 (品牌一致)。
    static func sceneArt(iconPath: String) -> NSImage? {
        guard let image = NSImage(contentsOfFile: iconPath),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = CGFloat(cg.width) / 1024
        // 裁切範圍完全落在圖示的圓角方塊內，邊角才不會露出白邊
        let crop = CGRect(x: 170 * scale, y: 190 * scale, width: 684 * scale, height: 478 * scale)
        guard let part = cg.cropping(to: crop) else { return nil }
        return NSImage(cgImage: part, size: NSSize(width: part.width, height: part.height))
    }

    private static func render<V: View>(_ view: V, _ name: String, _ dir: URL, dark: Bool) {
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name).png"))
        }
    }
}

// MARK: - 共用：模擬的視窗外框與側邊欄

private struct MockWindow<Content: View>: View {
    let dark: Bool
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
            }
            .padding(.leading, 18).padding(.top, 18)
        }
        .frame(width: 760, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(dark ? 0.18 : 0.12), lineWidth: 1))
        .padding(30)
        .background(dark ? Color(white: 0.2) : Color(white: 0.86))
    }
}

private struct MockSidebarRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    var selected = false
    var selectedFill: Color = .accentColor
    var textColor: Color = .primary
    var dim = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 10)).opacity(0.6)
            }
            .foregroundStyle(selected ? .white : textColor)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? selectedFill : .clear))
        .opacity(dim ? 0.5 : 1)
    }
}

private let navyTop = Color(red: 0.106, green: 0.133, blue: 0.2)      // #1B2233 (圖示底色)
private let navyBottom = Color(red: 0.027, green: 0.035, blue: 0.059) // #07090F
private let gold = Color(red: 0.91, green: 0.76, blue: 0.48)          // #E8C27A (拂塵把手)

// MARK: - A｜品牌插畫

private struct BrandIllustrationMock: View {
    let art: NSImage?
    var body: some View {
        HStack(spacing: 0) {
            // 側邊欄：深藍夜空，金色選取
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 52)
                Text("清潔模式").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 10)
                MockSidebarRow(symbol: "sparkles.tv", title: "B 面清潔", subtitle: "螢幕", tint: .indigo, selected: true,
                               selectedFill: Color.white.opacity(0.10), textColor: .white)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(gold.opacity(0.7), lineWidth: 1.5))
                MockSidebarRow(symbol: "keyboard", title: "C 面清潔", subtitle: "鍵盤", tint: .teal, textColor: .white)
                MockSidebarRow(symbol: "lock.fill", title: "全鎖", subtitle: "即將推出", tint: .orange, textColor: .white, dim: true)
                Text("設定").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 10).padding(.top, 12)
                MockSidebarRow(symbol: "hand.raised.fill", title: "權限", subtitle: "已允許", tint: .blue, textColor: .white)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 210)
            .background(Color.black.opacity(0.28))

            // 內容：滿版插畫＋標題疊在插畫下緣
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let art {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 550, height: 300).clipped()
                    }
                    LinearGradient(colors: [.clear, navyBottom.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("B 面清潔").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        Text("螢幕全黑、觸控停用，灰塵與指紋無所遁形。")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(28)
                }
                .frame(width: 550, height: 300)

                VStack(alignment: .leading, spacing: 10) {
                    stepCard("moon.fill", "螢幕變成全黑", "觸控螢幕怎麼碰都不會按到東西")
                    stepCard("keyboard", "按任意鍵叫出控制面板", "繼續清潔，或按住 2 秒結束")
                    stepCard("escape", "長按 Esc 2 秒也能結束", "8 秒沒操作自動變回全黑")
                }
                .padding(.horizontal, 28).padding(.top, 18)
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("倒數 3 秒後鎖定").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        Text("3 分鐘後自動解鎖").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Text("開始清潔")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(navyBottom)
                        .padding(.horizontal, 26).padding(.vertical, 10)
                        .background(Capsule().fill(gold))
                }
                .padding(.horizontal, 28).padding(.bottom, 22)
            }
            .frame(width: 550)
        }
        .frame(width: 760, height: 620)
        .background(LinearGradient(colors: [navyTop, navyBottom], startPoint: .top, endPoint: .bottom))
    }

    private func stepCard(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - B｜明亮清新

private struct BrightFreshMock: View {
    private let mint = Color(red: 0.62, green: 0.90, blue: 0.84)
    private let sky = Color(red: 0.68, green: 0.82, blue: 1.0)
    private let ink = Color(red: 0.12, green: 0.16, blue: 0.22)
    private let teal = Color(red: 0.1, green: 0.6, blue: 0.56)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 52)
                Text("清潔模式").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 10)
                MockSidebarRow(symbol: "sparkles.tv", title: "B 面清潔", subtitle: "螢幕", tint: .indigo, selected: true, selectedFill: teal)
                MockSidebarRow(symbol: "keyboard", title: "C 面清潔", subtitle: "鍵盤", tint: .teal)
                MockSidebarRow(symbol: "lock.fill", title: "全鎖", subtitle: "即將推出", tint: .orange, dim: true)
                Text("設定").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 12)
                MockSidebarRow(symbol: "hand.raised.fill", title: "權限", subtitle: "已允許", tint: .blue)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 210)
            .background(Color(white: 0.95))

            VStack(alignment: .leading, spacing: 0) {
                // 主視覺：柔和漸層光斑＋大型「乾淨螢幕」圖形
                ZStack {
                    Circle().fill(mint.opacity(0.55)).frame(width: 300).blur(radius: 60).offset(x: -110, y: -10)
                    Circle().fill(sky.opacity(0.6)).frame(width: 280).blur(radius: 60).offset(x: 120, y: 20)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 230, height: 150)
                        .shadow(color: ink.opacity(0.12), radius: 24, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                                .padding(10)
                                .overlay(Image(systemName: "sparkles").font(.system(size: 38, weight: .light)).foregroundStyle(.white.opacity(0.9)))
                        )
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 26)).foregroundStyle(teal)
                        .padding(10)
                        .background(Circle().fill(Color.white).shadow(color: ink.opacity(0.12), radius: 10, y: 4))
                        .offset(x: 150, y: 70)
                }
                .frame(width: 550, height: 220)

                VStack(alignment: .leading, spacing: 6) {
                    Text("B 面清潔").font(.system(size: 26, weight: .bold)).foregroundStyle(ink)
                    Text("螢幕全黑、觸控停用，灰塵與指紋一目了然。").font(.system(size: 14)).foregroundStyle(ink.opacity(0.6))
                }
                .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    step("moon.fill", "螢幕變成全黑", "觸控螢幕怎麼碰都不會按到東西")
                    step("keyboard", "按任意鍵叫出控制面板", "繼續清潔，或按住 2 秒結束")
                    step("escape", "長按 Esc 2 秒也能結束", "8 秒沒操作自動變回全黑")
                }
                .padding(.horizontal, 32).padding(.top, 18)
                Spacer()
                HStack {
                    Text("倒數 3 秒後鎖定 · 3 分鐘後自動解鎖").font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
                    Spacer()
                    Text("開始清潔")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 10)
                        .background(Capsule().fill(teal))
                }
                .padding(.horizontal, 32).padding(.bottom, 24)
            }
            .frame(width: 550)
            .background(Color.white)
        }
        .frame(width: 760, height: 620)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(teal)
                .frame(width: 30, height: 30).background(Circle().fill(mint.opacity(0.3)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.975)))
    }

    private func pill(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(teal)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(mint.opacity(0.28)))
    }
}

// MARK: - 混搭：B 的版面＋A 的插畫；淺色、深色同一套結構，只換配色

private struct HybridMock: View {
    let art: NSImage?
    let dark: Bool

    // 淺色：白底＋薄荷；深色：深藍夜空＋金色
    private var ink: Color { dark ? .white : Color(red: 0.12, green: 0.16, blue: 0.22) }
    private var accent: Color { dark ? gold : Color(red: 0.1, green: 0.58, blue: 0.54) }
    private var onAccent: Color { dark ? navyBottom : .white }
    private var glowA: Color { dark ? Color(red: 0.35, green: 0.4, blue: 0.9) : Color(red: 0.62, green: 0.90, blue: 0.84) }
    private var glowB: Color { dark ? gold : Color(red: 0.68, green: 0.82, blue: 1.0) }
    private var cardFill: Color { dark ? Color.white.opacity(0.06) : Color(white: 0.975) }
    private var sidebarFill: Color { dark ? Color.black.opacity(0.28) : Color(white: 0.95) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 52)
                header("清潔模式")
                MockSidebarRow(symbol: "sparkles.tv", title: "B 面清潔", subtitle: "螢幕", tint: .indigo, selected: true,
                               selectedFill: dark ? Color.white.opacity(0.10) : accent, textColor: ink)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(dark ? gold.opacity(0.7) : .clear, lineWidth: 1.5))
                MockSidebarRow(symbol: "keyboard", title: "C 面清潔", subtitle: "鍵盤", tint: .teal, textColor: ink)
                MockSidebarRow(symbol: "lock.fill", title: "全鎖", subtitle: "即將推出", tint: .orange, textColor: ink, dim: true)
                header("設定").padding(.top, 12)
                MockSidebarRow(symbol: "hand.raised.fill", title: "權限", subtitle: "已允許", tint: .blue, textColor: ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 210)
            .background(sidebarFill)

            VStack(alignment: .leading, spacing: 0) {
                // 主視覺：16:10 插畫卡片 (和螢幕同比例，完整不裁切)＋背後柔和光暈
                ZStack {
                    // 光暈只用在淺色；深色模式的模糊光暈會變成灰色汙漬，所以不用
                    if !dark {
                        Circle().fill(glowA.opacity(0.55)).frame(width: 320).blur(radius: 80).offset(x: -150, y: 10)
                        Circle().fill(glowB.opacity(0.6)).frame(width: 280).blur(radius: 70).offset(x: 170, y: 30)
                    }
                    if let art {
                        Image(nsImage: art).resizable().aspectRatio(16.0 / 10.0, contentMode: .fit)
                            .frame(width: 448, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(dark ? gold.opacity(0.35) : Color.white.opacity(0.9), lineWidth: dark ? 1.5 : 4))
                            .shadow(color: Color.black.opacity(dark ? 0.6 : 0.18), radius: 22, y: 12)
                    }
                }
                .frame(width: 550, height: 316)

                VStack(alignment: .leading, spacing: 6) {
                    Text("B 面清潔").font(.system(size: 26, weight: .bold)).foregroundStyle(ink)
                    Text("螢幕全黑、觸控停用，灰塵與指紋一目了然。").font(.system(size: 14)).foregroundStyle(ink.opacity(0.6))
                }
                .padding(.horizontal, 32)

                VStack(spacing: 8) {
                    step("moon.fill", "螢幕變成全黑", "觸控螢幕怎麼碰都不會按到東西")
                    step("keyboard", "按任意鍵叫出控制面板", "繼續清潔，或按住 2 秒結束")
                    step("escape", "長按 Esc 2 秒也能結束", "8 秒沒操作自動變回全黑")
                }
                .padding(.horizontal, 32).padding(.top, 12)
                Spacer(minLength: 8)
                HStack {
                    Text("倒數 3 秒後鎖定 · 3 分鐘後自動解鎖").font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
                    Spacer()
                    Text("開始清潔")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(onAccent)
                        .padding(.horizontal, 26).padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                }
                .padding(.horizontal, 32).padding(.bottom, 20)
            }
            .frame(width: 550)
            .background(dark ? Color.clear : Color.white)
        }
        .frame(width: 760, height: 620)
        .background(dark ? AnyView(LinearGradient(colors: [navyTop, navyBottom], startPoint: .top, endPoint: .bottom))
                         : AnyView(Color.white))
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.opacity(0.45)).padding(.leading, 10)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 30, height: 30).background(Circle().fill(accent.opacity(dark ? 0.15 : 0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(dark ? 0.08 : 0)))
    }
}

// MARK: - C｜精品工具

private struct PremiumToolMock: View {
    private let violet = Color(red: 0.55, green: 0.45, blue: 1.0)
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08)
            RadialGradient(colors: [violet.opacity(0.35), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 360)
            VStack(spacing: 0) {
                // 頂部模式切換膠囊 (取代側邊欄)
                HStack(spacing: 4) {
                    seg("B 面 · 螢幕", selected: true)
                    seg("C 面 · 鍵盤", selected: false)
                    seg("全鎖 · 即將推出", selected: false, dim: true)
                }
                .padding(4)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .padding(.top, 54)

                Text("讓螢幕回到一塵不染")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                Text("全黑畫面、觸控停用。按任意鍵叫出控制面板，按住 2 秒結束。")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 10)

                // 大圓形開始按鈕：外圈是自動解鎖時間
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10).frame(width: 190)
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(LinearGradient(colors: [violet, Color(red: 0.4, green: 0.8, blue: 1)], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 190)
                    Circle().fill(LinearGradient(colors: [violet, Color(red: 0.35, green: 0.3, blue: 0.9)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 140)
                        .shadow(color: violet.opacity(0.6), radius: 30)
                    VStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 26, weight: .semibold))
                        Text("開始").font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.top, 40)

                Text("3 分鐘後自動解鎖")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 18)
                Spacer()
                HStack(spacing: 22) {
                    Label("權限已允許", systemImage: "checkmark.seal.fill")
                    Label("設定", systemImage: "gearshape")
                    Label("說明", systemImage: "questionmark.circle")
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 22)
            }
        }
        .frame(width: 760, height: 620)
    }

    private func seg(_ title: String, selected: Bool, dim: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? Color.black : Color.white.opacity(dim ? 0.35 : 0.75))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(selected ? Color.white : .clear))
    }
}
#endif
