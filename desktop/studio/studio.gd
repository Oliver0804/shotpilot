extends Node3D
## ShotPilot：簡易場景編輯器 + 手機運鏡 + 給 AI 影片用的 RGB／深度輸出。
## 整個介面都在程式裡建立，studio.tscn 只有這個根節點。

const SNAP := 0.25
const LEFT_W := 290.0
const RIGHT_W := 360.0
const TOP_H := 46.0
const UNDO_LIMIT := 100

var world_env: WorldEnvironment
var env_res: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var floor_mesh: MeshInstance3D
var floor_mat := StandardMaterial3D.new()
var grid: MeshInstance3D
var objects_root: Node3D
var phone_cam: Camera3D
var anim_player: AnimationPlayer
var rig: PhoneCameraRig
var overview: PhoneCamOverview
var gizmo: StudioGizmo
var exporter: TakeExporter

var selected: StudioShape
var api: StudioApi
## 記錄點：[{"xf": Transform3D, "fov": float}]，用來產生自動運鏡
var waypoints: Array = []
var _wp_mesh := ImmediateMesh.new()
var _wp_labels: Node3D
var current_path := ""
const DEFAULT_ENV := {
	"sun_elev": 50.0, "sun_azim": 30.0, "sun_energy": 1.2, "sun_color": "fff4e0",
	"sky": true, "sky_top": "6f8fb8", "sky_horizon": "c9d3de", "bg_color": "202226",
	"ambient": 1.0, "fog": 0.0, "floor": true, "floor_color": "9e9aa8", "floor_size": 30.0,
	"grid": true, "shadows": true,
}
var env := DEFAULT_ENV.duplicate()

var _undo: Array = []
var _redo: Array = []
var _last_undo_tag := ""
var _last_undo_time := 0
var _dirty := false

var _drag_mode := "" # "", "axis", "plane"
var _drag_axis := -1
var _drag_start_pos := Vector3.ZERO
var _drag_start_s := 0.0
var _drag_hit0 := Vector3.ZERO
var _drag_vertical := false
var _drag_dir := Vector3.RIGHT
var _drag_start_basis := Basis()
var _drag_start_scale := Vector3.ONE
var _drag_mouse0 := Vector2.ZERO
var _drag_last_angle := 0.0
var _drag_total_angle := 0.0
var _drag_moved := false
var _drag_was_dirty := false
var _drag_snap := true
var mode_btns: Array[Button] = []

## 物件動畫的場景時間（秒）；錄製開始時歸零，回放／匯出時跟 take 時間同步
var scene_time := 0.0
var objects_playing := false
var obj_play_btn: Button
var _was_recording := false
var _was_take_playing := false
var _placing_path := false
var _path_mesh := ImmediateMesh.new()
const STEP_UP := 0.8 ## 自動貼合時最多「爬上」多高的物件（避免跳到天花板上）

# UI
var outliner: ItemList
var inspector: StudioInspector
var status_lbl: Label
var snap_chk: CheckBox
var server_lbl: Label
var rec_btn: Button
var takes_list: ItemList
var export_res: OptionButton
var export_fps: OptionButton
var export_aspect: OptionButton
var export_depth: CheckBox
var export_png: CheckBox
var export_far: HSlider
var export_bar: ProgressBar
var export_lbl: Label
var export_btn: Button
var last_export_dir := ""
var env_controls := {}
var file_dialog: FileDialog
var _ui_t := 0.0


func _ready() -> void:
	get_window().title = "ShotPilot"
	get_tree().auto_accept_quit = false # 關視窗前確認未儲存的修改
	_build_world()
	_build_ui()
	# 主題繼承碰到 CanvasLayer 會斷，apply() 會把同一份 Theme 補到各個斷點
	StudioTheme.apply(self)
	StudioTheme.hud_label_style(overview.get_hud_label())
	overview.get_pip_frame().add_theme_stylebox_override("panel", StudioTheme.pip_style())
	_apply_env()
	_load_default_scene()
	_reset_undo()


# ================================================================ 世界

func _build_world() -> void:
	env_res = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env_res.sky = sky
	env_res.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_res.ssao_enabled = true
	world_env = WorldEnvironment.new()
	world_env.environment = env_res
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	grid = MeshInstance3D.new()
	grid.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = gm
	add_child(grid)

	objects_root = Node3D.new()
	objects_root.name = "Objects"
	add_child(objects_root)

	phone_cam = Camera3D.new()
	phone_cam.name = "PhoneCamera"
	phone_cam.fov = 50.0
	add_child(phone_cam)
	phone_cam.look_at_from_position(Vector3(0, 1.5, 4.5), Vector3(0, 1.0, 0))

	anim_player = AnimationPlayer.new()
	add_child(anim_player)

	rig = PhoneCameraRig.new()
	rig.target = phone_cam
	rig.animation_player = anim_player
	rig.take_recorded.connect(func(n):
		if n == "":
			_status("錄製時間太短，已捨棄")
			return
		_mark_dirty()
		_refresh_takes())
	add_child(rig)

	overview = PhoneCamOverview.new()
	overview.rig = rig
	overview.orbit_with_left = false
	overview.shortcuts_enabled = false
	overview.hud_position = Vector2(LEFT_W + 14, TOP_H + 8)
	overview.pip_margin = Vector2(RIGHT_W + 16, 16)
	overview.pip_width = 0.26
	overview.hint_text = "右鍵環繞（按住加 WASD 飛行）｜中鍵或 Shift+右鍵平移｜滾輪縮放｜F 對準選取｜A 看全部｜1/3/7 前/右/上｜5 正交｜W/E/R 移動/旋轉/縮放"
	add_child(overview)

	gizmo = StudioGizmo.new()
	add_child(gizmo)
	gizmo.camera = overview.get_camera()

	var wp_mi := MeshInstance3D.new()
	wp_mi.mesh = _wp_mesh
	var wpm := StandardMaterial3D.new()
	wpm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wpm.vertex_color_use_as_albedo = true
	wpm.no_depth_test = true
	wp_mi.material_override = wpm
	wp_mi.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	add_child(wp_mi)
	_wp_labels = Node3D.new()
	add_child(_wp_labels)

	var path_mi := MeshInstance3D.new()
	path_mi.mesh = _path_mesh
	path_mi.material_override = wpm
	path_mi.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	add_child(path_mi)

	rig.command.connect(_on_phone_command)

	api = StudioApi.new()
	api.studio = self
	add_child(api)

	exporter = TakeExporter.new()
	exporter.progress.connect(_on_export_progress)
	exporter.finished.connect(_on_export_finished)
	add_child(exporter)


func _rebuild_grid(size: float) -> void:
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := int(size / 2.0)
	for i in range(-half, half + 1):
		var c := Color(1, 1, 1, 0.35 if i == 0 else 0.12)
		for seg in [[Vector3(i, 0.002, -half), Vector3(i, 0.002, half)], [Vector3(-half, 0.002, i), Vector3(half, 0.002, i)]]:
			m.surface_set_color(c)
			m.surface_add_vertex(seg[0])
			m.surface_set_color(c)
			m.surface_add_vertex(seg[1])
	m.surface_end()
	grid.mesh = m


func _apply_env() -> void:
	sun.rotation_degrees = Vector3(-float(env.sun_elev), float(env.sun_azim), 0)
	sun.light_energy = env.sun_energy
	sun.light_color = Color.from_string(env.sun_color, Color.WHITE)
	sun.shadow_enabled = env.shadows
	sky_mat.sky_top_color = Color.from_string(env.sky_top, Color.SKY_BLUE)
	sky_mat.sky_horizon_color = Color.from_string(env.sky_horizon, Color.WHITE)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color.from_string(env.floor_color, Color.GRAY).darkened(0.4)
	sky_mat.sun_angle_max = 30.0
	if env.sky:
		env_res.background_mode = Environment.BG_SKY
		env_res.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env_res.background_mode = Environment.BG_COLOR
		env_res.background_color = Color.from_string(env.bg_color, Color.BLACK)
		env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env_res.ambient_light_color = env_res.background_color.lerp(Color.WHITE, 0.3)
	env_res.ambient_light_energy = env.ambient
	env_res.fog_enabled = float(env.fog) > 0.0
	env_res.fog_density = env.fog
	env_res.fog_light_color = sky_mat.sky_horizon_color
	floor_mesh.visible = env.floor
	floor_mat.albedo_color = Color.from_string(env.floor_color, Color.GRAY)
	floor_mat.roughness = 0.9
	(floor_mesh.mesh as PlaneMesh).size = Vector2.ONE * float(env.floor_size)
	grid.visible = env.grid
	_rebuild_grid(float(env.floor_size))
	_sync_env_controls()


