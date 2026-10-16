class_name StudioTheme

## ShotPilot 的桌面端 UI 主題（Live2D / VTube Studio 風的櫻花粉配色）。
##
## 用法：
##     get_window().theme = StudioTheme.build()
##     StudioTheme.hud_label_style(hud_label)   # 疊在 3D 視窗上的文字
##
## 所有圖示（勾勾、圓點滑桿頭、箭頭…）都是啟動時用程式畫成 ImageTexture，
## 不依賴任何圖檔，所以不會留下 Godot 預設的灰色控制項。

const FONT: FontFile = preload("res://fonts/jf-openhuninn-2.1.ttf")

# ================================================================ 配色

## 主色：櫻花粉
const ACCENT := Color(1.0, 0.5608, 0.6941)
## 主色加深（按下、強調文字）
const ACCENT_DEEP := Color(0.9098, 0.3412, 0.5412)
## 主色淡底（hover、選取項）
const ACCENT_SOFT := Color(1.0, 0.8824, 0.9216)
## 主色最淡（大面積底色）
const ACCENT_TINT := Color(1.0, 0.949, 0.9647)
## 輔色：薰衣草紫
const LAVENDER := Color(0.7255, 0.6431, 0.9176)
const LAVENDER_DEEP := Color(0.5569, 0.4745, 0.7882)
## 輔色：淺藍
const SKY := Color(0.5608, 0.8392, 0.9412)

## 面板底色（帶一點透明的淡紫白）
const PANEL := Color(0.992, 0.98, 1.0, 0.94)
## 面板內的次級區塊
const PANEL_SOFT := Color(0.9608, 0.9373, 0.9804)
## 輸入欄位底色
const FIELD := Color(0.9843, 0.9686, 0.9961)
## 軌道、進度條底
const TRACK := Color(0.9255, 0.8941, 0.9647)

## 主要文字（深紫灰，不用純黑）
const TEXT := Color(0.3059, 0.2588, 0.3765)
## 次要文字
const TEXT_DIM := Color(0.5412, 0.4863, 0.6392)
## 停用文字
const TEXT_FAINT := Color(0.7137, 0.6745, 0.7765)
## 深色底上的文字（HUD、提示泡泡）
const TEXT_ON_DARK := Color(1.0, 0.9569, 0.9725)

const BORDER := Color(0.9255, 0.8784, 0.9608)
const BORDER_DEEP := Color(0.8471, 0.7804, 0.9255)
## 柔和陰影
const SHADOW := Color(0.45, 0.33, 0.55, 0.17)
## 深色墨（提示泡泡、HUD 底板）
const INK := Color(0.2902, 0.2392, 0.3686)
## 錄製中 / 警示
const REC := Color(1.0, 0.4314, 0.5412)
## 成功
const OK := Color(0.4863, 0.8235, 0.6392)

const FONT_SIZE := 15
const RADIUS_PANEL := 16
const RADIUS_CARD := 12
const RADIUS_PILL := 14

static var _bold: FontVariation


## 粗一點的字（標題、分頁用）
static func font_bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FONT
		_bold.variation_embolden = 0.22
	return _bold


# ================================================================ 對外工具

## 建立整份主題。套在 Window 上即可（Window / PopupMenu / 對話框都已覆蓋）。
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = FONT_SIZE
	_setup_panels(t)
	_setup_labels(t)
	_setup_buttons(t)
	_setup_checks(t)
	_setup_inputs(t)
	_setup_sliders(t)
	_setup_tabs(t)
	_setup_lists(t)
	_setup_popups(t)
	_setup_scrollbars(t)
	_setup_windows(t)
	return t


## 套用主題並回傳它。
##
## Godot 的主題繼承鏈只走 Control / Window，碰到 CanvasLayer、Node3D 這類節點就會斷掉
## （studio 的 UI 與 addon 的 HUD 都掛在 CanvasLayer 底下），所以光是
## `get_window().theme = ...` 不夠；這裡會再把同一份 Theme 補到每個「父節點不是
## Control／Window」的 Control 上，讓整棵樹都吃得到。UI 建好之後呼叫一次即可：
##     StudioTheme.apply(self)
static func apply(from: Node, custom: Theme = null) -> Theme:
	var t: Theme = custom if custom != null else build()
	var win: Window = from as Window
	if win == null:
		win = from.get_window()
	if win != null:
		win.theme = t
		_patch_theme_chain(win, t)
	else:
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


## 面板底板（卡片）樣式，可直接給自訂 Panel / PanelContainer 用。
static func panel_style() -> StyleBoxFlat:
	return _sb(PANEL, RADIUS_PANEL, 1, BORDER, 6, 6, 10)


