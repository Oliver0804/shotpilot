#!/usr/bin/env bash
# 匯出 Godot iOS 專案 → xcodebuild（App Store Connect API key 自動簽章）→ 安裝並啟動到實機
# 用法：./ios_run.sh [裝置 UDID]   （未指定則取第一台已連接的實體 iPhone）
set -euo pipefail
cd "$(dirname "$0")"

GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
# 換成自己的 Apple Team ID / Bundle ID（export_presets.cfg 的 app_store_team_id 也要一起改）
TEAM=${IOS_TEAM_ID:-A3VXSGZPQ2}
BUNDLE=${IOS_BUNDLE_ID:-net.bashcat.shotpilot}
# App Store Connect API key：檔案內定義 ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH（.p8 路徑），不要放進 repo
ASC_ENV=${ASC_ENV:-$HOME/.config/shotpilot/asc-api.env}
[ -f "$ASC_ENV" ] || { echo "找不到 $ASC_ENV（需要 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH）"; exit 1; }
. "$ASC_ENV"

DEVICE=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /physical/ && /available|connected/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}
[ -n "$DEVICE" ] || { echo "找不到已連接的 iPhone"; exit 1; }
echo "▶ 裝置 $DEVICE"

echo "▶ Godot 匯出 Xcode 專案"
rm -rf build/ios/ShotPilot build/ios/ShotPilot.pck build/ios/ShotPilot.xcodeproj
mkdir -p build/ios && touch build/.gdignore
"$GODOT" --headless --path . --export-debug iOS build/ios/ShotPilot.xcodeproj 2>&1 | grep -E "ERROR" -A1 || true
[ -d build/ios/ShotPilot.xcodeproj ] || { echo "Godot 匯出失敗"; exit 1; }

echo "▶ xcodebuild"
xcodebuild -project build/ios/ShotPilot.xcodeproj -scheme ShotPilot -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath build/ios/dd \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH" \
  DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE \
  build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP=$(find build/ios/dd/Build/Products -maxdepth 2 -name "*.app" -path "*iphoneos*" | head -1)
echo "▶ 安裝 $APP"
xcrun devicectl device install app --device "$DEVICE" "$APP" | tail -2
echo "▶ 啟動"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" | tail -1
