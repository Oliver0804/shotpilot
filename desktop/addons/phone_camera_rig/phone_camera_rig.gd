@tool
class_name PhoneCameraRig
extends Node
## 接收手機 App 傳來的姿態，驅動 target（Camera3D 或任何 Node3D）的位置與角度，
## 同時把 target 視角的畫面即時串流回手機。編輯器內（@tool）與遊戲執行時都能用。

const Server := preload("phone_cam_server.gd")
## 視覺化輔助物件（視錐、軌跡）放在這個 render layer，串流鏡頭不會拍到
const GIZMO_LAYER := 20

enum PositionMode {
	ROTATION_ONLY, ## 只控制角度，位置不動
	JOYSTICK, ## 手機上的虛擬搖桿移動
	ACCELEROMETER, ## 加速度計積分（會飄，搭配回歸錨點）＋搖桿
}

@export var target: Node3D
@export var port := 8765
@export var autostart_in_game := true
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var server_running := false:
	set(v):
		if v:
			start()
		else:
			stop()
	get:
		return _server != null and _server.is_running()

@export_group("旋轉")
@export_range(0.0, 0.98, 0.01) var rotation_smoothing := 0.5
## 移除滾轉（鏡頭水平線永遠保持水平）
@export var lock_roll := false
## 手機右搖桿推到底時的轉動速度（度/秒）
@export var look_speed := 90.0

@export_group("位置")
@export var position_mode := PositionMode.JOYSTICK
@export var move_speed := 2.0
@export var vertical_speed := 1.0
@export var accel_gain := 1.0
@export var velocity_damping := 3.0
@export var accel_deadzone := 0.25
## 加速度計造成的位移每秒往錨點拉回的強度（抑制積分漂移）
@export var return_to_anchor := 0.5

@export_group("高度追蹤")
## 用垂直加速度偵測蹲下／站起，鏡頭跟著升降（不需 AR）
@export var track_height := true
@export_range(0.2, 3.0, 0.05) var height_gain := 1.15
## 低於這個加速度（m/s²）且持續一小段時間視為靜止，速度歸零並校正偏差
@export var height_still_threshold := 0.18
## 相對站姿的可移動範圍（m）：x＝最低、y＝最高
@export var height_range := Vector2(-1.4, 0.6)

@export_group("串流")
@export var stream_enabled := true
## 長邊像素，短邊依手機螢幕比例計算
@export_range(240, 1920, 1) var stream_long_side := 960
@export_range(1, 60, 1) var stream_fps := 30
@export_range(0.1, 1.0, 0.05) var stream_quality := 0.6

@export_group("錄製")
@export var animation_player: AnimationPlayer
@export var take_prefix := "phone_take"
@export_range(10, 120, 1) var record_fps := 30
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR) var recording := false:
	set(v):
		if v:
			start_recording()
		else:
			stop_recording()
	get:
		return _anim != null

signal clients_changed(count: int)
signal take_recorded(anim_name: String)
## 手機送來的、rig 本身不處理的指令（例如 "waypoint"、"auto"），交給上層（Studio）處理
signal command(name: String)

## 額外附在 state 訊息裡回傳給手機的欄位（例如記錄點數量）
var extra_state := {}

var _server: Server
var _has_pose := false
var _need_recenter := true
var _need_rehold := false
var _phone_q := Quaternion.IDENTITY
var _cur_q := Quaternion.IDENTITY
var _yaw_offset := 0.0
var _anchor := Vector3.ZERO
var _offset := Vector3.ZERO # 搖桿位移
var _drift := Vector3.ZERO # 加速度計位移
var _vel := Vector3.ZERO
var _joy := Vector2.ZERO
var _lift := 0.0
var _look := Vector2.ZERO
var _h_off := 0.0
var _h_vel := 0.0
var _h_bias := 0.0
var _h_still_t := 0.0
var _h_at_still := 0.0
var _pitch_offset := 0.0
var _frozen := false
var _phone_aspect := 16.0 / 9.0
var _was_playing := false
var _pre_play_xf := Transform3D()

var _viewport: SubViewport
var _stream_cam: Camera3D
var _stream_t := 0.0
var _encode_task := -1
var _encoded := PackedByteArray()
var _cam_send_t := 0.0

var _anim: Animation
var _pos_track := -1
var _rot_track := -1
var _fov_track := -1
var _rec_t := 0.0
var _next_key_t := 0.0


func _ready() -> void:
	if not Engine.is_editor_hint() and autostart_in_game:
		start()


func _exit_tree() -> void:
	stop_recording()
	_finish_encode()
	stop()


