extends Control
## 手機端：讀感測器 → 傳姿態給 PC；接收 PC 串流的 JPEG 畫面全螢幕顯示。

const Fusion := preload("res://sensor_fusion.gd")
const Joystick := preload("res://joystick.gd")
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
	udp.bind(BEACON_PORT)
	if ip_edit.text != "":
		_connect()


func _process(delta: float) -> void:
	fusion.update(delta, Input.get_gyroscope(), Input.get_gravity(), Input.get_accelerometer())
	_update_hold_dir()
	_layout_stage()
	_poll_discovery()
	_poll_ws(delta)

	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and fusion.initialized:
		# 橫拿時鏡頭座標＝手機座標繞螢幕法線轉 ∓90°（鏡頭的「上」改成手機的側邊）
		var q := Quaternion(fusion.basis * Basis(Vector3.BACK, -hold_dir * PI * 0.5))
		var a := fusion.linear_world
		var vs := stage.size
		ws.send_text(JSON.stringify({
			"t": "pose",
			"q": [q.x, q.y, q.z, q.w],
			"a": [a.x, a.y, a.z],
			"dt": delta,
			"j": [move_joy.value.x, move_joy.value.y],
			"v": lift_joy.value.y,
			"l": [look_joy.value.x, look_joy.value.y],
			"f": frozen,
			"aspect": vs.x / maxf(vs.y, 1.0),
		}))

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
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.send_text(JSON.stringify({"t": "fov", "v": cur_fov}))
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
		play_btn.text = "■ 停止回放" if playing else "▶ 回放"
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
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({"t": "cmd", "c": c}))


# ---------------------------------------------------------------- 手持方向

func _update_hold_dir() -> void:
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
	side.columns = 2
	side.add_theme_constant_override("h_separation", 10)
	side.add_theme_constant_override("v_separation", 10)
	_anchor(side, 1, 0, 16, 160, 290, 330)
	stage.add_child(side)
	rec_btn = _side_button(side, "● 錄製", func(): _send_cmd("rec"))
	wp_btn = _side_button(side, "記點 (0)", func(): _send_cmd("waypoint"))
	_side_button(side, "自動運鏡", func(): _send_cmd("auto"))
	play_btn = _side_button(side, "▶ 回放", func(): _send_cmd("play"))
	_side_button(side, "清除點", func(): _send_cmd("clear_wp"))
	_side_button(side, "歸零", func(): _send_cmd("recenter"))
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
