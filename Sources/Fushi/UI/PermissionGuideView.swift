import SwiftUI

/// 權限頁：說明為什麼需要、一鍵打開系統設定、每秒即時更新授權狀態。品牌卡片樣式。
struct PermissionsPane: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var permissions = AppModel.shared.permissions

    @State private var visible = CGSize(width: 560, height: 640)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("權限").font(.largeTitle.weight(.bold))
                Text("拂拭只在清潔期間攔截輸入，結束後立刻放行，不會記錄你按了什麼。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                SectionTitle("系統權限")
                // 「輸入監控」等「鎖觸控板」推出時再出現；還沒用到的權限不先要
                PermissionCard(
                    granted: permissions.accessibility,
                    symbol: "accessibility",
                    title: "輔助使用",
                    detail: "C 面清潔需要：在鍵盤事件送到其他 App 之前把它擋下來。",
                    action: permissions.requestAccessibility)
                Text("B 面清潔不需要任何權限。勾選後這一頁會自動更新。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                SectionTitle("找不到或勾了沒反應？")
                VStack(spacing: 8) {
                    BrandStepCard(symbol: "arrow.triangle.2.circlepath", title: "移除後重新加入",
                                  detail: "在系統設定的清單裡，先用「−」移除舊的「拂拭」，再按「+」加入並打開開關。")
                    BrandStepCard(symbol: "power", title: "重新打開拂拭",
                                  detail: "系統有時要重新打開 App，新權限才會生效。")
                }
            }
            .frame(width: ContentColumn.width(visibleWidth: visible.width, visibleHeight: visible.height))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { visible = $0 }
        .background(BrandBackground())
        .navigationTitle("權限")
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
    let title: String
    let detail: String
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Label("已允許", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("打開系統設定…", action: action)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.cardStroke))
    }
}