func start() -> void:
	if _server == null:
		_server = Server.new()
		_server.message.connect(_on_message)
		_server.clients_changed.connect(_on_clients_changed)
	if _server.is_running():
		return
	var err := _server.start(port)
	if err != OK:
		push_error("PhoneCameraRig: 無法監聽 port %d（%s）" % [port, error_string(err)])
		return
	print("PhoneCameraRig: 伺服器啟動，手機 App 連到 %s" % ", ".join(get_addresses()))
	notify_property_list_changed()


func stop() -> void:
	if _server:
		_server.stop()
	_has_pose = false
	_free_viewport()
	notify_property_list_changed()


func get_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in Server.local_addresses():
		out.append("%s:%d" % [ip, port])
	return out


func get_client_count() -> int:
	return _server.client_count if _server else 0


func recenter() -> void:
	_need_recenter = true


## 手機螢幕寬/高（直拿 < 1、橫拿 > 1），串流與視錐都依此比例
func get_aspect() -> float:
	return _phone_aspect


func is_tracking() -> bool:
	return _has_pose


## 串流畫面的貼圖（尚未有手機連線時為 null）
func get_stream_texture() -> Texture2D:
	return _viewport.get_texture() if _viewport else null


# ---------------------------------------------------------------- 網路訊息

func _on_clients_changed(n: int) -> void:
	if n == 0:
		_has_pose = false
		_need_recenter = true
		_free_viewport()
	clients_changed.emit(n)


func _on_message(_id: int, d: Dictionary) -> void:
	match d.get("t"):
		"pose":
			var q = d.get("q")
			if q is Array and q.size() == 4:
				_phone_q = Quaternion(q[0], q[1], q[2], q[3]).normalized()
			var j = d.get("j")
			if j is Array and j.size() == 2:
				_joy = Vector2(j[0], j[1]).limit_length(1.0)
			_lift = clampf(float(d.get("v", 0.0)), -1.0, 1.0)
			var l = d.get("l")
			_look = Vector2(l[0], l[1]).limit_length(1.0) if l is Array and l.size() == 2 else Vector2.ZERO
			_phone_aspect = clampf(float(d.get("aspect", _phone_aspect)), 0.25, 4.0)
			var f := bool(d.get("f", false))
			if _frozen and not f:
				_need_rehold = true
			_frozen = f
			var a = d.get("a")
			if a is Array and a.size() == 3 and not _frozen:
				var acc := Vector3(a[0], a[1], a[2])
				var dt := clampf(float(d.get("dt", 0.016)), 0.0, 0.1)
				if track_height:
					_integrate_height(acc.y, dt)
					acc.y = 0.0
				if position_mode == PositionMode.ACCELEROMETER:
					_integrate_accel(acc, dt)
			_has_pose = true
		"fov":
			# 手機雙指縮放
			var cam := target as Camera3D
			if cam:
				cam.fov = clampf(float(d.get("v", cam.fov)), 10.0, 120.0)
		"cmd":
			match d.get("c"):
				"recenter":
					_need_recenter = true
				"rec":
					recording = not recording
					notify_property_list_changed()
				var other:
					command.emit(str(other))


## 垂直方向單獨積分：蹲下／站起是「加速→減速→停住」的短動作，
## 停住時（加速度持續很小）把速度歸零並學習感測器偏差，抑制漂移。
func _integrate_height(raw_ay: float, dt: float) -> void:
	var ay := raw_ay - _h_bias
	if absf(ay) < height_still_threshold:
		if _h_still_t == 0.0:
			_h_at_still = _h_off # 記下開始靜止的高度
		_h_still_t += dt
	else:
		_h_still_t = 0.0
	if _h_still_t > 0.25:
		if _h_vel != 0.0:
			_h_off = _h_at_still # 確認是靜止：撤銷等待期間殘餘速度造成的漂移
		_h_vel = 0.0
		_h_bias = lerpf(_h_bias, raw_ay, 0.05)
	else:
		_h_vel += ay * height_gain * dt
		_h_vel *= exp(-0.3 * dt)
	var h := _h_off + _h_vel * dt
	if h < height_range.x or h > height_range.y:
		_h_vel = 0.0
	_h_off = clampf(h, height_range.x, height_range.y)


func is_playing_back() -> bool:
	return _anim == null and animation_player != null and animation_player.is_playing()


func get_height_offset() -> float:
	return _h_off


func _integrate_accel(a_world: Vector3, dt: float) -> void:
	a_world = Basis(Vector3.UP, _yaw_offset) * a_world
	if a_world.length() < accel_deadzone:
		a_world = Vector3.ZERO
		_vel *= exp(-8.0 * dt) # 零速修正：靜止時速度快速歸零
	_vel += a_world * accel_gain * dt
	_vel *= exp(-velocity_damping * dt)
	_drift += _vel * dt


# ---------------------------------------------------------------- 每幀

