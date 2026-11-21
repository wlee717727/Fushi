# Translating Fushi / 翻譯拂拭

Fushi uses Apple's standard **String Catalog** (`.xcstrings`). The source language is **English**; every other language is a translation. macOS picks the user's preferred language automatically and falls back to English.

拂拭使用 Apple 標準的 **String Catalog** (`.xcstrings`)。來源語言是**英文**，其他語言都是翻譯。macOS 會依使用者的偏好語言自動切換，沒有支援的語言會顯示英文。

## Current languages / 目前支援

English (en), 繁體中文 (zh-Hant), 简体中文 (zh-Hans), 日本語 (ja), 한국어 (ko), Español (es)

## Files / 檔案

| File / 檔案 | Contains / 內容 |
|---|---|
| `Sources/Fushi/Resources/Localizable.xcstrings` | Every string in the app: main window, panels, menu bar, Help / App 裡所有文字：主視窗、面板、選單列、說明 |
| `Sources/Fushi/Resources/InfoPlist.xcstrings` | App name in Finder and the Dock, About text / Finder 與 Dock 顯示的 App 名稱、關於視窗的文字 |
| `project.yml` → `CFBundleLocalizations` | Languages the app declares / App 宣告支援的語言清單 |

## Add a new language / 新增一種語言

1. Generate the Xcode project with `xcodegen generate` and open `Fushi.xcodeproj`.
   用 `xcodegen generate` 產生專案，再用 Xcode 打開 `Fushi.xcodeproj`。
2. Open `Localizable.xcstrings`, click **+** under the language list and add your language. Do the same for `InfoPlist.xcstrings`.
   打開 `Localizable.xcstrings`，按語言清單下方的 **+** 加入語言；`InfoPlist.xcstrings` 也一樣。
3. Translate every row. Keep placeholders exactly: `%@`, `%lld`, `%1$@`. Keep `Esc`, `Return` and `⌘`.
   逐句翻譯。變數 `%@`、`%lld`、`%1$@` 必須原樣保留；`Esc`、`Return`、`⌘` 不翻。
4. Add the language code to `CFBundleLocalizations` in `project.yml` (for example `fr`). Without this, macOS will not show your language.
   把語言代碼加到 `project.yml` 的 `CFBundleLocalizations` (例如 `fr`)。沒加的話 macOS 不會顯示這個語言。
5. Run `scripts/build.sh`. It prints how many strings are missing per language (`… 還缺 0 句翻譯` = complete) and warns about untranslatable English.
   執行 `scripts/build.sh`，會列出每種語言還缺幾句 (`還缺 0 句翻譯` 代表完成)，也會警告沒被翻譯的英文。
6. Check the layout in your language. Easiest: launch the development build with a language argument, no settings changed:
   用你的語言檢查排版。最簡單的方法是用啟動參數打開開發版，不必改任何設定：
   ```bash
   build/dd/Build/Products/Debug/Fushi.app/Contents/MacOS/Fushi -AppleLanguages "(fr)" -AppleLocale fr_FR
   ```
   Or System Settings › General › Language & Region › Applications. Look at all four pages, Permissions, the lock panels and Help, in a narrow and a wide window.
   也可以到「系統設定 › 一般 › 語言與地區 › App」設定。四個模式頁、權限頁、鎖定面板、說明都要看，窄視窗與寬視窗各看一次。

## Rules for every language / 共通原則

- **Keep names identical everywhere** (sidebar, page titles, menu bar, Help): the four modes and the buttons. When text refers to the end button, say "the red button" — never quote a different button name.
  **同一個名稱在各處必須完全相同**：四個模式名稱、按鈕名稱 (側邊欄、頁面標題、選單列、說明)。提到結束按鈕時一律說「紅色按鈕」，不要引用和按鈕上不同的名稱。
- **Short and plain.** Card titles say the action; no explanatory sentences. Sidebar names must fit without truncation — prefer the shorter wording.
  **簡短直白**。卡片標題直接說動作，不寫解說句。側邊欄名稱不可以被截斷，請選短的說法。
- **Use your language's official macOS terms** (the Accessibility setting, System Settings, menu bar, trackpad…).
  **用該語言 macOS 的官方用詞** (輔助使用、系統設定、選單列、觸控板……)。
- Languages much longer than English (German, French…) need extra layout checks.
  比英文長很多的語言 (德文、法文……) 要特別檢查排版。

## Per-language conventions / 各語言的固定規則

| Language | Conventions / 規則 |
|---|---|
| zh-Hant | 台灣 macOS 用語 (螢幕、滑鼠、觸控板、輔助使用、結束)；引號「」；App 名稱「拂拭」 |
| zh-Hans | 中国大陆 macOS 用语 (屏幕、鼠标、触控板、辅助功能、退出、默认)；引号“”；App 名称「拂拭」 |
| ja | です／ます調；「アプリ」；アクセシビリティ、システム設定、メニューバー；App 名稱維持 Fushi |
| ko | 합니다／하세요체；손쉬운 사용、시스템 설정、메뉴 막대、외장 마우스；App 名稱維持 Fushi |
| es | Spain Spanish terms, informal **tú** (ratón, pulsar, Ajustes del Sistema). A Latin American version (`es-419`: mouse, presionar, Configuración del Sistema) would be a separate language. / 採用西班牙本土用詞與 tú；拉丁美洲版 (`es-419`) 要另外新增 |

## For developers / 給開發者

- In SwiftUI, pass text as `LocalizedStringKey` (literals in `Text("…")`, view parameters typed `LocalizedStringKey`). A `String` passed to `Text` is **not** translated.
  SwiftUI 的文字要用 `LocalizedStringKey` 傳遞；把 `String` 傳給 `Text` **不會**被翻譯。
- Text built in code uses `String(localized: "…")`; pure numbers use `Text(verbatim:)`.
  程式算出來的文字用 `String(localized: "…")`；純數字用 `Text(verbatim:)`。
- `scripts/sync-strings.py` (run by `build.sh`) adds new strings to the catalog and warns about English sentences that are not translatable.
  `scripts/sync-strings.py` (由 `build.sh` 執行) 會把新文字加進翻譯表，並警告沒被翻譯的英文句子。

## Proofreading with an AI / 請 AI 校稿

1. `python3 scripts/i18n/export_review.py` → one Markdown file per language in `translation-review/` (plus `Fushi-translation-review.zip`). Each file starts with instructions for the AI.
   產生每種語言一份校稿檔 (檔案開頭已寫好給 AI 的說明)，另外打包成 ZIP。
2. Give one file to the AI. It fills in "建議修改" (suggestion) and "理由" (reason) only for rows that need a change.
   一次給 AI 一份，它只在需要修改的行填上建議和理由。
3. Save the reply as a `.md` file, then check it: `python3 scripts/i18n/import_review.py ja reply.md --dry-run`
   把回覆存成 `.md`，先用 `--dry-run` 檢查。
4. Apply it: `python3 scripts/i18n/import_review.py ja reply.md`, then run `scripts/build.sh`.
   確認沒問題再正式匯入，然後重新建置。

The import refuses the whole file if any row has a wrong number, a changed English source, or broken `%@` / `%lld` placeholders.
只要有任何一行編號錯誤、英文原文被改、或變數被改壞，整份都不會寫入。