## 右下角子畫面（PiP）的外框：半透明深紫底 + 粉紅細框，讓串流畫面像貼紙一樣浮在上面。
static func pip_style() -> StyleBoxFlat:
	var s := _sb(Color(INK.r, INK.g, INK.b, 0.55), RADIUS_CARD, 2, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), 0, 0, 12)
	s.shadow_offset = Vector2(0, 3)
	s.expand_margin_left = 3.0
	s.expand_margin_right = 3.0
	s.expand_margin_top = 3.0
	s.expand_margin_bottom = 3.0
	return s


## 給疊在 3D 視窗上的 HUD 文字用：半透明深紫底板 + 淡粉字 + 柔和描邊，
## 不管背後是亮天空還是暗場景都讀得清楚。
static func hud_label_style(label: Label, size: int = 15) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_ON_DARK)
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.13, 0.24, 0.55))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0.18, 0.13, 0.24, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("line_spacing", 2)
	label.add_theme_stylebox_override("normal", hud_panel_style())


## HUD 文字的底板樣式（hud_label_style 會自動套上，單獨要用也行）。
static func hud_panel_style() -> StyleBoxFlat:
	var s := _sb(Color(INK.r, INK.g, INK.b, 0.42), RADIUS_CARD, 1, Color(1.0, 0.9, 0.95, 0.22), 12, 8)
	s.shadow_size = 8
	s.shadow_color = Color(0.2, 0.14, 0.26, 0.2)
	s.shadow_offset = Vector2(0, 2)
	return s


## 區塊標題（粉紅＋粗體）。
static func section_label_style(label: Label, size: int = 17) -> void:
	label.add_theme_font_override("font", font_bold())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ACCENT_DEEP)


## 把按鈕變成實心粉紅的「主要動作」樣式（例如開始錄製 / 匯出）。
static func primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _sb(ACCENT, RADIUS_PILL, 0, BORDER, 16, 7, 8))
	button.add_theme_stylebox_override("hover", _sb(ACCENT.lightened(0.08), RADIUS_PILL, 0, BORDER, 16, 7, 10))
	button.add_theme_stylebox_override("pressed", _sb(ACCENT_DEEP, RADIUS_PILL, 0, BORDER, 16, 7, 4))
	button.add_theme_stylebox_override("disabled", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35), RADIUS_PILL, 0, BORDER, 16, 7))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(c, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))


# ================================================================ 各類控制項

static func _setup_panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "ScrollContainer", _empty(0, 0))
	t.set_stylebox("focus", "ScrollContainer", _empty(0, 0))

	var line := StyleBoxLine.new()
	line.color = BORDER_DEEP
	line.thickness = 1
	line.grow_begin = -2.0
	line.grow_end = -2.0
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = BORDER_DEEP
	vline.thickness = 1
	vline.vertical = true
	vline.grow_begin = -6.0
	vline.grow_end = -6.0
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "HSeparator", 6)
	t.set_constant("separation", "VSeparator", 8)


static func _setup_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(1, 1, 1, 0))
	t.set_color("font_shadow_color", "Label", Color(1, 1, 1, 0))
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_shadow_color", "RichTextLabel", Color(1, 1, 1, 0))
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.4))
	t.set_stylebox("normal", "RichTextLabel", _empty(0, 0))
	t.set_stylebox("focus", "RichTextLabel", _focus_ring())

	t.set_color("font_color", "LinkButton", LAVENDER_DEEP)
	t.set_color("font_hover_color", "LinkButton", ACCENT_DEEP)
	t.set_color("font_pressed_color", "LinkButton", ACCENT_DEEP)
	t.set_stylebox("focus", "LinkButton", _empty(0, 0))


