#!/usr/bin/env python3
"""
把編譯器抽出的介面字串，同步到 String Catalog (Localizable.xcstrings，zh-Hant)。

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
LANG = "zh-Hant"
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
        entry = {"localizations": {LANG: {"stringUnit": {"state": "translated", "value": key}}}}
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
        catalog["sourceLanguage"] = LANG
        catalog["version"] = catalog.get("version", "1.0")
        with open(catalog_path, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
    print("%s：字串 %d 個 (新增 %d、標記為不再使用 %d)" % (target, len(keys), added, stale))

sys.exit(10 if changed_any else 0)
