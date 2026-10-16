# ShotPilot MCP

讓 AI（Claude Code、Claude Desktop 等 MCP 客戶端）直接操作 ShotPilot：讀場景、擺物件、調環境、
設鏡頭、記錄點→自動運鏡、截圖驗證、匯出 RGB／深度影片。

```
AI ──MCP(stdio)──► shotpilot_mcp.py ──HTTP──► ShotPilot（127.0.0.1:8766/rpc）
```

- 純 Python 標準庫，不用安裝任何套件（Python 3.10+）
- **要先開啟 ShotPilot**（`desktop` 專案執行），Studio 啟動時會在 `127.0.0.1:8766` 開 API，只接受本機連線

## 註冊

Claude Code：

```bash
claude mcp add shotpilot -- python3 /path/to/shotpilot/mcp/shotpilot_mcp.py
```

Claude Desktop（`claude_desktop_config.json`）：

```json
{
  "mcpServers": {
    "shotpilot": {
      "command": "python3",
      "args": ["/path/to/shotpilot/mcp/shotpilot_mcp.py"],
      "env": { "SHOTPILOT_URL": "http://127.0.0.1:8766/rpc" }
    }
  }
}
```

| 環境變數 | 預設 | 說明 |
|---|---|---|
| `SHOTPILOT_URL` | `http://127.0.0.1:8766/rpc` | Studio API 位址 |
| `SHOTPILOT_TIMEOUT` | 30 | 一般工具逾時（秒） |
| `SHOTPILOT_EXPORT_TIMEOUT` | 900 | `export_take` 逾時（秒） |

## 工具

座標：公尺、Y 朝上、旋轉單位為度；物件以唯一的 `name` 辨識；顏色 `#rrggbb`。

| 工具 | 用途 |
|---|---|
| `get_scene` | 讀取物件、鏡頭、環境、記錄點、take 清單（修改前先呼叫） |
| `screenshot` | `view: "editor"`（全局編輯視角）或 `"camera"`（手機鏡頭畫面），回傳圖片 |
| `add_object` / `update_object` / `delete_object` / `clear_scene` | 物件增刪改：box、sphere、cylinder、capsule、cone、torus、slab、wall、stairs、mannequin（人偶）、light |
| `set_camera` | 鏡頭位置、角度或 `look_at`、FOV |
| `set_editor_view` | 調整全局觀察視角（方便截圖檢查） |
| `set_environment` | 太陽角度／顏色、天空或純色背景、霧、地板 |
| `add_waypoint` / `clear_waypoints` | 記錄點（不給參數＝目前鏡頭） |
| `create_auto_take` | 依記錄點產生平滑自動運鏡 |
| `play_take` | 預覽 take |
| `export_take` | 離線渲染 RGB＋深度 mp4、camera.json（輸出到 `文件/ShotPilot/exports`） |
| `apply_preset` | 套用場景／燈光／機位範本 |
| `play_objects` | 物件路線動畫：播放、暫停、重置、跳到某秒 |
| `save_scene` / `load_scene` | 存／讀場景 JSON |

## 範例提示

> 用 ShotPilot 做一個「巷口」場景：兩面牆夾出一條 2 公尺寬的巷子，巷口放一個人偶和幾個箱子，黃昏斜陽。
> 鏡頭從巷子深處低角度往巷口推進，記 4 個點產生 6 秒自動運鏡，截圖給我看構圖，沒問題就匯出 1080p 24fps 含深度。
