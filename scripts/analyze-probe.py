#!/usr/bin/env python3
"""
拂拭 第 0 階段偵測紀錄分析 (只用 Python 3 標準函式庫，不需安裝任何套件)。

用法：
    python3 scripts/analyze-probe.py                      # 自動分析 probe-logs 裡最新的一份
    python3 scripts/analyze-probe.py probe-logs/probe-20261122-101500.jsonl
    python3 scripts/analyze-probe.py --all                # 合併 probe-logs 裡所有紀錄
    python3 scripts/analyze-probe.py ... --out report.md  # 另存成 Markdown 檔

做法：
1. 依「測試標籤」分組，統計各標籤出現的事件類型與數量。
2. 對每一組要比較的標籤 (例如觸控螢幕 vs 內建觸控板)，在「同一種事件類型」裡
   逐一檢查每個欄位 (含原始欄位編號 raw_int[N]、raw_double[N])，
   找出兩邊數值「完全不重疊」或「幾乎不重疊」的欄位。
3. 對照 HID 層：每個標籤期間，是哪個實體裝置在送資料。
4. 輸出結論表：能不能區分、靠哪個欄位、可信度。
"""
import argparse
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_DIR = os.path.join(ROOT, "probe-logs")

LABEL_TITLES = {
    "keyboard": "鍵盤",
    "builtin_trackpad": "內建觸控板",
    "touchscreen": "觸控螢幕",
    "external_mouse": "外接滑鼠",
    "external_trackpad": "外接觸控板",
    "idle": "閒置",
    "unlabeled": "未標記",
}

# 要回答的比較 (依重要性排序)
PAIRS = [
    ("touchscreen", "builtin_trackpad"),
    ("builtin_trackpad", "external_mouse"),
    ("touchscreen", "external_mouse"),
    ("builtin_trackpad", "external_trackpad"),
    ("touchscreen", "external_trackpad"),
]

KEY_TYPES = {10, 11, 12}
# 指標類事件：滑鼠按鍵、移動、拖曳、捲動、手勢、壓力、數位板
POINTER_TYPES = {1, 2, 3, 4, 5, 6, 7, 22, 23, 24, 25, 26, 27, 18, 19, 20, 29, 30, 31, 32, 33, 34, 37}

# 這些欄位本來就每筆都不一樣 (時間、座標、位移、計數)，不能拿來分辨裝置
NOISY_FIELDS = {
    "event_ts", "x", "y", "uptime_ns", "t_ms", "since_label_ms", "dropped_before",
    "fields.mouseEventNumber", "fields.mouseEventDeltaX", "fields.mouseEventDeltaY",
    "fields.mouseEventDeltaX_double", "fields.mouseEventDeltaY_double",
    "fields.scrollWheelEventDeltaAxis1", "fields.scrollWheelEventDeltaAxis2",
    "fields.scrollWheelEventPointDeltaAxis1", "fields.scrollWheelEventPointDeltaAxis2",
    "fields.eventTargetUnixProcessID", "fields.mouseEventClickState",
    "nsevent.clickCount", "flags",
}
# 欄位在某個標籤裡出現超過這麼多種不同的值，就視為「連續變化的量」，不當作分辨依據
MAX_DISTINCT = 12
# 切換標籤後這段時間內的事件不採用 (按標籤按鈕本身留下的點擊)
LABEL_GUARD_MS = 800
MIN_SAMPLES = 20


def load(paths):
    records = []
    bad = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    bad += 1
    return records, bad


def flatten(rec):
    """把一筆事件層紀錄攤平成 {欄位名稱: 值}。缺少的原始欄位代表 0 (紀錄時只存非零值)。"""
    out = {}
    for k, v in (rec.get("fields") or {}).items():
        out["fields." + k] = v
    for k, v in (rec.get("raw_int") or {}).items():
        out["raw_int[%s]" % k] = v
    for k, v in (rec.get("raw_double") or {}).items():
        out["raw_double[%s]" % k] = v
    sender = rec.get("sender")
    if sender == "<null>":
        sender = None
    if isinstance(sender, dict):
        out["sender.device"] = sender_name(sender)
        out["sender.builtin"] = sender.get("sender_Built-In")
        out["sender.usage"] = "%s/%s" % (sender.get("sender_PrimaryUsagePage"), sender.get("sender_PrimaryUsage"))
    else:
        out["sender.device"] = "(無來源)"
    ns = rec.get("nsevent") or {}
    for k, v in ns.items():
        if k == "touches":
            types = sorted({t.get("type") for t in v})
            out["nsevent.touch_types"] = ",".join(str(t) for t in types)
            devices = sorted({t.get("device") for t in v if t.get("device")})
            out["nsevent.touch_devices"] = ",".join(devices)
        elif isinstance(v, (int, float, str, bool)) or v is None:
            out["nsevent." + k] = v
    return out