func _process(delta: float) -> void:
	if _server == null:
		return
	_server.poll(delta)
	if not is_instance_valid(target) or not target.is_inside_tree():
		return

	# AnimationPlayer 在回放 take 時，讓出鏡頭控制權（只串流畫面），結束後回到原位
	if is_playing_back():
		if not _was_playing:
			_was_playing = true
			_pre_play_xf = target.global_transform
		_send_camera_state(delta)
		if stream_enabled and _has_pose:
			_stream_frame(delta)
		return
	elif _was_playing:
		_was_playing = false
		target.global_transform = _pre_play_xf
		_need_rehold = true

	if not _has_pose:
		if _anim:
			_record_frame(delta) # 沒連手機也照錄（鏡頭不動，但物件動畫、手動調整都會錄進去）
		return

	if _need_recenter:
		_recenter(true)
		_need_recenter = false
	elif _need_rehold:
		_recenter(false)
	_need_rehold = false

	if not _frozen:
		# 右搖桿：左右＝水平轉、上下＝俯仰（疊加在手機姿態上）
		var look_rad := deg_to_rad(look_speed) * delta
		_yaw_offset -= _look.x * look_rad
		_pitch_offset = clampf(_pitch_offset + _look.y * look_rad, -1.4, 1.4)
		var tgt := Quaternion(Vector3.UP, _yaw_offset) * _phone_q * Quaternion(Vector3.RIGHT, _pitch_offset)
		if lock_roll:
			tgt = _remove_roll(tgt)
		_cur_q = _cur_q.slerp(tgt, 1.0 - pow(rotation_smoothing, delta * 60.0))

	if position_mode != PositionMode.ROTATION_ONLY:
		var b := Basis(_cur_q)
		var fwd := _flat_forward(b)
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		_offset += (right * _joy.x + fwd * _joy.y) * move_speed * delta
		_offset += Vector3.UP * _lift * vertical_speed * delta
	_drift *= exp(-return_to_anchor * delta)

	var scale := target.global_basis.get_scale()
	target.global_transform = Transform3D(Basis(_cur_q).scaled(scale), _anchor + _offset + _drift + Vector3.UP * _h_off)

	if _anim:
		_record_frame(delta)
	_send_camera_state(delta)
	if stream_enabled:
		_stream_frame(delta)


func _recenter(reset_position: bool) -> void:
	var cam_yaw := _yaw_of(target.global_basis.orthonormalized())
	_yaw_offset = cam_yaw - _yaw_of(Basis(_phone_q))
	if reset_position:
		_anchor = target.global_position
		_offset = Vector3.ZERO
		_drift = Vector3.ZERO
		_vel = Vector3.ZERO
		_pitch_offset = 0.0
		_h_off = 0.0
		_h_vel = 0.0
		_cur_q = Quaternion(Vector3.UP, _yaw_offset) * _phone_q


## 鏡頭朝向的水平角；鏡頭幾乎垂直朝下/朝上時改用鏡頭的 up 向量判斷
static func _yaw_of(b: Basis) -> float:
	var f := _flat_forward(b)
	return atan2(-f.x, -f.z)


static func _flat_forward(b: Basis) -> Vector3:
	var f := -b.z
	if absf(f.y) > 0.9:
		f = b.y * -signf(f.y)
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


static func _remove_roll(q: Quaternion) -> Quaternion:
	var f := -(Basis(q).z)
	if absf(f.y) > 0.99:
		return q
	var right := f.cross(Vector3.UP).normalized()
	var up := right.cross(f)
	return Quaternion(Basis(right, up, -f))


# ---------------------------------------------------------------- 串流

func _send_camera_state(delta: float) -> void:
	_cam_send_t += delta
	if _cam_send_t < 0.1:
		return
	_cam_send_t = 0.0
	var p := target.global_position
	var state := {
		"t": "state",
		"p": [p.x, p.y, p.z],
		"rec": _anim != null,
		"rec_t": _rec_t if _anim else 0.0,
		"playing": is_playing_back(),
	}
	if target is Camera3D:
		state["fov"] = (target as Camera3D).fov
	state.merge(extra_state)
	_server.broadcast(state)


func _ensure_viewport() -> void:
	if _viewport:
		return
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = target.get_world_3d()
	_stream_cam = Camera3D.new()
	_viewport.add_child(_stream_cam)
	add_child(_viewport, false, Node.INTERNAL_MODE_BACK)


func _free_viewport() -> void:
	if _viewport:
		_viewport.queue_free()
	_viewport = null
	_stream_cam = null