# ================================================================ 物件

func add_shape(type: String, at = null) -> StudioShape:
	push_undo("add")
	var s := StudioShape.new().setup(type)
	match type:
		"mannequin":
			s.color = Color(0.2, 0.2, 0.22)
		"light":
			s.color = Color(1.0, 0.85, 0.6)
		"wall":
			s.color = Color(0.85, 0.85, 0.82)
	s.apply_material()
	objects_root.add_child(s, true)
	s.position = at if at is Vector3 else _spawn_point()
	if s.is_light():
		s.position.y = 2.2
	elif s.auto_ground:
		ground_object(s)
	select(s)
	_structure_changed()
	return s


func _spawn_point() -> Vector3:
	var cam := overview.get_camera()
	var vp := get_viewport().get_visible_rect().size
	var center := Vector2(LEFT_W + (vp.x - LEFT_W - RIGHT_W) * 0.5, vp.y * 0.5)
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	var p: Vector3 = hit if hit != null and from.distance_to(hit) < 30.0 else Vector3.ZERO
	return _snap(p) if snap_chk.button_pressed else p


func import_model(path: String) -> void:
	push_undo("add")
	var s := StudioShape.new()
	s.model_path = path
	s.name = path.get_file().get_basename()
	s.setup("model")
	objects_root.add_child(s, true)
	s.position = _spawn_point()
	select(s)
	_structure_changed()


func delete_selected() -> void:
	if not selected:
		return
	push_undo("delete")
	var s := selected
	select(null)
	objects_root.remove_child(s)
	s.queue_free()
	_structure_changed()


func duplicate_selected() -> void:
	if not selected:
		return
	push_undo("duplicate")
	var s := StudioShape.from_dict(selected.to_dict())
	objects_root.add_child(s, true)
	s.position += Vector3(0.5, 0, 0.5)
	if s.auto_ground:
		ground_object(s)
	select(s)
	_structure_changed()


func select(s: StudioShape) -> void:
	selected = s
	gizmo.target = s
	inspector.set_target(s)
	outliner.deselect_all()
	if s:
		var idx := s.get_index()
		if idx < outliner.item_count:
			outliner.select(idx)
			outliner.ensure_current_is_visible()


func _structure_changed() -> void:
	_mark_dirty()
	outliner.clear()
	for s: StudioShape in objects_root.get_children():
		if s.is_queued_for_deletion():
			continue
		var icon := "💡 " if s.is_light() else ""
		outliner.add_item("%s%s" % [icon, s.name])
	if selected:
		select(selected)


func _snap(p: Vector3) -> Vector3:
	return p.snapped(Vector3.ONE * SNAP)


func _clear_objects() -> void:
	select(null)
	for c in objects_root.get_children():
		objects_root.remove_child(c)
		c.queue_free()


func _load_default_scene() -> void:
	var defaults := [
		{"type": "mannequin", "name": "人物", "pos": [0, 0, 0], "color": "333338"},
		{"type": "sphere", "name": "大球", "pos": [-1.1, 0, 0.2], "scale": [0.9, 0.9, 0.9], "color": "406640"},
		{"type": "cylinder", "name": "桶子", "pos": [-1.8, 0, 0.7], "scale": [0.45, 0.8, 0.45], "color": "e6801f"},
		{"type": "box", "name": "箱子", "pos": [1.0, 0, 0.3], "scale": [0.6, 0.8, 0.6], "color": "2a2a2e"},
		{"type": "wall", "name": "背牆", "pos": [0, 0, -2.0], "scale": [2.0, 1.0, 1.0], "color": "d9d6cf"},
	]
	for d in defaults:
		objects_root.add_child(StudioShape.from_dict(d), true)
	_structure_changed()
	_dirty = false
	_update_title()


# ================================================================ 復原 / 重做

func _snapshot() -> Dictionary:
	var objs := []
	for s: StudioShape in objects_root.get_children():
		if not s.is_queued_for_deletion():
			objs.append(s.to_dict())
	return {"env": env.duplicate(), "objects": objs, "selected": selected.get_index() if selected else -1}


## tag 相同且間隔很短的連續修改（例如拖動滑桿）合併成一個復原步驟
func push_undo(tag: String) -> void:
	var now := Time.get_ticks_msec()
	if tag == _last_undo_tag and tag != "add" and tag != "delete" and now - _last_undo_time < 800:
		_last_undo_time = now
		return
	_last_undo_tag = tag
	_last_undo_time = now
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _reset_undo() -> void:
	_undo.clear()
	_redo.clear()
	_last_undo_tag = ""


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())


func _restore(snap: Dictionary) -> void:
	_last_undo_tag = ""
	_clear_objects()
	for d in snap.objects:
		objects_root.add_child(StudioShape.from_dict(d), true)
	env = snap.env.duplicate()
	_apply_env()
	_structure_changed()
	var idx: int = snap.get("selected", -1)
	if idx >= 0 and idx < objects_root.get_child_count():
		select(objects_root.get_child(idx))


# ================================================================ 滑鼠 / 鍵盤

