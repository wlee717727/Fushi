#!/usr/bin/env python3
"""
產生「模擬的」偵測紀錄，只用來測試 analyze-probe.py 本身有沒有寫對。
這不是真實資料，不能拿來做任何判斷。

用法：python3 scripts/make-sample-probe.py <輸出.jsonl>
"""
import json
import random
import sys

random.seed(7)
out = sys.argv[1]
rows = []
t = 0.0


def add(rec):
    global t
    t += 5
    rec.setdefault("t_ms", t)
    rec.setdefault("since_label_ms", 2000)
    rec.setdefault("uptime_ns", int(t * 1e6))
    rows.append(rec)


add({"src": "meta", "event": "event_tap_start", "sender_api_available": True, "label": "unlabeled"})
add({"src": "meta", "event": "start", "os": "模擬", "hw_model": "模擬機", "input_monitoring": True, "label": "unlabeled"})

# 假設：觸控螢幕的未公開欄位 87 = 3、subtype = 0；觸控板 87 = 0、subtype = 3；滑鼠兩者皆 0 但 keyboardType 不同
profiles = {
    "touchscreen": {"raw87": 3, "subtype": 0, "pid": 0},
    "builtin_trackpad": {"raw87": 0, "subtype": 3, "pid": 0},
    "external_mouse": {"raw87": 0, "subtype": 0, "pid": 0},
}
for label, prof in profiles.items():
    for i in range(150):
        for tap in ("session", "hid"):
            raw_int = {"1": random.randint(1, 10**6)}  # 連續變化的雜訊欄位
            if prof["raw87"]:
                raw_int["87"] = prof["raw87"]
            if prof["subtype"]:
                raw_int["7"] = prof["subtype"]
            add({"src": "tap", "tap": tap, "label": label, "type": 5 if i % 3 else 1,
                 "type_name": "mouseMoved" if i % 3 else "leftMouseDown",
                 "x": random.random() * 1000, "y": random.random() * 800,
                 "fields": {"mouseEventSubtype": prof["subtype"], "mouseEventDeltaX": random.randint(-5, 5)},
                 "raw_int": raw_int, "raw_double": {},
                 "nsevent": {"type": 5, "subtype": prof["subtype"]},
                 "sender": {"sender_id": 1000 + len(label), "sender_Product": {"touchscreen": "Kiwi", "builtin_trackpad": "Apple Internal Keyboard / Trackpad", "external_mouse": "MX Master 3"}[label],
                            "sender_device_registry_id": 500 + len(label), "sender_Built-In": label != "external_mouse"}})
    for i in range(40):
        add({"src": "hid", "label": label, "product": {"touchscreen": "Touch Display", "builtin_trackpad": "Apple Internal Trackpad",
                                                     "external_mouse": "USB Mouse"}[label],
             "registry_id": hash(label) % 1000, "usage_page": 13, "usage": 0x30})
for i in range(30):
    add({"src": "tap", "tap": "session", "label": "keyboard", "type": 10, "type_name": "keyDown",
         "fields": {"keyboardEventKeyboardType": 91}, "raw_int": {"10": 91}, "raw_nonzero_fields": [8, 10],
         "nsevent": {"type": 10, "subtype": 0}})
add({"src": "touch", "label": "touchscreen", "kind": "touches", "direct": 1, "indirect": 0, "count": 1})
# 切換標籤後 0.3 秒內的點擊 (應該被分析排除)
add({"src": "tap", "tap": "session", "label": "touchscreen", "type": 1, "type_name": "leftMouseDown",
     "since_label_ms": 300, "fields": {}, "raw_int": {"7": 3}, "nsevent": {}})

with open(out, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("已產生模擬紀錄 %d 筆：%s" % (len(rows), out))