def sender_name(sender):
    """來源裝置的可讀名稱：產品名稱＋裝置編號 (同名的內建裝置靠編號區分)。"""
    if not isinstance(sender, dict):
        return "(無來源)"
    name = sender.get("sender_Product") or sender.get("sender_class") or "未知"
    return "%s #%s" % (name, sender.get("sender_device_registry_id") or sender.get("sender_id"))


def is_raw(field):
    return field.startswith("raw_")


def value_sets(events, field):
    vals = collections.Counter()
    for e in events:
        v = e["_flat"].get(field)
        if v is None and is_raw(field):
            v = 0
        vals[json.dumps(v)] += 1
    return vals


def compare(a_events, b_events):
    """回傳能分辨 a、b 的欄位清單：(欄位, 重疊比例, a 的值, b 的值)。"""
    fields = set()
    for e in a_events + b_events:
        fields.update(e["_flat"].keys())
    results = []
    for field in sorted(fields):
        if field in NOISY_FIELDS:
            continue
        va = value_sets(a_events, field)
        vb = value_sets(b_events, field)
        if len(va) > MAX_DISTINCT or len(vb) > MAX_DISTINCT:
            continue
        shared = set(va) & set(vb)
        if shared == set(va) == set(vb):
            continue  # 兩邊完全一樣，沒有資訊
        overlap_a = sum(va[s] for s in shared) / max(1, sum(va.values()))
        overlap_b = sum(vb[s] for s in shared) / max(1, sum(vb.values()))
        overlap = max(overlap_a, overlap_b)
        if overlap <= 0.10:
            results.append((field, overlap, va, vb))
    results.sort(key=lambda r: (r[1], not r[0].startswith("sender."), is_raw(r[0]), r[0]))
    return results


def fmt_values(counter, limit=4):
    items = counter.most_common(limit)
    text = "、".join("%s×%d" % (json.loads(k), n) for k, n in items)
    if len(counter) > limit:
        text += "…"
    return text


def confidence(overlap, na, nb):
    if na < MIN_SAMPLES or nb < MIN_SAMPLES:
        return "低 (樣本太少)"
    if overlap == 0:
        return "高" if min(na, nb) >= 100 else "中"
    return "中" if overlap <= 0.02 else "低"


