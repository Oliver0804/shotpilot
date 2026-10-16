class_name StudioGizmo
extends Node3D
## 選取物件的黃色外框 + 變換把手（螢幕上大小固定），三種模式：
##   移動：XYZ 箭頭（世界軸）
##   旋轉：XYZ 圓環（世界軸）
##   縮放：XYZ 方塊端點（物件本身的軸）＋中心點等比縮放
## 只畫在 GIZMO_LAYER，串流與匯出都不會拍到。

enum Mode { MOVE, ROTATE, SCALE }

const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS: Array[Color] = [Color(1, 0.3, 0.3), Color(0.35, 1, 0.35), Color(0.35, 0.55, 1)]
const PICK_PX := 12.0
const UNIFORM := 3 ## 縮放模式的中心點

var mode := Mode.MOVE
var target: StudioShape
var camera: Camera3D
var hover_axis := -1
var active_axis := -1

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 20
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = mat
	mi.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func axis_length() -> float:
	if not target or not camera:
		return 1.0
	return camera.global_position.distance_to(target.global_position) * 0.15


## 目前模式下第 i 軸的世界方向（縮放用物件自己的軸）
func axis_dir(i: int) -> Vector3:
	if mode == Mode.SCALE and is_instance_valid(target):
		return target.global_basis[i].normalized()
	return AXES[i]


## 滑鼠位置對應到哪個把手（-1＝沒有）
func pick_axis(mouse: Vector2) -> int:
	if not is_instance_valid(target) or not camera:
		return -1
	var o := target.global_position
	if camera.is_position_behind(o):
		return -1
	var c2 := camera.unproject_position(o)
	if mode == Mode.SCALE and c2.distance_to(mouse) < PICK_PX:
		return UNIFORM
	var best := -1
	var best_d := PICK_PX
	for i in 3:
		for seg in _handle_segments(i):
			if camera.is_position_behind(seg[0]) or camera.is_position_behind(seg[1]):
				continue
			var a := camera.unproject_position(seg[0])
			var b := camera.unproject_position(seg[1])
			var d := Geometry2D.get_closest_point_to_segment(mouse, a, b).distance_to(mouse)
			if d < best_d:
				best_d = d
				best = i
	return best


## 用來點選的線段（移動／縮放＝軸線，旋轉＝圓環）
func _handle_segments(i: int) -> Array:
	var o := target.global_position
	var L := axis_length()
	if mode == Mode.ROTATE:
		var out := []
		var pts := _ring(i, o, L * 0.85, 32)
		for k in pts.size():
			out.append([pts[k], pts[(k + 1) % pts.size()]])
		return out
	return [[o, o + axis_dir(i) * L]]


func _ring(i: int, o: Vector3, r: float, n: int) -> PackedVector3Array:
	var u := AXES[(i + 1) % 3]
	var v := AXES[(i + 2) % 3]
	var pts := PackedVector3Array()
	for k in n:
		var t := TAU * k / n
		pts.append(o + (u * cos(t) + v * sin(t)) * r)
	return pts


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not is_instance_valid(target) or not camera:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_box(target.global_transform, target.local_aabb(), Color(1, 0.85, 0.2))
	var o := target.global_position
	var L := axis_length()
	for i in 3:
		var hot := i == active_axis or (active_axis == -1 and i == hover_axis)
		var col := Color.WHITE if hot else COLORS[i]
		match mode:
			Mode.MOVE:
				var dir := axis_dir(i)
				var tip := o + dir * L
				_line(o, tip, col)
				var s1 := AXES[(i + 1) % 3] * L * 0.07
				var s2 := AXES[(i + 2) % 3] * L * 0.07
				var back := tip - dir * L * 0.18
				for s in [s1, -s1, s2, -s2]:
					_line(tip, back + s, col)
			Mode.ROTATE:
				var pts := _ring(i, o, L * 0.85, 64)
				for k in pts.size():
					_line(pts[k], pts[(k + 1) % pts.size()], col)
			Mode.SCALE:
				var dir := axis_dir(i)
				var tip := o + dir * L
				_line(o, tip, col)
				var half := L * 0.06
				_draw_box(Transform3D(target.global_basis.orthonormalized(), tip), AABB(-Vector3.ONE * half, Vector3.ONE * half * 2.0), col)
	if mode == Mode.SCALE:
		var hot := active_axis == UNIFORM or (active_axis == -1 and hover_axis == UNIFORM)
		var half := L * 0.05
		_draw_box(Transform3D(camera.global_basis, o), AABB(-Vector3.ONE * half, Vector3.ONE * half * 2.0), Color.WHITE if hot else Color(1, 0.85, 0.2))
	_mesh.surface_end()


func _draw_box(xf: Transform3D, b: AABB, col: Color) -> void:
	var p := []
	for i in 8:
		p.append(xf * b.get_endpoint(i))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line(p[e[0]], p[e[1]], col)


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)
