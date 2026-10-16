extends Control
## 手機端：讀感測器 → 傳姿態給 PC；接收 PC 串流的 JPEG 畫面全螢幕顯示。

const Fusion := preload("res://sensor_fusion.gd")
const Joystick := preload("res://joystick.gd")
const DemoWorld := preload("res://demo_world.gd")
const BEACON_PORT := 47011
const DEFAULT_PORT := 8765
const BUFFER_SIZE := 4 * 1024 * 1024
const SETTINGS_PATH := "user://settings.cfg"

var fusion := Fusion.new()
var ws := WebSocketPeer.new()
var udp := PacketPeerUDP.new()
var cfg := ConfigFile.new()

var host := ""
var port := DEFAULT_PORT
var want_connected := false
var frozen := false
var recording := false
var _was_open := false
var _retry_t := 0.0
var _frame_count := 0
var _fps_t := 0.0
var _fps := 0.0
var _stream_tex: ImageTexture

## 手持方向：0＝直拿、1＝逆時針橫拿（手機頂端朝左）、-1＝順時針橫拿（頂端朝右）
var hold_dir := 0

var stage: Control # 所有 UI 的容器，橫拿時整個旋轉 90°
var view: TextureRect
var ip_edit: LineEdit
var connect_btn: Button
var status_lbl: Label
var info_lbl: Label
var rec_btn: Button
var hold_btn: Button
var orient_opt: OptionButton
var move_joy: Joystick
var look_joy: Joystick
var lift_joy: Joystick
var wp_btn: Button
var play_btn: Button
var fov_lbl: Label
var waypoint_count := 0
var cur_fov := 50.0
var _touches := {} # 不在搖桿/按鈕上的手指：index -> 位置（雙指縮放用）
var _pinch_dist := 0.0
var _pinch_fov := 0.0
var _fov_lbl_t := 0.0
## 沒連電腦時的示範模式：手機自己渲染範例場景
var demo: DemoWorld
var scene_btn: Button
var _demo_on := false
var top_box: VBoxContainer
var side_box: GridContainer
var _insets := Vector4(-1, -1, -1, -1) # 舞台座標的安全區：上、右、下、左
## 商店截圖模式（只有啟動時帶 SHOTPILOT_SHOTS=1 環境變數才會開）
var _shots := false


func _ready() -> void:
	cfg.load(SETTINGS_PATH)
	_build_ui()
	ip_edit.text = cfg.get_value("net", "host", "")
	orient_opt.select(cfg.get_value("ui", "hold", 0))
	orient_opt.item_selected.connect(func(i):
		cfg.set_value("ui", "hold", i)
		cfg.save(SETTINGS_PATH))
	# 介面固定直式，不讓系統旋轉；橫拿由 App 依重力自行判斷（不受 iPhone 直向鎖定影響）
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	demo = DemoWorld.new()
	add_child(demo)
	demo.state_updated.connect(func(st):
		if _demo_on:
			_on_state(st))
	_set_demo(true)
	if OS.get_environment("SHOTPILOT_SHOTS") == "1":
		_shots = true
		ip_edit.text = ""
		_run_shots.call_deferred()
		return
	udp.bind(BEACON_PORT)
	if ip_edit.text != "":
		_connect()


