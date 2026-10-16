class_name PhoneCamOverview
extends Node3D
## 執行時的「全局觀察」視窗：固定的觀察鏡頭看整個場景，
## 畫出手機鏡頭的機身、FOV 視錐與移動軌跡，右下角子畫面顯示手機拍到的畫面。
##
## 操作：右鍵拖曳＝環繞、中鍵或 Shift+右鍵＝平移、滾輪＝縮放；
## Alt＋左／中／右鍵＝環繞／平移／推拉；右鍵按住＋WASD／QE＝飛行（Shift 加速）；觸控板雙指＝環繞、Shift 平移、捏合縮放；
## 1／3／7＝前／右／上視角（⌘ 反向）、5＝透視／正交；F＝對準手機鏡頭、T＝切換跟隨、C＝清除軌跡

@export var rig: PhoneCameraRig
@export var frustum_length := 0.8
@export var frustum_color := Color(1.0, 0.8, 0.1)
@export var trail_color := Color(0.2, 0.9, 1.0)
@export var trail_max_points := 600
## 子畫面寬度佔視窗寬度的比例
@export_range(0.1, 0.6, 0.01) var pip_width := 0.3
@export var follow_phone := false
## false 時左鍵留給其他用途（例如場景編輯器的點選），只用右鍵環繞
@export var orbit_with_left := true
@export var shortcuts_enabled := true
## HUD 最後一行的操作提示（空字串＝用內建的）
@export var hint_text := ""
@export var hud_position := Vector2(12, 10)
## 子畫面離視窗右下角的距離
@export var pip_margin := Vector2(16, 16)

var _cam: Camera3D
var _gizmo: MeshInstance3D
var _gizmo_mesh := ImmediateMesh.new()
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_points := PackedVector3Array()
var _pip: TextureRect
var _pip_frame: Panel
var _hud: Label
var _preview_vp: SubViewport
var _preview_cam: Camera3D

var _focus := Vector3(0, 0.8, 0)
var _yaw := deg_to_rad(40.0)
var _pitch := deg_to_rad(-30.0)
var _distance := 8.0
const PITCH_LIMIT := 1.565 ## 約 89.7°，正上／正下方仍可 look_at
const MIN_DISTANCE := 0.3


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()

	var layer := 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	_gizmo = _make_line_instance(_gizmo_mesh, layer)
	_trail = _make_line_instance(_trail_mesh, layer)

	var ui := CanvasLayer.new()
	add_child(ui)
	_pip_frame = Panel.new()
	ui.add_child(_pip_frame)
	_pip = TextureRect.new()
	_pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pip.stretch_mode = TextureRect.STRETCH_SCALE
	ui.add_child(_pip)
	_hud = Label.new()
	_hud.position = hud_position
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	ui.add_child(_hud)
	_update_camera()


func _make_line_instance(mesh: ImmediateMesh, layer: int) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## 拖曳導覽：在 3D 畫面按下才開始，之後移到 UI 面板上也繼續、放開在哪都會結束
enum Nav { NONE, ORBIT, PAN, DOLLY }
var _nav := Nav.NONE
var _nav_button := 0
## 右鍵按住時按 WASD 會進入飛行模式（同 Unity／Unreal／Godot 編輯器）：視角改成原地轉頭
var _flying := false
const FLY_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom(1.0 / 0.9)
			_:
				var n := _nav_for(event)
				if n != Nav.NONE and _nav == Nav.NONE:
					_nav = n
					_nav_button = event.button_index
					get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# 觸控板雙指：滑動＝環繞、Shift＝平移、⌘／Ctrl＝縮放（同 Blender）
		if event.is_command_or_control_pressed():
			zoom(exp(event.delta.y * 0.05))
		elif event.shift_pressed:
			pan(event.delta * 6.0)
		else:
			orbit(event.delta * 6.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / maxf(event.factor, 0.01))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _view_key(event):
			get_viewport().set_input_as_handled()
		elif shortcuts_enabled:
			match event.keycode:
				KEY_F:
					if _target():
						focus_on(_target().global_position)
				KEY_T:
					follow_phone = not follow_phone
				KEY_C:
					clear_trail()