static func _setup_buttons(t: Theme) -> void:
	# 工具列、屬性面板的一般按鈕：淡紫底、hover 轉粉、按下實心粉
	var normal := _sb(Color(0.9569, 0.9333, 0.9882, 0.95), RADIUS_PILL, 1, BORDER_DEEP, 13, 5, 5)
	var hover := _sb(ACCENT_SOFT, RADIUS_PILL, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75), 13, 5, 8)
	var pressed := _sb(ACCENT, RADIUS_PILL, 1, ACCENT_DEEP, 13, 5, 2)
	var disabled := _sb(Color(0.949, 0.933, 0.9647, 0.6), RADIUS_PILL, 1, Color(BORDER.r, BORDER.g, BORDER.b, 0.7), 13, 5)

	for ty in ["Button", "MenuButton", "OptionButton", "ColorPickerButton"]:
		t.set_stylebox("normal", ty, normal)
		t.set_stylebox("hover", ty, hover)
		t.set_stylebox("pressed", ty, pressed)
		t.set_stylebox("disabled", ty, disabled)
		t.set_stylebox("focus", ty, _focus_ring())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, ACCENT_DEEP)
		t.set_color("font_pressed_color", ty, Color.WHITE)
		t.set_color("font_hover_pressed_color", ty, Color.WHITE)
		t.set_color("font_focus_color", ty, TEXT)
		t.set_color("font_disabled_color", ty, TEXT_FAINT)
		t.set_color("font_outline_color", ty, Color(1, 1, 1, 0))
		t.set_constant("outline_size", ty, 0)
		t.set_constant("h_separation", ty, 6)
		t.set_color("icon_normal_color", ty, TEXT)
		t.set_color("icon_hover_color", ty, ACCENT_DEEP)
		t.set_color("icon_pressed_color", ty, Color.WHITE)
		t.set_color("icon_hover_pressed_color", ty, Color.WHITE)
		t.set_color("icon_focus_color", ty, TEXT)
		t.set_color("icon_disabled_color", ty, TEXT_FAINT)

	# OptionButton 的下拉箭頭：畫成白色，再靠 modulate_arrow 跟著各狀態的文字色變
	t.set_icon("arrow", "OptionButton", _chevron(16, 0, Color.WHITE, 2.2))
	t.set_constant("arrow_margin", "OptionButton", 6)
	t.set_constant("modulate_arrow", "OptionButton", 1)
	for n in ["normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored"]:
		t.set_stylebox(n, "OptionButton", t.get_stylebox(n.trim_suffix("_mirrored"), "OptionButton"))

	# ColorPickerButton 的棋盤底（改成淡粉格子，不要刺眼的黑白）
	t.set_icon("bg", "ColorPickerButton", _checker(14, Color(1, 1, 1, 1), ACCENT_SOFT))


static func _setup_checks(t: Theme) -> void:
	for ty in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", ty, _empty(8, 5))
		t.set_stylebox("hover", ty, _sb(ACCENT_TINT, RADIUS_CARD, 0, BORDER, 8, 5))
		t.set_stylebox("pressed", ty, _sb(ACCENT_TINT, RADIUS_CARD, 0, BORDER, 8, 5))
		t.set_stylebox("hover_pressed", ty, _sb(ACCENT_SOFT, RADIUS_CARD, 0, BORDER, 8, 5))
		t.set_stylebox("disabled", ty, _empty(8, 5))
		t.set_stylebox("focus", ty, _focus_ring())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, ACCENT_DEEP)
		t.set_color("font_pressed_color", ty, ACCENT_DEEP)
		t.set_color("font_hover_pressed_color", ty, ACCENT_DEEP)
		t.set_color("font_focus_color", ty, TEXT)
		t.set_color("font_disabled_color", ty, TEXT_FAINT)
		t.set_color("font_outline_color", ty, Color(1, 1, 1, 0))
		t.set_constant("outline_size", ty, 0)
		t.set_constant("h_separation", ty, 8)
		t.set_constant("check_v_offset", ty, 0)
		# 圖示本身已經上好色，所以 modulate 一律設白色
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

	# CheckButton 用膠囊開關
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", _switch_icon(true, false))
		t.set_icon("unchecked" + suffix, "CheckButton", _switch_icon(false, false))
		t.set_icon("checked_disabled" + suffix, "CheckButton", _switch_icon(true, true))
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", _switch_icon(false, true))