func _stream_frame(delta: float) -> void:
	_ensure_viewport()
	var long_side := float(stream_long_side)
	var size := Vector2i(long_side, long_side / _phone_aspect) if _phone_aspect >= 1.0 \
		else Vector2i(long_side * _phone_aspect, long_side)
	if _viewport.size != size:
		_viewport.size = size

	_stream_cam.global_transform = target.global_transform
	var src := target as Camera3D
	if src:
		_stream_cam.fov = src.fov
		_stream_cam.near = src.near
		_stream_cam.far = src.far
		_stream_cam.environment = src.environment
		_stream_cam.attributes = src.attributes
		_stream_cam.cull_mask = src.cull_mask
	_stream_cam.cull_mask &= ~(1 << (GIZMO_LAYER - 1))
	_stream_cam.current = true

	# 上一幀在背景編碼完成就送出
	if _encode_task != -1 and WorkerThreadPool.is_task_completed(_encode_task):
		_finish_encode()
		if not _encoded.is_empty():
			_server.broadcast_binary(_encoded)

	# 累加計時並保留餘數；若直接歸零，60Hz 下 24fps 會因量化變成每 3 幀一張（20fps）
	var interval := 1.0 / stream_fps
	_stream_t += delta
	if _stream_t < interval:
		return
	_stream_t = fmod(_stream_t, interval)
	if _encode_task != -1 or _server.is_congested():
		return # 編碼還沒完成或網路塞住就丟幀，避免延遲累積
	var img := _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return
	_encode_task = WorkerThreadPool.add_task(_encode.bind(img, stream_quality))


func _encode(img: Image, quality: float) -> void:
	_encoded = img.save_jpg_to_buffer(quality)


func _finish_encode() -> void:
	if _encode_task != -1:
		WorkerThreadPool.wait_for_task_completion(_encode_task)
		_encode_task = -1


# ---------------------------------------------------------------- 錄製

func start_recording() -> void:
	if _anim:
		return
	if animation_player == null or target == null:
		push_warning("PhoneCameraRig: 錄製需要設定 animation_player 與 target")
		return
	var root := animation_player.get_node_or_null(animation_player.root_node)
	if root == null:
		push_warning("PhoneCameraRig: AnimationPlayer 的 root_node 無效")
		return
	var path := root.get_path_to(target)
	_anim = Animation.new()
	_pos_track = _anim.add_track(Animation.TYPE_POSITION_3D)
	_anim.track_set_path(_pos_track, path)
	_rot_track = _anim.add_track(Animation.TYPE_ROTATION_3D)
	_anim.track_set_path(_rot_track, path)
	_fov_track = -1
	if target is Camera3D:
		_fov_track = _anim.add_track(Animation.TYPE_VALUE)
		_anim.track_set_path(_fov_track, NodePath(str(path) + ":fov"))
	_rec_t = 0.0
	_next_key_t = 0.0
	print("PhoneCameraRig: 開始錄製")


func stop_recording() -> void:
	if _anim == null:
		return
	if _rec_t < 0.2 or _anim.track_get_key_count(_pos_track) < 2:
		push_warning("PhoneCameraRig: 錄製時間太短（%.2f 秒），已捨棄" % _rec_t)
		_anim = null
		take_recorded.emit("")
		return
	_anim.length = maxf(_rec_t, 0.001)
	var lib: AnimationLibrary
	if animation_player.has_animation_library(""):
		lib = animation_player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		animation_player.add_animation_library("", lib)
	var i := 1
	while lib.has_animation("%s_%03d" % [take_prefix, i]):
		i += 1
	var anim_name := "%s_%03d" % [take_prefix, i]
	_anim.set_meta("aspect", _phone_aspect)
	if target is Camera3D:
		_anim.set_meta("fov", (target as Camera3D).fov)
	lib.add_animation(anim_name, _anim)
	_anim = null
	take_recorded.emit(anim_name)
	print("PhoneCameraRig: 錄製完成 → %s（%.2f 秒）" % [anim_name, _rec_t])
	if Engine.is_editor_hint():
		var ei = Engine.get_singleton("EditorInterface")
		if ei:
			ei.mark_scene_as_unsaved()


## 錄製上限（秒），超過自動停止，避免忘了按停止錄出超長 take
@export var max_record_seconds := 600.0


func _record_frame(delta: float) -> void:
	if _rec_t >= max_record_seconds:
		push_warning("PhoneCameraRig: 錄製達到上限 %.0f 秒，自動停止" % max_record_seconds)
		stop_recording()
		return
	if _rec_t >= _next_key_t:
		_anim.position_track_insert_key(_pos_track, _rec_t, target.position)
		_anim.rotation_track_insert_key(_rot_track, _rec_t, target.quaternion)
		if _fov_track >= 0:
			_anim.track_insert_key(_fov_track, _rec_t, (target as Camera3D).fov)
		_next_key_t += 1.0 / record_fps
	_rec_t += delta