func _process(delta: float) -> void:
	fusion.update(delta, Input.get_gyroscope(), Input.get_gravity(), Input.get_accelerometer())
	_update_hold_dir()
	_layout_stage()
	_poll_discovery()
	_poll_ws(delta)

	var online := ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	if online == _demo_on:
		_set_demo(not online)
	if _demo_on:
		_resize_demo()
	# 沒有陀螺儀（模擬器）時示範模式仍用固定朝向，搖桿照樣可以操作
	if fusion.initialized or _demo_on:
		# 橫拿時鏡頭座標＝手機座標繞螢幕法線轉 ∓90°（鏡頭的「上」改成手機的側邊）
		var base := fusion.basis if fusion.initialized and not _shots else Basis.IDENTITY
		var q := Quaternion(base * Basis(Vector3.BACK, -hold_dir * PI * 0.5))
		var a := fusion.linear_world if fusion.initialized else Vector3.ZERO
		var vs := stage.size
		_send({
			"t": "pose",
			"q": [q.x, q.y, q.z, q.w],
			"a": [a.x, a.y, a.z],
			"dt": delta,
			"j": [move_joy.value.x, move_joy.value.y],
			"v": lift_joy.value.y,
			"l": [look_joy.value.x, look_joy.value.y],
			"f": frozen,
			"aspect": vs.x / maxf(vs.y, 1.0),
		})

	if _fov_lbl_t > 0.0:
		_fov_lbl_t -= delta
		fov_lbl.visible = _fov_lbl_t > 0.0

	_fps_t += delta
	if _fps_t >= 1.0:
		_fps = _frame_count / _fps_t
		_frame_count = 0
		_fps_t = 0.0
		var sensor := "感測器 OK" if fusion.initialized else "沒有感測器"
		var vs := stage.size
		if _demo_on:
			info_lbl.text = "示範模式：%s｜%s（連上電腦後改用電腦的場景）" % [demo.SCENES[demo.scene_index], sensor]
		else:
			info_lbl.text = "%s｜%s｜串流 %.0f fps" % [sensor, "橫" if vs.x > vs.y else "直", _fps]


# ---------------------------------------------------------------- 雙指縮放 FOV

func _input(event: InputEvent) -> void:
	# 必須在 _input：Godot 4 的 GUI 會把落在 Control 上的觸控吃掉（全螢幕的根節點也算），
	# _unhandled_input 永遠收不到。搖桿是子節點、_input 比這裡早執行，會先吃掉自己的手指。
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				_pinch_dist = _pinch_distance()
				_pinch_fov = cur_fov
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_dist > 10.0:
			# 張開＝拉近（FOV 變小），捏合＝拉遠
			cur_fov = clampf(_pinch_fov * _pinch_dist / maxf(_pinch_distance(), 1.0), 10.0, 110.0)
			_send({"t": "fov", "v": cur_fov})
			fov_lbl.text = "FOV %d°" % roundi(cur_fov)
			fov_lbl.visible = true
			_fov_lbl_t = 1.2
			get_viewport().set_input_as_handled() # 縮放中不要讓手指順便按到按鈕


func _notification(what: int) -> void:
	# 切到背景時手指的放開事件可能不會送來，避免殘留的觸點讓之後一直誤判成雙指
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touches.clear()


func _pinch_distance() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


# ---------------------------------------------------------------- 網路

func _poll_discovery() -> void:
	while udp.get_available_packet_count() > 0:
		var pkt := udp.get_packet()
		var ip := udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if d is Dictionary and d.has("phonecam") and ip_edit.text == "":
			ip_edit.text = "%s:%d" % [ip, int(d.get("port", DEFAULT_PORT))]
			_connect()


func _connect() -> void:
	var text := ip_edit.text.strip_edges()
	if text == "":
		status_lbl.text = "請輸入 PC 的 IP"
		return
	var parts := text.split(":")
	host = parts[0]
	port = int(parts[1]) if parts.size() > 1 else DEFAULT_PORT
	cfg.set_value("net", "host", text)
	cfg.save(SETTINGS_PATH)
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = BUFFER_SIZE
	ws.outbound_buffer_size = BUFFER_SIZE
	var err := ws.connect_to_url("ws://%s:%d" % [host, port])
	want_connected = true
	_was_open = false
	status_lbl.text = "連線中…" if err == OK else "連線失敗：%s" % error_string(err)
	connect_btn.text = "斷線"


func _disconnect() -> void:
	want_connected = false
	ws.close()
	connect_btn.text = "連線"
	status_lbl.text = "未連線"


