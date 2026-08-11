class_name OrbitCamera
extends Node3D

## 盤の周囲を回り込むオービットカメラ。
## 左ドラッグで回転、ホイールでズーム。ズームは min/max で盤を見失わない。
## 左ドラッグは閾値を超えてから回転開始し、クリック選択(#5)と共存する。

const DRAG_THRESHOLD_PX := 6.0

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
var _button_down: bool = false
var _orbit_active: bool = false
var _press_pos: Vector2 = Vector2.ZERO


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
			# 閾値未満はクリック扱い(GameController と同じ DRAG_THRESHOLD_PX)。
			# handled にしないので release を双方が受け取れる。
			if mb.pressed:
				_button_down = true
				_orbit_active = false
				_press_pos = mb.position
			else:
				_button_down = false
				_orbit_active = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_distance(distance - zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_distance(distance + zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _button_down:
		var mm := event as InputEventMouseMotion
		if not _orbit_active:
			if _press_pos.distance_to(mm.position) <= DRAG_THRESHOLD_PX:
				return
			_orbit_active = true
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
