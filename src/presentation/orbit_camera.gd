class_name OrbitCamera
extends Node3D

## 盤の周囲を回り込むオービットカメラ。
## 左ドラッグで回転、ホイールでズーム。ズームは min/max で盤を見失わない。

@export var distance: float = 12.0
@export var min_distance: float = 5.0
@export var max_distance: float = 22.0
@export var yaw_degrees: float = 35.0
@export var pitch_degrees: float = -42.0
@export var min_pitch_degrees: float = -80.0
@export var max_pitch_degrees: float = -12.0
@export var orbit_sensitivity: float = 0.35
@export var zoom_step: float = 0.9

var _camera: Camera3D
var _dragging: bool = false


func _ready() -> void:
	_ensure_camera()
	_apply()


func camera() -> Camera3D:
	_ensure_camera()
	return _camera


func set_distance(value: float) -> void:
	distance = clampf(value, min_distance, max_distance)
	_apply()


func set_orbit(yaw: float, pitch: float) -> void:
	yaw_degrees = yaw
	pitch_degrees = clampf(pitch, min_pitch_degrees, max_pitch_degrees)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# 左ドラッグ開始/終了だけ記録。クリック選択(#5)を潰さないよう handled にしない。
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_distance(distance - zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_distance(distance + zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw_degrees -= mm.relative.x * orbit_sensitivity
		pitch_degrees = clampf(
			pitch_degrees - mm.relative.y * orbit_sensitivity,
			min_pitch_degrees,
			max_pitch_degrees
		)
		_apply()
		get_viewport().set_input_as_handled()


func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	add_child(_camera)


func _apply() -> void:
	_ensure_camera()
	distance = clampf(distance, min_distance, max_distance)
	pitch_degrees = clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	# ピボット(このノード)を盤中心に置き、ヨー/ピッチで回し、カメラを距離だけ後ろへ。
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.rotation = Vector3.ZERO