def main():
    parser = argparse.ArgumentParser(description="分析拂拭偵測工具的紀錄")
    parser.add_argument("paths", nargs="*", help="jsonl 紀錄檔 (預設：最新的一份)")
    parser.add_argument("--all", action="store_true", help="合併 probe-logs 裡所有紀錄")
    parser.add_argument("--out", help="另存 Markdown 報告的路徑")
    args = parser.parse_args()

    paths = args.paths
    if not paths:
        found = sorted(glob.glob(os.path.join(LOG_DIR, "probe-*.jsonl")))
        if not found:
            print("找不到紀錄檔：%s 裡沒有 probe-*.jsonl。請先執行 FushiProbe.app 做測試。" % LOG_DIR)
            return 1
        paths = found if args.all else [found[-1]]

    records, bad = load(paths)
    lines = []
    p = lines.append

    p("# 拂拭 偵測結果分析")
    p("")
    p("- 紀錄檔：" + "、".join(os.path.relpath(x, ROOT) for x in paths))
    p("- 總筆數：%d (無法解析 %d 筆)" % (len(records), bad))
    meta = [r for r in records if r.get("src") == "meta" and r.get("event") == "start"]
    if meta:
        m = meta[0]
        p("- 系統：%s；機型：%s；輸入監控權限：%s" % (m.get("os"), m.get("hw_model"), "有" if m.get("input_monitoring") else "沒有"))
    p("")

    meta_tap = [r for r in records if r.get("src") == "meta" and r.get("event") == "event_tap_start"]
    taps = []
    for r in records:
        if r.get("src") != "tap":
            continue
        if 0 <= (r.get("since_label_ms") if r.get("since_label_ms") is not None else -1) < LABEL_GUARD_MS:
            continue
        r["_flat"] = flatten(r)
        taps.append(r)
    hids = [r for r in records if r.get("src") == "hid"]
    touches = [r for r in records if r.get("src") == "touch"]

    if not taps:
        p("⚠️ 沒有任何事件層紀錄。最可能的原因：沒有授予「輸入監控」權限，事件層監聽沒有啟動。")

    # ---- 1. 各標籤的事件類型 ----
    p("## 1. 各標籤出現的事件類型與數量 (事件層，session 位置)")
    p("")
    by_label = collections.defaultdict(list)
    for r in taps:
        by_label[r.get("label", "unlabeled")].append(r)
    for label in LABEL_TITLES:
        events = [e for e in by_label.get(label, []) if e.get("tap") == "session"]
        if not events:
            continue
        counter = collections.Counter(e.get("type_name") for e in events)
        p("- **%s** (%d 筆)：%s" % (LABEL_TITLES[label], len(events),
                                  "、".join("%s %d" % (k, v) for k, v in counter.most_common())))
    p("")

    # ---- 2. 視窗觸控 ----
    p("## 2. 視窗內觸控 (NSTouch) — direct 代表手指直接碰螢幕")
    p("")
    if not touches:
        p("- 沒有視窗觸控紀錄 (沒有在「觸控測試區」裡操作)。")
    for label in LABEL_TITLES:
        rows = [t for t in touches if t.get("label") == label]
        if not rows:
            continue
        direct = sum(t.get("direct", 0) for t in rows if t.get("kind") == "touches")
        indirect = sum(t.get("indirect", 0) for t in rows if t.get("kind") == "touches")
        subtypes = collections.Counter(str(t.get("subtype")) for t in rows if t.get("kind") == "event")
        p("- **%s**：NSTouch 直接 %d、間接 %d；一般事件 subtype：%s" % (
            LABEL_TITLES[label], direct, indirect, "、".join("%s×%d" % kv for kv in subtypes.most_common()) or "無"))
    p("")

    # ---- 3. HID 層 ----
    p("## 3. HID 層：每個標籤期間是哪個裝置在送資料")
    p("")
    for label in LABEL_TITLES:
        rows = [h for h in hids if h.get("label") == label]
        if not rows:
            continue
        counter = collections.Counter("%s (#%s)" % (h.get("product") or "?", h.get("registry_id")) for h in rows)
        total = sum(counter.values())
        top = "、".join("%s %.0f%%" % (k, 100.0 * v / total) for k, v in counter.most_common(4))
        p("- **%s** (%d 筆)：%s" % (LABEL_TITLES[label], total, top))
    p("")

    # ---- 3b. 事件來源裝置 ----
    p("## 3b. 事件來源裝置 (事件層每個指標事件是哪個實體裝置送出的)")
    p("")
    if meta_tap and meta_tap[0].get("sender_api_available") is False:
        p("- ⚠️ 這台系統找不到讀取來源裝置的函式，這一節沒有資料。")
    for label in LABEL_TITLES:
        rows = [e for e in by_label.get(label, []) if e.get("tap") == "session" and e.get("type") in POINTER_TYPES]
        if not rows:
            continue
        counter = collections.Counter(sender_name(e.get("sender")) for e in rows)
        total = sum(counter.values())
        p("- **%s** (%d 筆指標事件)：%s" % (LABEL_TITLES[label], total,
          "、".join("%s %.0f%%" % (k, 100.0 * v / total) for k, v in counter.most_common(4))))
    p("")

    dominant = {}
    for label, events in by_label.items():
        names = collections.Counter(sender_name(e.get("sender")) for e in events
                                    if e.get("tap") == "session" and e.get("type") in POINTER_TYPES
                                    and sender_name(e.get("sender")) != "(無來源)")
        if names:
            name, n = names.most_common(1)[0]
            dominant[label] = (name, n / sum(names.values()))
    ts = [e for e in by_label.get("touchscreen", []) if e.get("type") in POINTER_TYPES]
    touch_missing = bool(ts) and not any(
        "kiwi" in sender_name(e.get("sender")).lower() or
        (isinstance(e.get("sender"), dict) and e["sender"].get("sender_PrimaryUsagePage") == 13) for e in ts)
    if ts and not any("kiwi" in sender_name(e.get("sender")).lower() or
                      (isinstance(e.get("sender"), dict) and e["sender"].get("sender_PrimaryUsagePage") == 13)
                      for e in ts):
        p("> ⚠️ 「觸控螢幕」標籤期間，事件層**沒有收到任何來自觸控螢幕 (數位板) 的事件**。")
        p("> 可能是測試時沒有實際點觸控螢幕，或是觸控螢幕的點擊根本不經過事件層。請照偵測指南重測觸控螢幕 30 秒。")
        p("")

    # ---- 4. 兩兩比較 ----
    p("## 4. 哪些欄位能把標籤區分開 (同一種事件類型裡比較)")
    p("")
    conclusions = []
    for a, b in PAIRS:
        title = "%s vs %s" % (LABEL_TITLES[a], LABEL_TITLES[b])
        p("### " + title)
        ea = by_label.get(a, [])
        eb = by_label.get(b, [])
        ea = [e for e in ea if e.get("type") in POINTER_TYPES]
        eb = [e for e in eb if e.get("type") in POINTER_TYPES]
        if not ea or not eb:
            missing = "、".join(LABEL_TITLES[x] for x, ev in ((a, ea), (b, eb)) if not ev)
            p("- 缺資料：%s 沒有指標事件紀錄。" % missing)
            p("")
            conclusions.append((title, "無法判斷", "缺資料 (%s)" % missing, "—"))
            continue
        if touch_missing and "touchscreen" in (a, b):
            p("- ⚠️ 「觸控螢幕」標籤期間沒有任何觸控螢幕事件，這組比較無法判斷。")
            p("")
            conclusions.append((title, "無法判斷", "沒有收到觸控螢幕的事件 (需重測)", "—"))
            continue
        da, db = dominant.get(a), dominant.get(b)
        if da and db and da[0] == db[0]:
            p("- ⚠️ 兩個標籤期間的事件其實都來自 **%s**，比較無效 (測試時動到的是同一個裝置)。" % da[0])
            p("")
            conclusions.append((title, "無效", "兩邊其實都是 %s 的事件" % da[0], "—"))
            continue
        best = None
        for tap in ("session", "hid"):
            for tname in sorted({e.get("type_name") for e in ea} & {e.get("type_name") for e in eb}):
                sa = [e for e in ea if e.get("tap") == tap and e.get("type_name") == tname]
                sb = [e for e in eb if e.get("tap") == tap and e.get("type_name") == tname]
                if not sa or not sb:
                    continue
                found = compare(sa, sb)
                if not found:
                    continue
                p("- **%s／%s** (%d vs %d 筆)：" % (tap, tname, len(sa), len(sb)))
                for field, overlap, va, vb in found[:6]:
                    p("  - `%s`：重疊 %.1f%%｜%s：%s｜%s：%s" % (
                        field, overlap * 100, LABEL_TITLES[a], fmt_values(va), LABEL_TITLES[b], fmt_values(vb)))
                field, overlap, va, vb = found[0]
                candidate = (overlap, -min(len(sa), len(sb)), tap, tname, field, len(sa), len(sb))
                if best is None or candidate < best:
                    best = candidate
        only_a = sorted({e.get("type_name") for e in ea} - {e.get("type_name") for e in eb})
        only_b = sorted({e.get("type_name") for e in eb} - {e.get("type_name") for e in ea})
        if only_a or only_b:
            p("- 只出現在一邊的事件類型：%s 獨有 %s；%s 獨有 %s" % (
                LABEL_TITLES[a], "、".join(only_a) or "無", LABEL_TITLES[b], "、".join(only_b) or "無"))
        if best is None:
            p("- 在相同事件類型裡找不到能區分的欄位。")
            conclusions.append((title, "目前分不出來", "—", "—"))
        else:
            overlap, _, tap, tname, field, na, nb = best
            conclusions.append((title, "可以" if overlap == 0 else "大致可以",
                                "%s／%s 的 `%s`" % (tap, tname, field), confidence(overlap, na, nb)))
        p("")

    # ---- 5. 結論表 ----
    p("## 5. 結論")
    p("")
    p("| 比較 | 能不能區分 | 靠哪個欄位 | 可信度 |")
    p("|---|---|---|---|")
    for row in conclusions:
        p("| %s |" % " | ".join(row))
    p("")
    p("說明：「可信度」依樣本數與重疊比例判斷，原始欄位 (raw_*) 是 Apple 未公開的欄位，")
    p("系統更新後可能改變，第 2 階段使用前要在新版系統上重測。")

    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        print("\n已另存報告：%s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
