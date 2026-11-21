#!/bin/bash
# 產生 App 圖示 (AppIcon.appiconset 與 .icns)。
#
# 正式圖示：把 1024×1024 的 PNG 放到
#   Design/AppIcon-1024.png      → 拂拭 (Fushi)
#   Design/ProbeIcon-1024.png    → 偵測工具 (FushiProbe)，沒有的話沿用 AppIcon-1024.png
# 再執行一次：scripts/make-appicon.sh
# 沒有正式圖時會自動產生純色佔位圖示。
#
# 只用 macOS 內建的 sips 與 iconutil。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESIGN="$ROOT/Design"
WORK="${TMPDIR:-/tmp}/fushi-icon-$$"
mkdir -p "$WORK" "$DESIGN"
trap 'rm -rf "$WORK"' EXIT   # 只清掉這支腳本自己產生的暫存檔

make_icon() {
    local target="$1" source="$2"
    local set="$ROOT/Sources/$target/Resources/Assets.xcassets/AppIcon.appiconset"
    local iconset="$WORK/$target.iconset"
    mkdir -p "$set" "$iconset"

    # macOS 圖示需要的尺寸：16、32、128、256、512 各有 1x 與 @2x。
    # 其中 32@1x 的 2 倍就是 64，512@2x 就是 1024。
    for base in 16 32 128 256 512; do
        for scale in 1 2; do
            local px=$((base * scale))
            local name="icon_${base}x${base}"
            [ "$scale" = 2 ] && name="${name}@2x"
            sips -s format png -z "$px" "$px" "$source" --out "$set/$name.png" >/dev/null
            cp "$set/$name.png" "$iconset/$name.png"
        done
    done

    cat > "$set/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

    iconutil -c icns -o "$DESIGN/$target.icns" "$iconset"
    echo "✅ $target 圖示完成 (來源：$source)"
}

# 拂拭
FUSHI_SRC="$DESIGN/AppIcon-1024.png"
if [ ! -f "$FUSHI_SRC" ]; then
    echo "⚠️ 找不到 Design/AppIcon-1024.png，產生佔位圖示"
    FUSHI_SRC="$WORK/fushi-placeholder.png"
    swift "$ROOT/scripts/render-placeholder-icon.swift" "$FUSHI_SRC" "拂" "#3E8C7A" "#1F4F46"
fi
make_icon Fushi "$FUSHI_SRC"

# 偵測工具
PROBE_SRC="$DESIGN/ProbeIcon-1024.png"
if [ ! -f "$PROBE_SRC" ]; then
    echo "⚠️ 找不到 Design/ProbeIcon-1024.png，產生偵測工具的佔位圖示"
    PROBE_SRC="$WORK/probe-placeholder.png"
    swift "$ROOT/scripts/render-placeholder-icon.swift" "$PROBE_SRC" "測" "#5C6BC0" "#2E3A7A"
fi
make_icon FushiProbe "$PROBE_SRC"