## 拖曳中的移動／放開在 _input 處理：游標滑到側邊面板上也不會中斷，放開也不會漏接
func _input(event: InputEvent) -> void:
	if _drag_mode == "":
		return
	if event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_end_drag() # 放開事件被別的視窗吃掉時的保險
		elif selected:
			_update_drag(event.position, event.shift_pressed, event.is_command_or_control_pressed())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_drag() # 拖曳中按右鍵＝取消（同 Blender / Godot）
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_META]:
		pass # 修飾鍵在下一次滑鼠移動時生效
	elif event is InputEventKey:
		get_viewport().set_input_as_handled() # 拖曳途中不處理其他快捷鍵（例如 ⌘Z）


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		get_viewport().gui_release_focus() # 點 3D 畫面＝離開輸入框，快捷鍵才會作用
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _placing_path and selected:
			_place_path_point(event.position)
			get_viewport().set_input_as_handled()
			return
		# 雙擊已選取的物件：移動 ⇄ 旋轉
		if event.double_click and selected and _pick(event.position) == selected:
			set_gizmo_mode(StudioGizmo.Mode.MOVE if gizmo.mode == StudioGizmo.Mode.ROTATE else StudioGizmo.Mode.ROTATE)
			get_viewport().set_input_as_handled()
			return
		var axis := gizmo.pick_axis(event.position)
		if axis >= 0:
			_begin_drag(["axis", "rotate", "scale"][gizmo.mode], axis, event.position)
		else:
			var hit := _pick(event.position)
			select(hit)
			if hit:
				_begin_drag("plane", -1, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if not overview.is_navigating():
			gizmo.hover_axis = gizmo.pick_axis(event.position)
	elif event is InputEventKey and event.pressed:
		var cmd: bool = event.is_command_or_control_pressed()
		match event.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				delete_selected()
			KEY_D when cmd:
				duplicate_selected()
			KEY_Z when cmd and event.shift_pressed:
				redo()
			KEY_Z when cmd:
				undo()
			KEY_Y when cmd:
				redo()
			KEY_S when cmd:
				save_scene(event.shift_pressed)
			KEY_O when cmd:
				_confirm_discard(func(): _open_dialog("open"))
			KEY_N when cmd:
				_confirm_discard(_new_scene)
			KEY_Q when not cmd:
				select(null)
			KEY_W when not cmd:
				set_gizmo_mode(StudioGizmo.Mode.MOVE)
			KEY_E when not cmd:
				set_gizmo_mode(StudioGizmo.Mode.ROTATE)
			KEY_R when not cmd:
				set_gizmo_mode(StudioGizmo.Mode.SCALE)
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				if selected:
					_stop_objects_for_edit()
					push_undo("rot")
					selected.rotation_degrees.y += 15.0 if event.keycode == KEY_BRACKETLEFT else -15.0
					if selected.auto_ground:
						ground_object(selected)
					inspector.refresh()
					_mark_dirty()
			KEY_F, KEY_KP_PERIOD when not cmd:
				frame_selected()
			KEY_HOME:
				frame_all()
			KEY_A when not cmd:
				frame_all()
			KEY_ESCAPE:
				if _placing_path:
					inspector.stop_placing()
				else:
					select(null)
			_:
				return
		get_viewport().set_input_as_handled()


## F：把選取的物件放滿畫面；沒選就對準手機鏡頭
func frame_selected() -> void:
	if selected:
		overview.frame_aabb(selected.world_aabb())
	else:
		overview.frame_aabb(AABB(phone_cam.global_position - Vector3.ONE * 0.6, Vector3.ONE * 1.2))


## Home／Shift+A：整個場景（含手機鏡頭）都放進畫面
func frame_all() -> void:
	var box := AABB(phone_cam.global_position, Vector3.ZERO)
	for s: StudioShape in _shapes():
		box = box.merge(s.world_aabb())
	overview.frame_aabb(box)


func _pick(mouse: Vector2) -> StudioShape:
	var cam := overview.get_camera()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best: StudioShape = null
	var best_d := INF
	for s: StudioShape in objects_root.get_children():
		if s.is_queued_for_deletion():
			continue
		var inv := s.global_transform.affine_inverse()
		var hit = s.local_aabb().intersects_ray(inv * from, inv.basis * dir)
		if hit != null:
			var d := from.distance_to(s.global_transform * (hit as Vector3))
			if d < best_d:
				best_d = d
				best = s
	return best


func _begin_drag(mode: String, axis: int, mouse: Vector2) -> void:
	_stop_objects_for_edit()
	push_undo("drag")
	_last_undo_tag = "" # 每次拖曳都是獨立的一步
	_drag_moved = false
	_drag_was_dirty = _dirty
	_drag_mode = mode
	_drag_axis = axis
	gizmo.active_axis = axis
	_drag_start_pos = selected.position
	_drag_start_basis = selected.global_basis
	_drag_start_scale = selected.scale
	_drag_mouse0 = mouse
	_drag_vertical = false
	match mode:
		"axis":
			_drag_dir = gizmo.axis_dir(axis)
			_drag_start_s = _axis_param(mouse)
		"rotate":
			_drag_dir = StudioGizmo.AXES[axis]
			_drag_last_angle = _screen_angle(mouse)
			_drag_total_angle = 0.0
		"scale":
			if axis != StudioGizmo.UNIFORM:
				_drag_dir = gizmo.axis_dir(axis)
				_drag_start_s = _axis_param(mouse)
		_:
			_drag_hit0 = _plane_hit(mouse, false)


## 放開：沒有真的移動（只是點選）就把剛剛記的復原步驟收回，免得 ⌘Z 按了沒反應
func _end_drag() -> void:
	if _drag_mode == "":
		return
	_drag_mode = ""
	gizmo.active_axis = -1
	if not _drag_moved and not _undo.is_empty():
		_undo.pop_back()


## 取消拖曳：回到按下前的狀態
func _cancel_drag() -> void:
	if _drag_mode == "":
		return
	_drag_mode = ""
	gizmo.active_axis = -1
	if not _undo.is_empty():
		var snap: Dictionary = _undo.pop_back()
		if _drag_moved:
			_restore(snap)
			_dirty = _drag_was_dirty
			_update_title()
	_status("已取消")


func _update_drag(mouse: Vector2, shift: bool, invert_snap := false) -> void:
	_drag_moved = true
	_drag_snap = snap_chk.button_pressed != invert_snap # 拖曳時按住 ⌘／Ctrl 暫時反轉吸附
	if _drag_mode == "rotate":
		_update_rotate(mouse)
		return
	if _drag_mode == "scale":
		_update_scale(mouse)
		return
	var p := _drag_start_pos
	if _drag_mode == "axis":
		var s := _axis_param(mouse)
		p = _drag_start_pos + _drag_dir * (s - _drag_start_s)
		if _drag_snap:
			p[_drag_axis] = snappedf(p[_drag_axis], SNAP)
	else:
		if shift != _drag_vertical: # 中途切換水平／垂直時重設參考點
			_drag_vertical = shift
			_drag_start_pos = selected.position
			_drag_hit0 = _plane_hit(mouse, shift)
			return
		var delta := _plane_hit(mouse, shift) - _drag_hit0
		if shift:
			p.y = maxf(_drag_start_pos.y + delta.y, -50.0)
			if _drag_snap:
				p.y = snappedf(p.y, SNAP)
			_disable_auto_ground(selected)
		else:
			p += Vector3(delta.x, 0, delta.z)
			if _drag_snap:
				p.x = snappedf(p.x, SNAP)
				p.z = snappedf(p.z, SNAP)
	if _drag_mode == "axis" and absf(_drag_dir.y) > 0.9:
		_disable_auto_ground(selected) # 沿 Y 軸拖＝手動指定高度
	selected.position = p
	if selected.auto_ground:
		ground_object(selected)
	inspector.refresh()
	_mark_dirty()


## 滑鼠射線與「通過拖曳起點、沿著軸方向的直線」最接近點的參數
func _axis_param(mouse: Vector2) -> float:
	var cam := overview.get_camera()
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	var u := _drag_dir
	var w := _drag_start_pos - o
	var b := u.dot(d)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-5:
		return _drag_start_s
	return (b * d.dot(w) - u.dot(w)) / denom


## 旋轉：用滑鼠繞物件螢幕中心轉的角度（任何視角都穩定，不受圓環側對鏡頭影響）
func _update_rotate(mouse: Vector2) -> void:
	var a := _screen_angle(mouse)
	_drag_total_angle += wrapf(a - _drag_last_angle, -PI, PI)
	_drag_last_angle = a
	# 螢幕角度（Y 向下）順時針為正；軸朝向鏡頭時，逆時針才是右手定則的正向
	var facing := signf(_drag_dir.dot(overview.get_camera().global_basis.z))
	var ang := -_drag_total_angle * (facing if facing != 0.0 else 1.0)
	if _drag_snap:
		ang = snappedf(ang, deg_to_rad(15.0))
	selected.global_basis = Basis(_drag_dir, ang) * _drag_start_basis
	if selected.auto_ground:
		ground_object(selected)
	inspector.refresh()
	_mark_dirty()


func _screen_angle(mouse: Vector2) -> float:
	var c := overview.get_camera().unproject_position(selected.global_position)
	return (mouse - c).angle()


func _update_scale(mouse: Vector2) -> void:
	var s := _drag_start_scale
	if _drag_axis == StudioGizmo.UNIFORM:
		var d := mouse - _drag_mouse0
		s = _drag_start_scale * exp((d.x - d.y) * 0.008) # 往右上拖放大、往左下縮小
	elif absf(_drag_start_s) > 0.001:
		var f := _axis_param(mouse) / _drag_start_s
		s[_drag_axis] = _drag_start_scale[_drag_axis] * f
	if _drag_snap:
		s = s.snapped(Vector3.ONE * 0.05)
	selected.scale = s.max(Vector3.ONE * 0.01)
	if selected.auto_ground:
		ground_object(selected)
	inspector.refresh()
	_mark_dirty()


func set_gizmo_mode(m: int) -> void:
	gizmo.mode = m
	for i in mode_btns.size():
		mode_btns[i].set_pressed_no_signal(i == m)
	_status(["移動模式（W）", "旋轉模式（E）：拖曳圓環旋轉", "縮放模式（R）：拖曳方塊單軸縮放、中心點等比縮放"][m])


func _plane_hit(mouse: Vector2, vertical: bool) -> Vector3:
	var cam := overview.get_camera()
	var o := cam.project_ray_origin(mouse)
	var d := cam.project_ray_normal(mouse)
	var plane: Plane
	if vertical:
		var n := -cam.global_basis.z
		n.y = 0.0
		plane = Plane(n.normalized() if n.length() > 0.01 else Vector3.BACK, selected.global_position)
	else:
		plane = Plane(Vector3.UP, selected.global_position.y)
	var hit = plane.intersects_ray(o, d)
	return hit if hit != null else selected.global_position


# ================================================================ 存檔 / 讀檔

func _scene_dict() -> Dictionary:
	var d := _snapshot()
	d.erase("selected")
	d["version"] = 1
	d["camera"] = {"pos": StudioShape._v(phone_cam.position), "rot": StudioShape._v(phone_cam.rotation_degrees), "fov": phone_cam.fov}
	var takes := []
	if anim_player.has_animation_library(""):
		var lib := anim_player.get_animation_library("")
		for n in lib.get_animation_list():
			takes.append(_take_to_dict(n, lib.get_animation(n)))
	d["takes"] = takes
	var wps := []
	for w in waypoints:
		var xf: Transform3D = w.xf
		wps.append({"pos": StudioShape._v(xf.origin), "rot": StudioShape._v(xf.basis.get_euler() * (180.0 / PI)), "fov": w.fov})
	d["waypoints"] = wps
	return d


func _take_to_dict(n: String, a: Animation) -> Dictionary:
	var pos := []
	var rot := []
	var fovk := []
	for ti in a.get_track_count():
		for k in a.track_get_key_count(ti):
			var t := snappedf(a.track_get_key_time(ti, k), 0.0001)
			var v = a.track_get_key_value(ti, k)
			if a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
				pos.append([t, v.x, v.y, v.z])
			elif a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				rot.append([t, v.x, v.y, v.z, v.w])
			elif a.track_get_type(ti) == Animation.TYPE_VALUE and str(a.track_get_path(ti)).ends_with(":fov"):
				fovk.append([t, v])
	return {"name": n, "length": a.length, "aspect": a.get_meta("aspect", 16.0 / 9.0), "fov": a.get_meta("fov", phone_cam.fov), "pos": pos, "rot": rot, "fov_keys": fovk}


func _take_from_dict(d: Dictionary) -> void:
	var a := Animation.new()
	var path := anim_player.get_node(anim_player.root_node).get_path_to(phone_cam)
	var pt := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pt, path)
	var rt := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(rt, path)
	for k in d.get("pos", []):
		a.position_track_insert_key(pt, k[0], Vector3(k[1], k[2], k[3]))
	for k in d.get("rot", []):
		a.rotation_track_insert_key(rt, k[0], Quaternion(k[1], k[2], k[3], k[4]))
	var fk: Array = d.get("fov_keys", [])
	if not fk.is_empty():
		var ft := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(ft, NodePath(str(path) + ":fov"))
		for k in fk:
			a.track_insert_key(ft, k[0], float(k[1]))
	a.length = d.get("length", 1.0)
	a.set_meta("aspect", d.get("aspect", 16.0 / 9.0))
	a.set_meta("fov", d.get("fov", 50.0))
	take_library().add_animation(d.get("name", "take"), a)


