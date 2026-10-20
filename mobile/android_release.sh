#!/usr/bin/env bash
# 產出 Google Play 上架用的 AAB：version/code＝git commit 數 → Godot Gradle 建置 → build/android/ShotPilot-<版本>-<build>.aab。
# AAB 不自動上傳，到 Play Console 手動拖進版本。
# 用法：./android_release.sh
# 簽章讀 ~/.config/shotpilot/android.env（GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD），不要放進 repo。
set -euo pipefail
cd "$(dirname "$0")"

GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
ANDROID_ENV=${ANDROID_ENV:-$HOME/.config/shotpilot/android.env}
OUT=build/android

DIRTY=$(git status --porcelain -- . ../desktop | grep -vE ' mobile/export_presets.cfg$' || true)
if [ -n "$DIRTY" ]; then
  echo "❌ 有未提交的變更，請先 commit："; echo "$DIRTY"; exit 1
fi
[ -f "$ANDROID_ENV" ] || { echo "❌ 找不到 $ANDROID_ENV"; exit 1; }
. "$ANDROID_ENV"

# 1. build number（跟 iOS 一樣用 git commit 數）
BUILD=$(git rev-list --count HEAD)
VERSION=$(sed -nE '/^\[preset\.1\.options\]/,/^\[/ s/^version\/name="(.*)"/\1/p' export_presets.cfg)
sed -i '' -E "/^\[preset\.1\.options\]/,/^\[/ s/^version\/code=.*/version\/code=$BUILD/" export_presets.cfg
echo "▶ 1/2 版本 ${VERSION}（build ${BUILD}）"

# 2. Godot 匯出 AAB（匯出期間把 export_format 暫時設 1，結束還原成 APK）
restore() { sed -i '' -E '/^\[preset\.1\.options\]/,/^\[/ s/^gradle_build\/export_format=.*/gradle_build\/export_format=0/' export_presets.cfg; }
trap restore EXIT
sed -i '' -E '/^\[preset\.1\.options\]/,/^\[/ s/^gradle_build\/export_format=.*/gradle_build\/export_format=1/' export_presets.cfg
echo "▶ 2/2 Godot 匯出 AAB"
./sync_shared.sh >/dev/null
mkdir -p "$OUT" && touch build/.gdignore
AAB="$OUT/ShotPilot-$VERSION-$BUILD.aab"
rm -f "$AAB"
INSTALL_TEMPLATE=()
[ -d android/build ] || INSTALL_TEMPLATE=(--install-android-build-template)
"$GODOT" --headless --path . "${INSTALL_TEMPLATE[@]}" --export-release Android "$AAB" > "$OUT/godot-release.log" 2>&1 || true
[ -f "$AAB" ] || { echo "❌ Godot 匯出失敗："; grep -E "ERROR|error:|FAILED" -A2 "$OUT/godot-release.log" | head -30; exit 1; }

echo "✅ ${AAB}（$(du -h "$AAB" | cut -f1)）"
