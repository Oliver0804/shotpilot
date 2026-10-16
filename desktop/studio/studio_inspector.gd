class_name StudioInspector
extends VBoxContainer
## 右側屬性面板：編輯選取物件的名稱、位置、旋轉、縮放、顏色、材質、燈光。

## 開始修改前發出（讓主程式存復原點），tag 相同且連續的修改會合併成一步
signal before_edit(tag: String)
signal edited(tag: String)
## 「在地面點選新增路徑點」開關
signal path_place_toggled(on: bool)

var target: StudioShape

var _title: Label
var _name: LineEdit
var _pos: Array[SpinBox] = []
var _rot: Array[SpinBox] = []
var _scl: Array[SpinBox] = []
var _uniform: CheckBox
var _color: ColorPickerButton
var _rough: HSlider
var _metal: HSlider
var _energy: HSlider
var _range: HSlider
var _mat_box: VBoxContainer
var _light_box: VBoxContainer
var _body: VBoxContainer
var _empty: Label
var _ground_chk: CheckBox
var _path_mode: OptionButton
var _path_speed: HSlider
var _face_chk: CheckBox
var _path_list: ItemList
var _place_btn: Button
var _path_detail: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.text = "屬性"
	add_child(_title)

	_empty = Label.new()
	_empty.text = "點選場景中的物件來編輯。\n\n左鍵：選取／拖曳移動\nShift+拖曳：上下移動\nW / E / R：移動／旋轉／縮放模式\n雙擊物件：移動 ⇄ 旋轉\n拖曳彩色把手：沿軸操作\n[ / ]：水平旋轉 15°\n右鍵拖曳：環繞視角\n中鍵：平移　滾輪：縮放\nDelete：刪除　⌘D：複製\n⌘Z / ⇧⌘Z：復原／重做\nF：對準選取物件"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.modulate = Color(1, 1, 1, 0.7)
	add_child(_empty)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)

	_name = LineEdit.new()
	_name.text_changed.connect(func(t):
		if target:
			before_edit.emit("name")
			target.name = t if t.strip_edges() != "" else target.name
			edited.emit("name"))
	_row(_body, "名稱", _name)

	_pos = _vec3_row(_body, "位置 (m)", 0.05, "pos")
	_rot = _vec3_row(_body, "旋轉 (°)", 1.0, "rot")
	_scl = _vec3_row(_body, "尺寸：寬 / 高 / 深 (m)", 0.05, "size")
	_uniform = CheckBox.new()
	_uniform.text = "等比"
	_uniform.button_pressed = false
	_body.add_child(_uniform)

	var reset := Button.new()
	reset.text = "放回地面"
	reset.tooltip_text = "讓物件底部貼齊地板（Y = 0）"
	reset.pressed.connect(func():
		if target:
			before_edit.emit("ground")
			target.position.y = 0.0
			refresh()
			edited.emit("ground"))
	_body.add_child(reset)

	_ground_chk = CheckBox.new()
	_ground_chk.text = "自動放在下方物件上"
	_ground_chk.tooltip_text = "水平移動時高度自動貼合腳下的物件或地板；手動調整高度會自動關閉"
	_ground_chk.toggled.connect(func(on):
		if target:
			before_edit.emit("ground_toggle")
			target.auto_ground = on
			edited.emit("ground_toggle"))
	_body.add_child(_ground_chk)

	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(0, 32)
	_color.color_changed.connect(func(c):
		if target:
			before_edit.emit("color")
			target.color = c
			target.apply_material()
			edited.emit("color"))
	_row(_body, "顏色", _color)

	_mat_box = VBoxContainer.new()
	_body.add_child(_mat_box)
	_rough = _slider_row(_mat_box, "粗糙度", 0.0, 1.0, 0.01, func(v): target.roughness = v, "rough")
	_metal = _slider_row(_mat_box, "金屬感", 0.0, 1.0, 0.01, func(v): target.metallic = v, "metal")

	_light_box = VBoxContainer.new()
	_body.add_child(_light_box)
	_energy = _slider_row(_light_box, "亮度", 0.0, 16.0, 0.1, func(v): target.light_energy = v, "energy")
	_range = _slider_row(_light_box, "照射範圍 (m)", 0.5, 40.0, 0.5, func(v): target.light_range = v, "range")

	_build_path_section()

	set_target(null)