static func _setup_inputs(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", _sb(FIELD, RADIUS_CARD, 1, BORDER_DEEP, 10, 6))
	t.set_stylebox("focus", "LineEdit", _sb(Color.WHITE, RADIUS_CARD, 2, ACCENT, 10, 6, 6))
	t.set_stylebox("read_only", "LineEdit", _sb(PANEL_SOFT, RADIUS_CARD, 1, BORDER, 10, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("font_uneditable_color", "LineEdit", TEXT_DIM)
	t.set_color("font_selected_color", "LineEdit", Color.WHITE)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85))
	t.set_color("caret_color", "LineEdit", ACCENT_DEEP)
	t.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	t.set_color("clear_button_color_pressed", "LineEdit", ACCENT_DEEP)
	t.set_color("font_outline_color", "LineEdit", Color(1, 1, 1, 0))
	t.set_constant("outline_size", "LineEdit", 0)
	t.set_constant("caret_width", "LineEdit", 2)

	t.set_stylebox("normal", "TextEdit", _sb(FIELD, RADIUS_CARD, 1, BORDER_DEEP, 10, 8))
	t.set_stylebox("focus", "TextEdit", _sb(Color.WHITE, RADIUS_CARD, 2, ACCENT, 10, 8, 6))
	t.set_stylebox("read_only", "TextEdit", _sb(PANEL_SOFT, RADIUS_CARD, 1, BORDER, 10, 8))
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_placeholder_color", "TextEdit", TEXT_FAINT)
	t.set_color("caret_color", "TextEdit", ACCENT_DEEP)
	t.set_color("selection_color", "TextEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6))
	t.set_color("current_line_color", "TextEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.08))

	# SpinBox：右側上下小箭頭
	var up := _sb(Color(0.9255, 0.8941, 0.9647, 1.0), 7, 1, BORDER_DEEP, 0, 0)
	var up_h := _sb(ACCENT_SOFT, 7, 1, ACCENT, 0, 0)
	var up_p := _sb(ACCENT, 7, 1, ACCENT_DEEP, 0, 0)
	var up_d := _sb(Color(0.949, 0.933, 0.9647, 0.5), 7, 1, BORDER, 0, 0)
	for side in ["up", "down"]:
		t.set_stylebox(side + "_background", "SpinBox", up)
		t.set_stylebox(side + "_background_hovered", "SpinBox", up_h)
		t.set_stylebox(side + "_background_pressed", "SpinBox", up_p)
		t.set_stylebox(side + "_background_disabled", "SpinBox", up_d)
		t.set_color(side + "_icon_modulate", "SpinBox", ACCENT_DEEP)
		t.set_color(side + "_hover_icon_modulate", "SpinBox", ACCENT_DEEP)
		t.set_color(side + "_pressed_icon_modulate", "SpinBox", Color.WHITE)
		t.set_color(side + "_disabled_icon_modulate", "SpinBox", TEXT_FAINT)
	var chev_up := _chevron(16, 1, Color.WHITE, 2.4)
	var chev_down := _chevron(16, 0, Color.WHITE, 2.4)
	for n in ["up", "up_hover", "up_pressed", "up_disabled"]:
		t.set_icon(n, "SpinBox", chev_up)
	for n in ["down", "down_hover", "down_pressed", "down_disabled"]:
		t.set_icon(n, "SpinBox", chev_down)
	# Godot 4.7 的 SpinBox 實際畫的是中間這個 updown 圖示（上下各一個小箭頭），
	# 上面那組 up/down 圖示只有在部分排版下才用得到，兩種都給。
	t.set_icon("updown", "SpinBox", _updown_icon(ACCENT_DEEP))
	t.set_stylebox("field_and_buttons_separator", "SpinBox", _empty(0, 0))
	t.set_stylebox("up_down_buttons_separator", "SpinBox", _empty(0, 0))
	t.set_constant("field_and_buttons_separation", "SpinBox", 4)
	t.set_constant("buttons_vertical_separation", "SpinBox", 2)
	t.set_constant("buttons_width", "SpinBox", 22)


static func _setup_sliders(t: Theme) -> void:
	var grabber := _dot_icon(22, Color.WHITE, ACCENT, 3.0)
	var grabber_hi := _dot_icon(22, ACCENT_TINT, ACCENT_DEEP, 3.5)
	var grabber_off := _dot_icon(22, Color(0.98, 0.97, 0.99, 0.9), BORDER_DEEP, 3.0)
	for ty in ["HSlider", "VSlider"]:
		var vertical: bool = ty == "VSlider"
		t.set_stylebox("slider", ty, _track(TRACK, vertical, 3, 1, BORDER))
		t.set_stylebox("grabber_area", ty, _track(ACCENT, vertical, 3, 0, BORDER))
		t.set_stylebox("grabber_area_highlight", ty, _track(ACCENT_DEEP, vertical, 3, 0, BORDER))
		t.set_icon("grabber", ty, grabber)
		t.set_icon("grabber_highlight", ty, grabber_hi)
		t.set_icon("grabber_disabled", ty, grabber_off)
		t.set_icon("tick", ty, _tick_icon())
		t.set_constant("center_grabber", ty, 0)
		t.set_constant("grabber_offset", ty, 0)

	t.set_stylebox("background", "ProgressBar", _sb(TRACK, 10, 1, BORDER, 0, 3))
	t.set_stylebox("fill", "ProgressBar", _sb(ACCENT, 10, 0, BORDER, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color(1, 1, 1, 0.65))
	t.set_constant("outline_size", "ProgressBar", 3)


static func _setup_tabs(t: Theme) -> void:
	t.set_stylebox("panel", "TabContainer", _empty(2, 6))
	t.set_stylebox("tabbar_background", "TabContainer", _empty(0, 0))
	t.set_stylebox("tab_selected", "TabContainer", _sb(ACCENT, RADIUS_PILL, 0, BORDER, 14, 6, 6))
	t.set_stylebox("tab_hovered", "TabContainer", _sb(ACCENT_SOFT, RADIUS_PILL, 0, BORDER, 14, 6))
	t.set_stylebox("tab_unselected", "TabContainer", _sb(Color(0.9569, 0.9333, 0.9882, 0.55), RADIUS_PILL, 1, BORDER, 14, 6))
	t.set_stylebox("tab_disabled", "TabContainer", _sb(Color(0.949, 0.933, 0.9647, 0.4), RADIUS_PILL, 0, BORDER, 14, 6))
	t.set_stylebox("tab_focus", "TabContainer", _focus_ring())
	t.set_font("font", "TabContainer", font_bold())
	t.set_font_size("font_size", "TabContainer", FONT_SIZE)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_hovered_color", "TabContainer", ACCENT_DEEP)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_disabled_color", "TabContainer", TEXT_FAINT)
	t.set_color("font_outline_color", "TabContainer", Color(1, 1, 1, 0))
	t.set_color("drop_mark_color", "TabContainer", ACCENT)
	t.set_color("icon_selected_color", "TabContainer", Color.WHITE)
	t.set_color("icon_hovered_color", "TabContainer", ACCENT_DEEP)
	t.set_color("icon_unselected_color", "TabContainer", TEXT_DIM)
	t.set_constant("side_margin", "TabContainer", 2)
	t.set_constant("outline_size", "TabContainer", 0)
	t.set_icon("increment", "TabContainer", _chevron(16, 2, TEXT_DIM, 2.2))
	t.set_icon("increment_highlight", "TabContainer", _chevron(16, 2, ACCENT_DEEP, 2.2))
	t.set_icon("decrement", "TabContainer", _chevron(16, 3, TEXT_DIM, 2.2))
	t.set_icon("decrement_highlight", "TabContainer", _chevron(16, 3, ACCENT_DEEP, 2.2))
	t.set_icon("menu", "TabContainer", _chevron(16, 0, TEXT_DIM, 2.2))
	t.set_icon("menu_highlight", "TabContainer", _chevron(16, 0, ACCENT_DEEP, 2.2))
	t.set_icon("drop_mark", "TabContainer", _empty_icon())

	# TabBar 單獨使用時也一樣
	t.set_stylebox("tab_selected", "TabBar", t.get_stylebox("tab_selected", "TabContainer"))
	t.set_stylebox("tab_hovered", "TabBar", t.get_stylebox("tab_hovered", "TabContainer"))
	t.set_stylebox("tab_unselected", "TabBar", t.get_stylebox("tab_unselected", "TabContainer"))
	t.set_stylebox("tab_focus", "TabBar", _focus_ring())
	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", ACCENT_DEEP)


static func _setup_lists(t: Theme) -> void:
	t.set_stylebox("panel", "ItemList", _sb(FIELD, RADIUS_CARD, 1, BORDER_DEEP, 4, 4))
	t.set_stylebox("focus", "ItemList", _focus_ring())
	t.set_stylebox("selected", "ItemList", _sb(ACCENT_SOFT, 10, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _sb(ACCENT_SOFT, 10, 1, ACCENT, 4, 2))
	t.set_stylebox("hovered", "ItemList", _sb(ACCENT_TINT, 10, 0, BORDER, 4, 2))
	t.set_stylebox("hovered_selected", "ItemList", _sb(ACCENT_SOFT.lightened(0.04), 10, 1, ACCENT, 4, 2))
	t.set_stylebox("hovered_selected_focus", "ItemList", _sb(ACCENT_SOFT.lightened(0.04), 10, 1, ACCENT, 4, 2))
	t.set_stylebox("cursor", "ItemList", _sb(Color(1, 1, 1, 0), 10, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7), 4, 2))
	t.set_stylebox("cursor_unfocused", "ItemList", _sb(Color(1, 1, 1, 0), 10, 1, BORDER_DEEP, 4, 2))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", ACCENT_DEEP)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_hovered_selected_color", "ItemList", ACCENT_DEEP)
	t.set_color("font_outline_color", "ItemList", Color(1, 1, 1, 0))
	t.set_color("guide_color", "ItemList", Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, 0.5))
	t.set_constant("outline_size", "ItemList", 0)
	t.set_constant("v_separation", "ItemList", 4)
	t.set_constant("h_separation", "ItemList", 6)
	t.set_constant("line_separation", "ItemList", 2)

	# Tree（FileDialog 的檔案清單）
	t.set_stylebox("panel", "Tree", _sb(FIELD, RADIUS_CARD, 1, BORDER_DEEP, 4, 4))
	t.set_stylebox("focus", "Tree", _focus_ring())
	t.set_stylebox("selected", "Tree", _sb(ACCENT_SOFT, 8, 0, BORDER, 4, 2))
	t.set_stylebox("selected_focus", "Tree", _sb(ACCENT_SOFT, 8, 1, ACCENT, 4, 2))
	t.set_stylebox("hovered", "Tree", _sb(ACCENT_TINT, 8, 0, BORDER, 4, 2))
	t.set_stylebox("hovered_dimmed", "Tree", _sb(ACCENT_TINT, 8, 0, BORDER, 4, 2))
	t.set_stylebox("hovered_selected", "Tree", _sb(ACCENT_SOFT, 8, 1, ACCENT, 4, 2))
	t.set_stylebox("hovered_selected_focus", "Tree", _sb(ACCENT_SOFT, 8, 1, ACCENT, 4, 2))
	t.set_stylebox("cursor", "Tree", _sb(Color(1, 1, 1, 0), 8, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7), 4, 2))
	t.set_stylebox("cursor_unfocused", "Tree", _sb(Color(1, 1, 1, 0), 8, 1, BORDER_DEEP, 4, 2))
	t.set_stylebox("title_button_normal", "Tree", _sb(PANEL_SOFT, 8, 1, BORDER, 6, 4))
	t.set_stylebox("title_button_hover", "Tree", _sb(ACCENT_SOFT, 8, 1, BORDER, 6, 4))
	t.set_stylebox("title_button_pressed", "Tree", _sb(ACCENT, 8, 1, BORDER, 6, 4))
	t.set_stylebox("button_hover", "Tree", _sb(ACCENT_TINT, 8, 0, BORDER, 2, 2))
	t.set_stylebox("button_pressed", "Tree", _sb(ACCENT_SOFT, 8, 0, BORDER, 2, 2))
	t.set_stylebox("custom_button", "Tree", _sb(PANEL_SOFT, 10, 1, BORDER, 8, 4))
	t.set_stylebox("custom_button_hover", "Tree", _sb(ACCENT_SOFT, 10, 1, ACCENT, 8, 4))
	t.set_stylebox("custom_button_pressed", "Tree", _sb(ACCENT, 10, 1, ACCENT_DEEP, 8, 4))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_hovered_color", "Tree", TEXT)
	t.set_color("font_hovered_dimmed_color", "Tree", TEXT_DIM)
	t.set_color("font_selected_color", "Tree", ACCENT_DEEP)
	t.set_color("font_hovered_selected_color", "Tree", ACCENT_DEEP)
	t.set_color("font_disabled_color", "Tree", TEXT_FAINT)
	t.set_color("font_outline_color", "Tree", Color(1, 1, 1, 0))
	t.set_color("title_button_color", "Tree", TEXT)
	t.set_color("guide_color", "Tree", Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, 0.5))
	t.set_color("relationship_line_color", "Tree", BORDER_DEEP)
	t.set_color("parent_hl_line_color", "Tree", ACCENT)
	t.set_color("children_hl_line_color", "Tree", LAVENDER)
	t.set_color("drop_position_color", "Tree", ACCENT)
	t.set_constant("outline_size", "Tree", 0)
	t.set_constant("v_separation", "Tree", 4)
	t.set_icon("checked", "Tree", _check_icon(true, false))
	t.set_icon("unchecked", "Tree", _check_icon(false, false))
	t.set_icon("checked_disabled", "Tree", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "Tree", _check_icon(false, true))
	t.set_icon("arrow", "Tree", _chevron(16, 0, TEXT_DIM, 2.0))
	t.set_icon("arrow_collapsed", "Tree", _chevron(16, 2, TEXT_DIM, 2.0))
	t.set_icon("arrow_collapsed_mirrored", "Tree", _chevron(16, 3, TEXT_DIM, 2.0))
	t.set_icon("select_arrow", "Tree", _chevron(16, 0, ACCENT_DEEP, 2.0))
	t.set_icon("updown", "Tree", _updown_icon(TEXT_DIM))

	t.set_color("folder_icon_color", "FileDialog", ACCENT)
	t.set_color("file_icon_color", "FileDialog", LAVENDER_DEEP)
	t.set_color("file_disabled_color", "FileDialog", TEXT_FAINT)


