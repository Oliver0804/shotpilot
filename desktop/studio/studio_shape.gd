class_name StudioShape
extends Node3D
## 場景編輯器裡的一個物件。原點在物件底部中心（position.y = 0 就是放在地板上），
## 大小用 scale 調整。可序列化成 Dictionary 存檔。

const TYPES := {
	"box": "方塊",
	"sphere": "球體",
	"cylinder": "圓柱",
	"capsule": "膠囊",
	"cone": "圓錐",
	"torus": "圓環",
	"slab": "平板",
	"wall": "牆",
	"stairs": "樓梯",
	"mannequin": "人偶",
	"light": "點光源",
	"model": "模型",
}

var shape_type := "box"
var color := Color(0.75, 0.75, 0.78)
var roughness := 0.8
var metallic := 0.0
var light_energy := 2.0
var light_range := 6.0
var model_path := ""

## 移動路線：相對物件「起點」（編輯時的位置）的偏移點，依序走過
const PATH_MODES := {"none": "不移動", "once": "單次", "loop": "循環", "pingpong": "往復"}
var path_offsets: Array[Vector3] = []
var path_mode := "none"
var path_speed := 1.0
var face_motion := false
## 自動放在下方物件（或地板）上：水平移動時高度自動貼合
var auto_ground := true
var _animating := false
var _home_pos := Vector3.ZERO
var _home_rot := Vector3.ZERO

var _mat := StandardMaterial3D.new()
var _light: OmniLight3D
var _marker_mat: StandardMaterial3D
var _aabb := AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func setup(p_type: String) -> StudioShape:
	shape_type = p_type
	if p_type == "light":
		auto_ground = false
	if name == "" or name.begins_with("@"):
		name = TYPES.get(shape_type, shape_type)
	_build()
	return self


func is_light() -> bool:
	return shape_type == "light"


func has_material() -> bool:
	return shape_type != "light" and shape_type != "model"


## 物件本身座標系下的包圍盒（不含 scale），用來點選與畫選取框
func local_aabb() -> AABB:
	return _aabb