func set_target(t: StudioShape) -> void:
	target = t
	_body.visible = t != null
	_empty.visible = t == null
	_title.text = "屬性" if t == null else "屬性：%s" % StudioShape.TYPES.get(t.shape_type, t.shape_type)
	if _place_btn and _place_btn.button_pressed:
		_place_btn.button_pressed = false # 換選取物件就結束路徑點選
	if t:
		_mat_box.visible = t.has_material()
		_light_box.visible = t.is_light()
		_color.visible = t.shape_type != "model"
		refresh()


## 從物件讀回數值（不觸發修改事件），拖曳移動時每幀呼叫
func refresh() -> void:
	if not target:
		return
	if not _name.has_focus():
		_name.text = target.name
	_set_vec(_pos, target.position)
	_set_vec(_rot, target.rotation_degrees)
	_set_vec(_scl, _size_of(target))
	_color.color = target.color
	_rough.set_value_no_signal(target.roughness)
	_metal.set_value_no_signal(target.metallic)
	_energy.set_value_no_signal(target.light_energy)
	_range.set_value_no_signal(target.light_range)
	_path_speed.set_value_no_signal(target.path_speed)
	for sl in [_rough, _metal, _energy, _range, _path_speed]:
		sl.get_meta("update_label").call(sl.value)
	_ground_chk.set_pressed_no_signal(target.auto_ground)
	refresh_path()


func _set_vec(boxes: Array[SpinBox], v: Vector3) -> void:
	for i in 3:
		if not boxes[i].get_line_edit().has_focus():
			boxes[i].set_value_no_signal(snappedf(v[i], 0.001))


static func _size_of(s: StudioShape) -> Vector3:
	return s.local_aabb().size * s.scale.abs()


