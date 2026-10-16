class_name ScenePresets
extends RefCounted
## 內建範本：場景（物件＋燈光＋機位）、燈光（環境）、機位（相對主角）。
## 物件格式同 StudioShape.to_dict()，另可用 "size": [寬, 高, 深]（公尺）。
## 物件的「正面」是 +Z：機位預設從主角的 +Z 方向拍。

const LIGHTING := {
	"晴天正午": {"sun_elev": 68.0, "sun_azim": 30.0, "sun_energy": 1.3, "sun_color": "fff6e8", "sky": true,
		"sky_top": "4f7fc0", "sky_horizon": "c4d6e8", "ambient": 1.0, "fog": 0.0, "shadows": true},
	"黃昏斜陽": {"sun_elev": 8.0, "sun_azim": -60.0, "sun_energy": 1.6, "sun_color": "ffa860", "sky": true,
		"sky_top": "3c4f8a", "sky_horizon": "ffb37a", "ambient": 0.7, "fog": 0.01, "shadows": true},
	"清晨薄霧": {"sun_elev": 12.0, "sun_azim": 120.0, "sun_energy": 0.9, "sun_color": "ffe2c4", "sky": true,
		"sky_top": "8fa9c9", "sky_horizon": "e9d9cf", "ambient": 0.9, "fog": 0.04, "shadows": true},
	"陰天": {"sun_elev": 60.0, "sun_azim": 10.0, "sun_energy": 0.35, "sun_color": "e8eef5", "sky": true,
		"sky_top": "9aa4ae", "sky_horizon": "c9ced3", "ambient": 1.4, "fog": 0.015, "shadows": false},
	"夜晚": {"sun_elev": 35.0, "sun_azim": -20.0, "sun_energy": 0.12, "sun_color": "9db4ff", "sky": true,
		"sky_top": "070b1c", "sky_horizon": "1c2340", "ambient": 0.2, "fog": 0.02, "shadows": true},
	"攝影棚": {"sun_elev": 55.0, "sun_azim": 35.0, "sun_energy": 1.0, "sun_color": "ffffff", "sky": false,
		"bg_color": "2a2a30", "ambient": 0.8, "fog": 0.0, "shadows": true},
	"綠幕": {"sun_elev": 50.0, "sun_azim": 20.0, "sun_energy": 0.8, "sun_color": "ffffff", "sky": false,
		"bg_color": "00b140", "floor_color": "00b140", "ambient": 1.2, "fog": 0.0, "shadows": false},
}

const CAMERAS := ["特寫", "中景", "全身", "大遠景", "低角度仰拍", "高角度俯拍", "側面", "過肩", "鳥瞰"]


## 主角：pos＝底部中心、height＝高度、front／right＝水平的正面與右方
static func camera_for(preset: String, pos: Vector3, height: float, front: Vector3, right: Vector3) -> Dictionary:
	var h := maxf(height, 0.3)
	var eye := pos + Vector3.UP * minf(h * 0.9, 1.6)
	var cam := pos + front * 3.0 + Vector3.UP * 1.5
	var look := pos + Vector3.UP * h * 0.6
	var fov := 45.0
	match preset:
		"特寫":
			look = pos + Vector3.UP * h * 0.9
			cam = look + front * maxf(h * 0.55, 0.6)
			fov = 35.0
		"中景":
			look = pos + Vector3.UP * h * 0.7
			cam = pos + front * maxf(h * 1.4, 1.5) + Vector3.UP * h * 0.8
			fov = 40.0
		"全身":
			look = pos + Vector3.UP * h * 0.5
			cam = pos + front * maxf(h * 2.3, 2.5) + Vector3.UP * h * 0.65
			fov = 45.0
		"大遠景":
			look = pos + Vector3.UP * h * 0.5
			cam = pos + front * maxf(h * 6.0, 8.0) + Vector3.UP * maxf(h * 1.5, 2.5)
			fov = 50.0
		"低角度仰拍":
			look = pos + Vector3.UP * h * 0.8
			cam = pos + front * maxf(h * 1.5, 1.8) + Vector3.UP * 0.3
			fov = 50.0
		"高角度俯拍":
			look = pos + Vector3.UP * h * 0.3
			cam = pos + front * maxf(h * 1.6, 2.0) + Vector3.UP * maxf(h * 2.4, 3.5)
			fov = 45.0
		"側面":
			look = pos + Vector3.UP * h * 0.65
			cam = pos + right * maxf(h * 2.0, 2.5) + Vector3.UP * h * 0.75
			fov = 42.0
		"過肩":
			# 站在主角右後方，越過肩膀往前拍
			cam = pos - front * 0.7 + right * 0.4 + Vector3.UP * minf(h * 0.95, 1.65)
			look = eye + front * 3.0 - Vector3.UP * 0.1
			fov = 45.0
		"鳥瞰":
			look = pos
			cam = pos + Vector3.UP * maxf(h * 5.0, 8.0) + front * 0.01
			fov = 50.0
	return {"xf": Transform3D(Basis(), cam).looking_at(look, Vector3.UP), "fov": fov}