static func _setup_popups(t: Theme) -> void:
	var pop := _sb(Color(1.0, 0.9922, 1.0, 0.985), RADIUS_PANEL, 1, BORDER_DEEP, 6, 8, 16)
	pop.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	t.set_stylebox("hover", "PopupMenu", _sb(ACCENT_SOFT, 10, 0, BORDER, 0, 0))
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	sep.grow_begin = -4.0
	sep.grow_end = -4.0
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_DEEP)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_accelerator_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_separator_color", "PopupMenu", LAVENDER_DEEP)
	t.set_color("font_outline_color", "PopupMenu", Color(1, 1, 1, 0))
	t.set_constant("outline_size", "PopupMenu", 0)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 8)
	t.set_constant("item_end_padding", "PopupMenu", 8)
	t.set_icon("checked", "PopupMenu", _check_icon(true, false))
	t.set_icon("unchecked", "PopupMenu", _check_icon(false, false))
	t.set_icon("checked_disabled", "PopupMenu", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "PopupMenu", _check_icon(false, true))
	t.set_icon("radio_checked", "PopupMenu", _radio_icon(true, false))
	t.set_icon("radio_unchecked", "PopupMenu", _radio_icon(false, false))
	t.set_icon("radio_checked_disabled", "PopupMenu", _radio_icon(true, true))
	t.set_icon("radio_unchecked_disabled", "PopupMenu", _radio_icon(false, true))
	t.set_icon("submenu", "PopupMenu", _chevron(16, 2, TEXT_DIM, 2.0))
	t.set_icon("submenu_mirrored", "PopupMenu", _chevron(16, 3, TEXT_DIM, 2.0))

	# 滑鼠提示泡泡：深紫底 + 淡粉字，疊在任何背景上都看得清
	var tip := _sb(Color(INK.r, INK.g, INK.b, 0.95), 10, 1, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5), 10, 6, 10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT_ON_DARK)
	t.set_color("font_shadow_color", "TooltipLabel", Color(1, 1, 1, 0))
	t.set_color("font_outline_color", "TooltipLabel", Color(1, 1, 1, 0))
	t.set_font_size("font_size", "TooltipLabel", 14)


