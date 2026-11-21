#!/usr/bin/env python3
"""
從 App 圖示的原始向量檔 (Design/AppIcon.svg) 產生主視覺插畫，品牌畫風完全一致。

為什麼不直接裁圖示？圖示是正方形、有圓角，硬裁會把拂塵頂端和星星切掉。
這支腳本改的是「構圖」：把背景延伸成 16:10 (和螢幕同比例) 的長方形、拿掉圓角裁切，
重新取景，必要時把拂塵移到要清潔的位置。

用法：python3 scripts/make-hero-art.py
輸出：Design/Hero-*.svg 與 Sources/Fushi/Resources/Assets.xcassets/Hero*.imageset/
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Design", "AppIcon.svg")

# 拂塵 = 拂塵毛 (<g><path d="M650,470 ...) ＋ 握把 (<g filter="url(#hs)">…</g>)
DUSTER_START = '<g><path d="M650,470'
DUSTER_END = '<circle cx="662" cy="482" r="18" fill="#A8762C"/></g>'

# 每張插畫：名稱、取景範圍 (圖示座標，16:10)、拂塵的變形 (SVG transform，None 表示不動)
# 四張插畫用「完全相同」的取景：整台筆電 (含最下方的觸控板) 都入鏡，16:10。
# 切換頁面時筆電不動，只有拂塵移動：螢幕 → 鍵盤 → 觸控板 → 蓋過整台 (全鎖)。
VIEW = (-96, 130, 1216, 760)   # 上下各留空間：拂塵最頂端約 177、筆電底座約 860
DUSTER_KEYBOARD = "translate(-40,196) rotate(-35 650 470) translate(650 470) scale(0.85) translate(-650 -470)"
DUSTER_TRACKPAD = "translate(28,296) rotate(-38 650 470) translate(650 470) scale(0.88) translate(-650 -470)"
DUSTER_ALL = "translate(10,120) rotate(-12 650 470) translate(650 470) scale(1.12) translate(-650 -470)"
ARTS = [
    ("HeroScreen", "Hero-1-screen.svg", VIEW, None),
    ("HeroKeyboard", "Hero-2-keyboard.svg", VIEW, DUSTER_KEYBOARD),
    ("HeroTrackpad", "Hero-3-trackpad.svg", VIEW, DUSTER_TRACKPAD),
    ("HeroAll", "Hero-4-all.svg", VIEW, DUSTER_ALL),
]


def build(view, duster_offset):
    vx, vy, vw, vh = view
    svg = open(SRC, encoding="utf-8").read()
    svg = re.sub(r'viewBox="[^"]+"', 'viewBox="%d %d %d %d"' % view, svg, count=1)
    svg = re.sub(r'width="1024" height="1024"', 'width="%d" height="%d"' % (vw * 2, vh * 2), svg, count=1)
    # 圓角方塊背景換成鋪滿取景範圍的長方形 (同樣的深藍夜空漸層)
    svg = svg.replace(
        '<g filter="url(#sh)"><rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/></g>',
        '<rect x="%d" y="%d" width="%d" height="%d" fill="url(#bg)"/>' % view)
    # 拿掉圓角裁切與外框描邊
    svg = svg.replace('<g clip-path="url(#sq)">', '<g>')
    svg = svg.replace('<rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="#fff" '
                      'stroke-opacity="0.08" stroke-width="3"/>', '')
    # 背景漸層依整張圖計算
    svg = svg.replace('<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">',
                      '<linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="0" y1="%d" x2="0" y2="%d">' % (vy, vy + vh))
    # 移動拂塵
    if duster_offset:
        a = svg.index(DUSTER_START)
        b = svg.index(DUSTER_END) + len(DUSTER_END)
        svg = svg[:a] + '<g transform="%s">' % duster_offset + svg[a:b] + '</g>' + svg[b:]
    return svg


for asset, svg_name, view, offset in ARTS:
    out_svg = os.path.join(ROOT, "Design", svg_name)
    open(out_svg, "w", encoding="utf-8").write(build(view, offset))
    imageset = os.path.join(ROOT, "Sources", "Fushi", "Resources", "Assets.xcassets", asset + ".imageset")
    os.makedirs(imageset, exist_ok=True)
    png = os.path.join(imageset, asset + "@2x.png")
    # 用系統的 WebKit 轉檔，陰影與光暈濾鏡才完整
    r = subprocess.run(["swift", os.path.join(ROOT, "scripts", "render-svg.swift"), out_svg, png,
                        str(view[2] * 2), str(view[3] * 2)], capture_output=True, text=True)
    if r.returncode == 0:
        # 主視窗插畫最寬 560 點，Retina 約需 1120 像素；輸出 1680 像素寬保留餘裕，檔案小很多
        subprocess.run(["sips", "-Z", "1680", png], capture_output=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        sys.exit(r.returncode)
    open(os.path.join(imageset, "Contents.json"), "w").write('''{
  "images" : [
    { "idiom" : "universal", "scale" : "1x" },
    { "filename" : "%s@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''' % asset)
    print("已產生：Design/%s → %s" % (svg_name, os.path.relpath(png, ROOT)))
