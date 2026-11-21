#!/bin/bash
# 一鍵建置：產生 Xcode 專案 → 跑測試 → 用 Release 模式編譯兩個 App → 複製到專案根目錄。
# 用法：scripts/build.sh            (完整流程)
#       scripts/build.sh --no-test  (略過測試)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/DerivedData"
RUN_TESTS=1
[ "${1:-}" = "--no-test" ] && RUN_TESTS=0

echo "▶︎ 1/4 產生 Fushi.xcodeproj"
xcodegen generate --quiet

if [ "$RUN_TESTS" = 1 ]; then
    echo "▶︎ 2/4 執行單元測試 (狀態機與計時器邏輯)"
    xcodebuild -project Fushi.xcodeproj -scheme Fushi -configuration Debug \
        -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' test -quiet
else
    echo "▶︎ 2/4 略過測試"
fi

release_build() {
    for scheme in Fushi FushiProbe; do
        xcodebuild -project Fushi.xcodeproj -scheme "$scheme" -configuration Release \
            -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' build -quiet
    done
}

echo "▶︎ 3/4 Release 編譯"
release_build
# 把介面字串同步到 String Catalog；有新字串就再編譯一次，讓 App 包含最新的字串目錄
set +e
python3 "$ROOT/scripts/sync-strings.py" Release
sync_status=$?
set -e
if [ "$sync_status" = 10 ]; then
    echo "  字串目錄有更新，重新編譯一次"
    release_build
elif [ "$sync_status" != 0 ]; then
    echo "  ⚠️ 字串同步失敗 (代碼 $sync_status)"
    exit "$sync_status"
fi

echo "▶︎ 4/4 複製 App 到專案根目錄"
for app in Fushi FushiProbe; do
    src="$DERIVED/Build/Products/Release/$app.app"
    dst="$ROOT/$app.app"
    if [ -d "$dst" ]; then
        # 舊版移到垃圾桶，不永久刪除
        mv "$dst" "$HOME/.Trash/$app-$(date +%Y%m%d-%H%M%S).app"
    fi
    ditto "$src" "$dst"
    echo "  ✅ $dst"
done
