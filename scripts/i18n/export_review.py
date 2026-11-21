#!/usr/bin/env python3
"""
匯出翻譯校稿檔：每種語言一份 Markdown，丟給 ChatGPT 檢查翻譯品質。

用法：python3 scripts/i18n/export_review.py [輸出資料夾]
預設輸出到專案根目錄的 translation-review/，並打包成 Fushi-translation-review.zip。

ChatGPT 回覆的表格存回同一個資料夾後，用 import_review.py 匯入。
"""
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "Sources/Fushi/Resources/Localizable.xcstrings")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "translation-review")

LANGS = {
    "zh-Hant": ("繁體中文 (台灣)", "台灣 macOS 用語 (螢幕、滑鼠、觸控板、輔助使用、結束、預設)；引號用「」；App 名稱是「拂拭」。"),
    "zh-Hans": ("简体中文 (中国大陆)", "中国大陆 macOS 用语 (屏幕、鼠标、触控板、辅助功能、退出、默认)；引号用“”；App 名称是「拂拭」。不要出现台湾用语。"),
    "ja": ("日本語", "です／ます調で統一。macOS 日本語版の正式な用語 (アクセシビリティ、システム設定、メニューバー、トラックパッド、アプリ) を使う。App 名は Fushi のまま。"),
    "ko": ("한국어", "합니다／하세요체로 통일. macOS 한국어판의 공식 용어 (손쉬운 사용, 시스템 설정, 메뉴 막대, 트랙패드, 외장 마우스) 사용. 앱 이름은 Fushi 그대로."),
    "es": ("Español", "Español de España con tú (ratón, pulsar, Ajustes del Sistema), terminología oficial de macOS en español. El nombre de la app se queda como Fushi."),
}

SKIP = {"Esc", "Return", "•", "⌘ ,", "⌘ ?", "⌘ Q"}

INTRO = """# 拂拭 (Fushi) 翻譯校稿：{name}

## 給 ChatGPT 的說明 (請照這段做)

你是專業的 macOS App 在地化校稿人員。下面是 macOS App「Fushi」的介面文字，請以「{name}」母語者的角度檢查翻譯。

**這個 App 做什麼**：清潔 Mac 時暫時鎖住輸入。四個模式：螢幕清潔 (螢幕全黑、觸控螢幕點了沒反應)、鍵盤清潔 (所有按鍵失效，可選擇同時鎖住觸控板)、觸控板清潔 (只鎖內建觸控板)、全部鎖定 (螢幕全黑、全部輸入鎖住，只留外接滑鼠)。任何模式長按 Esc 3 秒一定能結束，時間到會自動解鎖。鎖定時畫面上有一顆紅色的「按住 2 秒結束清潔」按鈕。

**用詞規則**：{rules}

**共通規則**：
- 同一個名稱在各處必須完全相同 (四個模式名稱、按鈕名稱)。
- 簡短直白，卡片標題直接說動作；側邊欄的模式名稱要短，不可以太長。
- `%@`、`%lld` 是程式會填入的變數 (時間、名稱、數字)，**絕對不可以刪除、增加或改動**，只能移動位置。
- 英文原文是來源，翻譯要忠於原意，但要用當地自然的說法，不要逐字直譯。

**請你做的事**：
1. 逐行檢查「目前翻譯」：是否自然、是否符合當地 macOS 的官方用詞、語氣是否一致、有沒有錯字。
2. **只在需要修改的那一行**，把建議寫在「建議修改」欄，並在「理由」欄用繁體中文簡短說明。不需要修改的行，這兩欄留空。
3. 回覆時**保留整張表格的格式與編號**，不要刪行、不要改「#」和「英文原文」欄，直接輸出完整表格 (可以只輸出有修改的行)。
4. 表格最後用繁體中文寫三行以內的整體評語。

## 對照表

| # | 英文原文 | 目前翻譯 | 建議修改 | 理由 |
|---|---|---|---|---|
"""


def cell(text):
    """表格儲存格：跳脫直線、把換行寫成 \\n，避免破壞表格。"""
    return text.replace("|", "\\|").replace("\n", "\\n")


def main():
    data = json.load(open(CATALOG, encoding="utf-8"))
    keys = sorted(k for k, e in data["strings"].items()
                  if e.get("extractionState") != "stale" and k not in SKIP and e.get("shouldTranslate", True))
    os.makedirs(OUT, exist_ok=True)   # 同名檔案直接覆蓋，不刪除任何東西
    index = {str(i + 1): k for i, k in enumerate(keys)}
    json.dump(index, open(os.path.join(OUT, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for code, (name, rules) in LANGS.items():
        lines = [INTRO.format(name=name, rules=rules)]
        for i, k in enumerate(keys, 1):
            v = data["strings"][k].get("localizations", {}).get(code, {}).get("stringUnit", {}).get("value", "")
            lines.append("| %d | %s | %s |  |  |" % (i, cell(k), cell(v)))
        path = os.path.join(OUT, "Fushi-review-%s.md" % code)
        open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
        print("已匯出 %s：%d 句" % (os.path.basename(path), len(keys)))
    zip_path = os.path.join(ROOT, "Fushi-translation-review")
    shutil.make_archive(zip_path, "zip", OUT)
    print("已打包：%s.zip" % zip_path)


if __name__ == "__main__":
    main()
