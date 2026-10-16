class_name PhoneTheme

## 手機端 UI 主題（Live2D / VTube Studio 風的櫻花粉配色，為觸控放大）。
##
## 用法：
##     theme = PhoneTheme.build()              # main.gd 是 Control，直接設就會往下傳
##     rec_btn.add_theme_stylebox_override("normal", PhoneTheme.rec_style())   # 錄製中
##     rec_btn.remove_theme_stylebox_override("normal")                        # 恢復
##
## 控制項全部疊在串流畫面上，所以底色一律半透明深紫（玻璃感），
## 文字淡粉白＋描邊，不管背後的影像是亮是暗都看得清楚。

const FONT: FontFile = preload("res://fonts/jf-openhuninn-2.1.ttf")

# ================================================================ 配色

## 主色：櫻花粉
const ACCENT := Color(1.0, 0.5608, 0.6941)
const ACCENT_DEEP := Color(0.9529, 0.3765, 0.5608)
const ACCENT_SOFT := Color(1.0, 0.7647, 0.8392)
## 輔色：薰衣草紫
const LAVENDER := Color(0.7255, 0.6431, 0.9176)
## 輔色：淺藍
const SKY := Color(0.5608, 0.8392, 0.9412)

## 按鈕／面板的半透明玻璃底
const GLASS := Color(0.2118, 0.1529, 0.2745, 0.52)
## 按下、強調時的玻璃底
const GLASS_DEEP := Color(0.1686, 0.1176, 0.2235, 0.72)
## 彈出選單這種需要讀內容的面板
const PANEL := Color(0.1569, 0.1098, 0.2118, 0.94)

## 主要文字（淡粉白）
const TEXT := Color(1.0, 0.9569, 0.9725)
## 次要文字
const TEXT_DIM := Color(0.8745, 0.8196, 0.898)
## 停用文字
const TEXT_FAINT := Color(0.7137, 0.6627, 0.749, 0.7)
## 文字描邊（疊在影像上用）
const TEXT_OUTLINE := Color(0.1098, 0.0745, 0.1569, 0.65)

const BORDER := Color(1.0, 0.5608, 0.6941, 0.6)
const BORDER_SOFT := Color(1.0, 0.8, 0.8706, 0.3)
const SHADOW := Color(0.08, 0.05, 0.12, 0.35)

## 錄製中 / 警示
const REC := Color(1.0, 0.302, 0.4745)

const FONT_SIZE := 24
const RADIUS_PANEL := 22
const RADIUS_PILL := 26

static var _bold: FontVariation


static func font_bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FONT
		_bold.variation_embolden = 0.2
	return _bold


# ================================================================ 對外工具

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = FONT_SIZE
	_setup_labels(t)
	_setup_buttons(t)
	_setup_inputs(t)
	_setup_popups(t)
	_setup_misc(t)
	return t


## 「錄製中」的紅粉色按鈕底：直接 override 到按鈕的 normal（想恢復就 remove override）。
static func rec_style() -> StyleBoxFlat:
	var s := _sb(Color(REC.r, REC.g, REC.b, 0.88), RADIUS_PILL, 2, Color(1.0, 0.7, 0.78, 0.95), 18, 12, 14)
	s.shadow_color = Color(REC.r, REC.g, REC.b, 0.45)
	s.shadow_offset = Vector2(0, 0)
	return s


## 半透明玻璃面板，想自己做浮層時可用。
static func panel_style() -> StyleBoxFlat:
	return _sb(GLASS, RADIUS_PANEL, 1, BORDER_SOFT, 14, 10, 12)


## 套用主題。Godot 的主題繼承鏈碰到 CanvasLayer / Node2D 這類節點會斷掉，
## 所以這裡順便把主題補到那些斷點下的 Control 上。
static func apply(from: Node, custom: Theme = null) -> Theme:
	var t: Theme = custom if custom != null else build()
	if from is Control:
		(from as Control).theme = t
	elif from is Window:
		(from as Window).theme = t
	_patch_theme_chain(from, t)
	return t


static func _patch_theme_chain(node: Node, t: Theme) -> void:
	for child in node.get_children():
		var parent_ok := node is Control or node is Window
		if child is Control:
			if not parent_ok:
				(child as Control).theme = t
		elif child is Window:
			if not parent_ok:
				(child as Window).theme = t
		_patch_theme_chain(child, t)


# ================================================================ 各類控制項

static func _setup_labels(t: Theme) -> void:
	# 疊在影像上，所以預設就給描邊
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", TEXT_OUTLINE)
	t.set_constant("outline_size", "Label", 4)
	t.set_constant("line_spacing", "Label", 3)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", TEXT_OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", 4)


