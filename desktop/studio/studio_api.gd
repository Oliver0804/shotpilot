class_name StudioApi
extends Node
## 本機 HTTP JSON API（只綁 127.0.0.1），給 MCP 伺服器（mcp/shotpilot_mcp.py）轉發 AI 的工具呼叫。
## POST /rpc  {"method": "...", "params": {...}}  →  {"ok": true, "result": ...} / {"ok": false, "error": "..."}

const PORT := 8766
const MAX_BODY := 8 * 1024 * 1024

var studio: Node # studio.gd

var _tcp := TCPServer.new()
var _conns: Array = [] # {peer: StreamPeerTCP, buf: PackedByteArray, busy: bool}


func _ready() -> void:
	var err := _tcp.listen(PORT, "127.0.0.1")
	if err != OK:
		push_warning("StudioApi: 無法監聽 127.0.0.1:%d（%s），MCP 將無法連線" % [PORT, error_string(err)])
	else:
		print("StudioApi: MCP 介面在 http://127.0.0.1:%d/rpc" % PORT)


func _exit_tree() -> void:
	_tcp.stop()


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		_conns.append({"peer": _tcp.take_connection(), "buf": PackedByteArray(), "busy": false})
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		if c.busy:
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var r := peer.get_partial_data(n)
			if r[0] == OK:
				c.buf.append_array(r[1])
		_try_handle(c)


func _try_handle(c: Dictionary) -> void:
	var buf: PackedByteArray = c.buf
	var text := buf.get_string_from_ascii()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		if buf.size() > MAX_BODY:
			_respond(c, 413, {"ok": false, "error": "request too large"})
		return
	var head := text.substr(0, head_end)
	var length := 0
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			length = int(line.split(":", true, 1)[1].strip_edges())
	var body_start := head_end + 4
	if buf.size() < body_start + length:
		return
	var body := buf.slice(body_start, body_start + length).get_string_from_utf8()
	c.busy = true
	if not head.begins_with("POST /rpc"):
		_respond(c, 404, {"ok": false, "error": "POST /rpc only"})
		return
	var req = JSON.parse_string(body)
	if not req is Dictionary:
		_respond(c, 400, {"ok": false, "error": "invalid JSON"})
		return
	var params = req.get("params", {})
	if not params is Dictionary:
		params = {}
	var result = await _dispatch(str(req.get("method", "")), params)
	if result is Dictionary and result.has("__error"):
		_respond(c, 200, {"ok": false, "error": result.__error})
	else:
		_respond(c, 200, {"ok": true, "result": result})


func _respond(c: Dictionary, code: int, data: Dictionary) -> void:
	var peer: StreamPeerTCP = c.peer
	var body := JSON.stringify(data).to_utf8_buffer()
	var head := "HTTP/1.1 %d OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, body.size()]
	peer.set_no_delay(true)
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
	_conns.erase(c)


static func _err(msg: String) -> Dictionary:
	return {"__error": msg}


static func _vec(v, fallback: Vector3) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and v.size() == 3 else fallback


# ---------------------------------------------------------------- 方法