func _row(parent: Control, label: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.modulate = Color(1, 1, 1, 0.75)
	parent.add_child(l)
	parent.add_child(ctrl)


func _vec3_row(parent: Control, label: String, step: float, tag: String) -> Array[SpinBox]:
	var row := HBoxContainer.new()
	var boxes: Array[SpinBox] = []
	var axis_cols := [Color(0.85, 0.3, 0.4), Color(0.25, 0.6, 0.35), Color(0.35, 0.45, 0.85)]
	for i in 3:
		var sb := SpinBox.new()
		sb.step = step
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.min_value = -1000 if tag != "size" else 0.0 # Range 的步進從 min_value 起算，min 用 0.01 會讓 1 變成 1.01
		sb.max_value = 1000
		sb.select_all_on_focus = true
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size.x = 0
		sb.get_line_edit().add_theme_color_override("font_color", axis_cols[i])
		var axis := i
		sb.value_changed.connect(func(v): _on_vec_changed(tag, axis, v))
		row.add_child(sb)
		boxes.append(sb)
	_row(parent, label, row)
	return boxes


func _on_vec_changed(tag: String, axis: int, v: float) -> void:
	if not target:
		return
	before_edit.emit(tag)
	match tag:
		"pos":
			var p := target.position
			p[axis] = v
			target.position = p
			if axis == 1 and target.auto_ground: # 手動指定高度＝不要自動貼合
				target.auto_ground = false
				_ground_chk.set_pressed_no_signal(false)
		"rot":
			var r := target.rotation_degrees
			r[axis] = v
			target.rotation_degrees = r
		"size":
			# 尺寸＝物件原始包圍盒 × scale，輸入公尺換算回 scale
			v = maxf(v, 0.01)
			var base := target.local_aabb().size.max(Vector3.ONE * 0.001)
			var cur := _size_of(target)
			var s := target.scale
			if _uniform.button_pressed and cur[axis] > 0.0001:
				s *= v / cur[axis]
			else:
				s[axis] = v / base[axis]
			target.scale = s
			_set_vec(_scl, _size_of(target))
	edited.emit(tag)


func _slider_row(parent: Control, label: String, lo: float, hi: float, step: float, apply: Callable, tag: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 24
	var l := Label.new()
	l.modulate = Color(1, 1, 1, 0.75)
	parent.add_child(l)
	parent.add_child(s)
	var update_label := func(v): l.text = "%s：%s" % [label, str(snappedf(v, step))]
	update_label.call(s.value)
	s.set_meta("update_label", update_label) # set_value_no_signal 不會觸發訊號，refresh() 時手動更新標籤
	s.value_changed.connect(func(v):
		update_label.call(v)
		if target:
			before_edit.emit(tag)
			apply.call(v)
			target.apply_material()
			edited.emit(tag))
	return s


# ---------------------------------------------------------------- 移動路線

func _build_path_section() -> void:
	var title := Label.new()
	title.text = "移動路線"
	title.add_theme_font_size_override("font_size", 17)
	_body.add_child(title)
	_path_mode = OptionButton.new()
	for k in StudioShape.PATH_MODES:
		_path_mode.add_item(StudioShape.PATH_MODES[k])
		_path_mode.set_item_metadata(_path_mode.item_count - 1, k)
	_path_mode.item_selected.connect(func(i):
		if target:
			before_edit.emit("path")
			target.path_mode = _path_mode.get_item_metadata(i)
			if target.path_mode == "none":
				target.reset_motion()
			refresh_path()
			edited.emit("path"))
	_body.add_child(_path_mode)

	_path_detail = VBoxContainer.new()
	_body.add_child(_path_detail)
	_path_speed = _slider_row(_path_detail, "速度 (m/s)", 0.1, 10.0, 0.1, func(v): target.path_speed = v, "path")
	_face_chk = CheckBox.new()
	_face_chk.text = "面向前進方向"
	_face_chk.toggled.connect(func(on):
		if target:
			before_edit.emit("path")
			target.face_motion = on
			edited.emit("path"))
	_path_detail.add_child(_face_chk)
	_path_list = ItemList.new()
	_path_list.custom_minimum_size.y = 90
	_path_detail.add_child(_path_list)
	_place_btn = Button.new()
	_place_btn.text = "在場景中點選新增路徑點"
	_place_btn.toggle_mode = true
	_place_btn.toggled.connect(func(on):
		_place_btn.text = "點選中…（Esc 或再按一次結束）" if on else "在場景中點選新增路徑點"
		path_place_toggled.emit(on))
	_path_detail.add_child(_place_btn)
	var row := HBoxContainer.new()
	_path_detail.add_child(row)
	var del := Button.new()
	del.text = "刪除最後一點"
	del.pressed.connect(func():
		if target and not target.path_offsets.is_empty():
			before_edit.emit("path_pts")
			target.reset_motion()
			target.path_offsets.pop_back()
			refresh_path()
			edited.emit("path"))
	row.add_child(del)
	var clr := Button.new()
	clr.text = "清除路線"
	clr.pressed.connect(func():
		if target:
			before_edit.emit("path_pts")
			target.reset_motion()
			target.path_offsets.clear()
			refresh_path()
			edited.emit("path"))
	row.add_child(clr)
	var hint := Label.new()
	hint.text = "起點＝物件目前位置。按工具列「▶ 物件動畫」預覽；錄製、回放與匯出時會自動同步。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	_path_detail.add_child(hint)


func stop_placing() -> void:
	if _place_btn and _place_btn.button_pressed:
		_place_btn.button_pressed = false


func refresh_path() -> void:
	if not target:
		return
	for i in _path_mode.item_count:
		if _path_mode.get_item_metadata(i) == target.path_mode:
			_path_mode.select(i)
	_face_chk.set_pressed_no_signal(target.face_motion)
	_path_list.clear()
	_path_list.add_item("起點（物件位置）")
	for i in target.path_offsets.size():
		var w: Vector3 = target.home_position() + target.path_offsets[i]
		_path_list.add_item("點 %d　(%.2f, %.2f, %.2f)" % [i + 1, w.x, w.y, w.z])