static func _setup_scrollbars(t: Theme) -> void:
	for ty in ["HScrollBar", "VScrollBar"]:
		var vertical: bool = ty == "VScrollBar"
		t.set_stylebox("scroll", ty, _track(Color(TRACK.r, TRACK.g, TRACK.b, 0.6), vertical, 5, 0, BORDER))
		t.set_stylebox("scroll_focus", ty, _track(Color(TRACK.r, TRACK.g, TRACK.b, 0.8), vertical, 5, 0, BORDER))
		t.set_stylebox("grabber", ty, _track(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), vertical, 5, 0, BORDER))
		t.set_stylebox("grabber_highlight", ty, _track(ACCENT, vertical, 5, 0, BORDER))
		t.set_stylebox("grabber_pressed", ty, _track(ACCENT_DEEP, vertical, 5, 0, BORDER))
		for n in ["increment", "increment_highlight", "increment_pressed",
				"decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(n, ty, _empty_icon())


static func _setup_windows(t: Theme) -> void:
	var win := _sb(Color(1.0, 0.9922, 1.0, 0.99), RADIUS_PANEL, 2, ACCENT, 10, 10, 20)
	win.shadow_offset = Vector2(0, 6)
	t.set_stylebox("embedded_border", "Window", win)
	var win_off := _sb(Color(1.0, 0.9922, 1.0, 0.97), RADIUS_PANEL, 2, BORDER_DEEP, 10, 10, 14)
	t.set_stylebox("embedded_unfocused_border", "Window", win_off)
	t.set_font("title_font", "Window", font_bold())
	t.set_font_size("title_font_size", "Window", 16)
	t.set_color("title_color", "Window", TEXT)
	t.set_constant("title_outline_size", "Window", 0)
	t.set_constant("title_height", "Window", 34)
	t.set_constant("close_h_offset", "Window", 20)
	t.set_constant("close_v_offset", "Window", 26)
	t.set_icon("close", "Window", _close_icon(TEXT_DIM))
	t.set_icon("close_pressed", "Window", _close_icon(ACCENT_DEEP))

	var dlg := _sb(Color(1.0, 0.9922, 1.0, 0.99), RADIUS_PANEL, 1, BORDER_DEEP, 12, 12, 18)
	t.set_stylebox("panel", "AcceptDialog", dlg)
	t.set_constant("buttons_separation", "AcceptDialog", 10)

	# ColorPicker（ColorPickerButton 的彈窗）
	t.set_stylebox("sample_focus", "ColorPicker", _focus_ring())
	t.set_stylebox("picker_focus_rectangle", "ColorPicker", _focus_ring())
	t.set_stylebox("picker_focus_circle", "ColorPicker", _focus_ring())
	t.set_icon("sample_bg", "ColorPicker", _checker(14, Color.WHITE, ACCENT_SOFT))


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
		s.shadow_offset = Vector2(0, 2)
	return s


## 滑桿／捲軸的軌道：厚度由 content margin 決定（Godot 用 stylebox 最小尺寸當軌道粗細）
static func _track(col: Color, vertical: bool, half_thickness: int, bw: int, bc: Color) -> StyleBoxFlat:
	var s := _sb(col, half_thickness, bw, bc)
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
	s.set_border_width_all(2)
	s.border_color = Color(LAVENDER_DEEP.r, LAVENDER_DEEP.g, LAVENDER_DEEP.b, 0.85)
	s.anti_aliasing = true
	s.set_expand_margin_all(1.0)
	return s


# ================================================================ 程式畫圖示

static func _empty_icon() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))


