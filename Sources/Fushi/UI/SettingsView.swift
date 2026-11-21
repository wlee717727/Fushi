import SwiftUI

/// 「設定」視窗 (⌘,)：所有模式共用的設定。
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.language) {
                    Text("Follow System").tag(AppLanguage.system)
                    Divider()
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                        // 語言名稱用該語言書寫 (慣例)，看不懂目前語言的人也找得到
                        Text(verbatim: lang.nativeName ?? "").tag(lang)
                    }
                } label: {
                    Text("Language")
                }
            } footer: {
                if model.language != model.launchLanguage {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("Reopen Fushi to use the new language.")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Reopen Now") { model.relaunch() }
                                .disabled(!model.state.isIdle || model.isRelaunching)
                        }
                        // 失敗時直接顯示在這裡 (使用者正在看設定視窗)
                        if let error = model.relaunchError {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("“Follow System” uses the language in System Settings › General › Language & Region.")
                        .foregroundStyle(.secondary)
                }
            }

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
                    Text("Auto-unlock time")
                    Text("Input always unlocks when time is up, even if you forget to end cleaning")
                }
            } header: {
                Text("Cleaning")
            } footer: {
                if SessionPolicy.isDebugBuild {
                    Text("Development build: auto-unlock is capped at \(SessionPolicy.debugCapSeconds) seconds.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Launch") {
                Toggle(isOn: $model.autoStartLastMode) {
                    Text("Start the last mode when Fushi opens")
                    if let last = model.lastMode {
                        Text("Last mode: \(last.title). A 3-second countdown still runs, so you can cancel")
                    } else {
                        Text("No cleaning history yet")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
