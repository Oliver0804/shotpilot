extends Control
## 多點觸控虛擬搖桿。value：x 右為正、y 上（前進）為正，長度 ≤ 1。

@export var vertical_only := false
@export var label := ""

var value := Vector2.ZERO

var _touch := -1
var _knob := Vector2.ZERO


func _radius() -> float:
	return size.x * 0.5 if vertical_only else minf(size.x, size.y) * 0.5


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and Rect2(Vector2.ZERO, size).has_point(_to_local(event.position)):
			_touch = event.index
			_set_knob(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_knob = Vector2.ZERO
			value = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch:
		_set_knob(event.position)
		get_viewport().set_input_as_handled()


## 父節點可能整個旋轉（橫拿時），所以用完整的 transform 換算，不能用 get_global_rect()
func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _set_knob(screen_pos: Vector2) -> void:
	var k := _to_local(screen_pos) - size * 0.5
	if vertical_only:
		var travel := maxf(size.y * 0.5 - _radius() * 0.42, 1.0)
		k = Vector2(0.0, clampf(k.y, -travel, travel))
		value = Vector2(0.0, -k.y / travel)
	else:
		var r := _radius()
		k = k.limit_length(r)
		value = Vector2(k.x, -k.y) / r
	_knob = k
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	if vertical_only:
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(PhoneTheme.GLASS, 0.35)
		bar.border_color = Color(PhoneTheme.ACCENT_SOFT, 0.7)
		bar.set_border_width_all(3)
		bar.set_corner_radius_all(int(r * 0.6))
		draw_style_box(bar, Rect2(Vector2(c.x - r * 0.6, 0), Vector2(r * 1.2, size.y)))
	else:
		draw_circle(c, r, Color(PhoneTheme.GLASS, 0.35))
		draw_arc(c, r, 0, TAU, 64, Color(PhoneTheme.ACCENT_SOFT, 0.7), 3.0, true)
	var knob := PhoneTheme.ACCENT if _touch != -1 else PhoneTheme.ACCENT_SOFT
	draw_circle(c + _knob, r * 0.42, Color(knob, 0.85 if _touch != -1 else 0.55))
	draw_arc(c + _knob, r * 0.42, 0, TAU, 48, Color(1, 1, 1, 0.8), 2.0, true)
	if label != "":
		var font := get_theme_default_font()
		draw_string_outline(font, Vector2(0, -8), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 6, Color(PhoneTheme.TEXT_OUTLINE, 0.8))
		draw_string(font, Vector2(0, -8), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, PhoneTheme.TEXT)
