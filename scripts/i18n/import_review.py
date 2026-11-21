#!/usr/bin/env python3
"""
匯入 ChatGPT 校稿後的翻譯：讀回 Markdown 表格裡「建議修改」欄有內容的行，寫進翻譯表。

用法：
  python3 scripts/i18n/import_review.py <語言代碼> <校稿檔.md> [--dry-run]
  例如：python3 scripts/i18n/import_review.py ja translation-review/Fushi-review-ja.md --dry-run

安全檢查 (任何一行不通過，整份都不寫入)：
- 編號必須存在，而且「英文原文」要和匯出時一致 (避免表格被改亂、對錯行)
- %@、%lld 等變數的種類與數量必須和英文原文一樣
- 建議內容不可以是空白
--dry-run：只檢查、列出會改哪些行，不寫入。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "Sources/Fushi/Resources/Localizable.xcstrings")
INDEX = os.path.join(ROOT, "translation-review", "index.json")
SPEC = re.compile(r"%(\d+\$)?(lld|ld|d|@|f)")
LANGS = {"zh-Hant", "zh-Hans", "ja", "ko", "es", "en"}


def uncell(text):
    return text.strip().replace("\\n", "\n").replace("\\|", "|")


def split_row(line):
    # 以沒有被跳脫的「|」切欄
    parts = re.split(r"(?<!\\)\|", line.strip())
    return [p for p in parts[1:-1]]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 2 or args[0] not in LANGS:
        print(__doc__)
        sys.exit(2)
    lang, review = args
    index = json.load(open(INDEX, encoding="utf-8"))
    data = json.load(open(CATALOG, encoding="utf-8"))
    changes, errors = [], []
    for n, line in enumerate(open(review, encoding="utf-8"), 1):
        if not line.lstrip().startswith("|"):
            continue
        cols = split_row(line)
        if len(cols) < 4 or not cols[0].strip().isdigit():
            continue
        num, english, current, suggestion = cols[0].strip(), uncell(cols[1]), uncell(cols[2]), uncell(cols[3])
        if not suggestion:
            continue
        key = index.get(num)
        if key is None:
            errors.append("第 %d 行：編號 %s 不存在" % (n, num)); continue
        if english != key:
            errors.append("第 %d 行：編號 %s 的英文原文和匯出時不同 (表格可能被改亂)" % (n, num)); continue
        want = sorted(m.group(2) for m in SPEC.finditer(key))
        got = sorted(m.group(2) for m in SPEC.finditer(suggestion))
        if want != got:
            errors.append("第 %d 行：編號 %s 的變數不一致 (原文 %s，建議 %s)" % (n, num, want, got)); continue
        changes.append((num, key, current, suggestion))
    if errors:
        print("❌ 有問題，整份都沒有寫入：")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    for num, key, current, suggestion in changes:
        print("#%s  %s\n    目前：%s\n    改成：%s" % (num, key, current, suggestion))
    if dry:
        print("（只檢查，未寫入）共 %d 句會修改" % len(changes))
        return
    for _, key, _, suggestion in changes:
        data["strings"][key].setdefault("localizations", {})[lang] = {
            "stringUnit": {"state": "translated", "value": suggestion}}
    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print("✅ 已寫入 %s：%d 句。接著執行 scripts/build.sh 重新建置。" % (lang, len(changes)))


if __name__ == "__main__":
    main()