func _input(event: InputEvent) -> void:
	if _nav == Nav.NONE:
		return
	if event is InputEventMouseMotion:
		match _nav:
			Nav.ORBIT:
				if _flying:
					look(event.relative)
				else:
					orbit(event.relative)
			Nav.PAN:
				pan(event.relative)
			Nav.DOLLY:
				zoom(exp((event.relative.y - event.relative.x) * 0.005))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == _nav_button:
		_nav = Nav.NONE
		_flying = false
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		# 拖曳視角時鍵盤只給飛行用，不會誤觸 W／E／R 等快捷鍵
		if event.pressed and event.keycode in FLY_KEYS and _nav == Nav.ORBIT and _nav_button == MOUSE_BUTTON_RIGHT:
			_flying = true
		get_viewport().set_input_as_handled()


## 右鍵＝環繞、中鍵＝平移、Shift+右鍵＝平移（沒有中鍵的滑鼠）；
## Alt＋左／中／右＝環繞／平移／推拉（Maya、Unity 的習慣）
func _nav_for(e: InputEventMouseButton) -> Nav:
	if e.alt_pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				return Nav.ORBIT
			MOUSE_BUTTON_MIDDLE:
				return Nav.PAN
			MOUSE_BUTTON_RIGHT:
				return Nav.DOLLY
		return Nav.NONE
	match e.button_index:
		MOUSE_BUTTON_MIDDLE:
			return Nav.PAN
		MOUSE_BUTTON_RIGHT:
			return Nav.PAN if e.shift_pressed else Nav.ORBIT
		MOUSE_BUTTON_LEFT:
			return Nav.ORBIT if orbit_with_left and not e.shift_pressed else Nav.NONE
	return Nav.NONE


## 是否正在用滑鼠拖曳視角（場景編輯器用來避免同時拖物件）
func is_navigating() -> bool:
	return _nav != Nav.NONE


## 數字鍵視角（同 Blender，主鍵盤與數字鍵盤都可以）：
## 1 前、3 右、7 上，加 ⌘／Ctrl 是反方向；5 切換透視／正交；. 或 F 由場景編輯器處理
func _view_key(e: InputEventKey) -> bool:
	var opposite := e.is_command_or_control_pressed()
	match e.keycode:
		KEY_1, KEY_KP_1:
			set_view(_focus, -1.0, 180.0 if opposite else 0.0, 0.0)
		KEY_3, KEY_KP_3:
			set_view(_focus, -1.0, -90.0 if opposite else 90.0, 0.0)
		KEY_7, KEY_KP_7:
			set_view(_focus, -1.0, 0.0, 90.0 if opposite else -90.0)
		KEY_5, KEY_KP_5:
			set_orthogonal(_cam.projection != Camera3D.PROJECTION_ORTHOGONAL)
		_:
			return false
	return true


func orbit(rel: Vector2) -> void:
	_yaw -= rel.x * 0.006
	_pitch = clampf(_pitch - rel.y * 0.006, -PITCH_LIMIT, PITCH_LIMIT)
	_update_camera()


## 飛行模式的轉頭：鏡頭位置不動、焦點跟著轉
func look(rel: Vector2) -> void:
	var p := _cam.global_position
	_yaw -= rel.x * 0.004
	_pitch = clampf(_pitch - rel.y * 0.004, -PITCH_LIMIT, PITCH_LIMIT)
	_focus = p - _orbit_dir() * _distance
	_update_camera()


func _fly(delta: float) -> void:
	var v := Vector3.ZERO
	var b := _cam.global_basis
	if Input.is_key_pressed(KEY_W): v -= b.z
	if Input.is_key_pressed(KEY_S): v += b.z
	if Input.is_key_pressed(KEY_A): v -= b.x
	if Input.is_key_pressed(KEY_D): v += b.x
	if Input.is_key_pressed(KEY_E): v += Vector3.UP
	if Input.is_key_pressed(KEY_Q): v -= Vector3.UP
	if v == Vector3.ZERO:
		return
	var speed := clampf(_distance * 0.8, 1.5, 30.0) * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_focus += v.normalized() * speed * delta
	follow_phone = false
	_update_camera()


func _orbit_dir() -> Vector3:
	return Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))


