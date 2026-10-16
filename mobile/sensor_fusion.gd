extends RefCounted
## 陀螺儀 + 重力的互補濾波，輸出手機在世界中的姿態。
##
## 座標慣例：手機螢幕座標 = Godot 攝影機座標（X 右、Y 螢幕上方、Z 朝向使用者），
## 所以 basis 可直接當 Camera3D 的 basis 用（鏡頭看向手機背面）。
## 世界 Y 朝上；水平朝向（yaw）沒有絕對參考，由 PC 端「歸零」對齊。

## 每秒用重力修正傾斜的比例（越大越不飄，但抖動越明顯）
var gravity_gain := 1.5
## 陀螺儀方向相反的機種可設 -1
var gyro_sign := 1.0
## 額外繞螢幕法線旋轉感測器軸（度）；螢幕方向鎖定導致軸向錯位時使用
var axis_rotation := 0.0

var basis := Basis()
var initialized := false
## 世界座標的線性加速度（已扣除重力），m/s²
var linear_world := Vector3.ZERO

var _last_up := Vector3.ZERO


func reset() -> void:
	initialized = false


func update(delta: float, gyro: Vector3, grav: Vector3, acc: Vector3) -> void:
	var r := Basis(Vector3.BACK, deg_to_rad(axis_rotation))
	gyro = r * gyro * gyro_sign
	grav = r * grav
	acc = r * acc
	if grav.length() < 0.1:
		grav = acc # 沒有 OS 融合的重力就退回加速度計
	if grav.length() < 0.1:
		return # 沒有感測器（桌機）

	var up_dev := -grav.normalized()
	if not initialized:
		basis = Basis(Quaternion(up_dev, Vector3.UP))
		initialized = true
		_last_up = up_dev
		return

	# 螢幕自動旋轉時引擎會把感測器軸換成新的螢幕座標，重力方向會在一幀內跳 90°/180°。
	# 真實手部不可能這麼快，所以偵測到就把 basis 轉到新螢幕座標，避免畫面亂轉。
	if _last_up.dot(up_dev) < 0.5:
		_remap_screen_rotation(up_dev)
	_last_up = up_dev

	var w := gyro.length()
	if w > 1e-6:
		basis = basis * Basis(gyro / w, w * delta)

	var up_meas := basis * up_dev
	var axis := up_meas.cross(Vector3.UP)
	var s := axis.length()
	if s > 1e-6:
		var ang := atan2(s, up_meas.dot(Vector3.UP))
		basis = Basis(axis / s, ang * clampf(gravity_gain * delta, 0.0, 1.0)) * basis
	basis = basis.orthonormalized()

	linear_world = basis * (grav - acc)


func _remap_screen_rotation(up_new: Vector3) -> void:
	var best := 0.0
	var best_dot := -2.0
	for deg in [90.0, -90.0, 180.0]:
		var d := (Basis(Vector3.BACK, deg_to_rad(deg)) * up_new).dot(_last_up)
		if d > best_dot:
			best_dot = d
			best = deg
	if best_dot > 0.8:
		basis = basis * Basis(Vector3.BACK, deg_to_rad(best))
	else:
		basis = Basis(Quaternion(up_new, Vector3.UP)) # 手機平放時無法判斷，重新初始化
