import SwiftUI

/// 權限頁：說明為什麼需要、一鍵打開系統設定、每秒即時更新授權狀態。品牌卡片樣式。
struct PermissionsPane: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var permissions = AppModel.shared.permissions

    @State private var visible = CGSize(width: 560, height: 640)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Permissions").font(.largeTitle.weight(.bold))
                Text("Fushi blocks input only while cleaning and releases it the moment you finish. It never records what you type.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                SectionTitle("System permissions")
                // 「輸入監控」等「鎖觸控板」推出時再出現；還沒用到的權限不先要
                PermissionCard(
                    granted: permissions.accessibility,
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Needed for Keyboard Cleaning, Trackpad Cleaning, and Full Lock: blocks input before it reaches other apps.",
                    action: permissions.requestAccessibility)
                Text("Screen cleaning needs no permission. This page updates as soon as you turn it on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                SectionTitle("Can’t find it, or turning it on has no effect?")
                VStack(spacing: 8) {
                    BrandStepCard(symbol: "arrow.triangle.2.circlepath", title: "Remove and add it again",
                                  detail: "In the list in System Settings, remove the old “Fushi” with “−”, then add it with “+” and turn it on.")
                    BrandStepCard(symbol: "power", title: "Reopen Fushi",
                                  detail: "Sometimes an app must be reopened before a new permission takes effect.")
                }
            }
            .frame(width: ContentColumn.width(visibleWidth: visible.width, visibleHeight: visible.height))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { visible = $0 }
        .background(BrandBackground())
        .navigationTitle("Permissions")
        .modifier(HideToolbarTitle())
        .onAppear {
            permissions.startPolling()
            model.markGuideSeen()
        }
        .onDisappear { permissions.stopPolling() }
    }

}

/// 一項權限：圖示圓點｜說明｜狀態。狀態固定在右邊，兩項排法永遠一致。
private struct PermissionCard: View {
    let granted: Bool
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Brand.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 按鈕放在說明下方：各語言的按鈕文字長短不一，放右邊會把說明擠成一字一行
                if !granted {
                    Button("Open System Settings…", action: action)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.cardStroke))
    }
}
