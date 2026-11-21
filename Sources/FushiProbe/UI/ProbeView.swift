import SwiftUI

struct ProbeView: View {
    @ObservedObject var model: ProbeModel

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 860
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labelBar(columns: wide ? 6 : (proxy.size.width >= 520 ? 3 : 2))
                    statusBar(wide: wide)
                    let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                                      : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                    layout {
                        touchPad
                        deviceList
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 測試標籤

    private func labelBar(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("現在要測試哪一個裝置？")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(ProbeLabel.selectable) { item in
                    let selected = model.label == item
                    Button {
                        model.select(item)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.title2)
                            Text(item.title).font(.callout.weight(.semibold))
                            Text("⌘\(String(item.shortcutDigit ?? " "))")
                                .font(.caption2)
                                .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .foregroundStyle(selected ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeOut(duration: 0.15), value: selected)
                }
            }
        }
    }

    // MARK: 狀態

    private func statusBar(wide: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 22))
                                  : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    statusItem(title: "目前標籤", value: model.label.title, symbol: model.label.symbol)
                    statusItem(title: "已記錄 (HID 層)", value: "\(model.counts["hid"] ?? 0) 筆", symbol: "cable.connector")
                    statusItem(title: "已記錄 (事件層)", value: "\(model.counts["tap"] ?? 0) 筆", symbol: "waveform.path.ecg")
                    statusItem(title: "已記錄 (視窗觸控)", value: "\(model.counts["touch"] ?? 0) 筆", symbol: "hand.tap")
                    statusItem(title: "已執行", value: model.elapsedText, symbol: "clock")
                    statusItem(title: "最近事件來自", value: model.lastSender, symbol: "dot.radiowaves.left.and.right")
                }
                Divider()
                HStack(spacing: 8) {
                    let ready = model.tapRunning && model.inputMonitoringGranted && !model.needsRelaunch
                    Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ready ? .green : .orange)
                    Text(model.statusText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !model.inputMonitoringGranted {
                        Button("打開「輸入監控」設定") { model.requestInputMonitoring() }
                    } else if model.needsRelaunch {
                        Button("結束偵測工具") { NSApp.terminate(nil) }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(model.logError ?? model.logPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(model.logError == nil ? Color.secondary : Color.red)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("在 Finder 中顯示") { model.revealLogs() }
                }
            }
            .padding(6)
        }
    }

    private func statusItem(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }

    // MARK: 觸控測試區

    private var touchPad: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("觸控測試區").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                VStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left").font(.system(size: 30)).foregroundStyle(.tint)
                    Text("在這個區域裡用觸控螢幕點、長按、拖曳、兩指捲動")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Text("也用觸控板、滑鼠在這裡操作，方便比較")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.lastTouchSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .allowsHitTesting(false)
                TouchPadRepresentable { summary, fields in
                    model.recordTouch(summary: summary, fields: fields)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 260, idealHeight: 340, maxHeight: 380)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: 裝置清單

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HID 裝置 (\(model.devices.count))").font(.headline)
                Spacer()
                Text("插拔裝置會即時更新").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                if model.devices.isEmpty {
                    Text("正在讀取裝置…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Divider() }
                    DeviceRowView(device: device)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DeviceRowView: View {
    let device: HIDDeviceRow
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(device.product).font(.callout.weight(.semibold))
                if device.builtIn == true {
                    Text("內建")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                }
                Spacer(minLength: 4)
                Text(device.kindText).font(.caption).foregroundStyle(.secondary)
            }
            Text(String(format: "VID 0x%04X・PID 0x%04X・%@・%@・Usage 0x%02X/0x%02X",
                        device.vendorID, device.productID,
                        device.transport.isEmpty ? "未知傳輸" : device.transport,
                        device.className, device.usagePage, device.usage))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// 偵測工具的使用說明。
struct ProbeHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("拂拭偵測工具 使用說明").font(.largeTitle.weight(.semibold))
                Group {
                    Text("這是做什麼的").font(.title3.weight(.semibold))
                    Text("找出鍵盤、內建觸控板、觸控螢幕、外接滑鼠、外接觸控板在系統裡各自長什麼樣子，決定拂拭第 2 階段能不能「只鎖觸控板、保留觸控螢幕」。這個工具只監聽、絕不攔截，不會影響任何輸入。")
                    Text("快速開始").font(.title3.weight(.semibold))
                    Text("1. 第一次開啟時，到「系統設定 › 隱私權與安全性 › 輸入監控」勾選「拂拭偵測工具」。\n2. 按上方的裝置按鈕 (或 ⌘1～⌘6) 選擇現在要測試的裝置。\n3. 用那個裝置操作約 10 秒 (詳細動作見 docs/PROBE-GUIDE.md)。\n4. 全部測完後結束 App，執行分析腳本：python3 scripts/analyze-probe.py")
                    Text("鍵盤快速鍵").font(.title3.weight(.semibold))
                    Text("⌘1 鍵盤　⌘2 內建觸控板　⌘3 觸控螢幕　⌘4 外接滑鼠　⌘5 外接觸控板　⌘6 閒置　⌘? 使用說明")
                    Text("隱私").font(.title3.weight(.semibold))
                    Text("鍵盤事件不記錄按了哪個鍵 (不記 keycode、不記字元)，只記錄「這是鍵盤事件」與其他欄位。紀錄檔存在專案資料夾的 probe-logs，不會上傳。")
                    Text("常見問題").font(.title3.weight(.semibold))
                    Text("• 事件層一直顯示未啟動：確認已勾選輸入監控；重新建置過的版本要把清單裡舊的項目移除再重新加入。\n• 跳出「想取用桌面資料夾」：允許，紀錄才能存到桌面的專案資料夾。")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(minWidth: 360, minHeight: 360)
    }
}