## 各個網格零件的世界包圍盒（樓梯每一階、人偶各部位分開算，貼合比整體包圍盒準）
func world_part_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for mi in find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).layers & (1 << (PhoneCameraRig.GIZMO_LAYER - 1)):
			continue # 燈光標記之類的輔助物件
		out.append((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
	return out


## 世界座標的包圍盒（含旋轉、縮放）
func world_aabb() -> AABB:
	return global_transform * _aabb


func apply_material() -> void:
	_mat.albedo_color = color
	_mat.roughness = roughness
	_mat.metallic = metallic
	if _light:
		_light.light_color = color
		_light.light_energy = light_energy
		_light.omni_range = light_range
		_marker_mat.albedo_color = color


func _build() -> void:
	for c in get_children():
		remove_child(c) # 先移除，否則 queue_free 前仍會被算進包圍盒
		c.queue_free()
	_light = null
	match shape_type:
		"box":
			_add_mesh(_box(Vector3.ONE), Vector3(0, 0.5, 0))
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			_add_mesh(m, Vector3(0, 0.5, 0))
		"cylinder":
			_add_mesh(_cyl(0.5, 0.5, 1.0), Vector3(0, 0.5, 0))
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = 0.3
			m.height = 1.2
			_add_mesh(m, Vector3(0, 0.6, 0))
		"cone":
			_add_mesh(_cyl(0.0, 0.5, 1.0), Vector3(0, 0.5, 0))
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = 0.3
			m.outer_radius = 0.5
			_add_mesh(m, Vector3(0, 0.1, 0))
		"slab":
			_add_mesh(_box(Vector3(1, 0.05, 1)), Vector3(0, 0.025, 0))
		"wall":
			_add_mesh(_box(Vector3(3, 2.5, 0.15)), Vector3(0, 1.25, 0))
		"stairs":
			var steps := 6
			for i in steps:
				var h := (i + 1) * 0.18
				_add_mesh(_box(Vector3(1.0, h, 0.28)), Vector3(0, h * 0.5, -i * 0.28))
		"mannequin":
			_build_mannequin()
		"light":
			_light = OmniLight3D.new()
			_light.position = Vector3(0, 0.15, 0)
			_light.shadow_enabled = true
			add_child(_light)
			var m := SphereMesh.new()
			m.radius = 0.15
			m.height = 0.3
			_marker_mat = StandardMaterial3D.new()
			_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var mi := _add_mesh(m, Vector3(0, 0.15, 0), _marker_mat)
			mi.layers = 1 << (PhoneCameraRig.GIZMO_LAYER - 1) # 只在編輯視圖看得到，不會被拍進去
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"model":
			_build_model()
	_aabb = _compute_aabb()
	apply_material()


func _build_mannequin() -> void:
	# 約 1.75m 的簡易人偶，給 AI 影片當「人物站位」
	for x in [-0.11, 0.11]:
		_add_mesh(_capsule(0.08, 0.85), Vector3(x, 0.43, 0))
	_add_mesh(_capsule(0.19, 0.62), Vector3(0, 1.15, 0))
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.26
	_add_mesh(head, Vector3(0, 1.6, 0))
	for x in [-0.27, 0.27]:
		var arm := _add_mesh(_capsule(0.06, 0.66), Vector3(x, 1.12, 0))
		arm.rotation.z = signf(x) * 0.12


func _build_model() -> void:
	if model_path == "":
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(model_path, state) != OK:
		push_warning("無法載入模型：%s" % model_path)
		_add_mesh(_box(Vector3.ONE), Vector3(0, 0.5, 0))
		return
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		return
	add_child(scene)
	# 讓模型底部中心對齊原點
	var box := _compute_aabb()
	scene.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)


func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat if mat else _mat
	add_child(mi)
	return mi


func _compute_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi in find_children("*", "MeshInstance3D", true, false):
		var xf := _relative_transform(mi)
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _relative_transform(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur and cur != self:
		xf = cur.transform * xf
		cur = cur.get_parent() as Node3D
	return xf


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


# ---------------------------------------------------------------- 移動路線

func has_motion() -> bool:
	return path_mode != "none" and not path_offsets.is_empty() and path_speed > 0.0


## 編輯時的位置（動畫中讀 position 會是移動後的位置）
func home_position() -> Vector3:
	return _home_pos if _animating else position


## 依場景時間 t（秒）擺到路線上的位置；t 相同結果就相同（錄製／回放／匯出一致）
func apply_motion(t: float) -> void:
	if not has_motion():
		return
	if not _animating:
		_home_pos = position
		_home_rot = rotation
		_animating = true
	var r := evaluate_path(t)
	position = _home_pos + r[0]
	rotation = _home_rot
	var dir: Vector3 = r[1]
	if face_motion and Vector2(dir.x, dir.z).length() > 0.001:
		rotation.y = atan2(dir.x, dir.z) # 物件正面是 +Z


func reset_motion() -> void:
	if _animating:
		position = _home_pos
		rotation = _home_rot
		_animating = false


## 回傳 [偏移, 前進方向]
func evaluate_path(t: float) -> Array:
	var pts: Array[Vector3] = [Vector3.ZERO]
	pts.append_array(path_offsets)
	if path_mode == "loop":
		pts.append(Vector3.ZERO)
	var lens: Array[float] = []
	var total := 0.0
	for i in range(1, pts.size()):
		var l := pts[i].distance_to(pts[i - 1])
		lens.append(l)
		total += l
	if total < 0.0001:
		return [Vector3.ZERO, Vector3.ZERO]
	var d := maxf(t, 0.0) * path_speed
	var backward := false
	match path_mode:
		"once":
			d = minf(d, total)
		"loop":
			d = fmod(d, total)
		"pingpong":
			backward = int(d / total) % 2 == 1
			d = pingpong(d, total)
	for i in lens.size():
		if d <= lens[i] or i == lens.size() - 1:
			var w := clampf(d / maxf(lens[i], 0.0001), 0.0, 1.0)
			var dir := (pts[i + 1] - pts[i]).normalized()
			return [pts[i].lerp(pts[i + 1], w), -dir if backward else dir]
		d -= lens[i]
	return [pts[-1], Vector3.ZERO]


## 路線上各點的世界座標（含起點），給視覺化用
func path_world_points() -> PackedVector3Array:
	var out := PackedVector3Array([home_position()])
	for o in path_offsets:
		out.append(home_position() + o)
	return out


# ---------------------------------------------------------------- 存檔

func to_dict() -> Dictionary:
	var d := {
		"type": shape_type,
		"name": String(name),
		"pos": _v(home_position()),
		"rot": _v(_home_rot * (180.0 / PI) if _animating else rotation_degrees),
		"scale": _v(scale),
		"color": color.to_html(),
		"roughness": roughness,
		"metallic": metallic,
		"ground": auto_ground,
	}
	if is_light():
		d["energy"] = light_energy
		d["range"] = light_range
	if shape_type == "model":
		d["model_path"] = model_path
	if not path_offsets.is_empty() or path_mode != "none":
		var offs := []
		for o in path_offsets:
			offs.append(_v(o))
		d["path"] = {"mode": path_mode, "speed": path_speed, "face": face_motion, "offsets": offs}
	return d


static func from_dict(d: Dictionary) -> StudioShape:
	var s := StudioShape.new()
	s.name = d.get("name", "")
	s.color = Color.from_string(d.get("color", "bfbfc7"), Color.GRAY)
	s.roughness = d.get("roughness", 0.8)
	s.metallic = d.get("metallic", 0.0)
	s.light_energy = d.get("energy", 2.0)
	s.light_range = d.get("range", 6.0)
	s.model_path = d.get("model_path", "")
	s.setup(d.get("type", "box"))
	s.position = _to_v(d.get("pos"), Vector3.ZERO)
	s.rotation_degrees = _to_v(d.get("rot"), Vector3.ZERO)
	s.scale = _to_v(d.get("scale"), Vector3.ONE)
	if d.has("ground"):
		s.auto_ground = bool(d.ground)
	var pd = d.get("path")
	if pd is Dictionary:
		s.path_mode = str(pd.get("mode", "none"))
		s.path_speed = float(pd.get("speed", 1.0))
		s.face_motion = bool(pd.get("face", false))
		for o in pd.get("offsets", []):
			s.path_offsets.append(_to_v(o, Vector3.ZERO))
	if d.has("size"): # 以公尺指定實際尺寸（範本用）
		var base := s.local_aabb().size.max(Vector3.ONE * 0.001)
		s.scale = (_to_v(d.size, base) / base).max(Vector3.ONE * 0.001)
	return s


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func _to_v(a, fallback: Vector3) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() == 3 else fallback
