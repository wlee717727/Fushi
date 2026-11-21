# 拂拭 (Fushi)

> 時時勤拂拭，勿使惹塵埃。

清潔 Mac 時暫時鎖住輸入的 macOS App：擦螢幕時讓觸控螢幕沒有反應，擦鍵盤時讓按鍵不會打進任何地方，時間到自動解鎖。為 2026 年 MacBook Pro 16 吋 M5 Max 觸控螢幕機型設計。

## 功能

| 模式 | 做什麼 | 怎麼結束 |
|---|---|---|
| B 面清潔 | 螢幕全黑，觸控螢幕點了沒反應；碰鍵盤或觸控板時四周金光呼吸提示 | 長按 Esc 3 秒 (有倒數)，或時間到 |
| C 面清潔 | 鍵盤、觸控板各自選擇要不要鎖 | 用觸控螢幕／滑鼠按住「結束清潔」2 秒 |
| 全鎖 | 螢幕全黑＋全部輸入鎖住，只留外接滑鼠 | 動滑鼠叫出面板；**拔掉外接滑鼠立刻解鎖** |

所有模式：**長按 Esc 3 秒一定能退出**、時間到自動解鎖、App 當掉時鎖定自動消失。

- 支援 macOS 14 以上，Apple Silicon 與 Intel 通用。專為觸控螢幕 MacBook Pro 設計，沒有觸控螢幕的 Mac 也能用。
- 鎖觸控板的原理：每個指標事件都查「是哪個實體裝置送的」，只擋內建觸控板 (已用偵測工具在實機驗證)。

## 專案內容

```
Fushi/
├── Fushi.app            第 1 階段 App (Release 版)
├── FushiProbe.app       第 0 階段偵測工具 (Release 版)
├── Design/              圖示原稿 (AppIcon-1024.png、AppIcon.svg) 與產生的 .icns
├── docs/
│   ├── SPEC.md          規格整理
│   ├── PROBE-GUIDE.md   偵測測試步驟
│   └── PHASE2-PLAN.md   第 2 階段計畫
├── scripts/
│   ├── build.sh                    一鍵建置 (產生專案 → 測試 → Release 編譯 → 複製到根目錄)
│   ├── make-appicon.sh             產生 App 圖示
│   ├── render-placeholder-icon.swift  沒有正式圖時產生佔位圖示
│   ├── analyze-probe.py            分析偵測紀錄
│   └── make-sample-probe.py        產生模擬紀錄 (只用來測試分析腳本)
├── Sources/
│   ├── Fushi/           拂拭原始碼 (Core = 純邏輯、Lock = 鎖定、UI = 畫面)
│   └── FushiProbe/      偵測工具原始碼
├── Tests/FushiTests/    狀態機與計時規則的單元測試
├── project.yml          XcodeGen 設定 (產生 Fushi.xcodeproj)
└── probe-logs/          偵測紀錄 (不進版控)
```

## 使用方式

1. 打開 `Fushi.app`。第一次會出現權限引導；B 面清潔不需要權限，C 面鎖鍵盤需要「輔助使用」。
2. 選模式 → 調自動解鎖時間 → 按【開始清潔】→ 倒數 3 秒後鎖定。
3. 結束：任何模式長按 Esc 3 秒 (畫面會出現 3、2、1 倒數)、C 面與全鎖可用觸控螢幕或外接滑鼠按住【結束清潔】2 秒、或等時間到。
4. App 內「說明」選單 (⌘?) 有完整使用說明。

**電源鍵與 Touch ID 無法鎖定**，清潔時請避開。

## 建置

需要 Xcode 27 與 XcodeGen (`/opt/homebrew/bin/xcodegen`)。

```bash
scripts/build.sh
```

完成後 `Fushi.app`、`FushiProbe.app` 會放在專案根目錄 (舊版移到垃圾桶)。

只想用 Xcode 開啟：

```bash
xcodegen generate && open Fushi.xcodeproj
```

### 開發者注意事項

- **簽章與權限**：目前用 ad-hoc 簽章。macOS 的「輔助使用」權限綁定在 App 的簽章身分上。Release 版用 `signing/Fushi.req` 把身分固定成 Bundle ID，重新建置後權限不會失效；Debug 版 (`拂拭 (開發版)`) 沒有固定，每次重新建置都要到系統設定移除舊項目再重新勾選。
- **Debug 版**：自動解鎖上限強制 30 秒，方便開發測試時不會被鎖太久。
- **圖示**：把 1024×1024 的正式圖放到 `Design/AppIcon-1024.png` (偵測工具用 `Design/ProbeIcon-1024.png`)，執行 `scripts/make-appicon.sh` 再重新建置。

## 授權與參考

只參考以下專案的思路，沒有複製程式碼：Mac Pause、KeepClean (限制商業使用授權)、keylock (MIT)。