static func _setup_buttons(t: Theme) -> void:
	var normal := _sb(GLASS, RADIUS_PILL, 2, BORDER, 20, 12, 10)
	var hover := _sb(Color(0.2588, 0.1843, 0.3294, 0.62), RADIUS_PILL, 2, ACCENT, 20, 12, 12)
	var pressed := _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.88), RADIUS_PILL, 2, ACCENT_DEEP, 20, 12, 6)
	var disabled := _sb(Color(0.2118, 0.1843, 0.2471, 0.35), RADIUS_PILL, 2, Color(1, 1, 1, 0.15), 20, 12)

	for ty in ["Button", "MenuButton", "OptionButton"]:
		t.set_stylebox("normal", ty, normal)
		t.set_stylebox("hover", ty, hover)
		t.set_stylebox("pressed", ty, pressed)
		t.set_stylebox("disabled", ty, disabled)
		t.set_stylebox("focus", ty, _focus_ring())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, Color(0.2235, 0.1294, 0.1843))
		t.set_color("font_hover_pressed_color", ty, Color(0.2235, 0.1294, 0.1843))
		t.set_color("font_focus_color", ty, TEXT)
		t.set_color("font_disabled_color", ty, TEXT_FAINT)
		t.set_color("font_outline_color", ty, TEXT_OUTLINE)
		t.set_constant("outline_size", ty, 3)
		t.set_constant("h_separation", ty, 8)
		t.set_color("icon_normal_color", ty, TEXT)
		t.set_color("icon_pressed_color", ty, Color(0.2235, 0.1294, 0.1843))
		t.set_color("icon_disabled_color", ty, TEXT_FAINT)

	# 切換成開啟狀態的按鈕（toggle_mode）用粉紅實心，一眼看得出來
	t.set_icon("arrow", "OptionButton", _chevron(22, 0, Color.WHITE, 3.0))
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_constant("modulate_arrow", "OptionButton", 1)
	for n in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(n + "_mirrored", "OptionButton", t.get_stylebox(n, "OptionButton"))

	for ty in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", ty, _sb(GLASS, RADIUS_PILL, 2, BORDER_SOFT, 16, 10))
		t.set_stylebox("hover", ty, _sb(GLASS_DEEP, RADIUS_PILL, 2, BORDER, 16, 10))
		t.set_stylebox("pressed", ty, _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22), RADIUS_PILL, 2, ACCENT, 16, 10))
		t.set_stylebox("hover_pressed", ty, _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3), RADIUS_PILL, 2, ACCENT, 16, 10))
		t.set_stylebox("disabled", ty, _sb(Color(0.21, 0.18, 0.25, 0.3), RADIUS_PILL, 2, Color(1, 1, 1, 0.12), 16, 10))
		t.set_stylebox("focus", ty, _focus_ring())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, Color.WHITE)
		t.set_color("font_hover_pressed_color", ty, Color.WHITE)
		t.set_color("font_disabled_color", ty, TEXT_FAINT)
		t.set_color("font_outline_color", ty, TEXT_OUTLINE)
		t.set_constant("outline_size", ty, 3)
		t.set_constant("h_separation", ty, 10)
		t.set_color("checkbox_checked_color", ty, Color.WHITE)
		t.set_color("checkbox_unchecked_color", ty, Color.WHITE)
		t.set_color("button_checked_color", ty, Color.WHITE)
		t.set_color("button_unchecked_color", ty, Color.WHITE)

	t.set_icon("checked", "CheckBox", _check_icon(true, false))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("radio_checked", "CheckBox", _radio_icon(true, false))
	t.set_icon("radio_unchecked", "CheckBox", _radio_icon(false, false))
	t.set_icon("radio_checked_disabled", "CheckBox", _radio_icon(true, true))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _radio_icon(false, true))
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", _switch_icon(true, false))
		t.set_icon("unchecked" + suffix, "CheckButton", _switch_icon(false, false))
		t.set_icon("checked_disabled" + suffix, "CheckButton", _switch_icon(true, true))
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", _switch_icon(false, true))


