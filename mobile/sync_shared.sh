#!/usr/bin/env bash
# 把桌面端的共用腳本複製到手機專案（示範模式用同一套鏡頭邏輯、物件與範本）。
# 改了 desktop/ 裡這些檔案之後要重跑一次。
set -euo pipefail
cd "$(dirname "$0")"
D=../desktop
mkdir -p shared
cp $D/addons/phone_camera_rig/phone_camera_rig.gd $D/addons/phone_camera_rig/phone_cam_server.gd shared/
cp $D/studio/studio_shape.gd $D/studio/scene_presets.gd $D/studio/camera_path.gd shared/
echo "已同步到 mobile/shared/"