func _dispatch(method: String, p: Dictionary) -> Variant:
	match method:
		"get_scene":
			return studio.api_scene_info()
		"screenshot":
			var img: Image = await studio.api_screenshot(str(p.get("view", "editor")), int(p.get("long_side", 1280)))
			if img == null:
				return _err("截圖失敗")
			return {"png_base64": Marshalls.raw_to_base64(img.save_png_to_buffer()), "width": img.get_width(), "height": img.get_height()}
		"add_object":
			var type := str(p.get("type", "box"))
			if not StudioShape.TYPES.has(type) or type == "model":
				return _err("未知的物件類型：%s，可用：%s" % [type, ", ".join(StudioShape.TYPES.keys().filter(func(k): return k != "model"))])
			var s: StudioShape = studio.add_shape(type, _vec(p.get("pos"), Vector3.ZERO))
			if p.has("name"):
				s.name = studio.unique_name(str(p.name), s)
			_apply_object(s, p)
			studio.after_api_edit()
			return {"name": String(s.name)}
		"update_object":
			var s: StudioShape = studio.find_object(str(p.get("name", "")))
			if s == null:
				return _err("找不到物件：%s" % p.get("name", ""))
			studio.push_undo("api")
			if p.has("rename"):
				s.name = studio.unique_name(str(p.rename), s)
			_apply_object(s, p)
			studio.after_api_edit()
			return {"name": String(s.name)}
		"delete_object":
			var s: StudioShape = studio.find_object(str(p.get("name", "")))
			if s == null:
				return _err("找不到物件：%s" % p.get("name", ""))
			studio.select(s)
			studio.delete_selected()
			return {}
		"clear_scene":
			studio.push_undo("api")
			studio.clear_objects_api()
			return {}
		"set_camera":
			return studio.api_set_camera(p)
		"set_editor_view":
			studio.overview.set_view(_vec(p.get("focus"), studio.overview.get_focus()), p.get("distance", -1.0), p.get("yaw", null), p.get("pitch", null))
			return {}
		"set_environment":
			return {"env": studio.api_set_env(p)}
		"add_waypoint":
			if p.has("pos") or p.has("rot") or p.has("look_at"):
				var xf := _camera_xf(p, studio.phone_cam.global_transform)
				studio.add_waypoint(xf, float(p.get("fov", studio.phone_cam.fov)))
			else:
				studio.add_waypoint(studio.phone_cam.global_transform, studio.phone_cam.fov)
			return {"count": studio.waypoints.size()}
		"apply_preset":
			var kind := str(p.get("kind", ""))
			var n := str(p.get("name", ""))
			var ok := false
			match kind:
				"scene":
					ok = studio.apply_scene_preset(n)
				"lighting":
					ok = studio.apply_lighting_preset(n)
				"camera":
					if p.has("subject"):
						var subj: StudioShape = studio.find_object(str(p.subject))
						if subj == null:
							return _err("找不到主角物件：%s" % p.subject)
						studio.select(subj)
					ok = studio.apply_camera_preset(n)
			if not ok:
				return _err("未知的範本：%s / %s" % [kind, n])
			return {"camera": {"pos": StudioShape._v(studio.phone_cam.position), "rot": StudioShape._v(studio.phone_cam.rotation_degrees), "fov": studio.phone_cam.fov}}
		"play_objects":
			if bool(p.get("reset", false)):
				studio.reset_objects()
			if p.has("play"):
				studio.play_objects(bool(p.play))
			if p.has("time"):
				studio.objects_playing = false
				studio.scene_time = float(p.time)
				studio._apply_scene_time(studio.scene_time)
			return {"playing": studio.objects_playing, "time": studio.scene_time}
		"clear_waypoints":
			studio.clear_waypoints()
			return {}
		"create_auto_take":
			if studio.waypoints.size() < 2:
				return _err("至少需要 2 個記錄點（目前 %d 個）" % studio.waypoints.size())
			var n: String = studio.create_auto_take(float(p.get("duration", 0.0)), bool(p.get("ease", true)), str(p.get("name", "")))
			return {"name": n, "length": studio.take_library().get_animation(n).length}
		"play_take":
			var n := str(p.get("name", ""))
			if not studio.take_library().has_animation(n):
				return _err("找不到 take：%s" % n)
			studio.anim_player.play(n)
			return {}
		"export_take":
			var n := str(p.get("name", ""))
			if not studio.take_library().has_animation(n):
				return _err("找不到 take：%s" % n)
			var out: String = await studio.api_export(n, p)
			if out == "":
				return _err("匯出失敗：%s" % (studio.exporter.last_message if studio.exporter.last_message != "" else "已有匯出進行中"))
			var files := []
			for f in DirAccess.get_files_at(out):
				files.append(out.path_join(f))
			return {"out_dir": out, "files": files}
		"save_scene":
			var path := str(p.get("path", studio.current_path))
			if path == "":
				path = studio.studio_dir("scenes").path_join("ai_scene.json")
			studio.current_path = path if path.ends_with(".json") else path + ".json"
			studio.save_scene(false)
			return {"path": studio.current_path}
		"load_scene":
			var path := str(p.get("path", ""))
			if not FileAccess.file_exists(path):
				return _err("檔案不存在：%s" % path)
			studio.load_scene(path)
			return {}
	return _err("未知的方法：%s" % method)


func _apply_object(s: StudioShape, p: Dictionary) -> void:
	if p.has("pos"):
		s.position = _vec(p.pos, s.position)
	if p.has("rot"):
		s.rotation_degrees = _vec(p.rot, s.rotation_degrees)
	if p.has("size"):
		# 以公尺指定寬高深，換算成 scale
		var base := s.local_aabb().size.max(Vector3.ONE * 0.001)
		var sz := _vec(p.size, base * s.scale)
		s.scale = (sz / base).max(Vector3.ONE * 0.001)
	elif p.has("scale"):
		var sc = p.scale
		s.scale = Vector3.ONE * float(sc) if (sc is float or sc is int) else _vec(sc, s.scale)
	if p.has("color"):
		s.color = Color.from_string(str(p.color), s.color)
	if p.has("auto_ground"):
		s.auto_ground = bool(p.auto_ground)
	elif p.has("pos") and p.pos is Array and p.pos.size() == 3 and float(p.pos[1]) > 0.01:
		s.auto_ground = false # 明確給了高度＝不要自動貼合
	if p.has("path"):
		# 路線：世界座標點的陣列（起點＝物件位置，不用包含）
		s.reset_motion()
		s.path_offsets.clear()
		for w in p.path:
			s.path_offsets.append(_vec(w, s.position) - s.position)
		if s.path_mode == "none" and not s.path_offsets.is_empty():
			s.path_mode = "pingpong"
	if p.has("path_mode") and StudioShape.PATH_MODES.has(str(p.path_mode)):
		s.path_mode = str(p.path_mode)
	if p.has("path_speed"):
		s.path_speed = maxf(float(p.path_speed), 0.01)
	if p.has("face_motion"):
		s.face_motion = bool(p.face_motion)
	if p.has("roughness"):
		s.roughness = clampf(float(p.roughness), 0, 1)
	if p.has("metallic"):
		s.metallic = clampf(float(p.metallic), 0, 1)
	if p.has("energy"):
		s.light_energy = float(p.energy)
	if p.has("range"):
		s.light_range = float(p.range)
	s.apply_material()
	if s.auto_ground:
		studio.ground_object(s)


## 由 pos / rot（度）/ look_at 組出鏡頭 transform
static func _camera_xf(p: Dictionary, base: Transform3D) -> Transform3D:
	var xf := base
	if p.has("pos"):
		xf.origin = _vec(p.pos, xf.origin)
	if p.has("look_at"):
		var target := _vec(p.look_at, Vector3.ZERO)
		if target.distance_to(xf.origin) > 0.001:
			xf = xf.looking_at(target, Vector3.UP)
	elif p.has("rot"):
		var r := _vec(p.rot, Vector3.ZERO) * (PI / 180.0)
		xf.basis = Basis.from_euler(r)
	return xf