static func _setup_inputs(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", _sb(GLASS_DEEP, RADIUS_PANEL, 2, BORDER_SOFT, 18, 12, 8))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0.1686, 0.1176, 0.2235, 0.88), RADIUS_PANEL, 2, ACCENT, 18, 12, 10))
	t.set_stylebox("read_only", "LineEdit", _sb(Color(0.21, 0.18, 0.25, 0.45), RADIUS_PANEL, 2, Color(1, 1, 1, 0.12), 18, 12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.55))
	t.set_color("font_uneditable_color", "LineEdit", TEXT_DIM)
	t.set_color("font_selected_color", "LineEdit", Color(0.2235, 0.1294, 0.1843))
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_outline_color", "LineEdit", Color(0, 0, 0, 0))
	t.set_constant("outline_size", "LineEdit", 0)
	t.set_constant("caret_width", "LineEdit", 3)
	t.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	t.set_color("clear_button_color_pressed", "LineEdit", ACCENT)

	# 滑桿（觸控用的粗軌道 + 大圓點）
	var grabber := _dot_icon(34, Color(1, 1, 1, 0.98), ACCENT, 5.0)
	for ty in ["HSlider", "VSlider"]:
		var vertical: bool = ty == "VSlider"
		t.set_stylebox("slider", ty, _track(Color(1, 1, 1, 0.22), vertical, 6))
		t.set_stylebox("grabber_area", ty, _track(ACCENT, vertical, 6))
		t.set_stylebox("grabber_area_highlight", ty, _track(ACCENT_DEEP, vertical, 6))
		t.set_icon("grabber", ty, grabber)
		t.set_icon("grabber_highlight", ty, _dot_icon(34, Color(1, 0.95, 0.97, 1.0), ACCENT_DEEP, 5.5))
		t.set_icon("grabber_disabled", ty, _dot_icon(34, Color(0.8, 0.78, 0.82, 0.8), Color(1, 1, 1, 0.3), 5.0))
		t.set_icon("tick", ty, _empty_icon())

	t.set_stylebox("background", "ProgressBar", _sb(Color(1, 1, 1, 0.2), 12, 0, BORDER, 0, 4))
	t.set_stylebox("fill", "ProgressBar", _sb(ACCENT, 12, 0, BORDER, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", TEXT_OUTLINE)
	t.set_constant("outline_size", "ProgressBar", 4)


static func _setup_popups(t: Theme) -> void:
	var pop := _sb(PANEL, RADIUS_PANEL, 2, BORDER, 8, 10, 18)
	pop.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	t.set_stylebox("hover", "PopupMenu", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3), 16, 0, BORDER, 0, 0))
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.thickness = 1
	sep.grow_begin = -6.0
	sep.grow_end = -6.0
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_accelerator_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_separator_color", "PopupMenu", ACCENT_SOFT)
	t.set_color("font_outline_color", "PopupMenu", Color(0, 0, 0, 0))
	t.set_constant("outline_size", "PopupMenu", 0)
	t.set_constant("v_separation", "PopupMenu", 14)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)
	t.set_icon("checked", "PopupMenu", _check_icon(true, false))
	t.set_icon("unchecked", "PopupMenu", _check_icon(false, false))
	t.set_icon("checked_disabled", "PopupMenu", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "PopupMenu", _check_icon(false, true))
	t.set_icon("radio_checked", "PopupMenu", _radio_icon(true, false))
	t.set_icon("radio_unchecked", "PopupMenu", _radio_icon(false, false))
	t.set_icon("radio_checked_disabled", "PopupMenu", _radio_icon(true, true))
	t.set_icon("radio_unchecked_disabled", "PopupMenu", _radio_icon(false, true))
	t.set_icon("submenu", "PopupMenu", _chevron(22, 2, ACCENT_SOFT, 2.6))
	t.set_icon("submenu_mirrored", "PopupMenu", _chevron(22, 3, ACCENT_SOFT, 2.6))

	var tip := _sb(PANEL, 16, 1, BORDER, 14, 8, 12)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_color("font_outline_color", "TooltipLabel", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "TooltipLabel", 20)


