# 拂拭 (Fushi) 規格整理 — v0.1.0

> 名稱出自「時時勤拂拭，勿使惹塵埃」。用途：清潔 Mac 時暫時鎖住輸入，取代 KeyboardCleanTool。

## 一、環境與限制

| 項目 | 內容 |
|---|---|
| 目標機器 | MacBook Pro 16 吋 M5 Max (2026 觸控螢幕 PROLED XDR 機型) |
| 最低系統 | macOS 27.0 (本機主版本) |
| 架構 | 只做 arm64 (觸控機型都是 Apple Silicon) |
| App Sandbox | 關閉 (事件攔截需要)，不上架 App Store |
| 第三方套件 | 不使用，只用 SwiftUI、AppKit、CoreGraphics、IOKit |
| Bundle ID | `com.wlee717727.Fushi`、`com.wlee717727.FushiProbe` |
| 顯示名稱 | 拂拭、拂拭偵測工具 |
| 簽章 | 本機沒有 Apple Development 憑證 → ad-hoc 簽章 |

## 二、技術路線

- 從 macOS 26.4 起，DriverKit 虛擬 HID 攔截不到內建鍵盤，第三方驅動也綁不上內建觸控板，**不走 DriverKit／Karabiner，也不獨占 (seize) 內建裝置**。
- 採用 Apple 官方建議的 `CGEventTapCreate`：
  - 主動攔截 (擋下事件) 需要「輔助使用」權限；
  - 只監聽需要「輸入監控」權限。
- 亮度、音量、媒體鍵是「系統定義事件」(NX_SYSDEFINED，類型 14)，必須一起擋 (子類型 7 是滑鼠按鍵狀態，放行)。
- 擋不住：電源鍵、Touch ID。
- 最大未知數：內建觸控板、觸控螢幕、外接滑鼠在事件層可能長得一樣 → 第 0 階段偵測。

## 三、第 0 階段：偵測工具 FushiProbe

| 功能 | 做法 |
|---|---|
| 裝置清單 | `IOHIDManager` 列出所有 HID 裝置 (Product、Manufacturer、VID、PID、Transport、PrimaryUsagePage／Usage、DeviceUsagePairs、Built-In、LocationID、IORegistry entry ID、類別名稱)，插拔即時更新並記錄 |
| HID 層 | 輸入回呼「只聽不擋」，記錄裝置、時間、UsagePage／Usage；每裝置每秒最多 30 筆 |
| 事件層 | `listenOnly` 的 CGEventTap，同時在 HID 與 Session 兩個位置；記錄類型、時間、位置、已知欄位、欄位 0～255 原始掃描 (只記非零)、NSEvent 的 type／subtype／pressure／stage 等；高頻事件每類型每秒最多 30 筆 |
| 視窗觸控 | 觸控測試區開啟 `allowedTouchTypes = [.direct, .indirect]`，記錄 NSTouch 類型、phase、數量與事件 subtype |
| 測試標籤 | 鍵盤／內建觸控板／觸控螢幕／外接滑鼠／外接觸控板／閒置 (⌘1～⌘6) |
| 隱私 | 鍵盤事件不記 keycode 與字元；HID 鍵盤頁 usage 遮掉 |
| 輸出 | `probe-logs/probe-YYYYMMDD-HHMMSS.jsonl`、`devices-YYYYMMDD-HHMMSS.json` |
| 分析 | `scripts/analyze-probe.py` (Python 3 標準函式庫) |

## 四、第 1 階段：拂拭 App 本體

### 模式 (`Sources/Fushi/Core/CleaningMode.swift`)

```swift
enum DeckTarget { case keyboard, trackpad, keyboardAndTrackpad }
enum CleaningMode {
    case screenB            // B 面：螢幕
    case deckC(DeckTarget)  // C 面：鍵盤／觸控板
    case all                // 全鎖 (第 2 階段)
}
```

原始需求寫的是 `deckC(keyboard: Bool, trackpad: Bool)`；改成 `DeckTarget` 三個 case，
讓「兩個都不鎖」這個不合法狀態根本寫不出來。

| 模式 | 第 1 階段 |
|---|---|
| B 面清潔 | ✅ 完整實作 |
| C 面：只鎖鍵盤 | ✅ 完整實作 |
| C 面：只鎖觸控板／鍵盤＋觸控板 | UI 與狀態完成，開始按鈕標註「待偵測結果確認」 |
| 全鎖 | 灰色，標註「待偵測結果確認後開放」 |

### 主畫面

- 三張模式卡片 (寬視窗三欄、窄視窗一欄，跟著視窗即時重排)。
- C 面三態勾選框：父項目「C 面清潔」由子項目「鍵盤」「觸控板」推算 (SwiftUI `Toggle(sources:)`)，不另外儲存。兩個都不勾 → 【開始清潔】變灰。
- 自動解鎖時間：預設 180 秒，30～600 秒，每格 10 秒。
- 【開始清潔】→ 3 秒倒數 (可取消) → 鎖定。
- 選單列圖示顯示狀態 (✦ 待命／計時器 倒數／鎖頭 清潔中)，可開始／結束。
- 「開啟拂拭時，立即開始上次的模式」。

### B 面清潔

- 蓋住所有螢幕、層級 `.screenSaver` (高於選單列與 Dock) 的全黑無邊框視窗，設為焦點視窗。
- 同時隱藏 Dock 與選單列、停用 ⌘Tab (只對拂拭有效，結束時系統自動還原)。
- 全黑 → 按任意鍵 → 控制面板 (「清潔中・觸控已鎖定」、剩餘時間、【繼續清潔】、【結束清潔】按住 2 秒)；長按 Esc 2 秒也能結束；8 秒沒操作回到全黑。
- 第 1 階段只用鍵盤喚醒。

### C 面：只鎖鍵盤

- 主動式 CGEventTap (`.cgSessionEventTap`、`.headInsertEventTap`、`.defaultTap`)，擋 keyDown、keyUp、flagsChanged、類型 14。
- 浮動面板：「鍵盤已鎖定」、剩餘時間、【結束清潔】(按住 2 秒，觸控板／滑鼠／觸控螢幕都可以按)。

### 安全機制

1. 自動解鎖計時器：主計時器 (0.2 秒) ＋ 背景佇列保險計時器 ＋ 鍵盤攔截自己的 watchdog ＋ 攔截回呼內檢查截止時間。
2. `tapDisabledByTimeout`／`tapDisabledByUserInput` 立刻重新啟用；攔截跑在專用執行緒，回呼只做判斷。
3. 不修改任何系統設定；App 當掉時攔截與視窗隨程序消失。
4. Debug 版自動解鎖上限 30 秒。
5. 缺少權限時直接帶到權限引導畫面，不進入鎖定。

### 權限引導

首次啟動顯示：說明「輔助使用」「輸入監控」用途、各一個按鈕開啟系統設定對應頁面、每秒即時更新授權狀態。

## 五、第 2 階段

見 `docs/PHASE2-PLAN.md`。