func _poll_ws(delta: float) -> void:
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				status_lbl.text = "已連線 %s" % host
			var latest_frame := PackedByteArray()
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if ws.was_string_packet():
					_on_text(pkt.get_string_from_utf8())
				else:
					latest_frame = pkt # 同一幀收到多張畫面時只解碼最新的，舊的直接丟
			if not latest_frame.is_empty():
				_on_frame(latest_frame)
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				_was_open = false
				status_lbl.text = "已斷線，重試中…"
			if want_connected:
				_retry_t += delta
				if _retry_t > 2.0:
					_retry_t = 0.0
					_connect()


func _on_text(text: String) -> void:
	var d = JSON.parse_string(text)
	if not d is Dictionary:
		return
	if d.get("t") == "state":
		_on_state(d)


func _on_state(d: Dictionary) -> void:
	if true:
		recording = bool(d.get("rec", false))
		rec_btn.text = "■ %.1fs" % float(d.get("rec_t", 0.0)) if recording else "● 錄製"
		if recording:
			rec_btn.add_theme_stylebox_override("normal", PhoneTheme.rec_style())
		else:
			rec_btn.remove_theme_stylebox_override("normal")
		waypoint_count = int(d.get("wp", waypoint_count))
		if _touches.size() < 2:
			cur_fov = float(d.get("fov", cur_fov))
		var playing := bool(d.get("playing", false))
		play_btn.text = "■ 停止回放" if playing else "回放"
		wp_btn.text = "記點 (%d)" % waypoint_count


func _on_frame(jpg: PackedByteArray) -> void:
	var img := Image.new()
	if img.load_jpg_from_buffer(jpg) != OK:
		return
	if _stream_tex and Vector2i(_stream_tex.get_size()) == img.get_size():
		_stream_tex.update(img)
	else:
		_stream_tex = ImageTexture.create_from_image(img)
		view.texture = _stream_tex
	_frame_count += 1


func _send_cmd(c: String) -> void:
	_send({"t": "cmd", "c": c})


## 連上電腦就送過去，否則餵給示範模式（兩邊格式完全相同）
func _send(d: Dictionary) -> void:
	if _demo_on:
		demo.feed(d)
	elif ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func _set_demo(on: bool) -> void:
	_demo_on = on
	demo.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	demo.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if scene_btn:
		scene_btn.visible = on
	if on:
		view.texture = demo.get_texture()
		info_lbl.text = "示範模式：%s（連上電腦後改用電腦的場景）" % demo.SCENES[demo.scene_index]
	elif _stream_tex:
		view.texture = _stream_tex


## 示範畫面的解析度跟著螢幕實際像素與手持方向
func _resize_demo() -> void:
	var px := float(DisplayServer.window_get_size().x) / maxf(get_viewport_rect().size.x, 1.0)
	var want := Vector2i((stage.size * px).round())
	if want.x > 0 and want.y > 0 and demo.size != want:
		demo.size = want


# ---------------------------------------------------------------- 手持方向

func _update_hold_dir() -> void:
	if _shots:
		hold_dir = 0
		return
	match orient_opt.selected:
		1: hold_dir = 0
		2: hold_dir = 1
		3: hold_dir = -1
		_:
			var g := Input.get_gravity()
			if g.length() < 0.1:
				return
			g = g.normalized()
			if absf(g.z) > 0.85:
				return # 平放時無法判斷，維持原狀
			# 遲滯：超過 ~50° 才切換，避免在 45° 附近來回跳
			var want := hold_dir
			if absf(g.x) > 0.75:
				want = 1 if g.x < 0.0 else -1
			elif absf(g.y) > 0.75:
				want = 0
			hold_dir = want


func _layout_stage() -> void:
	var vs := get_viewport_rect().size
	_apply_safe_area(vs)
	match hold_dir:
		0:
			stage.rotation = 0.0
			stage.position = Vector2.ZERO
			stage.size = vs
		1:
			stage.rotation = PI * 0.5
			stage.position = Vector2(vs.x, 0.0)
			stage.size = Vector2(vs.y, vs.x)
		-1:
			stage.rotation = -PI * 0.5
			stage.position = Vector2(0.0, vs.y)
			stage.size = Vector2(vs.y, vs.x)