static func _setup_misc(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "ScrollContainer", _empty(0, 0))
	t.set_stylebox("focus", "ScrollContainer", _empty(0, 0))

	for ty in ["HScrollBar", "VScrollBar"]:
		var vertical: bool = ty == "VScrollBar"
		t.set_stylebox("scroll", ty, _track(Color(1, 1, 1, 0.14), vertical, 6))
		t.set_stylebox("scroll_focus", ty, _track(Color(1, 1, 1, 0.2), vertical, 6))
		t.set_stylebox("grabber", ty, _track(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7), vertical, 6))
		t.set_stylebox("grabber_highlight", ty, _track(ACCENT, vertical, 6))
		t.set_stylebox("grabber_pressed", ty, _track(ACCENT_DEEP, vertical, 6))
		for n in ["increment", "increment_highlight", "increment_pressed",
				"decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(n, ty, _empty_icon())

	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.2)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = Color(1, 1, 1, 0.2)
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)

	t.set_stylebox("panel", "ItemList", _sb(GLASS_DEEP, RADIUS_PANEL, 1, BORDER_SOFT, 6, 6))
	t.set_stylebox("selected", "ItemList", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35), 16, 1, ACCENT, 6, 4))
	t.set_stylebox("selected_focus", "ItemList", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45), 16, 1, ACCENT, 6, 4))
	t.set_stylebox("hovered", "ItemList", _sb(Color(1, 1, 1, 0.08), 16, 0, BORDER, 6, 4))
	t.set_stylebox("cursor", "ItemList", _sb(Color(1, 1, 1, 0), 16, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 6, 4))
	t.set_stylebox("cursor_unfocused", "ItemList", _sb(Color(1, 1, 1, 0), 16, 1, Color(1, 1, 1, 0.2), 6, 4))
	t.set_stylebox("focus", "ItemList", _focus_ring())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.12))
	t.set_constant("v_separation", "ItemList", 8)

	var win := _sb(PANEL, RADIUS_PANEL, 2, ACCENT, 12, 12, 20)
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", _sb(PANEL, RADIUS_PANEL, 2, BORDER_SOFT, 12, 12, 14))
	t.set_font("title_font", "Window", font_bold())
	t.set_font_size("title_font_size", "Window", 22)
	t.set_color("title_color", "Window", TEXT)
	t.set_constant("title_height", "Window", 40)
	t.set_icon("close", "Window", _close_icon(TEXT_DIM))
	t.set_icon("close_pressed", "Window", _close_icon(ACCENT))
	t.set_stylebox("panel", "AcceptDialog", _sb(PANEL, RADIUS_PANEL, 2, BORDER, 16, 16, 20))


# ================================================================ StyleBox 小工具

static func _sb(bg: Color, radius: int, bw: int = 0, bc: Color = BORDER,
		mh: int = 0, mv: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.0
	if bw > 0:
		s.set_border_width_all(bw)
		s.border_color = bc
	s.content_margin_left = mh
	s.content_margin_right = mh
	s.content_margin_top = mv
	s.content_margin_bottom = mv
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = SHADOW
		s.shadow_offset = Vector2(0, 3)
	return s


## 滑桿／捲軸軌道：粗細由 content margin 決定
static func _track(col: Color, vertical: bool, half_thickness: int) -> StyleBoxFlat:
	var s := _sb(col, half_thickness, 0, BORDER)
	if vertical:
		s.content_margin_left = half_thickness
		s.content_margin_right = half_thickness
	else:
		s.content_margin_top = half_thickness
		s.content_margin_bottom = half_thickness
	return s


static func _empty(mh: int, mv: int) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = mh
	s.content_margin_right = mh
	s.content_margin_top = mv
	s.content_margin_bottom = mv
	return s


static func _focus_ring() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_corner_radius_all(RADIUS_PILL)
	s.corner_detail = 12
	s.set_border_width_all(3)
	s.border_color = Color(1, 1, 1, 0.75)
	s.anti_aliasing = true
	s.set_expand_margin_all(1.0)
	return s


# ================================================================ 程式畫圖示

static func _empty_icon() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))


static func _sd_rrect(p: Vector2, half: Vector2, r: float) -> float:
	var rr := minf(r, minf(half.x, half.y))
	var q := p.abs() - half + Vector2(rr, rr)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rr


static func _blend(img: Image, x: int, y: int, col: Color) -> void:
	if col.a <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var out_a := col.a + dst.a * (1.0 - col.a)
	if out_a <= 0.0001:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var w1 := col.a / out_a
	var w2 := dst.a * (1.0 - col.a) / out_a
	img.set_pixel(x, y, Color(
		col.r * w1 + dst.r * w2,
		col.g * w1 + dst.g * w2,
		col.b * w1 + dst.b * w2,
		out_a))