## 圓角矩形的 signed distance，用來做抗鋸齒
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
	var pad := width * 0.5 + 1.5
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var x0 := maxi(int(lo.x - pad), 0)
	var y0 := maxi(int(lo.y - pad), 0)
	var x1 := mini(int(hi.x + pad) + 1, img.get_width())
	var y1 := mini(int(hi.y + pad) + 1, img.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
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
	var s := 22
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var box := Rect2(1, 1, s - 2, s - 2)
	var fade := 0.45 if disabled else 1.0
	if on:
		var fill := ACCENT if not disabled else ACCENT.lerp(Color(0.9, 0.88, 0.92), 0.6)
		_draw_rrect(img, box, 7.0, fill, ACCENT_DEEP, 0.0)
		var tick := PackedVector2Array([Vector2(5.5, 11.3), Vector2(9.2, 15.0), Vector2(16.0, 7.0)])
		_draw_path(img, tick, 2.8, Color(1, 1, 1, fade))
	else:
		_draw_rrect(img, box, 7.0, Color(1, 1, 1, 0.85 * fade), Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, fade), 2.0)
	return ImageTexture.create_from_image(img)


static func _radio_icon(on: bool, disabled: bool) -> ImageTexture:
	var s := 22
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var box := Rect2(1, 1, s - 2, s - 2)
	var fade := 0.45 if disabled else 1.0
	if on:
		_draw_rrect(img, box, 10.0, ACCENT, ACCENT_DEEP, 0.0)
		_draw_rrect(img, Rect2(7.5, 7.5, 7, 7), 3.5, Color(1, 1, 1, fade), Color.WHITE, 0.0)
	else:
		_draw_rrect(img, box, 10.0, Color(1, 1, 1, 0.85 * fade), Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, fade), 2.0)
	return ImageTexture.create_from_image(img)


