#!/usr/bin/env bash
# 一鍵上 TestFlight：build number＝git commit 數 → Godot 匯出 Xcode 專案 → archive → 直傳 App Store Connect → commit 版號。
# 用法：./release.sh ["release note"]
# 讀輸出時不要接 | tail（退出碼會被吃掉），導到檔案再讀：
#   ./release.sh "note" > /tmp/release.log 2>&1; echo "EXIT=$?"; tail -25 /tmp/release.log
set -euo pipefail
cd "$(dirname "$0")"

GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
TEAM=${IOS_TEAM_ID:-A3VXSGZPQ2}
ASC_ENV=${ASC_ENV:-$HOME/.config/shotpilot/asc-api.env}
NOTE="${1:-release}"
OUT=build/release

DIRTY=$(git status --porcelain -- . ../desktop | grep -vE ' mobile/export_presets.cfg$' || true)
if [ -n "$DIRTY" ]; then
  echo "❌ 有未提交的變更，請先 commit："; echo "$DIRTY"; exit 1
fi
[ -f "$ASC_ENV" ] || { echo "❌ 找不到 $ASC_ENV"; exit 1; }
. "$ASC_ENV"
AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")

# 1. build number（git commit 數，單調遞增、可重現）
BUILD=$(git rev-list --count HEAD)
sed -i '' -E "s/^application\/version=\".*\"/application\/version=\"$BUILD\"/" export_presets.cfg
VERSION=$(sed -nE 's/^application\/short_version="(.*)"/\1/p' export_presets.cfg)
echo "▶ 1/4 版本 $VERSION（build $BUILD）"

# 2. Godot 匯出 Xcode 專案（共用腳本先同步，確保示範模式跟桌面端一致）
echo "▶ 2/4 Godot 匯出"
./sync_shared.sh >/dev/null
rm -rf "$OUT" && mkdir -p "$OUT" && touch build/.gdignore
"$GODOT" --headless --path . --export-release iOS "$OUT/ShotPilot.xcodeproj" > "$OUT/godot.log" 2>&1 || true
[ -d "$OUT/ShotPilot.xcodeproj" ] || { echo "❌ Godot 匯出失敗："; grep -E "ERROR" -A1 "$OUT/godot.log"; exit 1; }

# 3. Archive
echo "▶ 3/4 archive"
xcodebuild -project "$OUT/ShotPilot.xcodeproj" -scheme ShotPilot -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/ShotPilot.xcarchive" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  archive -quiet > "$OUT/archive.log" 2>&1 || { echo "❌ archive 失敗："; grep -E "error:" "$OUT/archive.log" | head; exit 1; }

# 4. Upload（失敗時不要重跑 archive，只重跑這一步）
echo "▶ 4/4 上傳 App Store Connect"
set +e
xcodebuild -exportArchive -archivePath "$OUT/ShotPilot.xcarchive" -exportOptionsPlist ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates "${AUTH[@]}" > "$OUT/upload.log" 2>&1
RC=$?
set -e
grep -E "Upload|EXPORT|error" "$OUT/upload.log" | tail -5
if [ $RC -ne 0 ] || grep -q "EXPORT FAILED" "$OUT/upload.log"; then
  echo "❌ 上傳失敗，完整紀錄：$OUT/upload.log"; exit 1
fi

git add export_presets.cfg
if ! git diff --cached --quiet; then
  git commit -q -m "release: build $BUILD

$NOTE"
  git push -q
fi
echo "🎉 $VERSION ($BUILD) 已上傳，Apple 處理約 10–30 分鐘後會出現在 TestFlight"
