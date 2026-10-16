@tool
extends EditorPlugin
## 右側 Dock：顯示目前場景中 PhoneCameraRig 的連線狀態，提供啟動伺服器、歸零、錄製按鈕。

const Rig := preload("phone_camera_rig.gd")

var _dock: VBoxContainer
var _status: Label
var _btn_server: Button
var _btn_recenter: Button
var _btn_rec: Button
var _refresh_t := 0.0


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "ShotPilot"

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 160
	_dock.add_child(_status)

	_btn_server = _add_button("啟動伺服器", _on_server_pressed)
	_btn_recenter = _add_button("歸零（對齊目前鏡頭）", func(): _with_rig(func(r): r.recenter()))
	_btn_rec = _add_button("● 開始錄製", _on_rec_pressed)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_refresh()


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t >= 0.3:
		_refresh_t = 0.0
		_refresh()


func _add_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_dock.add_child(b)
	return b


func _find_rig() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root.get_script() == Rig:
		return root
	for n in root.find_children("*", "Node", true, false):
		if n.get_script() == Rig:
			return n
	return null


func _with_rig(cb: Callable) -> void:
	var rig := _find_rig()
	if rig:
		cb.call(rig)
	_refresh()


func _on_server_pressed() -> void:
	_with_rig(func(r): r.server_running = not r.server_running)


func _on_rec_pressed() -> void:
	_with_rig(func(r): r.recording = not r.recording)


func _refresh() -> void:
	var rig := _find_rig()
	var has := rig != null
	_btn_server.disabled = not has
	_btn_recenter.disabled = not has
	_btn_rec.disabled = not has
	if not has:
		_status.text = "目前場景沒有 PhoneCameraRig 節點。\n新增節點 → 搜尋 PhoneCameraRig，並指定 target。"
		return

	var running: bool = rig.server_running
	_btn_server.text = "停止伺服器" if running else "啟動伺服器"
	_btn_rec.text = "■ 停止錄製" if rig.recording else "● 開始錄製"
	var lines := PackedStringArray()
	lines.append("目標：%s" % (rig.target.name if rig.target else "（未設定）"))
	if running:
		lines.append("伺服器執行中，手機 App 連到：")
		for a in rig.get_addresses():
			lines.append("  " + a)
		lines.append("已連線手機：%d" % rig.get_client_count())
		lines.append("提示：3D 視窗勾選攝影機 Preview 可同步看畫面")
	else:
		lines.append("伺服器未啟動")
	if rig.recording:
		lines.append("● 錄製中")
	_status.text = "\n".join(lines)