## 瀏海／動態島／Home 指示條：UI 往內縮，避免被蓋住（橫拿時舞台旋轉，安全區跟著換邊）
func _apply_safe_area(vs: Vector2) -> void:
	var ws := Vector2(DisplayServer.window_get_size())
	if ws.x <= 0.0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var k := vs.x / ws.x
	var t := sa.position.y * k
	var l := sa.position.x * k
	var b := maxf(ws.y - sa.end.y, 0.0) * k
	var r := maxf(ws.x - sa.end.x, 0.0) * k
	var ins: Vector4
	match hold_dir:
		1: ins = Vector4(r, b, l, t)
		-1: ins = Vector4(l, t, r, b)
		_: ins = Vector4(t, r, b, l)
	if ins == _insets:
		return
	_insets = ins
	top_box.offset_top = 12 + ins.x
	top_box.offset_left = 12 + ins.w
	top_box.offset_right = -12 - ins.y
	_anchor(side_box, 1, 0, 16 + ins.y, 160 + ins.x, 290, 330)
	_anchor(move_joy, 0, 1, 30 + ins.w, 30 + ins.z, 230, 230)
	_anchor(lift_joy, 0, 1, 280 + ins.w, 30 + ins.z, 70, 230)
	_anchor(look_joy, 1, 1, 30 + ins.y, 30 + ins.z, 230, 230)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# Live2D 風格主題（內含粉圓字型；Godot 內建字型沒有中文，iOS 也不會自動補字）
	theme = PhoneTheme.build()

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	stage = Control.new()
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)

	view = TextureRect.new()
	view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(view)

	# 上方：連線列 + 設定列
	var top := VBoxContainer.new()
	top_box = top
	top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 12
	stage.add_child(top)

	var row1 := HBoxContainer.new()
	top.add_child(row1)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "PC IP（自動搜尋中）"
	ip_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	ip_edit.custom_minimum_size.x = 160
	row1.add_child(ip_edit)
	connect_btn = Button.new()
	connect_btn.text = "連線"
	connect_btn.pressed.connect(func(): _disconnect() if want_connected else _connect())
	row1.add_child(connect_btn)
	status_lbl = Label.new()
	status_lbl.text = "未連線"
	row1.add_child(status_lbl)

	var row2 := HBoxContainer.new()
	top.add_child(row2)
	orient_opt = OptionButton.new()
	for t in ["自動（依手持方向）", "固定直拿", "固定橫拿（頂端朝左）", "固定橫拿（頂端朝右）"]:
		orient_opt.add_item(t)
	orient_opt.focus_mode = FOCUS_NONE
	row2.add_child(orient_opt)

	info_lbl = Label.new()
	info_lbl.modulate = Color(1, 1, 1, 0.7)
	top.add_child(info_lbl)

	# 右上：操作按鈕（2 欄）
	var side := GridContainer.new()
	side_box = side
	side.columns = 2
	side.add_theme_constant_override("h_separation", 10)
	side.add_theme_constant_override("v_separation", 10)
	_anchor(side, 1, 0, 16, 160, 290, 330)
	stage.add_child(side)
	rec_btn = _side_button(side, "● 錄製", func(): _send_cmd("rec"))
	wp_btn = _side_button(side, "記點 (0)", func(): _send_cmd("waypoint"))
	_side_button(side, "自動運鏡", func(): _send_cmd("auto"))
	play_btn = _side_button(side, "回放",  # 粉圓字型沒有 ▶，iOS 不會補字
		 func(): _send_cmd("play"))
	_side_button(side, "清除點", func(): _send_cmd("clear_wp"))
	_side_button(side, "歸零", func(): _send_cmd("recenter"))
	scene_btn = _side_button(side, "換場景", func():
		var n := demo.next_scene()
		info_lbl.text = "示範模式：%s（連上電腦後改用電腦的場景）" % n)
	hold_btn = _side_button(side, "暫停跟隨", Callable())
	hold_btn.toggle_mode = true
	hold_btn.toggled.connect(func(on): frozen = on)

	# 畫面中央：縮放時顯示 FOV
	fov_lbl = Label.new()
	fov_lbl.add_theme_font_size_override("font_size", 44)
	fov_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	fov_lbl.add_theme_constant_override("outline_size", 10)
	fov_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fov_lbl.visible = false
	fov_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	fov_lbl.set_anchors_and_offsets_preset(PRESET_CENTER)
	fov_lbl.custom_minimum_size = Vector2(300, 60)
	fov_lbl.offset_left = -150
	fov_lbl.offset_right = 150
	stage.add_child(fov_lbl)

	# 下方：左＝移動、中左＝升降、右＝鏡頭角度
	move_joy = Joystick.new()
	move_joy.label = "移動"
	_anchor(move_joy, 0, 1, 30, 30, 230, 230)
	stage.add_child(move_joy)
	lift_joy = Joystick.new()
	lift_joy.vertical_only = true
	lift_joy.label = "升降"
	_anchor(lift_joy, 0, 1, 280, 30, 70, 230)
	stage.add_child(lift_joy)
	look_joy = Joystick.new()
	look_joy.label = "鏡頭角度"
	_anchor(look_joy, 1, 1, 30, 30, 230, 230)
	stage.add_child(look_joy)