## 平移：游標下的點跟著滑鼠走（以焦點的深度換算）
func pan(rel: Vector2) -> void:
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var per_px := 2.0 * _distance * tan(deg_to_rad(_cam.fov) * 0.5) / vp_h
	var b := _cam.global_basis
	_focus += (-b.x * rel.x + b.y * rel.y) * per_px
	follow_phone = false
	_update_camera()


## factor < 1 拉近；已經貼近焦點時改成整個往前推，不會卡住
func zoom(factor: float) -> void:
	var d := _distance * factor
	if d < MIN_DISTANCE:
		_focus += -_cam.global_basis.z * (_distance - d)
		d = MIN_DISTANCE
	_distance = minf(d, 500.0)
	_update_camera()


func set_orthogonal(on: bool) -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if on else Camera3D.PROJECTION_PERSPECTIVE
	_update_camera()


func is_orthogonal() -> bool:
	return _cam.projection == Camera3D.PROJECTION_ORTHOGONAL


## 把一個範圍完整放進畫面（F 對準選取物件、Home 看全部）
func frame_aabb(box: AABB) -> void:
	var r := maxf(box.size.length() * 0.5, 0.25)
	_focus = box.get_center()
	_distance = clampf(r / sin(deg_to_rad(_cam.fov) * 0.5) * 1.3, MIN_DISTANCE, 500.0)
	follow_phone = false
	_update_camera()


func get_camera() -> Camera3D:
	return _cam


func focus_on(pos: Vector3) -> void:
	_focus = pos
	_update_camera()


func get_hud_label() -> Label:
	return _hud


func get_pip_frame() -> Panel:
	return _pip_frame


func get_focus() -> Vector3:
	return _focus


## 設定觀察視角；distance < 0 或 yaw/pitch 為 null 時維持原值（角度單位：度）
func set_view(focus: Vector3, distance = -1.0, yaw = null, pitch = null) -> void:
	_focus = focus
	if distance != null and float(distance) > 0.0:
		_distance = float(distance)
	if yaw != null:
		_yaw = deg_to_rad(float(yaw))
	if pitch != null:
		_pitch = clampf(deg_to_rad(float(pitch)), -PITCH_LIMIT, PITCH_LIMIT)
	_update_camera()


func clear_trail() -> void:
	_trail_points.clear()


func _update_camera() -> void:
	_cam.global_position = _focus + _orbit_dir() * _distance
	_cam.look_at(_focus, Vector3.UP)
	# 正交模式的畫面大小跟透視模式在焦點處一樣，切換時構圖不跳
	_cam.size = 2.0 * _distance * tan(deg_to_rad(_cam.fov) * 0.5)


func _target() -> Node3D:
	return rig.target if rig and is_instance_valid(rig.target) else null


func _process(delta: float) -> void:
	if _flying:
		_fly(delta)
	var t := _target()
	if t == null:
		return
	if follow_phone:
		_focus = _focus.lerp(t.global_position, 0.1)
		_update_camera()

	if rig.is_tracking():
		if _trail_points.is_empty() or _trail_points[-1].distance_to(t.global_position) > 0.02:
			_trail_points.append(t.global_position)
			if _trail_points.size() > trail_max_points:
				_trail_points.remove_at(0)

	_draw_frustum(t)
	_draw_trail()
	_update_ui(t)


