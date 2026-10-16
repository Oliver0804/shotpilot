extends SubViewport
## 示範模式：沒連電腦時，手機自己渲染一個範例場景。
## 鏡頭邏輯直接用桌面端的 PhoneCameraRig（本機模式），物件與場景範本也跟桌面端共用，
## 所以手感、錄製、記點、自動運鏡都跟連上電腦時一樣。

signal state_updated(state: Dictionary)

const DEFAULT_ENV := {
	"sun_elev": 50.0, "sun_azim": 30.0, "sun_energy": 1.2, "sun_color": "fff4e0",
	"sky": true, "sky_top": "6f8fb8", "sky_horizon": "c9d3de", "bg_color": "202226",
	"ambient": 1.0, "fog": 0.0, "floor": true, "floor_color": "9e9aa8", "floor_size": 30.0,
	"shadows": true,
}
## 示範用的場景（ScenePresets 的名稱），第一個是預設
const SCENES := ["街道巷口", "客廳", "公園", "空白攝影棚", "舞台", "走廊", "辦公室"]

var rig: PhoneCameraRig
var cam: Camera3D
var anim_player: AnimationPlayer
var scene_index := 0
var waypoints: Array = []

var _env := Environment.new()
var _sky_mat := ProceduralSkyMaterial.new()
var _sun := DirectionalLight3D.new()
var _floor := MeshInstance3D.new()
var _floor_mat := StandardMaterial3D.new()
var _objects := Node3D.new()
var _scene_t := 0.0
var _was_recording := false
var _last_take := ""


func _ready() -> void:
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_2X

	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	add_child(_sun)
	_floor.mesh = PlaneMesh.new()
	_floor.material_override = _floor_mat
	add_child(_floor)
	add_child(_objects)

	cam = Camera3D.new()
	cam.name = "PhoneCamera"
	cam.cull_mask &= ~(1 << (PhoneCameraRig.GIZMO_LAYER - 1)) # 燈泡等編輯用的輔助物件不入鏡
	add_child(cam)
	anim_player = AnimationPlayer.new()
	add_child(anim_player)

	rig = PhoneCameraRig.new()
	rig.autostart_in_game = false
	rig.local_mode = true
	rig.stream_enabled = false
	rig.target = cam
	rig.animation_player = anim_player
	rig.command.connect(_on_command)
	rig.state_updated.connect(func(s): state_updated.emit(s))
	rig.take_recorded.connect(func(n):
		if n != "":
			_last_take = n)
	add_child(rig)

	apply_scene(0)


func _process(delta: float) -> void:
	# 物件的移動路線：錄製從 0 秒開始、回放跟著 take 的時間走，其他時候一直播
	if rig.recording and not _was_recording:
		_scene_t = 0.0
	_was_recording = rig.recording
	var t := _scene_t
	if rig.is_playing_back():
		t = anim_player.current_animation_position
	else:
		_scene_t += delta
	for s: StudioShape in _objects.get_children():
		if s.has_motion():
			s.apply_motion(t)


## 跟網路訊息相同格式的 pose／fov／cmd
func feed(d: Dictionary) -> void:
	rig.feed(d)


func next_scene() -> String:
	return apply_scene((scene_index + 1) % SCENES.size())


func apply_scene(i: int) -> String:
	scene_index = i
	var n: String = SCENES[i]
	var d: Dictionary = ScenePresets.scenes().get(n, {})
	anim_player.stop()
	for c in _objects.get_children():
		_objects.remove_child(c)
		c.queue_free()
	for o in d.get("objects", []):
		_objects.add_child(StudioShape.from_dict(o), true)
	var env := DEFAULT_ENV.duplicate()
	env.merge(ScenePresets.LIGHTING.get(d.get("lighting", ""), {}), true)
	env.merge(d.get("env", {}), true)
	_apply_env(env)
	var c: Dictionary = d.get("camera", {})
	var pos := StudioShape._to_v(c.get("pos"), Vector3(0, 1.5, 4))
	var look := StudioShape._to_v(c.get("look_at"), Vector3(0, 1, 0))
	cam.look_at_from_position(pos, look, Vector3.UP)
	cam.fov = float(c.get("fov", 50.0))
	waypoints.clear()
	for take in _library().get_animation_list():
		_library().remove_animation(take)
	_last_take = ""
	_scene_t = 0.0
	rig.extra_state = {"wp": 0}
	rig.recenter()
	return n


func _apply_env(env: Dictionary) -> void:
	_sun.rotation_degrees = Vector3(-float(env.sun_elev), float(env.sun_azim), 0)
	_sun.light_energy = float(env.sun_energy)
	_sun.light_color = Color.from_string(env.sun_color, Color.WHITE)
	_sun.shadow_enabled = env.shadows
	_sky_mat.sky_top_color = Color.from_string(env.sky_top, Color.SKY_BLUE)
	_sky_mat.sky_horizon_color = Color.from_string(env.sky_horizon, Color.WHITE)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color.from_string(env.floor_color, Color.GRAY).darkened(0.4)
	if env.sky:
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color.from_string(env.bg_color, Color.BLACK)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = _env.background_color.lerp(Color.WHITE, 0.3)
	_env.ambient_light_energy = float(env.ambient)
	_env.fog_enabled = float(env.fog) > 0.0
	_env.fog_density = float(env.fog)
	_env.fog_light_color = _sky_mat.sky_horizon_color
	_floor.visible = env.floor
	_floor_mat.albedo_color = Color.from_string(env.floor_color, Color.GRAY)
	_floor_mat.roughness = 0.9
	(_floor.mesh as PlaneMesh).size = Vector2.ONE * float(env.floor_size)


# ---------------------------------------------------------------- 記點／自動運鏡／回放

func _on_command(c: String) -> void:
	match c:
		"waypoint":
			waypoints.append({"xf": cam.global_transform.orthonormalized(), "fov": cam.fov})
		"undo_wp":
			if not waypoints.is_empty():
				waypoints.pop_back()
		"clear_wp":
			waypoints.clear()
		"auto":
			if waypoints.size() >= 2:
				_play(_bake_auto())
		"play":
			if anim_player.is_playing():
				anim_player.stop()
			else:
				_play(_latest_take())
	rig.extra_state = {"wp": waypoints.size()}


func _bake_auto() -> String:
	var length := 0.0
	for i in range(1, waypoints.size()):
		length += (waypoints[i].xf.origin as Vector3).distance_to(waypoints[i - 1].xf.origin)
		length += (waypoints[i].xf.basis.get_rotation_quaternion() as Quaternion).angle_to(waypoints[i - 1].xf.basis.get_rotation_quaternion()) * 1.5
	var path := anim_player.get_node(anim_player.root_node).get_path_to(cam)
	var a := CameraPath.bake(waypoints, clampf(length, 2.0, 60.0), true, path)
	var lib := _library()
	var i := 1
	while lib.has_animation("auto_%03d" % i):
		i += 1
	lib.add_animation("auto_%03d" % i, a)
	_last_take = "auto_%03d" % i
	return _last_take


func _latest_take() -> String:
	return _last_take if _library().has_animation(_last_take) else ""


func _play(n: String) -> void:
	if n == "":
		return
	anim_player.stop()
	anim_player.play(n)


func _library() -> AnimationLibrary:
	if not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", AnimationLibrary.new())
	return anim_player.get_animation_library("")