static func scene_names() -> Array:
	return scenes().keys()


static func scenes() -> Dictionary:
	return {
		"空白攝影棚": {
			"lighting": "攝影棚", "env": {"floor_color": "3a3a40"},
			"camera": {"pos": [0, 1.5, 3.2], "look_at": [0, 1.1, 0], "fov": 40},
			"objects": [
				_o("mannequin", "人物", [0, 0, 0], "3a3a40"),
				_o("light", "主燈", [-1.8, 2.4, 1.6], "fff1dc", {"energy": 3.0, "range": 7.0}),
				_o("light", "輪廓光", [1.5, 2.2, -1.5], "c8d8ff", {"energy": 2.0, "range": 6.0}),
			],
		},
		"客廳": {
			"lighting": "晴天正午", "env": {"floor_color": "8a6f55"},
			"camera": {"pos": [1.8, 1.5, 3.6], "look_at": [0, 0.9, -0.5], "fov": 45},
			"objects": [
				_o("wall", "後牆", [0, 0, -2.5], "e8e2d6", {"size": [7, 2.8, 0.15]}),
				_o("wall", "左牆", [-3.5, 0, 0.5], "ded7c9", {"size": [6, 2.8, 0.15], "rot": [0, 90, 0]}),
				_o("box", "沙發座", [0, 0, -1.8], "6b7a8f", {"size": [2.2, 0.45, 0.9]}),
				_o("box", "沙發背", [0, 0.45, -2.15], "5f6e83", {"size": [2.2, 0.45, 0.2]}),
				_o("box", "沙發扶手L", [-1.0, 0.45, -1.8], "5f6e83", {"size": [0.2, 0.2, 0.9]}),
				_o("box", "沙發扶手R", [1.0, 0.45, -1.8], "5f6e83", {"size": [0.2, 0.2, 0.9]}),
				_o("box", "茶几", [0, 0, -0.5], "4a3a2c", {"size": [1.1, 0.42, 0.6]}),
				_o("box", "電視櫃", [0, 0, 1.6], "3a3330", {"size": [1.8, 0.5, 0.45]}),
				_o("box", "電視", [0, 0.5, 1.7], "151518", {"size": [1.4, 0.8, 0.06]}),
				_o("cylinder", "立燈桿", [-2.6, 0, -1.9], "2d2d2d", {"size": [0.06, 1.6, 0.06]}),
				_o("cone", "燈罩", [-2.6, 1.45, -1.9], "f1e3c8", {"size": [0.45, 0.35, 0.45]}),
				_o("light", "立燈光", [-2.6, 1.35, -1.9], "ffd9a0", {"energy": 2.0, "range": 5.0}),
				_o("mannequin", "人物", [0.6, 0, 0.3], "333338", {"rot": [0, 160, 0]}),
			],
		},
		"街道巷口": {
			"lighting": "黃昏斜陽", "env": {"floor_color": "55555a"},
			"camera": {"pos": [0.3, 0.6, 6.0], "look_at": [0, 1.2, 0], "fov": 40},
			"objects": [
				_o("box", "左側建築", [-2.6, 0, -3], "8c7f75", {"size": [3, 7, 14]}),
				_o("box", "右側建築", [2.6, 0, -3], "9a8a7a", {"size": [3, 6, 14]}),
				_o("slab", "人行道L", [-0.8, 0, -3], "77777c", {"size": [0.6, 0.15, 14]}),
				_o("slab", "人行道R", [0.8, 0, -3], "77777c", {"size": [0.6, 0.15, 14]}),
				_o("cylinder", "垃圾桶", [0.85, 0.15, 0.8], "3b5f45", {"size": [0.5, 0.9, 0.5]}),
				_o("box", "紙箱1", [-0.85, 0.15, -1.5], "a9845a", {"size": [0.6, 0.45, 0.5]}),
				_o("box", "紙箱2", [-0.8, 0.6, -1.45], "b8935f", {"size": [0.45, 0.35, 0.4], "rot": [0, 20, 0]}),
				_o("cylinder", "路燈桿", [0.9, 0.15, -4], "2a2a2a", {"size": [0.1, 3.6, 0.1]}),
				_o("light", "路燈", [0.6, 3.6, -4], "ffc27a", {"energy": 4.0, "range": 8.0}),
				_o("mannequin", "人物", [0, 0, 0], "2e2e33"),
			],
		},
		"辦公室": {
			"lighting": "陰天", "env": {"floor_color": "6f7378"},
			"camera": {"pos": [2.5, 1.6, 3.2], "look_at": [0, 0.9, -0.5], "fov": 45},
			"objects": [
				_o("wall", "後牆", [0, 0, -3], "dfe3e6", {"size": [8, 3, 0.15]}),
				_o("wall", "玻璃隔間", [-3, 0, 0], "b8d4e6", {"size": [6, 3, 0.08], "rot": [0, 90, 0], "roughness": 0.1, "metallic": 0.3}),
				_o("box", "辦公桌1", [-0.9, 0, -1.2], "c9b79c", {"size": [1.4, 0.75, 0.7]}),
				_o("box", "辦公桌2", [0.9, 0, -1.2], "c9b79c", {"size": [1.4, 0.75, 0.7]}),
				_o("box", "螢幕1", [-0.9, 0.75, -1.4], "1b1b1e", {"size": [0.6, 0.38, 0.04]}),
				_o("box", "螢幕2", [0.9, 0.75, -1.4], "1b1b1e", {"size": [0.6, 0.38, 0.04]}),
				_o("box", "椅子1", [-0.9, 0, -0.5], "2f3a4a", {"size": [0.5, 0.9, 0.5]}),
				_o("box", "椅子2", [0.9, 0, -0.5], "2f3a4a", {"size": [0.5, 0.9, 0.5]}),
				_o("light", "吸頂燈1", [-1, 2.8, -1], "f4f8ff", {"energy": 2.0, "range": 6.0}),
				_o("light", "吸頂燈2", [1, 2.8, -1], "f4f8ff", {"energy": 2.0, "range": 6.0}),
				_o("mannequin", "人物", [0.9, 0, 0.3], "333338", {"rot": [0, 180, 0]}),
			],
		},
		"公園": {
			"lighting": "晴天正午", "env": {"floor_color": "5f8a4a"},
			"camera": {"pos": [3.0, 1.4, 5.0], "look_at": [0, 1.0, 0], "fov": 45},
			"objects": [
				_o("slab", "步道", [0, 0, 0], "c8b99a", {"size": [1.6, 0.03, 16]}),
				_o("cylinder", "樹幹1", [-2.5, 0, -2], "6b4a32", {"size": [0.3, 2.2, 0.3]}),
				_o("sphere", "樹冠1", [-2.5, 1.8, -2], "3f7a3a", {"size": [2.2, 2.0, 2.2]}),
				_o("cylinder", "樹幹2", [2.8, 0, -4], "6b4a32", {"size": [0.35, 2.6, 0.35]}),
				_o("sphere", "樹冠2", [2.8, 2.1, -4], "4a8a40", {"size": [2.6, 2.3, 2.6]}),
				_o("cylinder", "樹幹3", [-3.0, 0, 3], "6b4a32", {"size": [0.28, 2.0, 0.28]}),
				_o("sphere", "樹冠3", [-3.0, 1.6, 3], "3a7036", {"size": [2.0, 1.8, 2.0]}),
				_o("box", "長椅座", [1.6, 0.4, 0.5], "8a5a3a", {"size": [1.6, 0.08, 0.45], "rot": [0, 90, 0]}),
				_o("box", "長椅腳", [1.6, 0, 0.5], "2a2a2a", {"size": [1.4, 0.4, 0.35], "rot": [0, 90, 0]}),
				_o("mannequin", "人物", [0, 0, 0.8], "333338"),
			],
		},
		"走廊": {
			"lighting": "夜晚", "env": {"floor_color": "4a4a50", "sky": false, "bg_color": "101014"},
			"camera": {"pos": [0, 1.5, 5.5], "look_at": [0, 1.4, -4], "fov": 45},
			"objects": [
				_o("box", "左牆", [-1.3, 0, -3], "c9c6bd", {"size": [0.15, 3, 18]}),
				_o("box", "右牆", [1.3, 0, -3], "c9c6bd", {"size": [0.15, 3, 18]}),
				_o("slab", "天花板", [0, 3, -3], "dedbd2", {"size": [2.8, 0.1, 18]}),
				_o("light", "燈1", [0, 2.8, 3], "e8f0ff", {"energy": 1.8, "range": 4.5}),
				_o("light", "燈2", [0, 2.8, -1], "e8f0ff", {"energy": 1.8, "range": 4.5}),
				_o("light", "燈3", [0, 2.8, -5], "e8f0ff", {"energy": 1.8, "range": 4.5}),
				_o("light", "燈4", [0, 2.8, -9], "ffb0a0", {"energy": 1.8, "range": 4.5}),
				_o("box", "門", [1.22, 0, -6], "5a4030", {"size": [0.05, 2.1, 0.9]}),
				_o("mannequin", "人物", [0, 0, -2], "2e2e33"),
			],
		},
		"舞台": {
			"lighting": "夜晚", "env": {"floor_color": "222226", "sky": false, "bg_color": "08080c"},
			"camera": {"pos": [0, 1.3, 7.0], "look_at": [0, 1.6, 0], "fov": 40},
			"objects": [
				_o("box", "舞台", [0, 0, -1], "1c1c20", {"size": [8, 0.8, 5]}),
				_o("wall", "背板", [0, 0.8, -3.4], "2a2240", {"size": [8, 4, 0.2]}),
				_o("light", "粉色聚光", [-2.5, 4, 1], "ff6fb0", {"energy": 6.0, "range": 9.0}),
				_o("light", "藍色聚光", [2.5, 4, 1], "6f9bff", {"energy": 6.0, "range": 9.0}),
				_o("light", "頂光", [0, 4.5, -1], "fff3e0", {"energy": 4.0, "range": 7.0}),
				_o("mannequin", "表演者", [0, 0.8, -0.5], "e8e0f0"),
				_o("box", "觀眾席1", [-2, 0, 3.5], "202024", {"size": [3, 0.5, 0.6]}),
				_o("box", "觀眾席2", [2, 0, 3.5], "202024", {"size": [3, 0.5, 0.6]}),
			],
		},
	}


static func _o(type: String, n: String, pos: Array, color: String, extra := {}) -> Dictionary:
	var d := {"type": type, "name": n, "pos": pos, "color": color}
	d.merge(extra, true)
	return d
