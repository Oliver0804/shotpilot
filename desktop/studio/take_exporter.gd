class_name TakeExporter
extends Node
## 把錄好的鏡頭 take 離線逐幀渲染（不受即時效能影響），輸出：
##   rgb/00001.png…  + rgb.mp4      一般畫面
##   depth/00001.png… + depth.mp4   深度圖（近白遠黑，可給 ControlNet / video-to-video 當結構參考）
##   camera.json                    每幀的鏡頭位置、旋轉、FOV

signal progress(done: int, total: int, message: String)
signal finished(out_dir: String, ok: bool)

const DEPTH_LAYER := 19

const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float near_m = 0.3;
uniform float far_m = 15.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0); // 全螢幕四邊形
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float dist = -view.z / view.w;
	float v = 1.0 - clamp((dist - near_m) / (far_m - near_m), 0.0, 1.0);
	// 輸出會再經過 sRGB 轉換，先轉回線性，讓存檔的灰階值剛好是 v
	ALBEDO = vec3(v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4));
}
"""

## 匯出長度上限（秒）與至少保留的硬碟空間
const MAX_SECONDS := 600
const MIN_FREE_BYTES := 2_000_000_000

var busy := false
## 最近一次匯出的結果（export_take 可能在第一個 await 前就失敗結束，呼叫端請用 await export_take() 後讀這個，不要等 finished 訊號）
var last_ok := false
var last_message := ""
var _cancel := false


func cancel() -> void:
	_cancel = true


static func find_ffmpeg() -> String:
	for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]:
		if FileAccess.file_exists(p):
			return p
	var out := []
	if OS.execute("which", ["ffmpeg"], out) == 0 and out.size() > 0:
		return String(out[0]).strip_edges()
	return ""


## anim：take；cam_parent：鏡頭的父節點（take 的軌跡是相對它的座標）；src_cam：複製 FOV／環境
## keep_png=false（預設）時畫面直接以 rawvideo 管線餵給 ffmpeg，硬碟上只留 mp4
func export_take(anim: Animation, cam_parent: Node3D, src_cam: Camera3D, out_dir: String,
		long_side: int, aspect: float, fps: int, with_depth: bool, depth_far: float,
		frame_cb := Callable(), keep_png := false) -> void:
	if busy:
		return
	busy = true
	_cancel = false

	var size := Vector2i(long_side, int(long_side / aspect)) if aspect >= 1.0 else Vector2i(int(long_side * aspect), long_side)
	size = Vector2i(size.x / 2 * 2, size.y / 2 * 2) # H.264 需要偶數尺寸
	var total := maxi(1, int(ceil(anim.length * fps)))
	var ffmpeg := find_ffmpeg()
	if ffmpeg == "":
		keep_png = true

	# ---- 安全檢查：長度與硬碟空間
	if not is_finite(anim.length) or anim.length > MAX_SECONDS:
		_fail(out_dir, "這段 take 長達 %.0f 秒，超過上限 %d 秒。可能是錄製沒有停止，請重新錄製。" % [anim.length, MAX_SECONDS])
		return
	var px := float(size.x * size.y)
	var per_frame := (px * 1.6 + (px * 0.5 if with_depth else 0.0)) if keep_png else px * 0.06
	var need := int(per_frame * total) + MIN_FREE_BYTES
	DirAccess.make_dir_recursive_absolute(out_dir)
	var dir := DirAccess.open(out_dir)
	var free := dir.get_space_left() if dir else 0
	if free > 0 and need > free:
		_fail(out_dir, "硬碟空間不足：預估需要 %.1f GB（含保留 2 GB），剩餘 %.1f GB。" % [need / 1e9, free / 1e9])
		return
	if keep_png:
		DirAccess.make_dir_recursive_absolute(out_dir + "/rgb")
		if with_depth:
			DirAccess.make_dir_recursive_absolute(out_dir + "/depth")

	var world := cam_parent.get_world_3d()
	var gizmo_bit := 1 << (PhoneCameraRig.GIZMO_LAYER - 1)
	var depth_bit := 1 << (DEPTH_LAYER - 1)

	var rgb_vp := _make_viewport(size, world)
	var rgb_cam := _make_cam(rgb_vp, src_cam)
	rgb_cam.cull_mask &= ~(gizmo_bit | depth_bit)

	var depth_vp: SubViewport
	var depth_cam: Camera3D
	if with_depth:
		depth_vp = _make_viewport(size, world)
		depth_cam = _make_cam(depth_vp, src_cam)
		depth_cam.cull_mask &= ~gizmo_bit
		var env := Environment.new() # 線性色調、無霧無光暈，確保灰階值準確
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		depth_cam.environment = env
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		quad.mesh = qm
		quad.layers = depth_bit
		quad.extra_cull_margin = 16384.0
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = DEPTH_SHADER
		sm.shader = sh
		sm.set_shader_parameter("near_m", src_cam.near if src_cam else 0.05)
		sm.set_shader_parameter("far_m", depth_far)
		quad.material_override = sm
		depth_cam.add_child(quad)

	# ---- ffmpeg 管線（不落地 PNG）
	var pipes := {}
	if not keep_png:
		pipes["rgb"] = _open_pipe(ffmpeg, size, fps, "rgb24", out_dir + "/rgb.mp4")
		if with_depth:
			pipes["depth"] = _open_pipe(ffmpeg, size, fps, "gray", out_dir + "/depth.mp4")
		for k in pipes:
			if pipes[k].is_empty():
				rgb_vp.queue_free()
				if depth_vp:
					depth_vp.queue_free()
				_close_pipes(pipes, true)
				_fail(out_dir, "無法啟動 ffmpeg")
				return

	var pos_track := _find_track(anim, Animation.TYPE_POSITION_3D)
	var rot_track := _find_track(anim, Animation.TYPE_ROTATION_3D)
	var fov_track := find_fov_track(anim)
	# 沒有關鍵影格的軌道視為不存在（否則 interpolate 會報錯並中斷匯出）
	if pos_track >= 0 and anim.track_get_key_count(pos_track) == 0:
		pos_track = -1
	if rot_track >= 0 and anim.track_get_key_count(rot_track) == 0:
		rot_track = -1
	if fov_track >= 0 and anim.track_get_key_count(fov_track) == 0:
		fov_track = -1
	var fallback := src_cam.global_transform if src_cam and src_cam.is_inside_tree() else Transform3D()
	var cam_log := []
	var ok := true
	var err_msg := ""

	for i in total:
		if _cancel:
			ok = false
			err_msg = "已取消"
			break
		var t := minf(i / float(fps), anim.length)
		if frame_cb.is_valid():
			frame_cb.call(t) # 讓會移動的物件擺到這一幀的位置
		var xf := fallback
		if pos_track >= 0 or rot_track >= 0:
			var local := Transform3D(
				Basis(anim.rotation_track_interpolate(rot_track, t)) if rot_track >= 0 else fallback.basis,
				anim.position_track_interpolate(pos_track, t) if pos_track >= 0 else fallback.origin)
			xf = cam_parent.global_transform * local
		rgb_cam.global_transform = xf
		if fov_track >= 0:
			var fv = anim.value_track_interpolate(fov_track, t)
			if fv is float or fv is int:
				rgb_cam.fov = float(fv)
		if depth_cam:
			depth_cam.global_transform = xf
			depth_cam.fov = rgb_cam.fov
		await RenderingServer.frame_post_draw

		var rgb := rgb_vp.get_texture().get_image()
		var depth: Image = null
		if depth_vp:
			depth = depth_vp.get_texture().get_image()
			depth.convert(Image.FORMAT_L8)
		if keep_png:
			var fname := "%05d.png" % (i + 1)
			if rgb.save_png(out_dir + "/rgb/" + fname) != OK or (depth and depth.save_png(out_dir + "/depth/" + fname) != OK):
				ok = false
				err_msg = "寫入 PNG 失敗（硬碟可能已滿），已停止"
				break
			if i % 50 == 49 and dir and dir.get_space_left() < MIN_FREE_BYTES:
				ok = false
				err_msg = "硬碟剩餘空間低於 2 GB，已停止匯出"
				break
		else:
			rgb.convert(Image.FORMAT_RGB8)
			if not _write_pipe(pipes["rgb"], rgb.get_data()) or (depth and not _write_pipe(pipes["depth"], depth.get_data())):
				ok = false
				err_msg = "ffmpeg 寫入失敗，已停止"
				break
		var q := xf.basis.get_rotation_quaternion()
		cam_log.append({"frame": i + 1, "t": t, "pos": [xf.origin.x, xf.origin.y, xf.origin.z],
			"quat": [q.x, q.y, q.z, q.w], "fov": rgb_cam.fov})
		progress.emit(i + 1, total, "渲染 %d / %d" % [i + 1, total])

	var final_fov := rgb_cam.fov
	rgb_vp.queue_free()
	if depth_vp:
		depth_vp.queue_free()

	if not keep_png:
		progress.emit(total, total, "ffmpeg 收尾中…")
		await _close_pipes(pipes, not ok)

	if ok:
		var f := FileAccess.open(out_dir + "/camera.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"fps": fps, "width": size.x, "height": size.y,
				"vertical_fov": final_fov, "frames": cam_log}, "\t"))
			f.close()
		if keep_png and ffmpeg != "":
			progress.emit(total, total, "ffmpeg 合成影片…")
			var passes := ["rgb"] + (["depth"] if with_depth else [])
			for p in passes:
				var args := ["-y", "-loglevel", "error", "-framerate", str(fps), "-i", "%s/%s/%%05d.png" % [out_dir, p],
					"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "%s/%s.mp4" % [out_dir, p]]
				var tid := WorkerThreadPool.add_task(func(): OS.execute(ffmpeg, args))
				while not WorkerThreadPool.is_task_completed(tid):
					await get_tree().process_frame
				WorkerThreadPool.wait_for_task_completion(tid)
		elif ffmpeg == "":
			progress.emit(total, total, "找不到 ffmpeg，只輸出 PNG 序列")
		if not FileAccess.file_exists(out_dir + "/rgb.mp4") and ffmpeg != "":
			ok = false
			err_msg = "ffmpeg 沒有產生 rgb.mp4"
	if not ok:
		progress.emit(0, 1, err_msg)
	busy = false
	last_ok = ok
	last_message = err_msg
	finished.emit(out_dir, ok)


func _fail(out_dir: String, msg: String) -> void:
	push_warning("TakeExporter: " + msg)
	progress.emit(0, 1, msg)
	busy = false
	last_ok = false
	last_message = msg
	finished.emit(out_dir, false)


func _open_pipe(ffmpeg: String, size: Vector2i, fps: int, pix_fmt: String, out_path: String) -> Dictionary:
	var args := ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", pix_fmt,
		"-s", "%dx%d" % [size.x, size.y], "-r", str(fps), "-i", "-",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", out_path]
	var p := OS.execute_with_pipe(ffmpeg, args)
	if p.is_empty() or p.get("stdio") == null:
		return {}
	p["out"] = out_path
	return p


func _write_pipe(p: Dictionary, data: PackedByteArray) -> bool:
	var fa: FileAccess = p.stdio
	if not OS.is_process_running(p.pid):
		return false
	fa.store_buffer(data)
	return fa.get_error() == OK


## 關閉 stdin 讓 ffmpeg 收尾；abort 時直接結束程序並刪掉不完整的檔案
func _close_pipes(pipes: Dictionary, abort: bool) -> void:
	for k in pipes:
		var p: Dictionary = pipes[k]
		if p.is_empty():
			continue
		if abort and OS.is_process_running(p.pid):
			OS.kill(p.pid)
		(p.stdio as FileAccess).close()
	for k in pipes:
		var p: Dictionary = pipes[k]
		if p.is_empty():
			continue
		var waited := 0.0
		while OS.is_process_running(p.pid) and waited < 120.0:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		if abort and FileAccess.file_exists(p.out):
			DirAccess.remove_absolute(p.out)


func _make_viewport(size: Vector2i, world: World3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.world_3d = world
	add_child(vp)
	return vp


func _make_cam(vp: SubViewport, src: Camera3D) -> Camera3D:
	var c := Camera3D.new()
	if src:
		c.fov = src.fov
		c.near = src.near
		c.far = src.far
		c.environment = src.environment
		c.attributes = src.attributes
		c.keep_aspect = src.keep_aspect
	vp.add_child(c)
	c.current = true
	return c


## 錄製或自動運鏡時的 FOV 變化（值軌，路徑以 ":fov" 結尾）
static func find_fov_track(anim: Animation) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_VALUE and str(anim.track_get_path(i)).ends_with(":fov"):
			return i
	return -1


static func _find_track(anim: Animation, type: int) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type:
			return i
	return -1
