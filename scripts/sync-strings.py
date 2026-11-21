#!/usr/bin/env python3
"""
把編譯器抽出的介面字串，同步到 String Catalog (Localizable.xcstrings)。

來源語言：拂拭是英文 (程式裡寫英文，其他語言是翻譯)；偵測工具維持繁體中文。
新加入的字串不會自動填翻譯，結尾會列出每種語言還缺幾句。

為什麼需要？在 Xcode 裡按建置時，Xcode 會自動把新字串寫進 .xcstrings；
但用命令列 xcodebuild 建置不會寫回去。這支腳本讀取建置時產生的 *.stringsdata，
補上缺少的字串，讓兩種建置方式結果一樣。

用法：python3 scripts/sync-strings.py [Release|Debug]
有變動時結束代碼為 10 (build.sh 會據此再編譯一次)，沒變動為 0。
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = sys.argv[1] if len(sys.argv) > 1 else "Release"
SOURCE_LANG = {"Fushi": "en", "FushiProbe": "zh-Hant"}
changed_any = False

for target in ("Fushi", "FushiProbe"):
    pattern = os.path.join(ROOT, "build/DerivedData/Build/Intermediates.noindex/Fushi.build",
                           CONFIG, target + ".build", "Objects-normal", "*", "*.stringsdata")
    keys = {}
    for path in glob.glob(pattern):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.setdefault(entry["key"], entry.get("comment", ""))

    catalog_path = os.path.join(ROOT, "Sources", target, "Resources", "Localizable.xcstrings")
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)
    strings = catalog.setdefault("strings", {})

    added = 0
    for key, comment in keys.items():
        if key in strings:
            if strings[key].get("extractionState") == "stale":
                strings[key].pop("extractionState", None)
            continue
        if SOURCE_LANG[target] == "en":
            entry = {}   # 英文來源：key 就是英文原文，翻譯之後再補
        else:
            entry = {"localizations": {SOURCE_LANG[target]: {"stringUnit": {"state": "translated", "value": key}}}}
        if comment:
            entry["comment"] = comment
        strings[key] = entry
        added += 1

    stale = 0
    for key, entry in strings.items():
        if key not in keys and entry.get("extractionState") != "stale" and keys:
            entry["extractionState"] = "stale"
            stale += 1

    if added or stale:
        changed_any = True
        catalog["sourceLanguage"] = SOURCE_LANG[target]
        catalog["version"] = catalog.get("version", "1.0")
        with open(catalog_path, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
    print("%s：字串 %d 個 (新增 %d、標記為不再使用 %d)" % (target, len(keys), added, stale))
    if SOURCE_LANG[target] == "en":
        langs = sorted({l for e in strings.values() for l in e.get("localizations", {})})
        for lang in langs:
            missing = [k for k, e in strings.items()
                       if e.get("extractionState") != "stale" and lang not in e.get("localizations", {})
                       and e.get("shouldTranslate", True)]
            print("  %s 還缺 %d 句翻譯" % (lang, len(missing)))

# 漏翻檢查：一般字串型別的文字不會被編譯器抽出 (例如回傳 String 的屬性)，在這裡另外掃一次。
# 找出 Sources/Fushi 裡「含空格的英文句子」，不在字串目錄、也沒用 String(localized:) 包起來的就警告。
import re
fushi_catalog = json.load(open(os.path.join(ROOT, "Sources/Fushi/Resources/Localizable.xcstrings"), encoding="utf-8"))
known = set(fushi_catalog["strings"].keys())
SKIP = re.compile(r"Diagnostics\.log|Logger|print\(|systemImage|forKey|\.name =|#if DEBUG|named:|localizedCaseInsensitiveContains")
literal = re.compile(r'"([A-Z][^"\\]*\s[^"\\]*)"')
warnings = []
for dp, _, fs in os.walk(os.path.join(ROOT, "Sources/Fushi")):
    for f in fs:
        if not f.endswith(".swift") or f in ("DirectionMockups.swift", "PanelSnapshots.swift", "Diagnostics.swift"):
            continue
        for n, line in enumerate(open(os.path.join(dp, f), encoding="utf-8"), 1):
            if line.strip().startswith("//") or SKIP.search(line):
                continue
            for m in literal.finditer(line):
                text = m.group(1)
                if "\\(" in text or text in known:
                    continue
                warnings.append("%s:%d  %s" % (f, n, text))
if warnings:
    print("⚠️ 可能沒有翻譯的英文 (請確認是否應改成 LocalizedStringKey 或 String(localized:))：")
    for w in warnings:
        print("  " + w)

sys.exit(10 if changed_any else 0)
