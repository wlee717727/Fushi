import SwiftUI

/// 內建使用說明 (「說明」選單 › 拂拭 使用說明，⌘?)。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("拂拭 使用說明").font(.largeTitle.weight(.semibold))
                        Text("清潔 Mac 時暫時鎖住輸入。版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }

                HelpSection(title: "這個 App 做什麼", symbol: "sparkles") {
                    Text("擦螢幕、擦鍵盤時，手一定會碰到按鍵、觸控板和觸控螢幕，很容易誤觸。拂拭會在清潔期間暫時鎖住這些輸入，時間到自動解鎖。名稱出自「時時勤拂拭，勿使惹塵埃」。")
                }

                HelpSection(title: "快速開始", symbol: "play.circle") {
                    HelpBullet("在主視窗左側選擇「B 面清潔」、「C 面清潔」或「全鎖」。")
                    HelpBullet("按下方的「開始清潔」(或按 Return)，倒數 3 秒後開始鎖定；倒數中可以按「取消」或 Esc。")
                    HelpBullet("清潔完按住「按住 2 秒結束清潔」，或等時間到自動解鎖。")
                    HelpBullet("自動解鎖時間預設 3 分鐘，可以在「拂拭 › 設定」(⌘,) 調整為 30 秒到 10 分鐘。")
                }

                HelpSection(title: "B 面清潔 (螢幕)", symbol: "sparkles.tv") {
                    HelpBullet("所有螢幕變成全黑，OLED 不發光，最容易看出灰塵與指紋。")
                    HelpBullet("觸控螢幕的點擊會落在黑色畫面上，不會按到任何東西。")
                    HelpBullet("碰到鍵盤、觸控板或滑鼠時，螢幕四周的金光會緩慢呼吸，提示電腦還開著；不會跳出按鈕，擦螢幕時不會誤觸。")
                    HelpBullet("結束：長按 Esc 3 秒 (會出現 3、2、1 倒數)，或等時間到自動解鎖。")
                    HelpBullet("不需要任何權限。")
                }

                HelpSection(title: "C 面清潔 (鍵盤與觸控板)", symbol: "keyboard") {
                    HelpBullet("可以各自選擇要不要鎖「鍵盤」和「觸控板」。螢幕照常顯示。")
                    HelpBullet("鎖鍵盤：所有按鍵都沒反應，包含亮度、音量、播放等功能鍵。")
                    HelpBullet("鎖觸控板：只鎖 Mac 內建的觸控板 (移動、點按、手勢)；外接滑鼠、觸控螢幕照常可用。")
                    HelpBullet("畫面上方會出現面板，按住「按住 2 秒結束清潔」就能解鎖。觸控板鎖住時請用觸控螢幕或外接滑鼠按。")
                    HelpBullet("需要「輔助使用」權限 (第一次使用時「權限」頁會引導你開啟)。")
                }

                HelpSection(title: "全鎖", symbol: "lock.fill") {
                    HelpBullet("螢幕全黑，鍵盤、觸控板、觸控螢幕全部鎖住，只留外接滑鼠 (藍牙或 USB 都可以)。")
                    HelpBullet("要先接上外接滑鼠才能開始。動一下滑鼠就會叫出控制面板，再用滑鼠按住「結束清潔」2 秒。")
                    HelpBullet("拔掉外接滑鼠 (或藍牙斷線、沒電) 會立刻全部解鎖，不會把你鎖在電腦外面。")
                }

                HelpSection(title: "選單列", symbol: "menubar.rectangle") {
                    HelpBullet("螢幕右上角的拂拭圖示會顯示目前狀態：星星是待命、計時器是倒數中、鎖頭是清潔中。")
                    HelpBullet("從選單列可以直接開始清潔、結束清潔、打開主視窗或設定。")
                    HelpBullet("在設定裡打開「打開拂拭時，直接開始上次的模式」，打開 App 就會直接倒數開始。")
                }

                HelpSection(title: "鍵盤快速鍵", symbol: "command") {
                    HelpShortcut(keys: "Return", text: "開始清潔 (主視窗)")
                    HelpShortcut(keys: "Esc", text: "取消倒數 (主視窗)")
                    HelpShortcut(keys: "長按 Esc 3 秒", text: "緊急退出：結束任何清潔模式")
                    HelpShortcut(keys: "⌘ ,", text: "打開設定")
                    HelpShortcut(keys: "⌘ ?", text: "打開使用說明")
                    HelpShortcut(keys: "⌘ Q", text: "結束拂拭 (B 面清潔中無效，避免誤觸)")
                }

                HelpSection(title: "安全機制", symbol: "checkmark.shield") {
                    HelpBullet("緊急退出：任何模式下長按 Esc 3 秒，一定能結束清潔 (鍵盤鎖住時也有效)。按住時畫面會出現 3、2、1 倒數圓環，放開就取消。")
                    HelpBullet("全黑時碰到鍵盤、觸控板或滑鼠，螢幕四周會亮起金色光暈呼吸一下，提醒電腦還開著、怎麼結束；擦觸控螢幕不會觸發。")
                    HelpBullet("一定會自動解鎖：時間到就解鎖，鍵盤鎖定另有獨立的保險計時器。")
                    HelpBullet("萬一拂拭當掉或被強制結束，鎖定會跟著消失，輸入立刻恢復。拂拭不修改任何系統設定。")
                    HelpBullet("缺少權限時不會進入鎖定，而是先帶你到「權限」頁。")
                }

                HelpSection(title: "常見問題", symbol: "questionmark.circle") {
                    HelpQA(q: "電源鍵、Touch ID 也會被鎖住嗎？",
                           a: "不會。電源鍵與 Touch ID 由硬體與系統直接處理，任何 App 都擋不住。清潔時請避開右上角的電源鍵／Touch ID，以免讓 Mac 睡眠或關機。")
                    HelpQA(q: "更新拂拭後，鎖鍵盤失敗？",
                           a: "打開主視窗的「權限」頁看看「輔助使用」是否還是「已允許」。如果不是，到系統設定的清單裡先移除舊的「拂拭」，再重新加入並打開開關。")
                    HelpQA(q: "B 面清潔時，觸控板手勢還會切換桌面嗎？",
                           a: "三指滑動、Mission Control 等系統手勢由系統處理，可能仍會作用。拂拭已停用 ⌘Tab 並隱藏 Dock 與選單列。")
                    HelpQA(q: "Caps Lock 燈還會亮嗎？",
                           a: "可能會。Caps Lock 的燈號由鍵盤硬體控制，事件被擋下後燈號仍可能切換，但不會影響輸入。")
                    HelpQA(q: "鎖住時要怎麼緊急解除？",
                           a: "按住「按住 2 秒結束清潔」、等自動解鎖，或從選單列的拂拭圖示選「結束清潔」。真的不行時，按住電源鍵強制關機也一定能恢復。")
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}

struct HelpSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) { content }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpBullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpShortcut: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(keys)
                .font(.callout)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                .frame(minWidth: 130, alignment: .leading)
            Text(text)
        }
    }
}

struct HelpQA: View {
    let q: String
    let a: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(q).font(.callout.weight(.semibold))
            Text(a).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