func _draw_frustum(t: Node3D) -> void:
	var cam := t as Camera3D
	var fov := cam.fov if cam else 75.0
	var aspect := rig.get_aspect()
	# Camera3D 預設 KEEP_HEIGHT：fov 是垂直視角
	var h := tan(deg_to_rad(fov) * 0.5) * frustum_length
	var w := h * aspect
	if cam and cam.keep_aspect == Camera3D.KEEP_WIDTH:
		w = tan(deg_to_rad(fov) * 0.5) * frustum_length
		h = w / aspect
	var xf := t.global_transform.orthonormalized()
	var o := xf.origin
	var c := [
		xf * Vector3(-w, h, -frustum_length), xf * Vector3(w, h, -frustum_length),
		xf * Vector3(w, -h, -frustum_length), xf * Vector3(-w, -h, -frustum_length),
	]
	var col := frustum_color if rig.is_tracking() else Color(0.6, 0.6, 0.6)

	_gizmo_mesh.clear_surfaces()
	_gizmo_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 4:
		_line(o, c[i], col)
		_line(c[i], c[(i + 1) % 4], col)
	# 上方三角形標示鏡頭的「上」
	var top := xf * Vector3(0, h * 1.35, -frustum_length)
	_line(c[0], top, col)
	_line(top, c[1], col)
	# 機身小方塊
	var s := 0.08
	var box := [Vector3(-s, -s, 0), Vector3(s, -s, 0), Vector3(s, s, 0), Vector3(-s, s, 0)]
	for i in 4:
		var a: Vector3 = box[i]
		var b: Vector3 = box[(i + 1) % 4]
		_line(xf * a, xf * b, col)
		_line(xf * (a + Vector3(0, 0, s * 2.5)), xf * (b + Vector3(0, 0, s * 2.5)), col)
		_line(xf * a, xf * (a + Vector3(0, 0, s * 2.5)), col)
	_gizmo_mesh.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_gizmo_mesh.surface_set_color(col)
	_gizmo_mesh.surface_add_vertex(a)
	_gizmo_mesh.surface_set_color(col)
	_gizmo_mesh.surface_add_vertex(b)


func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := _trail_points.size()
	for i in n:
		var col := trail_color
		col.a = 0.15 + 0.85 * float(i) / n
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(_trail_points[i])
	_trail_mesh.surface_end()


func _update_ui(t: Node3D) -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := rig.get_aspect()
	var pw := vp.x * pip_width
	var ph := pw / aspect
	if ph > vp.y * 0.6: # 直式畫面太高時改以高度為準
		ph = vp.y * 0.6
		pw = ph * aspect
	var rect := Rect2(vp - Vector2(pw, ph) - pip_margin, Vector2(pw, ph))
	var tex := rig.get_stream_texture()
	if tex == null:
		tex = _local_preview(t, aspect)
	_pip.texture = tex
	_pip.visible = tex != null
	_pip_frame.visible = tex != null
	_pip.position = rect.position
	_pip.size = rect.size
	_pip_frame.position = rect.position - Vector2(3, 3)
	_pip_frame.size = rect.size + Vector2(6, 6)

	var p := t.global_position
	var r := t.global_basis.get_euler() * (180.0 / PI)
	var cam := t as Camera3D
	var lines := PackedStringArray([
		"手機鏡頭  %s" % ("追蹤中" if rig.is_tracking() else "等待手機連線（%s）" % ", ".join(rig.get_addresses())),
		"位置  X %.2f  Y %.2f  Z %.2f" % [p.x, p.y, p.z],
		"角度  俯仰 %.1f°  水平 %.1f°  滾轉 %.1f°" % [r.x, r.y, r.z],
		"FOV  %.1f°   %s  %.2f   高度偏移 %+.2f m" % [cam.fov if cam else 0.0, "橫式" if aspect > 1.0 else "直式", aspect, rig.get_height_offset()],
	])
	if rig.recording:
		lines.append("● REC")
	if hint_text != "":
		lines.append(hint_text)
	elif shortcuts_enabled:
		lines.append("右鍵環繞｜中鍵平移｜滾輪縮放｜F 對準｜T 跟隨%s｜C 清軌跡" % ("(開)" if follow_phone else ""))
	_hud.text = "\n".join(lines)


## 沒有手機連線時，自己渲染一個小預覽，讓使用者也能先看構圖
func _local_preview(t: Node3D, aspect: float) -> Texture2D:
	if _preview_vp == null:
		_preview_vp = SubViewport.new()
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_preview_cam = Camera3D.new()
		_preview_cam.cull_mask &= ~(1 << (PhoneCameraRig.GIZMO_LAYER - 1))
		_preview_vp.add_child(_preview_cam)
		add_child(_preview_vp)
		_preview_vp.world_3d = get_viewport().find_world_3d()
	var long_side := 480.0
	var size := Vector2i(long_side, long_side / aspect) if aspect >= 1.0 else Vector2i(long_side * aspect, long_side)
	if _preview_vp.size != size:
		_preview_vp.size = size
	_preview_cam.global_transform = t.global_transform
	var cam := t as Camera3D
	if cam:
		_preview_cam.fov = cam.fov
		_preview_cam.environment = cam.environment
	_preview_cam.current = true
	return _preview_vp.get_texture()
