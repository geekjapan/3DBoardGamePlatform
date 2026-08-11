class_name OrbitCamera
extends Node3D

## 盤の周囲を回り込むオービットカメラ。
## 左ドラッグで回転、右ドラッグで注視点の平行移動、中クリックで中心へ戻す、ホイールでズーム。
## ズームと平行移動は min/max で盤を見失わない。
## 左ドラッグは閾値を超えてから回転開始し、クリック選択(#5)と共存する。

const DRAG_THRESHOLD_PX := 6.0

@export var distance: float = 7.5
@export var min_distance: float = 3.0
@export var max_distance: float = 22.0
@export var yaw_degrees: float = 35.0
@export var pitch_degrees: float = -42.0
@export var min_pitch_degrees: float = -80.0
@export var max_pitch_degrees: float = -12.0
@export var orbit_sensitivity: float = 0.35
@export var zoom_step: float = 0.9
## 1px あたりの平行移動量。距離に比例させ、寄っても引いても同じ手触りにする。
@export var pan_sensitivity: float = 0.0022
## 注視点を原点から離せる上限。盤(一辺 8)を見失わない範囲。
@export var max_pan_distance: float = 5.0
## 見下ろす角度のせいで盤は画面の下へ寄る。注視点を画面上方向へこれだけ下げて、
## 盤を画面中央に戻す。0 にすると盤の手前側が下にはみ出す。
@export var focus_lift: float = 1.6

## 注視点のオフセット。原点が盤中心。
var pan_offset: Vector3 = Vector3.ZERO

## ダイアログ表示中は false。スクロール端でホイールが消費されず盤に届くのを防ぐ。
var input_enabled: bool = true

var _camera: Camera3D
var _button_down: bool = false
var _orbit_active: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _panning: bool = false


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


func set_pan(offset: Vector3) -> void:
	pan_offset = offset.limit_length(max_pan_distance)
	_apply()


func reset_pan() -> void:
	set_pan(Vector3.ZERO)


func pan_by_screen_delta(delta: Vector2) -> void:
	## 画面上のドラッグ量を、いまの向きに合わせた注視点の移動に変換する。
	## 盤がカーソルに付いてくるよう、注視点はドラッグと逆向きに動かす。
	var step := distance * pan_sensitivity
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0))
	set_pan(pan_offset - basis.x * delta.x * step + basis.y * delta.y * step)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		# 押しっぱなしのまま無効化されても、次に有効化したとき暴れないよう畳む。
		_button_down = false
		_orbit_active = false
		_panning = false
		return
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			# ずらしすぎたときに盤中心へ戻す唯一の手段。
			reset_pan()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_distance(distance - zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_distance(distance + zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		pan_by_screen_delta((event as InputEventMouseMotion).relative)
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
	# ピボット(このノード)を注視点に置き、ヨー/ピッチで回し、カメラを距離だけ後ろへ。
	pan_offset = pan_offset.limit_length(max_pan_distance)
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0))
	# focus_lift は画面基準なので、回してもフレーミングが崩れない。
	position = basis * Vector3(0.0, -focus_lift, 0.0) + pan_offset
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.rotation = Vector3.ZERO