func take_library() -> AnimationLibrary:
	if not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", AnimationLibrary.new())
	return anim_player.get_animation_library("")


func save_scene(save_as: bool) -> void:
	if current_path == "" or save_as:
		_open_dialog("save")
		return
	var f := FileAccess.open(current_path, FileAccess.WRITE)
	if f == null:
		_status("存檔失敗：%s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(_scene_dict(), "\t"))
	f.close()
	_dirty = false
	_update_title()
	_status("已儲存 %s" % current_path)


func load_scene(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(text)
	if not d is Dictionary:
		_status("無法讀取場景：%s" % path)
		return
	anim_player.stop()
	reset_objects()
	_clear_objects()
	for o in d.get("objects", []):
		objects_root.add_child(StudioShape.from_dict(o), true)
	env = DEFAULT_ENV.duplicate()
	var e = d.get("env", {})
	if e is Dictionary:
		env.merge(e, true)
	_apply_env()
	var c = d.get("camera", {})
	if c is Dictionary and c.has("pos"):
		phone_cam.position = StudioShape._to_v(c.pos, phone_cam.position)
		phone_cam.rotation_degrees = StudioShape._to_v(c.rot, phone_cam.rotation_degrees)
		phone_cam.fov = c.get("fov", 50.0)
	var lib := take_library()
	for n in lib.get_animation_list():
		lib.remove_animation(n)
	for t in d.get("takes", []):
		_take_from_dict(t)
	waypoints.clear()
	for w in d.get("waypoints", []):
		var r := StudioShape._to_v(w.get("rot"), Vector3.ZERO) * (PI / 180.0)
		waypoints.append({"xf": Transform3D(Basis.from_euler(r), StudioShape._to_v(w.get("pos"), Vector3.ZERO)), "fov": float(w.get("fov", 50.0))})
	_waypoints_changed()
	current_path = path
	_reset_undo()
	_structure_changed()
	_refresh_takes()
	_sync_camera_controls()
	_dirty = false
	_update_title()
	_status("已開啟 %s" % path)


## 有未儲存的修改時先問一下再執行 action
func _confirm_discard(action: Callable) -> void:
	if not _dirty:
		action.call()
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "ShotPilot"
	dlg.dialog_text = "目前的場景還沒儲存，要放棄修改嗎？"
	dlg.ok_button_text = "放棄修改"
	dlg.cancel_button_text = "取消"
	dlg.theme = get_window().theme # 父節點是 Node3D，主題不會自動繼承
	dlg.confirmed.connect(action)
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_discard(func(): get_tree().quit())


func _new_scene() -> void:
	anim_player.stop()
	reset_objects()
	_clear_objects()
	env = DEFAULT_ENV.duplicate()
	_apply_env()
	waypoints.clear()
	_waypoints_changed()
	var lib := take_library()
	for n in lib.get_animation_list():
		lib.remove_animation(n)
	current_path = ""
	_reset_undo()
	_structure_changed()
	_refresh_takes()
	_dirty = false
	_update_title()


func studio_dir(sub: String) -> String:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("ShotPilot").path_join(sub)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _open_dialog(mode: String) -> void:
	if file_dialog:
		file_dialog.queue_free()
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	match mode:
		"open":
			file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			file_dialog.filters = PackedStringArray(["*.json ; ShotPilot 場景"])
			file_dialog.current_dir = studio_dir("scenes")
			file_dialog.file_selected.connect(load_scene)
		"save":
			file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			file_dialog.filters = PackedStringArray(["*.json ; ShotPilot 場景"])
			file_dialog.current_dir = studio_dir("scenes")
			file_dialog.current_file = current_path.get_file() if current_path != "" else "scene.json"
			file_dialog.file_selected.connect(func(p):
				current_path = p if p.ends_with(".json") else p + ".json"
				save_scene(false))
		"model":
			file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			file_dialog.filters = PackedStringArray(["*.glb, *.gltf ; glTF 模型"])
			file_dialog.file_selected.connect(import_model)
	add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(900, 600))


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		_update_title()


func _update_title() -> void:
	var n := current_path.get_file() if current_path != "" else "未命名場景"
	get_window().title = "ShotPilot — %s%s" % [n, " *" if _dirty else ""]


func _status(t: String) -> void:
	status_lbl.text = t


# ================================================================ 每幀

func _process(delta: float) -> void:
	_tick_scene_clock(delta)
	_ui_t += delta
	if _ui_t < 0.25:
		return
	_ui_t = 0.0
	var n := rig.get_client_count()
	server_lbl.text = "手機 App 連線位址：\n%s\n已連線：%d 台%s" % [
		"\n".join(rig.get_addresses()), n, "（追蹤中）" if rig.is_tracking() else ""]
	_draw_paths()
	rec_btn.text = "■ 停止錄製" if rig.recording else "● 開始錄製"
	if not _fov_slider.has_focus():
		_sync_camera_controls()
	rec_btn.modulate = Color(1, 0.75, 0.75) if rig.recording else Color.WHITE


# ================================================================ UI

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# ---- 上方工具列
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_H
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	top.add_child(bar)

	var add_menu := MenuButton.new()
	add_menu.text = "＋ 新增物件"
	add_menu.flat = false
	var keys := StudioShape.TYPES.keys().filter(func(k): return k != "model")
	for i in keys.size():
		add_menu.get_popup().add_item(StudioShape.TYPES[keys[i]], i)
	add_menu.get_popup().id_pressed.connect(func(id): add_shape(keys[id]))
	bar.add_child(add_menu)
	_tool_btn(bar, "匯入模型", func(): _open_dialog("model"), "匯入 .glb / .gltf")
	_tool_btn(bar, "複製", duplicate_selected, "⌘D")
	_tool_btn(bar, "刪除", delete_selected, "Delete")
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for i in 3:
		var b := _tool_btn(bar, ["✥ 移動", "⟳ 旋轉", "⤢ 縮放"][i], func(): set_gizmo_mode(i), ["W", "E（或雙擊物件）", "R"][i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		mode_btns.append(b)
	bar.add_child(VSeparator.new())
	obj_play_btn = _tool_btn(bar, "▶ 物件動畫", func(): play_objects(not objects_playing), "播放／暫停物件的移動路線")
	_tool_btn(bar, "⟲", reset_objects, "物件回到起點")
	bar.add_child(VSeparator.new())
	_tool_btn(bar, "復原", undo, "⌘Z")
	_tool_btn(bar, "重做", redo, "⇧⌘Z")
	bar.add_child(VSeparator.new())
	_tool_btn(bar, "新場景", func(): _confirm_discard(_new_scene), "⌘N")
	_tool_btn(bar, "開啟…", func(): _confirm_discard(func(): _open_dialog("open")), "⌘O")
	_tool_btn(bar, "儲存", func(): save_scene(false), "⌘S")
	_tool_btn(bar, "另存…", func(): save_scene(true), "⇧⌘S")
	bar.add_child(VSeparator.new())
	snap_chk = CheckBox.new()
	snap_chk.text = "吸附 %.2fm" % SNAP
	snap_chk.button_pressed = true
	snap_chk.focus_mode = Control.FOCUS_NONE
	bar.add_child(snap_chk)
	status_lbl = Label.new()
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_lbl.modulate = Color(1, 1, 1, 0.6)
	status_lbl.clip_text = true
	bar.add_child(status_lbl)

	# ---- 左側分頁
	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_top = TOP_H
	left.offset_right = LEFT_W
	root.add_child(left)
	var tabs := TabContainer.new()
	left.add_child(tabs)
	tabs.add_child(_build_objects_tab())
	tabs.add_child(_scroll(_build_presets_tab(), "範本"))
	tabs.add_child(_scroll(_build_env_tab(), "環境"))
	tabs.add_child(_scroll(_build_camera_tab(), "鏡頭／錄影"))

	# ---- 右側屬性
	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -RIGHT_W
	right.offset_top = TOP_H
	root.add_child(right)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rs)
	inspector = StudioInspector.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.before_edit.connect(func(tag):
		_stop_objects_for_edit()
		push_undo(tag))
	inspector.edited.connect(func(tag):
		_mark_dirty()
		if tag in ["pos", "rot", "size", "ground_toggle"] and selected and selected.auto_ground:
			ground_object(selected)
			inspector.refresh()
		if tag == "name":
			_structure_changed())
	inspector.path_place_toggled.connect(func(on):
		_placing_path = on
		if on:
			_stop_objects_for_edit()
			_status("點選場景中的位置新增路徑點（Esc 結束）"))
	rs.add_child(inspector)


func _tool_btn(parent: Control, text: String, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _scroll(content: Control, title: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _build_objects_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "物件"
	outliner = ItemList.new()
	outliner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outliner.item_selected.connect(func(i): select(objects_root.get_child(i)))
	box.add_child(outliner)
	var hint := Label.new()
	hint.text = "雙擊列表項目可對準該物件"
	hint.modulate = Color(1, 1, 1, 0.5)
	box.add_child(hint)
	outliner.item_activated.connect(func(i):
		overview.focus_on(objects_root.get_child(i).global_position + Vector3(0, 0.5, 0)))
	return box


func _build_env_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_section(box, "太陽")
	_env_slider(box, "sun_elev", "高度角 (°)", 0, 90, 1)
	_env_slider(box, "sun_azim", "方位角 (°)", -180, 180, 1)
	_env_slider(box, "sun_energy", "亮度", 0, 5, 0.05)
	_env_color(box, "sun_color", "顏色")
	_env_check(box, "shadows", "投射陰影")
	_section(box, "天空 / 背景")
	_env_check(box, "sky", "使用天空（取消＝純色背景）")
	_env_color(box, "sky_top", "天空頂部")
	_env_color(box, "sky_horizon", "地平線")
	_env_color(box, "bg_color", "純色背景")
	_env_slider(box, "ambient", "環境光", 0, 3, 0.05)
	_env_slider(box, "fog", "霧濃度", 0, 0.2, 0.002)
	_section(box, "地板")
	_env_check(box, "floor", "顯示地板")
	_env_color(box, "floor_color", "地板顏色")
	_env_slider(box, "floor_size", "地板大小 (m)", 4, 200, 1)
	_env_check(box, "grid", "顯示格線（只在編輯視圖）")
	return box


func _section(box: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	StudioTheme.section_label_style(l)
	box.add_child(l)


func _env_slider(box: Control, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var l := Label.new()
	l.modulate = Color(1, 1, 1, 0.75)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	box.add_child(s)
	var upd := func(): l.text = "%s：%s" % [label, str(snappedf(s.value, step))]
	s.value_changed.connect(func(v):
		upd.call()
		if not s.has_meta("syncing"):
			push_undo("env_" + key)
			env[key] = v
			_apply_env()
			_mark_dirty())
	env_controls[key] = [s, upd]


func _env_color(box: Control, key: String, label: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.modulate = Color(1, 1, 1, 0.75)
	row.add_child(l)
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(90, 28)
	c.color_changed.connect(func(col):
		push_undo("env_" + key)
		env[key] = col.to_html(false)
		_apply_env()
		_mark_dirty())
	row.add_child(c)
	box.add_child(row)
	env_controls[key] = [c, null]


func _env_check(box: Control, key: String, label: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.toggled.connect(func(on):
		if not c.has_meta("syncing"):
			push_undo("env_" + key)
			env[key] = on
			_apply_env()
			_mark_dirty())
	box.add_child(c)
	env_controls[key] = [c, null]


func _sync_env_controls() -> void:
	for key in env_controls:
		var ctrl: Control = env_controls[key][0]
		ctrl.set_meta("syncing", true)
		if ctrl is HSlider:
			(ctrl as HSlider).set_value_no_signal(float(env[key]))
			env_controls[key][1].call()
		elif ctrl is ColorPickerButton:
			(ctrl as ColorPickerButton).color = Color.from_string(env[key], Color.WHITE)
		elif ctrl is CheckBox:
			(ctrl as CheckBox).set_pressed_no_signal(bool(env[key]))
		ctrl.remove_meta("syncing")


var _fov_slider: HSlider
var _fov_lbl: Label


func _build_camera_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_section(box, "手機連線")
	server_lbl = Label.new()
	server_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(server_lbl)

	_section(box, "鏡頭")
	_fov_lbl = Label.new()
	box.add_child(_fov_lbl)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 15
	_fov_slider.max_value = 110
	_fov_slider.step = 1
	_fov_slider.value_changed.connect(func(v):
		phone_cam.fov = v
		_fov_lbl.text = "FOV（垂直視角）：%d°" % v
		_mark_dirty())
	box.add_child(_fov_slider)
	var place := Button.new()
	place.text = "把鏡頭放到目前視角"
	place.tooltip_text = "手機鏡頭移到編輯視圖的位置與角度，並重新對齊手機朝向"
	place.pressed.connect(func():
		phone_cam.global_transform = overview.get_camera().global_transform
		rig.recenter()
		_mark_dirty())
	box.add_child(place)
	var recenter := Button.new()
	recenter.text = "歸零（對齊手機目前朝向）"
	recenter.pressed.connect(rig.recenter)
	box.add_child(recenter)
	var follow := CheckBox.new()
	follow.text = "編輯視圖跟隨手機鏡頭"
	follow.toggled.connect(func(on): overview.follow_phone = on)
	box.add_child(follow)
	var trail := Button.new()
	trail.text = "清除移動軌跡"
	trail.pressed.connect(overview.clear_trail)
	box.add_child(trail)

	_section(box, "手感")
	var mode := OptionButton.new()
	for t in ["只控制角度", "搖桿移動", "加速度計＋搖桿"]:
		mode.add_item(t)
	mode.select(rig.position_mode)
	mode.item_selected.connect(func(i): rig.position_mode = i)
	box.add_child(mode)
	_rig_slider(box, "角度平滑", 0.0, 0.95, 0.01, rig.rotation_smoothing, func(v): rig.rotation_smoothing = v)
	_rig_slider(box, "移動速度 (m/s)", 0.2, 8.0, 0.1, rig.move_speed, func(v): rig.move_speed = v)
	_rig_slider(box, "升降速度 (m/s)", 0.1, 4.0, 0.1, rig.vertical_speed, func(v): rig.vertical_speed = v)
	_rig_slider(box, "串流 FPS", 5, 60, 1, rig.stream_fps, func(v): rig.stream_fps = int(v))
	var hchk := CheckBox.new()
	hchk.text = "蹲下／站起時鏡頭跟著升降"
	hchk.button_pressed = rig.track_height
	hchk.toggled.connect(func(on): rig.track_height = on)
	box.add_child(hchk)
	_rig_slider(box, "高度靈敏度", 0.2, 3.0, 0.05, rig.height_gain, func(v): rig.height_gain = v)
	var roll := CheckBox.new()
	roll.text = "鎖定水平（移除滾轉）"
	roll.toggled.connect(func(on): rig.lock_roll = on)
	box.add_child(roll)

	_build_waypoint_section(box)

	_section(box, "錄影")
	rec_btn = Button.new()
	rec_btn.custom_minimum_size.y = 40
	StudioTheme.primary_button(rec_btn)
	rec_btn.pressed.connect(func(): rig.recording = not rig.recording)
	box.add_child(rec_btn)
	takes_list = ItemList.new()
	takes_list.custom_minimum_size.y = 120
	box.add_child(takes_list)
	var trow := HBoxContainer.new()
	box.add_child(trow)
	_tool_btn(trow, "▶ 預覽", _play_take, "在手機鏡頭上播放這段運鏡")
	_tool_btn(trow, "■", func(): anim_player.stop(), "停止")
	_tool_btn(trow, "刪除", _delete_take, "")

	_section(box, "輸出給 AI 影片")
	export_res = OptionButton.new()
	for t in ["長邊 960", "長邊 1280（720p）", "長邊 1920（1080p）", "長邊 2560"]:
		export_res.add_item(t)
	export_res.select(1)
	box.add_child(export_res)
	export_fps = OptionButton.new()
	for t in ["24 fps", "30 fps", "60 fps"]:
		export_fps.add_item(t)
	export_fps.select(0)
	box.add_child(export_fps)
	export_aspect = OptionButton.new()
	for t in ["依錄製時的手機方向", "16:9 橫式", "9:16 直式", "1:1"]:
		export_aspect.add_item(t)
	box.add_child(export_aspect)
	export_depth = CheckBox.new()
	export_depth.text = "同時輸出深度圖"
	export_depth.button_pressed = true
	box.add_child(export_depth)
	export_png = CheckBox.new()
	export_png.text = "保留 PNG 序列（很佔空間）"
	export_png.tooltip_text = "預設畫面直接送進 ffmpeg，只留 mp4；勾選才會另外存每一幀 PNG"
	box.add_child(export_png)
	var far_lbl := Label.new()
	box.add_child(far_lbl)
	export_far = HSlider.new()
	export_far.min_value = 2
	export_far.max_value = 100
	export_far.step = 0.5
	export_far.value_changed.connect(func(v): far_lbl.text = "深度最遠距離：%.1f m（之後全黑）" % v)
	export_far.value = 15
	box.add_child(export_far)
	export_btn = Button.new()
	export_btn.text = "匯出選取的 take"
	export_btn.custom_minimum_size.y = 36
	StudioTheme.primary_button(export_btn)
	export_btn.pressed.connect(_export_take)
	box.add_child(export_btn)
	export_bar = ProgressBar.new()
	box.add_child(export_bar)
	export_lbl = Label.new()
	export_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_lbl.text = "輸出到 文件/ShotPilot/exports" + ("" if TakeExporter.find_ffmpeg() != "" else "\n（找不到 ffmpeg，只會輸出 PNG 序列）")
	box.add_child(export_lbl)
	_tool_btn(box, "開啟輸出資料夾", func():
		OS.shell_open(last_export_dir if last_export_dir != "" else studio_dir("exports")), "")

	_sync_camera_controls()
	return box


func _rig_slider(box: Control, label: String, lo: float, hi: float, step: float, value: float, apply: Callable) -> void:
	var l := Label.new()
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(func(v):
		l.text = "%s：%s" % [label, str(snappedf(v, step))]
		apply.call(v))
	s.value = value
	l.text = "%s：%s" % [label, str(snappedf(value, step))]
	box.add_child(s)


func _sync_camera_controls() -> void:
	if _fov_slider:
		_fov_slider.set_value_no_signal(phone_cam.fov)
		_fov_lbl.text = "FOV（垂直視角）：%d°" % phone_cam.fov


func _refresh_takes() -> void:
	takes_list.clear()
	if not anim_player.has_animation_library(""):
		return
	var lib := anim_player.get_animation_library("")
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		var asp: float = a.get_meta("aspect", 16.0 / 9.0)
		takes_list.add_item("%s　%.1fs　%s" % [n, a.length, "橫" if asp >= 1.0 else "直"])
		takes_list.set_item_metadata(takes_list.item_count - 1, n)
	if takes_list.item_count > 0:
		takes_list.select(takes_list.item_count - 1)


func _selected_take() -> String:
	var sel := takes_list.get_selected_items()
	return takes_list.get_item_metadata(sel[0]) if sel.size() > 0 else ""


func _play_take() -> void:
	var n := _selected_take()
	if n != "":
		anim_player.play(n)
		overview.clear_trail()


func _delete_take() -> void:
	var n := _selected_take()
	if n != "":
		if anim_player.current_animation == n:
			anim_player.stop()
		take_library().remove_animation(n)
		_refresh_takes()
		_mark_dirty()


func _export_take() -> void:
	if exporter.busy:
		exporter.cancel()
		return
	var n := _selected_take()
	if n == "":
		export_lbl.text = "請先錄一段 take（或從列表選一段）"
		return
	var a := take_library().get_animation(n)
	var long_side: int = [960, 1280, 1920, 2560][export_res.selected]
	var fps: int = [24, 30, 60][export_fps.selected]
	var aspect: float = [a.get_meta("aspect", 16.0 / 9.0), 16.0 / 9.0, 9.0 / 16.0, 1.0][export_aspect.selected]
	var scene_name := current_path.get_file().get_basename() if current_path != "" else "untitled"
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var out := studio_dir("exports").path_join("%s_%s_%s" % [scene_name, n, stamp])
	anim_player.stop()
	export_btn.text = "取消匯出"
	var src := Camera3D.new() # 用錄製當下的 FOV
	src.fov = a.get_meta("fov", phone_cam.fov)
	src.near = phone_cam.near
	src.far = phone_cam.far
	add_child(src)
	src.global_transform = phone_cam.global_transform # 軌道缺資料時的備用位置
	reset_objects()
	await exporter.export_take(a, self, src, out, long_side, aspect, fps, export_depth.button_pressed, export_far.value, _apply_scene_time, export_png.button_pressed)
	reset_objects()
	src.queue_free()


func _on_export_progress(done: int, total: int, msg: String) -> void:
	export_bar.max_value = total
	export_bar.value = done
	export_lbl.text = msg


func _on_export_finished(out_dir: String, ok: bool) -> void:
	export_btn.text = "匯出選取的 take"
	last_export_dir = out_dir
	if ok:
		export_lbl.text = "完成：" + out_dir
		OS.shell_open(out_dir)
	# 失敗時 progress 已經把原因寫進 export_lbl


# ================================================================ 記錄點 / 自動運鏡

var wp_list: ItemList
var wp_duration: HSlider
var wp_ease: CheckBox


func add_waypoint(xf: Transform3D, fov: float) -> void:
	waypoints.append({"xf": xf.orthonormalized(), "fov": fov})
	_waypoints_changed()
	_mark_dirty()


func clear_waypoints() -> void:
	waypoints.clear()
	_waypoints_changed()
	_mark_dirty()


## duration <= 0 時依路徑長度自動決定（約 1 m/s，2~60 秒）
func create_auto_take(duration: float, ease_in_out: bool, take_name: String) -> String:
	if waypoints.size() < 2:
		_status("至少要 2 個記錄點才能產生自動運鏡")
		return ""
	if duration <= 0.0:
		var length := 0.0
		for i in range(1, waypoints.size()):
			length += (waypoints[i].xf.origin as Vector3).distance_to(waypoints[i - 1].xf.origin)
			length += (waypoints[i].xf.basis.get_rotation_quaternion() as Quaternion).angle_to(waypoints[i - 1].xf.basis.get_rotation_quaternion()) * 1.5
		duration = clampf(length / 1.0, 2.0, 60.0)
	var path := anim_player.get_node(anim_player.root_node).get_path_to(phone_cam)
	var a := CameraPath.bake(waypoints, duration, ease_in_out, path)
	a.set_meta("aspect", rig.get_aspect())
	var lib := take_library()
	if take_name == "" or lib.has_animation(take_name):
		var i := 1
		while lib.has_animation("auto_%03d" % i):
			i += 1
		take_name = "auto_%03d" % i
	lib.add_animation(take_name, a)
	_refresh_takes()
	_mark_dirty()
	_status("已產生自動運鏡 %s（%.1f 秒，%d 個點）" % [take_name, duration, waypoints.size()])
	return take_name


func _waypoints_changed() -> void:
	rig.extra_state = {"wp": waypoints.size()}
	if wp_list:
		wp_list.clear()
		for i in waypoints.size():
			var o: Vector3 = waypoints[i].xf.origin
			wp_list.add_item("點 %d　(%.1f, %.1f, %.1f)" % [i + 1, o.x, o.y, o.z])
	_draw_waypoints()


func _draw_waypoints() -> void:
	_wp_mesh.clear_surfaces()
	for c in _wp_labels.get_children():
		c.queue_free()
	if waypoints.is_empty():
		return
	var col := Color(1.0, 0.55, 0.75)
	_wp_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in waypoints.size():
		var xf: Transform3D = waypoints[i].xf
		var h := 0.12
		var w := h * rig.get_aspect()
		var c := [xf * Vector3(-w, h, -0.3), xf * Vector3(w, h, -0.3), xf * Vector3(w, -h, -0.3), xf * Vector3(-w, -h, -0.3)]
		for k in 4:
			_wp_line(xf.origin, c[k], col)
			_wp_line(c[k], c[(k + 1) % 4], col)
		var lbl := Label3D.new()
		lbl.text = str(i + 1)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 48
		lbl.outline_size = 12
		lbl.modulate = col
		lbl.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
		lbl.position = xf.origin + Vector3(0, 0.25, 0)
		_wp_labels.add_child(lbl)
	# 預覽路徑（Catmull-Rom）
	if waypoints.size() >= 2:
		var pts: Array[Vector3] = []
		for wpt in waypoints:
			pts.append(wpt.xf.origin)
		var prev := pts[0]
		for i in pts.size() - 1:
			for k in range(1, 17):
				var p := pts[i].cubic_interpolate(pts[i + 1], pts[maxi(i - 1, 0)], pts[mini(i + 2, pts.size() - 1)], k / 16.0)
				_wp_line(prev, p, Color(1.0, 0.7, 0.85, 0.8))
				prev = p
	_wp_mesh.surface_end()


func _wp_line(a: Vector3, b: Vector3, col: Color) -> void:
	_wp_mesh.surface_set_color(col)
	_wp_mesh.surface_add_vertex(a)
	_wp_mesh.surface_set_color(col)
	_wp_mesh.surface_add_vertex(b)


func _on_phone_command(c: String) -> void:
	match c:
		"waypoint":
			add_waypoint(phone_cam.global_transform, phone_cam.fov)
			_status("手機新增記錄點 %d" % waypoints.size())
		"clear_wp":
			clear_waypoints()
		"undo_wp":
			if not waypoints.is_empty():
				waypoints.pop_back()
				_waypoints_changed()
				_mark_dirty()
		"auto":
			var n := create_auto_take(wp_duration.value if wp_duration else 0.0, wp_ease.button_pressed if wp_ease else true, "")
			if n != "":
				_play_take_named(n)
		"play":
			# 手機「回放」：播放中就停止，否則播放選取（或最新）的 take
			if anim_player.is_playing():
				anim_player.stop()
			else:
				var n := _selected_take()
				if n == "" and takes_list.item_count > 0:
					n = takes_list.get_item_metadata(takes_list.item_count - 1)
				if n != "":
					_play_take_named(n)
				else:
					_status("還沒有任何 take 可以回放")


func _play_take_named(n: String) -> void:
	anim_player.stop()
	anim_player.play(n)
	overview.clear_trail()


func _build_waypoint_section(box: Control) -> void:
	_section(box, "記錄點／自動運鏡")
	var hint := Label.new()
	hint.text = "不用錄影：把鏡頭擺到幾個位置各記一個點，自動產生平滑運鏡。手機上按「記點」也可以。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	box.add_child(hint)
	wp_list = ItemList.new()
	wp_list.custom_minimum_size.y = 100
	box.add_child(wp_list)
	var row := HBoxContainer.new()
	box.add_child(row)
	_tool_btn(row, "＋記點", func(): add_waypoint(phone_cam.global_transform, phone_cam.fov), "以目前手機鏡頭的位置與角度新增記錄點")
	_tool_btn(row, "跳到", func():
		var sel := wp_list.get_selected_items()
		if sel.size() > 0:
			phone_cam.global_transform = waypoints[sel[0]].xf
			phone_cam.fov = waypoints[sel[0]].fov
			_sync_camera_controls(), "把鏡頭移到選取的記錄點")
	_tool_btn(row, "刪除", func():
		var sel := wp_list.get_selected_items()
		if sel.size() > 0:
			waypoints.remove_at(sel[0])
			_waypoints_changed()
			_mark_dirty(), "")
	_tool_btn(row, "清除", clear_waypoints, "")
	var dl := Label.new()
	box.add_child(dl)
	wp_duration = HSlider.new()
	wp_duration.min_value = 0
	wp_duration.max_value = 60
	wp_duration.step = 0.5
	wp_duration.value_changed.connect(func(v): dl.text = "總長度：%s" % ("自動（依路徑長度）" if v <= 0.0 else "%.1f 秒" % v))
	wp_duration.value = 8.0
	box.add_child(wp_duration)
	wp_ease = CheckBox.new()
	wp_ease.text = "緩入緩出"
	wp_ease.button_pressed = true
	box.add_child(wp_ease)
	var gen := Button.new()
	gen.text = "產生自動運鏡並預覽"
	gen.custom_minimum_size.y = 36
	StudioTheme.primary_button(gen)
	gen.pressed.connect(func():
		var n := create_auto_take(wp_duration.value, wp_ease.button_pressed, "")
		if n != "":
			_play_take_named(n))
	box.add_child(gen)


# ================================================================ 給 StudioApi（MCP）用

func find_object(n: String) -> StudioShape:
	for s: StudioShape in objects_root.get_children():
		if String(s.name) == n and not s.is_queued_for_deletion():
			return s
	return null


## Godot 會自動讓同層節點名稱唯一（重複時加數字），設定後讀回即可
func unique_name(base: String, s: StudioShape) -> String:
	s.name = base.validate_node_name()
	return String(s.name)


func after_api_edit() -> void:
	inspector.refresh()
	_structure_changed()


func clear_objects_api() -> void:
	_clear_objects()
	_structure_changed()


func api_scene_info() -> Dictionary:
	var d := _scene_dict()
	d.erase("takes")
	var takes := []
	var lib := take_library()
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		takes.append({"name": n, "length": a.length, "aspect": a.get_meta("aspect", 16.0 / 9.0), "auto": a.get_meta("auto", false)})
	d["takes"] = takes
	d["object_types"] = StudioShape.TYPES
	d["presets"] = {"scene": ScenePresets.scene_names(), "lighting": ScenePresets.LIGHTING.keys(), "camera": ScenePresets.CAMERAS}
	d["path_modes"] = StudioShape.PATH_MODES
	d["phone_connected"] = rig.get_client_count() > 0
	return d


func api_set_camera(p: Dictionary) -> Dictionary:
	phone_cam.global_transform = StudioApi._camera_xf(p, phone_cam.global_transform)
	if p.has("fov"):
		phone_cam.fov = clampf(float(p.fov), 10.0, 120.0)
	_sync_camera_controls()
	rig.recenter()
	_mark_dirty()
	return {"pos": StudioShape._v(phone_cam.position), "rot": StudioShape._v(phone_cam.rotation_degrees), "fov": phone_cam.fov}


func api_set_env(p: Dictionary) -> Dictionary:
	push_undo("api_env")
	for k in p:
		if env.has(k):
			var v = p[k]
			if env[k] is String and v is String:
				env[k] = Color.from_string(v, Color.WHITE).to_html(false)
			else:
				env[k] = v
	_apply_env()
	_mark_dirty()
	return env


func api_screenshot(view: String, long_side: int) -> Image:
	long_side = clampi(long_side, 128, 4096)
	if view == "camera":
		var aspect := rig.get_aspect()
		var size := Vector2i(long_side, int(long_side / aspect)) if aspect >= 1.0 else Vector2i(int(long_side * aspect), long_side)
		var vp := SubViewport.new()
		vp.size = size
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.world_3d = get_world_3d()
		var cam := Camera3D.new()
		cam.fov = phone_cam.fov
		cam.cull_mask &= ~(1 << (PhoneCameraRig.GIZMO_LAYER - 1))
		vp.add_child(cam)
		add_child(vp)
		cam.global_transform = phone_cam.global_transform
		cam.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		vp.queue_free()
		return img
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var scale := float(long_side) / maxf(full.get_width(), full.get_height())
	if scale < 1.0:
		full.resize(int(full.get_width() * scale), int(full.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	return full


func api_export(take_name: String, p: Dictionary) -> String:
	if exporter.busy:
		return ""
	var a := take_library().get_animation(take_name)
	var long_side := int(p.get("long_side", 1280))
	var fps := int(p.get("fps", 24))
	var aspect := float(p.get("aspect", a.get_meta("aspect", 16.0 / 9.0)))
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var scene_name := current_path.get_file().get_basename() if current_path != "" else "untitled"
	var out := studio_dir("exports").path_join("%s_%s_%s" % [scene_name, take_name, stamp])
	var src := Camera3D.new()
	src.fov = a.get_meta("fov", phone_cam.fov)
	add_child(src)
	src.global_transform = phone_cam.global_transform
	anim_player.stop()
	reset_objects()
	await exporter.export_take(a, self, src, out, long_side, aspect, fps, bool(p.get("depth", true)), float(p.get("depth_far", 15.0)), _apply_scene_time, bool(p.get("keep_png", false)))
	reset_objects()
	src.queue_free()
	return out if exporter.last_ok else ""


# ================================================================ 物件動畫（移動路線）

func _shapes() -> Array:
	return objects_root.get_children().filter(func(s): return not s.is_queued_for_deletion())


func play_objects(on: bool) -> void:
	_stop_placing()
	objects_playing = on
	obj_play_btn.text = "⏸ 物件動畫" if on else "▶ 物件動畫"


func reset_objects() -> void:
	objects_playing = false
	scene_time = 0.0
	if obj_play_btn:
		obj_play_btn.text = "▶ 物件動畫"
	for s: StudioShape in _shapes():
		s.reset_motion()
	if selected:
		inspector.refresh()


func _stop_objects_for_edit() -> void:
	if objects_playing or scene_time > 0.0 or _shapes().any(func(s): return s._animating):
		reset_objects()


func _apply_scene_time(t: float) -> void:
	for s: StudioShape in _shapes():
		if s.has_motion():
			s.apply_motion(t)
			if s.auto_ground:
				ground_object(s)


func _tick_scene_clock(delta: float) -> void:
	# 開始錄製：物件從起點出發，take 的 0 秒＝場景時間 0 秒
	if rig.recording and not _was_recording:
		reset_objects()
		play_objects(true)
	_was_recording = rig.recording
	var take_playing := anim_player.is_playing() and not rig.recording
	if take_playing:
		_apply_scene_time(anim_player.current_animation_position)
	elif _was_take_playing:
		reset_objects()
	elif objects_playing:
		scene_time += delta
		_apply_scene_time(scene_time)
	_was_take_playing = take_playing


func _stop_placing() -> void:
	if _placing_path:
		inspector.stop_placing()


func _place_path_point(mouse: Vector2) -> void:
	var cam := overview.get_camera()
	var home := selected.home_position()
	# 點在起點高度的水平面上；物件開啟自動貼合時，走到樓梯、平台上會自動跟著高度
	var hit = Plane(Vector3.UP, home.y).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit == null:
		return
	push_undo("path_pts")
	var p: Vector3 = hit
	if snap_chk.button_pressed:
		p.x = snappedf(p.x, SNAP)
		p.z = snappedf(p.z, SNAP)
	selected.path_offsets.append(Vector3(p.x - home.x, 0.0, p.z - home.z))
	if selected.path_mode == "none":
		selected.path_mode = "pingpong"
	inspector.refresh_path()
	_draw_paths()
	_mark_dirty()
	_status("已新增路徑點 %d" % selected.path_offsets.size())


func _draw_paths() -> void:
	_path_mesh.clear_surfaces()
	var any := false
	for s: StudioShape in _shapes():
		if s.path_offsets.is_empty():
			continue
		if not any:
			_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		var col := Color(0.3, 0.95, 1.0) if s == selected else Color(0.3, 0.8, 0.9, 0.45)
		var pts := s.path_world_points()
		if s.path_mode == "loop":
			pts.append(pts[0])
		for i in pts.size():
			var p := pts[i] + Vector3(0, 0.03, 0)
			for d in [Vector3(0.12, 0, 0), Vector3(0, 0, 0.12)]:
				_path_line(p - d, p + d, col)
			if i > 0:
				_path_line(pts[i - 1] + Vector3(0, 0.03, 0), p, col)
	if any:
		_path_mesh.surface_end()


func _path_line(a: Vector3, b: Vector3, col: Color) -> void:
	_path_mesh.surface_set_color(col)
	_path_mesh.surface_add_vertex(a)
	_path_mesh.surface_set_color(col)
	_path_mesh.surface_add_vertex(b)


# ================================================================ 自動貼合下方物件

## 把物件放到腳下最高的表面上（地板或其他物件的頂面）。
## 只考慮「頂面不高於目前底部 + STEP_UP」的表面，避免跳到天花板或高樓上面。
func ground_object(s: StudioShape) -> void:
	var box := s.world_aabb()
	var c := box.get_center()
	var half := Vector2(maxf(box.size.x, 0.02), maxf(box.size.z, 0.02)) * 0.2
	var foot := Rect2(Vector2(c.x, c.z) - half, half * 2.0)
	var bottom := box.position.y
	var surface := 0.0
	for o: StudioShape in _shapes():
		if o == s or o.is_light():
			continue
		for b in o.world_part_boxes():
			if b.end.y > bottom + STEP_UP or b.end.y <= surface:
				continue
			if foot.intersects(Rect2(b.position.x, b.position.z, b.size.x, b.size.z)):
				surface = b.end.y
	s.position.y += surface - bottom


func _disable_auto_ground(s: StudioShape) -> void:
	if s.auto_ground:
		s.auto_ground = false
		_status("已關閉「%s」的自動貼合（手動調整了高度）" % s.name)


# ================================================================ 範本

func _build_presets_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_section(box, "場景")
	var hint := Label.new()
	hint.text = "一鍵換掉整個場景（物件＋燈光＋機位），可以 ⌘Z 復原"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	_preset_grid(box, ScenePresets.scene_names(), apply_scene_preset)
	_section(box, "燈光")
	_preset_grid(box, ScenePresets.LIGHTING.keys(), apply_lighting_preset)
	_section(box, "機位")
	var hint2 := Label.new()
	hint2.text = "以選取的物件為主角（沒選就找人偶），從它的正面（+Z）拍"
	hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint2.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint2)
	_preset_grid(box, ScenePresets.CAMERAS, apply_camera_preset)
	var addwp := CheckBox.new()
	addwp.text = "套用機位時同時記點"
	addwp.toggled.connect(func(on): set_meta("preset_adds_waypoint", on))
	box.add_child(addwp)
	return box


func _preset_grid(box: Control, names: Array, cb: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for n in names:
		var b := Button.new()
		b.text = n
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): cb.call(n))
		grid.add_child(b)
	box.add_child(grid)


func apply_scene_preset(n: String) -> bool:
	var d: Dictionary = ScenePresets.scenes().get(n, {})
	if d.is_empty():
		return false
	reset_objects()
	push_undo("preset")
	_last_undo_tag = ""
	_clear_objects()
	for o in d.objects:
		objects_root.add_child(StudioShape.from_dict(o), true)
	env.merge(ScenePresets.LIGHTING.get(d.get("lighting", ""), {}), true)
	env.merge(d.get("env", {}), true)
	if not d.get("env", {}).has("sky") and not ScenePresets.LIGHTING.get(d.get("lighting", ""), {}).has("sky"):
		env.sky = true
	_apply_env()
	var c: Dictionary = d.get("camera", {})
	if not c.is_empty():
		api_set_camera(c)
		overview.set_view(StudioApi._vec(c.get("look_at"), Vector3.ZERO), 10.0, 35.0, -28.0)
	_structure_changed()
	_status("已套用場景：%s" % n)
	return true


func apply_lighting_preset(n: String) -> bool:
	var e: Dictionary = ScenePresets.LIGHTING.get(n, {})
	if e.is_empty():
		return false
	push_undo("preset_light")
	_last_undo_tag = ""
	env.merge(e, true)
	_apply_env()
	_mark_dirty()
	_status("已套用燈光：%s" % n)
	return true


func apply_camera_preset(n: String) -> bool:
	var subject: StudioShape = selected
	if subject == null:
		for s: StudioShape in _shapes():
			if s.shape_type == "mannequin":
				subject = s
				break
	var pos := Vector3.ZERO
	var height := 1.7
	var front := Vector3.BACK
	if subject:
		var b := subject.world_aabb()
		pos = Vector3(b.get_center().x, b.position.y, b.get_center().z)
		height = b.size.y
		front = subject.global_basis.z
		front.y = 0.0
		front = front.normalized() if front.length() > 0.01 else Vector3.BACK
	var right := Vector3.UP.cross(front).normalized() * -1.0
	var r := ScenePresets.camera_for(n, pos, height, front, right)
	phone_cam.global_transform = r.xf
	phone_cam.fov = r.fov
	_sync_camera_controls()
	rig.recenter()
	if has_meta("preset_adds_waypoint") and get_meta("preset_adds_waypoint"):
		add_waypoint(phone_cam.global_transform, phone_cam.fov)
	_mark_dirty()
	_status("機位：%s%s" % [n, "（主角：%s）" % subject.name if subject else ""])
	return true