static func _switch_icon(on: bool, disabled: bool) -> ImageTexture:
	var w := 38
	var h := 22
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var fade := 0.45 if disabled else 1.0
	var track := ACCENT if on else TRACK
	if disabled:
		track = track.lerp(Color(0.93, 0.92, 0.95), 0.6)
	_draw_rrect(img, Rect2(1, 2, w - 2, h - 4), 9.0, Color(track.r, track.g, track.b, fade),
		Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, fade), 1.0)
	var cx := float(w - 10) if on else 10.0
	_draw_rrect(img, Rect2(cx - 8, h * 0.5 - 8, 16, 16), 8.0, Color(1, 1, 1, fade),
		Color(1, 1, 1, fade * 0.5), 0.0)
	return ImageTexture.create_from_image(img)


## 滑桿的圓形把手：白底 + 粉紅環 + 外圈淡暈
static func _dot_icon(size: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var f := float(size)
	_draw_rrect(img, Rect2(0, 0, f, f), f * 0.5, Color(ring.r, ring.g, ring.b, 0.18), ring, 0.0)
	var inset := 2.5
	_draw_rrect(img, Rect2(inset, inset, f - inset * 2.0, f - inset * 2.0),
		(f - inset * 2.0) * 0.5, fill, ring, ring_w)
	return ImageTexture.create_from_image(img)


static func _tick_icon() -> ImageTexture:
	var img := Image.create_empty(2, 6, false, Image.FORMAT_RGBA8)
	_draw_rrect(img, Rect2(0, 0, 2, 6), 1.0, Color(BORDER_DEEP.r, BORDER_DEEP.g, BORDER_DEEP.b, 0.9), BORDER_DEEP, 0.0)
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


## SpinBox 中間的上下小箭頭
static func _updown_icon(col: Color) -> ImageTexture:
	var img := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	_draw_path(img, PackedVector2Array([Vector2(4, 9), Vector2(8, 5), Vector2(12, 9)]), 2.2, col)
	_draw_path(img, PackedVector2Array([Vector2(4, 15), Vector2(8, 19), Vector2(12, 15)]), 2.2, col)
	return ImageTexture.create_from_image(img)


static func _close_icon(col: Color) -> ImageTexture:
	var s := 16
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	_draw_path(img, PackedVector2Array([Vector2(4.5, 4.5), Vector2(11.5, 11.5)]), 2.2, col)
	_draw_path(img, PackedVector2Array([Vector2(11.5, 4.5), Vector2(4.5, 11.5)]), 2.2, col)
	return ImageTexture.create_from_image(img)


## 透明色用的棋盤底
static func _checker(cell: int, a: Color, b: Color) -> ImageTexture:
	var s := cell * 2
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var odd := ((x / cell) + (y / cell)) % 2 == 1
			img.set_pixel(x, y, b if odd else a)
	return ImageTexture.create_from_image(img)
