import SwiftUI

/// 「設定」視窗 (⌘,)：所有模式共用的設定。
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: Binding(get: { Double(model.durationSeconds) },
                                              set: { model.durationSeconds = Int($0) }),
                               in: Double(SessionPolicy.minimumSeconds)...Double(SessionPolicy.maximumSeconds),
                               step: 30)
                            .frame(minWidth: 160)
                        Text(SessionPolicy.durationText(seconds: model.durationSeconds))
                            .monospacedDigit()
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                } label: {
                    Text("自動解鎖時間")
                    Text("時間一到一定會解鎖，就算忘了結束也沒關係")
                }
            } header: {
                Text("清潔")
            } footer: {
                if SessionPolicy.isDebugBuild {
                    Text("開發版：自動解鎖最多 \(SessionPolicy.debugCapSeconds) 秒。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("啟動") {
                Toggle(isOn: $model.autoStartLastMode) {
                    Text("打開拂拭時，直接開始上次的模式")
                    if let last = model.lastMode {
                        Text("上次：\(last.title)，一樣會先倒數 3 秒，可以取消")
                    } else {
                        Text("還沒有清潔紀錄")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