static func _draw_rrect(img: Image, rect: Rect2, radius: float, fill: Color, border: Color, bw: float) -> void:
	var c := rect.get_center()
	var half := rect.size * 0.5
	var x0 := maxi(int(floor(rect.position.x)) - 1, 0)
	var y0 := maxi(int(floor(rect.position.y)) - 1, 0)
	var x1 := mini(int(ceil(rect.end.x)) + 1, img.get_width())
	var y1 := mini(int(ceil(rect.end.y)) + 1, img.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var d := _sd_rrect(Vector2(x + 0.5, y + 0.5) - c, half, radius)
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := fill
			if bw > 0.0:
				col = border.lerp(fill, clampf(-d - bw + 0.5, 0.0, 1.0))
			col.a *= a
			_blend(img, x, y, col)


static func _sd_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var l2 := ba.length_squared()
	if l2 <= 0.0001:
		return pa.length()
	return (pa - ba * clampf(pa.dot(ba) / l2, 0.0, 1.0)).length()


static func _draw_path(img: Image, pts: PackedVector2Array, width: float, col: Color) -> void:
	if pts.size() < 2:
		return
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var d := 1.0e9
			for i in range(pts.size() - 1):
				d = minf(d, _sd_seg(p, pts[i], pts[i + 1]))
			var a := clampf(width * 0.5 - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				var c := col
				c.a *= a
				_blend(img, x, y, c)


static func _check_icon(on: bool, disabled: bool) -> ImageTexture:
	var s := 30
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var box := Rect2(1, 1, s - 2, s - 2)
	var fade := 0.4 if disabled else 1.0
	if on:
		_draw_rrect(img, box, 9.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, fade), ACCENT_DEEP, 0.0)
		_draw_path(img, PackedVector2Array([Vector2(8, 15.5), Vector2(13, 20.5), Vector2(22, 9.5)]),
			3.6, Color(1, 1, 1, fade))
	else:
		_draw_rrect(img, box, 9.0, Color(0.16, 0.11, 0.21, 0.5 * fade), Color(1, 1, 1, 0.55 * fade), 2.5)
	return ImageTexture.create_from_image(img)


static func _radio_icon(on: bool, disabled: bool) -> ImageTexture:
	var s := 30
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var box := Rect2(1, 1, s - 2, s - 2)
	var fade := 0.4 if disabled else 1.0
	if on:
		_draw_rrect(img, box, 14.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, fade), ACCENT_DEEP, 0.0)
		_draw_rrect(img, Rect2(10, 10, 10, 10), 5.0, Color(1, 1, 1, fade), Color.WHITE, 0.0)
	else:
		_draw_rrect(img, box, 14.0, Color(0.16, 0.11, 0.21, 0.5 * fade), Color(1, 1, 1, 0.55 * fade), 2.5)
	return ImageTexture.create_from_image(img)


static func _switch_icon(on: bool, disabled: bool) -> ImageTexture:
	var w := 54
	var h := 30
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var fade := 0.4 if disabled else 1.0
	var track := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95) if on else Color(0.16, 0.11, 0.21, 0.55)
	_draw_rrect(img, Rect2(1, 2, w - 2, h - 4), 13.0, Color(track.r, track.g, track.b, track.a * fade),
		Color(1, 1, 1, 0.5 * fade), 2.0)
	var cx := float(w - 14) if on else 14.0
	_draw_rrect(img, Rect2(cx - 11, h * 0.5 - 11, 22, 22), 11.0, Color(1, 1, 1, fade), Color.WHITE, 0.0)
	return ImageTexture.create_from_image(img)


static func _dot_icon(size: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var f := float(size)
	_draw_rrect(img, Rect2(0, 0, f, f), f * 0.5, Color(ring.r, ring.g, ring.b, 0.22), ring, 0.0)
	var inset := 4.0
	_draw_rrect(img, Rect2(inset, inset, f - inset * 2.0, f - inset * 2.0),
		(f - inset * 2.0) * 0.5, fill, ring, ring_w)
	return ImageTexture.create_from_image(img)


## dir: 0 下、1 上、2 右、3 左
static func _chevron(size: int, dir: int, col: Color, w: float) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	var r := size * 0.26
	var pts := PackedVector2Array()
	match dir:
		0:
			pts = PackedVector2Array([Vector2(c - r, c - r * 0.6), Vector2(c, c + r * 0.6), Vector2(c + r, c - r * 0.6)])
		1:
			pts = PackedVector2Array([Vector2(c - r, c + r * 0.6), Vector2(c, c - r * 0.6), Vector2(c + r, c + r * 0.6)])
		2:
			pts = PackedVector2Array([Vector2(c - r * 0.6, c - r), Vector2(c + r * 0.6, c), Vector2(c - r * 0.6, c + r)])
		_:
			pts = PackedVector2Array([Vector2(c + r * 0.6, c - r), Vector2(c - r * 0.6, c), Vector2(c + r * 0.6, c + r)])
	_draw_path(img, pts, w, col)
	return ImageTexture.create_from_image(img)


static func _close_icon(col: Color) -> ImageTexture:
	var s := 22
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	_draw_path(img, PackedVector2Array([Vector2(6, 6), Vector2(16, 16)]), 3.0, col)
	_draw_path(img, PackedVector2Array([Vector2(16, 6), Vector2(6, 16)]), 3.0, col)
	return ImageTexture.create_from_image(img)
