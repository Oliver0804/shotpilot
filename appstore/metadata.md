# App Store 上架資料

| 欄位 | 值 |
|---|---|
| Bundle ID | net.bashcat.shotpilot |
| SKU | shotpilot-ios |
| 主要語言 | 繁體中文（zh-Hant），另有英文（en-US） |
| 類別 | 攝影與錄影（Photo & Video）；次要：圖形與設計（Graphics & Design） |
| 價格 | 免費，全球上架 |
| 年齡分級 | 4+（無任何敏感內容） |
| 隱私權政策 | https://oliver0804.github.io/shotpilot/privacy.html |
| 支援網址 | https://github.com/Oliver0804/shotpilot |
| 行銷網址 | https://youtu.be/MtYnDYLFxHk |
| App 隱私 | 不蒐集資料（Data Not Collected） |
| 加密 | 不使用非豁免加密（Info.plist 已設 ITSAppUsesNonExemptEncryption=false） |
| 版權 | 2026 Oliver |

## 繁體中文（zh-Hant）

**名稱**（≤30）：ShotPilot

**副標題**（≤30）：手機當攝影機，為 AI 影片排運鏡

**宣傳文字**（≤170）：
轉動手機就是轉鏡頭、蹲下鏡頭跟著變低。內建範例場景，打開就能運鏡、錄製、記點自動生成平滑運鏡；連上電腦版還能自建場景，匯出給 AI 影片用的素材。

**關鍵字**（≤100）：
運鏡,虛擬攝影機,分鏡,previs,AI影片,鏡頭,攝影,3D,陀螺儀,運鏡軌跡,深度圖,構圖,影片生成,Godot

**描述**：
ShotPilot 把手機變成 3D 場景裡的虛擬攝影機。

AI 圖像與影片模型很難只靠文字控制「鏡頭從哪個角度、怎麼移動」。ShotPilot 讓你拿著手機在場景裡實際「拍」一次：轉動手機就是轉鏡頭，蹲下鏡頭就跟著變低，構圖與運鏡一目了然。

【打開就能用：內建範例場景】
・街道巷口、客廳、公園、攝影棚、舞台、走廊、辦公室 7 個範例場景
・陀螺儀控制鏡頭角度，直拿、橫拿自動切換
・雙搖桿：左邊移動、右邊轉動鏡頭，還有升降滑桿
・雙指縮放 FOV（10°～110°），特寫、遠景隨手切換

【錄製與自動運鏡】
・一鍵錄製整段運鏡（位置、角度、FOV），可立即回放
・記下幾個機位，自動串成平滑的推軌、環繞運鏡

【連上電腦，功能更完整】
搭配免費開源的 ShotPilot 桌面版（同一個 Wi-Fi）：
・用方塊、人偶、燈光、匯入的 3D 模型自建場景
・手機即時顯示電腦渲染的畫面
・匯出 RGB 影片、深度影片與鏡頭軌跡（camera.json），給 AI 影片生成、ControlNet、camera control 等工具使用
・桌面版內建 MCP，可以讓 AI 助理直接擺場景、設鏡頭

桌面版與原始碼：github.com/Oliver0804/shotpilot

不需要帳號，不蒐集任何個人資料。

**此版本新增內容**：第一版上架。

## English (en-US)

**Name**: ShotPilot

**Subtitle** (≤30): Virtual camera for AI video

**Promotional text** (≤170):
Turn your phone to pan, crouch to go low. Built-in scenes let you shoot, record and build smooth camera moves right away; pair with the desktop app to export material for AI video.

**Keywords** (≤100):
virtual camera,previs,camera move,storyboard,AI video,cinematography,3D,gyro,framing,depth map,shot

**Description**:
ShotPilot turns your phone into a virtual camera inside a 3D scene.

Image and video models are hard to direct with text alone — where the camera stands, which way it looks, how it moves. With ShotPilot you hold your phone and actually "shoot" the scene: turn the phone to turn the camera, crouch and the camera goes low.

BUILT-IN SCENES, READY TO SHOOT
• 7 sample scenes: street corner, living room, park, studio, stage, corridor, office
• Gyroscope camera control, automatic portrait / landscape switching
• Dual joysticks to move and aim, plus a height slider
• Pinch to change field of view (10°–110°), from wide to close-up

RECORD AND AUTO CAMERA MOVES
• Record a whole camera move (position, rotation, FOV) and replay it instantly
• Save a few camera positions and get a smooth dolly or orbit move automatically

EVEN MORE WITH A COMPUTER
Pair with the free, open-source ShotPilot desktop app on the same Wi-Fi:
• Build scenes from boxes, mannequins, lights and imported 3D models
• See the computer's render live on your phone
• Export RGB video, depth video and camera trajectories (camera.json) for AI video generation, ControlNet and camera-control tools
• Built-in MCP server so AI assistants can set up scenes and cameras

Desktop app and source code: github.com/Oliver0804/shotpilot

No account required. No personal data collected.

**What's New**: First release.

## App Review 備註（英文，只給審查員看）

ShotPilot works on its own: when it is not connected to a computer it runs in demo mode with built-in 3D scenes, so every feature can be tested on the device without any setup.

How to test:
1. Launch the app. A sample 3D scene is shown immediately (demo mode).
2. Move/rotate the phone to aim the camera. Use the left joystick to move, the right joystick to turn, the vertical slider to change height. Pinch with two fingers to change field of view.
3. Tap "錄製" (Record) to start, tap again to stop; tap "回放" (Playback) to replay the take.
4. Tap "記點" (Waypoint) at 2–3 different positions, then tap "自動運鏡" (Auto move) to generate a smooth camera move.
5. Tap "換場景" (Change scene) to cycle through 7 sample scenes.

Optional: the free, open-source ShotPilot desktop app (https://github.com/Oliver0804/shotpilot) connects over the local network to render custom scenes; this is why the app requests Local Network permission. Demo video: https://youtu.be/MtYnDYLFxHk

No sign-in is required.
