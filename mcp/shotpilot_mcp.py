#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ShotPilot MCP 伺服器（零依賴，只用 Python 3.10+ 標準庫）。

把 MCP 的工具呼叫轉成本機 Godot 桌面 App（ShotPilot）的 HTTP JSON-RPC：

    POST {SHOTPILOT_URL}            預設 http://127.0.0.1:8766/rpc
    body {"method": "<名稱>", "params": {...}}
    回應 {"ok": true, "result": ...} 或 {"ok": false, "error": "訊息"}

MCP 端走 stdio、換行分隔的 JSON-RPC 2.0：
stdout 只能出現協定訊息，所有 log 一律寫 stderr。
"""

from __future__ import annotations

import base64
import binascii
import json
import os
import socket
import sys
import urllib.error
import urllib.request

SERVER_NAME = "shotpilot"
SERVER_VERSION = "1.0.0"
DEFAULT_PROTOCOL_VERSION = "2025-06-18"

GODOT_URL = os.environ.get("SHOTPILOT_URL") or os.environ.get("PHONECAM_URL", "http://127.0.0.1:8766/rpc")

# export_take 要算整段影片，可能跑好幾分鐘；其餘呼叫都該在數秒內回來。
DEFAULT_TIMEOUT = float(os.environ.get("SHOTPILOT_TIMEOUT") or os.environ.get("PHONECAM_TIMEOUT", "30"))
LONG_TIMEOUT = float(os.environ.get("SHOTPILOT_EXPORT_TIMEOUT") or os.environ.get("PHONECAM_EXPORT_TIMEOUT", "900"))
TOOL_TIMEOUTS = {"export_take": LONG_TIMEOUT}

NOT_RUNNING_HINT = (
    "連不上 ShotPilot（{url}）。請先開啟 ShotPilot 桌面 App，"
    "確認它的 HTTP API 已啟動；若換了埠號請設環境變數 SHOTPILOT_URL。"
)


def log(msg: str) -> None:
    """所有診斷訊息都走 stderr，避免污染 stdio 上的協定訊息。"""
    print(f"[shotpilot-mcp] {msg}", file=sys.stderr, flush=True)


# --------------------------------------------------------------------------- #
# JSON Schema 片段
# --------------------------------------------------------------------------- #

COORD_NOTE = "世界座標 [x, y, z]，單位公尺，Y 軸朝上"


def vec3(description: str) -> dict:
    return {
        "type": "array",
        "items": {"type": "number"},
        "minItems": 3,
        "maxItems": 3,
        "description": description,
    }


def color(description: str) -> dict:
    return {
        "type": "string",
        "pattern": "^#[0-9a-fA-F]{6}$",
        "description": description,
    }


def schema(properties: dict, required: list[str] | None = None) -> dict:
    return {
        "type": "object",
        "properties": properties,
        "required": required or [],
        "additionalProperties": False,
    }


_POS = vec3(f"位置，{COORD_NOTE}")
_ROT = vec3("旋轉 [x, y, z]，單位為度（Euler，Y 為水平轉向）")
_SCALE = vec3("縮放倍率 [x, y, z]，1 為原始大小（建議改用 size 直接指定公尺）")
_MOTION_PROPS = {
    "auto_ground": {
        "type": "boolean",
        "description": "自動放在下方物件上（預設開啟）：高度自動貼合腳下最高的物件頂面或地板，可直接疊放；給了 pos 的 y>0 會自動關閉",
    },
    "path": {
        "type": "array",
        "items": vec3("路徑點的世界座標 [x, y, z]"),
        "description": "移動路線：依序經過的世界座標點（起點＝物件目前位置，不用包含）。給空陣列＝清除路線",
    },
    "path_mode": {
        "type": "string",
        "enum": ["none", "once", "loop", "pingpong"],
        "description": "路線模式：none 不移動、once 走到終點停、loop 走回起點循環、pingpong 來回往復",
    },
    "path_speed": {"type": "number", "minimum": 0.01, "description": "移動速度（m/s），人走路約 1.2、跑步約 3"},
    "face_motion": {"type": "boolean", "description": "物件轉向前進方向（物件正面為 +Z），人偶走路建議開啟"},
}
_SIZE = vec3("實際尺寸 [寬 x, 高 y, 深 z]，單位公尺（優先於 scale）。例：門 [0.9, 2.1, 0.05]、桌子 [1.2, 0.75, 0.7]")

OBJECT_TYPES = [
    "box",
    "sphere",
    "cylinder",
    "capsule",
    "cone",
    "torus",
    "slab",
    "wall",
    "stairs",
    "mannequin",
    "light",
]


# --------------------------------------------------------------------------- #
# 工具定義：name 同時就是 Godot 端的 method 名稱
# --------------------------------------------------------------------------- #

TOOLS: list[dict] = [
    {
        "name": "get_scene",
        "description": (
            "讀取 ShotPilot 目前的完整場景狀態，是所有操作的第一步。"
            "回傳 objects（每個物件的 name/type/pos/rot/scale/color）、camera（手機鏡頭的 pos/rot/fov）、"
            "env（環境設定）、waypoints（運鏡記錄點）、takes（已產生的鏡頭片段）、"
            "object_types（可用物件型別與中文名）。\n"
            "座標系：世界座標單位公尺、Y 軸朝上、旋轉單位為度。物件以唯一的 name 辨識。\n"
            "典型用法：先 get_scene 了解場景與既有物件名稱，再 add_object / update_object，"
            "最後用 screenshot 驗證結果。"
        ),
        "inputSchema": schema({}),
    },
    {
        "name": "screenshot",
        "description": (
            "擷取畫面並直接回傳 PNG 圖片，用來「親眼確認」場景改動的結果。\n"
            "view=\"editor\"：編輯器全局觀察視角（看得到整個場景、含 UI 與輔助線框），"
            "適合檢查物件擺位；可先用 set_editor_view 調整角度與距離。\n"
            "view=\"camera\"：手機鏡頭實際拍到的畫面，適合檢查構圖與打光。\n"
            "每次修改場景後都建議截一張圖確認，不要只憑數值猜測。"
        ),
        "inputSchema": schema(
            {
                "view": {
                    "type": "string",
                    "enum": ["editor", "camera"],
                    "description": "editor＝編輯器全局視角（含 UI）；camera＝手機鏡頭畫面",
                },
                "long_side": {
                    "type": "integer",
                    "minimum": 64,
                    "maximum": 4096,
                    "description": "輸出圖片長邊像素，預設由 App 決定（約 960）。想看細節再調大",
                },
            },
            ["view"],
        ),
    },
    {
        "name": "add_object",
        "description": (
            "在場景中新增一個物件並回傳它的 name（未指定 name 時由 App 自動命名，後續要改它就用這個 name）。\n"
            "type 可用：box 方塊、sphere 球、cylinder 圓柱、capsule 膠囊、cone 圓錐、torus 環、"
            "slab 板（當地面或桌面）、wall 牆、stairs 樓梯、mannequin 人偶（概略人形，用來抓比例與站位）、"
            "light 燈光（用 update_object 的 energy/range 調強度與範圍）。\n"
            "座標單位公尺、Y 軸朝上（pos=[0,0,0] 是地面原點，物件通常擺在 y>=0）；rot 單位為度。\n"
            "建議流程：get_scene 看現況 → add_object → screenshot 確認。"
        ),
        "inputSchema": schema(
            {
                "type": {
                    "type": "string",
                    "enum": OBJECT_TYPES,
                    "description": "物件型別",
                },
                "name": {
                    "type": "string",
                    "description": "唯一名稱，後續 update_object / delete_object 用它辨識；省略則自動命名",
                },
                "pos": _POS,
                "rot": _ROT,
                "scale": _SCALE,
                "size": _SIZE,
                **_MOTION_PROPS,
                "color": color("顏色 \"#rrggbb\"，例如 \"#cc3344\""),
            },
            ["type"],
        ),
    },
    {
        "name": "update_object",
        "description": (
            "修改既有物件（以 name 指定）。只送要改的欄位，沒送的保持原值。\n"
            "rename 可改名稱（改完之後要用新名字）。roughness/metallic 是材質參數（0~1）；"
            "energy/range 只對 type=light 的燈光有效。\n"
            "不確定物件叫什麼名字時，先 get_scene 取得 objects 清單。"
        ),
        "inputSchema": schema(
            {
                "name": {"type": "string", "description": "要修改的物件名稱"},
                "pos": _POS,
                "rot": _ROT,
                "scale": _SCALE,
                "size": _SIZE,
                **_MOTION_PROPS,
                "color": color("顏色 \"#rrggbb\"；燈光則是光的顏色"),
                "rename": {"type": "string", "description": "新名稱（改名用）"},
                "roughness": {
                    "type": "number",
                    "minimum": 0,
                    "maximum": 1,
                    "description": "材質粗糙度，0＝鏡面、1＝全霧面",
                },
                "metallic": {
                    "type": "number",
                    "minimum": 0,
                    "maximum": 1,
                    "description": "金屬度，0＝非金屬、1＝金屬",
                },
                "energy": {
                    "type": "number",
                    "minimum": 0,
                    "description": "燈光強度（type=light 專用）",
                },
                "range": {
                    "type": "number",
                    "minimum": 0,
                    "description": "燈光照射範圍，單位公尺（type=light 專用）",
                },
            },
            ["name"],
        ),
    },
    {
        "name": "delete_object",
        "description": "刪除指定名稱的物件。名稱可從 get_scene 的 objects 取得。",
        "inputSchema": schema(
            {"name": {"type": "string", "description": "要刪除的物件名稱"}},
            ["name"],
        ),
    },
    {
        "name": "clear_scene",
        "description": (
            "清空場景裡所有物件（不會動到環境設定、鏡頭與記錄點）。"
            "這個動作無法復原，要重新搭場景前才用；只想刪一個物件請用 delete_object。"
        ),
        "inputSchema": schema({}),
    },
    {
        "name": "set_camera",
        "description": (
            "設定手機鏡頭（實際拍攝用的 Camera3D）。回傳套用後的 pos/rot/fov。\n"
            "指定朝向有兩種方式：rot 直接給 Euler 角（度），或 look_at 給一個要對準的世界座標點"
            "（給了 look_at 就不必再給 rot）。fov 是垂直視角（度），數字小＝望遠＝壓縮空間，大＝廣角。\n"
            "調完鏡頭用 screenshot(view=\"camera\") 看構圖；滿意就 add_waypoint 把這個機位記下來。"
        ),
        "inputSchema": schema(
            {
                "pos": vec3(f"鏡頭位置，{COORD_NOTE}"),
                "rot": _ROT,
                "look_at": vec3(f"要對準的目標點，{COORD_NOTE}（與 rot 二選一）"),
                "fov": {
                    "type": "number",
                    "minimum": 1,
                    "maximum": 179,
                    "description": "垂直視角（度），一般 30~75",
                },
            }
        ),
    },
    {
        "name": "set_editor_view",
        "description": (
            "調整編輯器全局觀察視角（只影響 screenshot(view=\"editor\") 看到的畫面，"
            "不會動到手機鏡頭）。環繞式鏡頭：focus 是環繞中心、distance 是距離（公尺）、"
            "yaw 是水平角、pitch 是俯角（度，正值＝從上往下看）。\n"
            "想從別的角度檢查擺位時先呼叫它，再 screenshot。"
        ),
        "inputSchema": schema(
            {
                "focus": vec3(f"觀察中心點，{COORD_NOTE}"),
                "distance": {
                    "type": "number",
                    "minimum": 0,
                    "description": "鏡頭到中心點的距離，單位公尺",
                },
                "yaw": {"type": "number", "description": "水平環繞角度（度）"},
                "pitch": {
                    "type": "number",
                    "description": "俯仰角（度），正值＝由上往下俯視",
                },
            }
        ),
    },
    {
        "name": "set_environment",
        "description": (
            "設定環境：太陽、天空、背景、環境光、霧、地板與陰影。只送要改的欄位，回傳套用後的完整 env。\n"
            "sun_elev 是太陽仰角（度，0＝地平線、90＝正上方，低角度＝日出日落的長影子）；"
            "sun_azim 是方位角（度）；sun_energy 是日照強度。\n"
            "sky=false 時用 bg_color 當純色背景；floor 控制是否顯示地板，floor_size 是地板邊長（公尺）。\n"
            "改完用 screenshot 驗證光影方向。"
        ),
        "inputSchema": schema(
            {
                "sun_elev": {
                    "type": "number",
                    "minimum": -90,
                    "maximum": 90,
                    "description": "太陽仰角（度），0＝地平線、90＝頭頂",
                },
                "sun_azim": {"type": "number", "description": "太陽方位角（度）"},
                "sun_energy": {
                    "type": "number",
                    "minimum": 0,
                    "description": "日照強度，1 為一般值",
                },
                "sun_color": color("陽光顏色 \"#rrggbb\""),
                "sky": {"type": "boolean", "description": "true＝程序天空，false＝純色背景"},
                "sky_top": color("天頂顏色 \"#rrggbb\""),
                "sky_horizon": color("地平線附近的天空顏色 \"#rrggbb\""),
                "bg_color": color("背景色 \"#rrggbb\"（sky=false 時生效）"),
                "ambient": {
                    "type": "number",
                    "minimum": 0,
                    "description": "環境光強度，越大陰影越亮",
                },
                "fog": {"type": "number", "minimum": 0, "description": "霧的濃度，0＝無霧"},
                "floor": {"type": "boolean", "description": "是否顯示地板"},
                "floor_color": color("地板顏色 \"#rrggbb\""),
                "floor_size": {
                    "type": "number",
                    "minimum": 0,
                    "description": "地板邊長，單位公尺",
                },
                "shadows": {"type": "boolean", "description": "是否開啟陰影"},
            }
        ),
    },
    {
        "name": "add_waypoint",
        "description": (
            "把一個機位加進運鏡記錄點清單，回傳目前累積的點數 count。\n"
            "不給任何參數＝直接記下「目前手機鏡頭」的位置、角度與 fov（最常用：set_camera 調好構圖 → add_waypoint）。\n"
            "也可以直接給 pos/rot（或 look_at）/fov 指定一個機位。\n"
            "記滿兩個點以上就能用 create_auto_take 產生平滑運鏡。"
        ),
        "inputSchema": schema(
            {
                "pos": vec3(f"機位位置，{COORD_NOTE}；省略則用目前鏡頭位置"),
                "rot": _ROT,
                "look_at": vec3(f"要對準的目標點，{COORD_NOTE}（與 rot 二選一）"),
                "fov": {
                    "type": "number",
                    "minimum": 1,
                    "maximum": 179,
                    "description": "該機位的垂直視角（度）",
                },
            }
        ),
    },
    {
        "name": "apply_preset",
        "description": (
            "套用內建範本，快速建立場景。kind：\n"
            "- scene：整個換掉（物件＋燈光＋機位）：空白攝影棚、客廳、街道巷口、辦公室、公園、走廊、舞台\n"
            "- lighting：只換環境光：晴天正午、黃昏斜陽、清晨薄霧、陰天、夜晚、攝影棚、綠幕\n"
            "- camera：以主角為準擺鏡頭（從主角正面 +Z 拍）：特寫、中景、全身、大遠景、低角度仰拍、高角度俯拍、側面、過肩、鳥瞰；"
            "subject 指定主角物件名稱，省略時用目前選取或第一個人偶。\n"
            "典型流程：apply_preset(scene) → 微調物件 → apply_preset(camera) → screenshot(camera) 確認。"
        ),
        "inputSchema": schema(
            {
                "kind": {"type": "string", "enum": ["scene", "lighting", "camera"], "description": "範本類型"},
                "name": {"type": "string", "description": "範本名稱（見說明；get_scene 的 presets 也有清單）"},
                "subject": {"type": "string", "description": "camera 範本的主角物件名稱（選填）"},
            },
            ["kind", "name"],
        ),
    },
    {
        "name": "play_objects",
        "description": (
            "控制物件的移動路線動畫（用 add_object/update_object 的 path、path_mode 設定）。\n"
            "play=true 播放、false 暫停；reset=true 回到起點；time=秒數 直接跳到某個時間點（方便 screenshot 檢查某一刻）。\n"
            "錄製、回放 take、匯出影片時物件會自動與鏡頭同步，不需要手動播放。"
        ),
        "inputSchema": schema(
            {
                "play": {"type": "boolean", "description": "播放或暫停"},
                "reset": {"type": "boolean", "description": "回到起點（時間 0）"},
                "time": {"type": "number", "minimum": 0, "description": "跳到指定時間（秒）並停住"},
            }
        ),
    },
    {
        "name": "clear_waypoints",
        "description": "清掉所有運鏡記錄點，重新規劃路徑時用（不影響已產生的 takes）。",
        "inputSchema": schema({}),
    },
    {
        "name": "create_auto_take",
        "description": (
            "依照目前的運鏡記錄點產生一段平滑的自動運鏡（take），回傳 name 與 length（秒）。\n"
            "duration 是整段時長（秒），點與點之間會自動分配；ease=true 讓頭尾加減速（較電影感），"
            "false 則等速。至少要有 2 個 waypoint。\n"
            "產生後可用 play_take 在 App 裡預覽，確認無誤再 export_take 輸出影格。"
        ),
        "inputSchema": schema(
            {
                "duration": {
                    "type": "number",
                    "minimum": 0,
                    "description": "整段運鏡長度，單位秒",
                },
                "name": {"type": "string", "description": "take 名稱，省略則自動命名"},
                "ease": {
                    "type": "boolean",
                    "description": "true＝頭尾平滑加減速，false＝等速",
                },
            }
        ),
    },
    {
        "name": "play_take",
        "description": (
            "在 ShotPilot 裡播放指定的 take 以預覽運鏡（名稱可從 get_scene 的 takes 取得）。"
            "這是畫面上的即時播放，不會產生檔案；要輸出檔案請用 export_take。"
        ),
        "inputSchema": schema(
            {"name": {"type": "string", "description": "要播放的 take 名稱"}},
            ["name"],
        ),
    },
    {
        "name": "export_take",
        "description": (
            "把 take 算圖輸出成影格檔案，回傳 out_dir 與 files 清單。\n"
            "※ 這個操作可能跑好幾分鐘（解析度與 fps 越高越久），期間 App 會忙碌，請耐心等它回來，不要重複呼叫。\n"
            "long_side 是長邊像素（960/1280/1920/2560）、fps 24/30/60、depth=true 會額外輸出深度圖、"
            "aspect 是畫面寬高比（例如 1.777 代表 16:9，0.5625 代表直式 9:16）。\n"
            "建議先 play_take 預覽、先用 960 試算，確認構圖沒問題再輸出高解析度。"
        ),
        "inputSchema": schema(
            {
                "name": {"type": "string", "description": "要輸出的 take 名稱"},
                "long_side": {
                    "type": "integer",
                    "enum": [960, 1280, 1920, 2560],
                    "description": "輸出長邊像素",
                },
                "fps": {
                    "type": "integer",
                    "enum": [24, 30, 60],
                    "description": "每秒影格數",
                },
                "depth": {"type": "boolean", "description": "是否同時輸出深度圖"},
                "keep_png": {"type": "boolean", "description": "是否另外保留逐幀 PNG（預設否，只輸出 mp4；PNG 非常佔硬碟）"},
                "aspect": {
                    "type": "number",
                    "minimum": 0,
                    "description": "畫面寬高比（寬/高），16:9＝1.7778、9:16＝0.5625",
                },
            },
            ["name"],
        ),
    },
    {
        "name": "save_scene",
        "description": (
            "把目前場景存成檔案，回傳實際存檔的 path。省略 path 則存到 App 的預設位置。"
            "大改場景之前先存一份比較安全。"
        ),
        "inputSchema": schema(
            {"path": {"type": "string", "description": "存檔路徑，省略則用預設位置"}}
        ),
    },
    {
        "name": "load_scene",
        "description": (
            "從檔案載入場景，會取代目前場景的內容（無法復原，必要時先 save_scene）。"
            "載入後建議 get_scene 重新確認物件名稱。"
        ),
        "inputSchema": schema(
            {"path": {"type": "string", "description": "要載入的場景檔路徑"}},
            ["path"],
        ),
    },
]

TOOLS_BY_NAME = {t["name"]: t for t in TOOLS}


# --------------------------------------------------------------------------- #
# 參數驗證（依工具自己的 JSON Schema 做必要檢查）
# --------------------------------------------------------------------------- #

_TYPE_NAMES = {
    "object": "物件",
    "array": "陣列",
    "string": "字串",
    "number": "數字",
    "integer": "整數",
    "boolean": "布林值",
}


def _type_ok(value, json_type: str) -> bool:
    if json_type == "object":
        return isinstance(value, dict)
    if json_type == "array":
        return isinstance(value, list)
    if json_type == "string":
        return isinstance(value, str)
    if json_type == "boolean":
        return isinstance(value, bool)
    if json_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if json_type == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return True


class ValidationError(Exception):
    pass


def _check_value(name: str, value, spec: dict) -> None:
    json_type = spec.get("type")
    if json_type and not _type_ok(value, json_type):
        raise ValidationError(
            f"參數 {name} 必須是{_TYPE_NAMES.get(json_type, json_type)}，收到 {type(value).__name__}"
        )
    if "enum" in spec and value not in spec["enum"]:
        allowed = "、".join(json.dumps(v, ensure_ascii=False) for v in spec["enum"])
        raise ValidationError(f"參數 {name} 只能是 {allowed}，收到 {value!r}")
    if json_type == "array":
        if "minItems" in spec and len(value) < spec["minItems"]:
            raise ValidationError(f"參數 {name} 至少要 {spec['minItems']} 個元素")
        if "maxItems" in spec and len(value) > spec["maxItems"]:
            raise ValidationError(f"參數 {name} 最多 {spec['maxItems']} 個元素")
        item_spec = spec.get("items")
        if item_spec:
            for i, item in enumerate(value):
                _check_value(f"{name}[{i}]", item, item_spec)
    if json_type in ("number", "integer"):
        if "minimum" in spec and value < spec["minimum"]:
            raise ValidationError(f"參數 {name} 不可小於 {spec['minimum']}")
        if "maximum" in spec and value > spec["maximum"]:
            raise ValidationError(f"參數 {name} 不可大於 {spec['maximum']}")
    if json_type == "string" and spec.get("pattern") == "^#[0-9a-fA-F]{6}$":
        if len(value) != 7 or not value.startswith("#") or not all(
            c in "0123456789abcdefABCDEF" for c in value[1:]
        ):
            raise ValidationError(f"參數 {name} 必須是 \"#rrggbb\" 格式，收到 {value!r}")


def validate_arguments(tool: dict, args: dict) -> dict:
    """照工具 schema 檢查參數，回傳清掉 None 之後的 params。"""
    if not isinstance(args, dict):
        raise ValidationError("arguments 必須是物件")
    spec = tool["inputSchema"]
    props = spec.get("properties", {})
    cleaned = {k: v for k, v in args.items() if v is not None}
    for key in spec.get("required", []):
        if key not in cleaned:
            raise ValidationError(f"缺少必要參數 {key}")
    for key, value in cleaned.items():
        if key not in props:
            known = "、".join(props) or "（無）"
            raise ValidationError(f"不支援的參數 {key}；可用參數：{known}")
        _check_value(key, value, props[key])
    return cleaned


# --------------------------------------------------------------------------- #
# 與 Godot 端通訊
# --------------------------------------------------------------------------- #


class GodotError(Exception):
    """Godot 端明確回報的錯誤（ok:false）或連線／傳輸層失敗。"""


def call_godot(method: str, params: dict, timeout: float) -> object:
    body = json.dumps({"method": method, "params": params}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        GODOT_URL,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    log(f"→ {method} params={json.dumps(params, ensure_ascii=False)} timeout={timeout:g}s")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:  # 伺服器有回，但是 4xx/5xx
        detail = ""
        try:
            payload = json.loads(exc.read().decode("utf-8", "replace"))
            detail = str(payload.get("error") or payload)
        except Exception:
            pass
        raise GodotError(
            f"ShotPilot 回傳 HTTP {exc.code}" + (f"：{detail}" if detail else "")
        ) from exc
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, socket.timeout):
            raise GodotError(
                f"等 ShotPilot 回應超過 {timeout:g} 秒（method={method}）。"
                "若是長時間算圖請稍後再查詢，或用環境變數 SHOTPILOT_EXPORT_TIMEOUT 加長。"
            ) from exc
        raise GodotError(NOT_RUNNING_HINT.format(url=GODOT_URL) + f"（{reason}）") from exc
    except socket.timeout as exc:
        raise GodotError(
            f"等 ShotPilot 回應超過 {timeout:g} 秒（method={method}）。"
        ) from exc
    except OSError as exc:
        raise GodotError(NOT_RUNNING_HINT.format(url=GODOT_URL) + f"（{exc}）") from exc

    try:
        payload = json.loads(raw.decode("utf-8", "replace"))
    except json.JSONDecodeError as exc:
        snippet = raw[:200].decode("utf-8", "replace")
        raise GodotError(f"ShotPilot 回傳的不是 JSON：{snippet!r}") from exc

    if not isinstance(payload, dict):
        raise GodotError(f"ShotPilot 回傳格式不正確：{payload!r}")
    if not payload.get("ok"):
        raise GodotError(str(payload.get("error") or "ShotPilot 回報未知錯誤"))
    return payload.get("result")


# --------------------------------------------------------------------------- #
# tools/call 結果格式化
# --------------------------------------------------------------------------- #


def text_result(text: str, is_error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def format_screenshot(result: object) -> dict:
    if not isinstance(result, dict) or not result.get("png_base64"):
        raise GodotError("screenshot 回傳缺少 png_base64")
    data = result["png_base64"]
    if not isinstance(data, str):
        raise GodotError("screenshot 的 png_base64 必須是字串")
    data = data.strip()
    # data URI 前綴（data:image/png;base64,...）一併容許，方便 Godot 端實作。
    if data.startswith("data:"):
        data = data.split(",", 1)[-1]
    try:
        base64.b64decode(data, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise GodotError(f"screenshot 的 png_base64 不是合法 base64：{exc}") from exc
    width = result.get("width")
    height = result.get("height")
    size = f"{width}x{height}" if width and height else "未知尺寸"
    extra = {
        k: v for k, v in result.items() if k not in ("png_base64", "width", "height")
    }
    note = f"PNG 截圖，尺寸 {size} 像素。"
    if extra:
        note += "其他資訊：" + json.dumps(extra, ensure_ascii=False)
    return {
        "content": [
            {"type": "image", "data": data, "mimeType": "image/png"},
            {"type": "text", "text": note},
        ],
        "isError": False,
    }


def format_result(name: str, result: object) -> dict:
    if name == "screenshot":
        return format_screenshot(result)
    if result is None or result == {} or result == []:
        return text_result(f"{name} 完成。")
    if isinstance(result, str):
        return text_result(result)
    return text_result(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=False))


def handle_tool_call(params: dict) -> dict:
    name = params.get("name")
    if not isinstance(name, str) or name not in TOOLS_BY_NAME:
        available = "、".join(TOOLS_BY_NAME)
        return text_result(f"沒有名為 {name!r} 的工具。可用工具：{available}", True)
    tool = TOOLS_BY_NAME[name]
    args = params.get("arguments") or {}
    try:
        cleaned = validate_arguments(tool, args)
    except ValidationError as exc:
        log(f"參數錯誤 {name}: {exc}")
        return text_result(f"參數錯誤：{exc}", True)
    try:
        result = call_godot(name, cleaned, TOOL_TIMEOUTS.get(name, DEFAULT_TIMEOUT))
        formatted = format_result(name, result)
    except GodotError as exc:
        log(f"← {name} 失敗: {exc}")
        return text_result(f"{name} 失敗：{exc}", True)
    except Exception as exc:  # 不讓任何意外把伺服器打掉
        log(f"← {name} 發生未預期錯誤: {exc!r}")
        return text_result(f"{name} 發生未預期錯誤：{exc}", True)
    log(f"← {name} ok")
    return formatted


# --------------------------------------------------------------------------- #
# JSON-RPC / MCP 層
# --------------------------------------------------------------------------- #


def handle_initialize(params: dict) -> dict:
    requested = params.get("protocolVersion")
    version = requested if isinstance(requested, str) and requested else DEFAULT_PROTOCOL_VERSION
    client = params.get("clientInfo") or {}
    log(f"initialize：client={client.get('name')} {client.get('version')} protocol={version}")
    return {
        "protocolVersion": version,
        "capabilities": {"tools": {}},
        "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
    }


def dispatch(method: str, params: dict) -> dict:
    """回傳 JSON-RPC 的 result；要回 error 就 raise RpcError。"""
    if method == "initialize":
        return handle_initialize(params)
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return handle_tool_call(params)
    raise RpcError(-32601, f"Method not found: {method}")


class RpcError(Exception):
    def __init__(self, code: int, message: str, data: object = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


def send(message: dict, out=None) -> None:
    out = out or sys.stdout
    out.write(json.dumps(message, ensure_ascii=False) + "\n")
    out.flush()


def error_response(rid, code: int, message: str, data: object = None) -> dict:
    err: dict = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    return {"jsonrpc": "2.0", "id": rid, "error": err}


def handle_line(line: str) -> dict | None:
    """處理一行 JSON-RPC；回傳要送出的回應，通知則回 None。"""
    try:
        msg = json.loads(line)
    except json.JSONDecodeError as exc:
        log(f"JSON 解析失敗：{exc}")
        return error_response(None, -32700, f"Parse error: {exc}")

    if not isinstance(msg, dict):
        return error_response(None, -32600, "Invalid Request: 必須是 JSON 物件")

    # 客戶端送來的回應（有 result/error 又有 id）不需理會。
    if "method" not in msg:
        if "result" in msg or "error" in msg:
            log(f"忽略客戶端回應 id={msg.get('id')}")
            return None
        return error_response(msg.get("id"), -32600, "Invalid Request: 缺少 method")

    method = msg.get("method")
    rid = msg.get("id", None)
    is_notification = "id" not in msg or msg.get("id") is None
    params = msg.get("params")
    if params is None:
        params = {}
    if not isinstance(params, dict):
        if is_notification:
            return None
        return error_response(rid, -32602, "Invalid params: params 必須是物件")

    if is_notification:
        # notifications/initialized、notifications/cancelled 等都不回應。
        log(f"notification: {method}")
        return None

    try:
        result = dispatch(method, params)
    except RpcError as exc:
        log(f"method 錯誤 {method}: {exc.message}")
        return error_response(rid, exc.code, exc.message, exc.data)
    except Exception as exc:
        log(f"internal error {method}: {exc!r}")
        return error_response(rid, -32603, f"Internal error: {exc}")
    return {"jsonrpc": "2.0", "id": rid, "result": result}


def main() -> int:
    log(f"啟動：轉發到 {GODOT_URL}（export_take timeout {LONG_TIMEOUT:g}s，其他 {DEFAULT_TIMEOUT:g}s）")
    try:
        sys.stdout.reconfigure(encoding="utf-8", newline="\n")
        sys.stdin.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass
    while True:
        line = sys.stdin.readline()
        if line == "":
            log("stdin 關閉，結束。")
            return 0
        line = line.strip()
        if not line:
            continue
        response = handle_line(line)
        if response is not None:
            send(response)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