func _side_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 72)
	b.focus_mode = FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


## 以錨點 (ax, ay ∈ {0, 0.5, 1}) 放置固定大小的控制項；x/y 為離該側的邊距（ay=0.5 時 y 為相對中心的位移）
func _anchor(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x if ax == 0 else -x - w
	c.offset_top = y if ay != 1 else -y - h
	c.offset_right = c.offset_left + w
	c.offset_bottom = c.offset_top + h


# ---------------------------------------------------------------- 商店截圖

## 依序擺好幾個示範畫面並存成 user://shots/*.png（iOS 上是 App 的 Documents），用 devicectl 取回
func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	await _shot_scene("街道巷口", 55.0, 0.4)
	await _save("01_street")

	await _shot_scene("客廳", 58.0, 0.8)
	_send_cmd("rec")
	await _wait(3.2)
	await _save("02_record")
	_send_cmd("rec")

	await _shot_scene("走廊", 30.0, 0.0)
	cur_fov = 30.0
	fov_lbl.text = "FOV %d°" % roundi(cur_fov)
	fov_lbl.visible = true
	_fov_lbl_t = 10.0
	await _wait(0.3)
	await _save("03_fov")
	_fov_lbl_t = 0.0
	fov_lbl.visible = false

	await _shot_scene("舞台", 55.0, 0.3)
	for i in 3:
		_send_cmd("waypoint")
		move_joy.value = Vector2(0.4, 0.15)
		look_joy.value = Vector2(-0.25, 0)
		await _wait(0.5)
		move_joy.value = Vector2.ZERO
		look_joy.value = Vector2.ZERO
	_send_cmd("auto")
	await _wait(0.4)
	await _save("04_auto")
	_send_cmd("play")

	await _shot_scene("公園", 62.0, 1.0)
	await _save("05_park")
	var f := FileAccess.open("user://shots/done.txt", FileAccess.WRITE)
	f.store_string("ok")
	f.close()


## back_sec：用左搖桿往後退幾秒，直式畫面比較看得到環境
func _shot_scene(n: String, fov := 0.0, back_sec := 0.0) -> void:
	demo.apply_scene(demo.SCENES.find(n))
	if fov > 0.0:
		cur_fov = fov
		_send({"t": "fov", "v": fov})
	info_lbl.text = "示範模式：%s（連上電腦後改用電腦的場景）" % n
	# 範本機位的俯仰角：歸零後套回去（截圖模式沒有陀螺儀姿態）
	var pitch := asin(clampf(-demo.cam.global_basis.z.y, -1.0, 1.0))
	await _wait(0.3)
	demo.rig._pitch_offset = pitch
	if back_sec > 0.0:
		move_joy.value = Vector2(0, -1)
		await _wait(back_sec)
		move_joy.value = Vector2.ZERO
	await _wait(0.8)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % n)
