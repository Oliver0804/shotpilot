class_name CameraPath
extends RefCounted
## 依記錄點產生平滑運鏡：位置用 Catmull-Rom 曲線、旋轉用球面三次插值，
## 各段時間依「移動距離＋轉動角度」分配，整段可加緩入緩出。結果烘焙成 Animation。


## points：每個記錄點 {"xf": Transform3D, "fov": float}
static func bake(points: Array, duration: float, ease_in_out: bool, track_path: NodePath, fps := 30) -> Animation:
	var n := points.size()
	var a := Animation.new()
	var pt := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pt, track_path)
	var rt := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(rt, track_path)
	var ft := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ft, NodePath(str(track_path) + ":fov"))
	a.length = maxf(duration, 0.1)
	if n == 0:
		return a

	var fovs: Array[float] = []
	for p in points:
		fovs.append(float(p.get("fov", 50.0)))
	var pos: Array[Vector3] = []
	var rot: Array[Quaternion] = []
	for p in points:
		var xf: Transform3D = p.xf
		pos.append(xf.origin)
		var q := xf.basis.get_rotation_quaternion()
		if rot.size() > 0 and rot[-1].dot(q) < 0.0:
			q = -q # 保持同半球，避免繞遠路
		rot.append(q)

	# 每段的「成本」＝距離 + 轉角（1 弧度約當 1.5 公尺），用來分配時間
	var cum: Array[float] = [0.0]
	for i in range(1, n):
		var cost := pos[i].distance_to(pos[i - 1]) + rot[i].angle_to(rot[i - 1]) * 1.5
		cum.append(cum[-1] + maxf(cost, 0.05))
	var total: float = cum[-1]

	var frames := maxi(2, int(ceil(a.length * fps)) + 1)
	for f in frames:
		var t := minf(f / float(fps), a.length)
		var u := t / a.length
		if ease_in_out:
			u = u * u * (3.0 - 2.0 * u) # smoothstep
		var p: Vector3
		var q: Quaternion
		var fov: float
		if n == 1:
			p = pos[0]
			q = rot[0]
			fov = fovs[0]
		else:
			var d := u * total
			var i := 0
			while i < n - 2 and cum[i + 1] < d:
				i += 1
			var w := clampf((d - cum[i]) / (cum[i + 1] - cum[i]), 0.0, 1.0)
			var i0 := maxi(i - 1, 0)
			var i3 := mini(i + 2, n - 1)
			p = pos[i].cubic_interpolate(pos[i + 1], pos[i0], pos[i3], w)
			q = rot[i].spherical_cubic_interpolate(rot[i + 1], rot[i0], rot[i3], w).normalized()
			fov = cubic_interpolate(fovs[i], fovs[i + 1], fovs[i0], fovs[i3], w)
		a.position_track_insert_key(pt, t, p)
		a.rotation_track_insert_key(rt, t, q)
		a.track_insert_key(ft, t, fov)

	a.set_meta("fov", points[0].get("fov", 50.0))
	a.set_meta("auto", true)
	return a
