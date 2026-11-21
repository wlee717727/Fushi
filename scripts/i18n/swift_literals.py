#!/usr/bin/env python3
"""
找出 Swift 原始碼裡「畫面上會顯示」的中文字串常值 (不含註解、診斷紀錄、執行緒名稱、開發專用檔案)。
供來源語言改成英文時使用：extract 產生清單、apply 依對照表把原始碼換成英文。

用法：
  python3 scripts/i18n/swift_literals.py extract <輸出.json>
  python3 scripts/i18n/swift_literals.py apply <對照表.json>
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_DIRS = ["Sources/Fushi", "Sources/FushiProbe"]
SKIP_FILES = {"DirectionMockups.swift", "PanelSnapshots.swift", "Diagnostics.swift"}
SKIP_LINE = re.compile(r"Diagnostics\.log\(|\.name = |Logger\(|print\(")
CJK = re.compile(r"[㐀-鿿　-〿＀-￯]")


def literals(text):
    """回傳 (開始, 結束) 位置：所有最外層字串常值 (含引號)。"""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            i = text.find("\n", i); i = n if i < 0 else i; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if c == '"':
            end = parse_string(text, i)
            out.append((i, end)); i = end; continue
        i += 1
    return out


def parse_string(text, i):
    """從 text[i] 的引號開始，回傳字串結束後的位置 (支援跳脫、\\(...) 內插與內插裡的巢狀字串)。"""
    if text.startswith('"""', i):
        j = text.find('"""', i + 3)
        return j + 3
    i += 1
    while i < len(text):
        c = text[i]
        if c == "\\":
            if text[i + 1] == "(":
                i += 2; depth = 1
                while depth:
                    ch = text[i]
                    if ch == '"':
                        i = parse_string(text, i); continue
                    if ch == "(": depth += 1
                    elif ch == ")": depth -= 1
                    i += 1
                continue
            i += 2; continue
        if c == '"':
            return i + 1
        i += 1
    raise ValueError("字串沒有結束")


def files():
    for d in SRC_DIRS:
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            for f in fs:
                if f.endswith(".swift") and f not in SKIP_FILES:
                    yield os.path.join(dp, f)


def ui_literals(path):
    text = open(path, encoding="utf-8").read()
    for a, b in literals(text):
        lit = text[a:b]
        if not CJK.search(lit):
            continue
        line_start = text.rfind("\n", 0, a) + 1
        line_end = text.find("\n", a)
        if SKIP_LINE.search(text[line_start:line_end]):
            continue
        yield a, b, lit


def extract(out):
    found = {}
    for p in files():
        for _, _, lit in ui_literals(p):
            found.setdefault(lit, os.path.relpath(p, ROOT))
    json.dump({k: {"file": v, "en": ""} for k, v in found.items()}, open(out, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"找到 {len(found)} 個中文字串常值 → {out}")


def apply(mapping_path):
    mapping = json.load(open(mapping_path, encoding="utf-8"))
    missing, changed = set(), 0
    for p in files():
        text = open(p, encoding="utf-8").read()
        parts, last = [], 0
        for a, b, lit in ui_literals(p):
            en = mapping.get(lit, {}).get("en")
            if not en:
                missing.add(lit); continue
            parts.append(text[last:a]); parts.append(en); last = b; changed += 1
        if parts:
            parts.append(text[last:])
            open(p, "w", encoding="utf-8").write("".join(parts))
    print(f"已替換 {changed} 處")
    if missing:
        print("沒有對照的字串：")
        for m in sorted(missing): print("  ", m)
        sys.exit(1)


if __name__ == "__main__":
    {"extract": extract, "apply": apply}[sys.argv[1]](sys.argv[2])
