class_name CameraSettings
extends RefCounted

## 初期視点。user://settings.cfg に保存し次回起動でも保持する。
## AI・発話・チームと同じファイルの別セクションを使う(他設定を壊さない)。
##
## 保存されていなければ OrbitCamera の既定値をそのまま使う。
## 「初期値に戻す」はこのセクションを消して既定へ戻す。

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "camera"

## 未保存を表す番兵。距離が正でなければ「保存なし」とみなす。
const UNSET_DISTANCE := -1.0

var distance: float = UNSET_DISTANCE
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0
var pan_offset: Vector3 = Vector3.ZERO

## テスト差し替え用。空なら CONFIG_PATH を使う。
var config_path: String = ""


static func load_or_default(path: String = "") -> CameraSettings:
	var s := CameraSettings.new()
	if path != "":
		s.config_path = path
	s.load_from_disk()
	return s


func resolved_path() -> String:
	if config_path != "":
		return config_path
	return CONFIG_PATH


func has_saved_view() -> bool:
	return distance > 0.0


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(resolved_path()) != OK:
		distance = UNSET_DISTANCE
		return
	distance = float(cfg.get_value(SECTION, "distance", UNSET_DISTANCE))
	yaw_degrees = float(cfg.get_value(SECTION, "yaw_degrees", 0.0))
	pitch_degrees = float(cfg.get_value(SECTION, "pitch_degrees", 0.0))
	pan_offset = Vector3(
		float(cfg.get_value(SECTION, "pan_x", 0.0)),
		float(cfg.get_value(SECTION, "pan_y", 0.0)),
		float(cfg.get_value(SECTION, "pan_z", 0.0))
	)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	# 他セクションを壊さないよう既存を読んでから書く。
	cfg.load(resolved_path())
	cfg.set_value(SECTION, "distance", distance)
	cfg.set_value(SECTION, "yaw_degrees", yaw_degrees)
	cfg.set_value(SECTION, "pitch_degrees", pitch_degrees)
	cfg.set_value(SECTION, "pan_x", pan_offset.x)
	cfg.set_value(SECTION, "pan_y", pan_offset.y)
	cfg.set_value(SECTION, "pan_z", pan_offset.z)
	cfg.save(resolved_path())


func clear_saved_view() -> void:
	## 保存を消して OrbitCamera の既定構図に戻す。
	distance = UNSET_DISTANCE
	var cfg := ConfigFile.new()
	if cfg.load(resolved_path()) != OK:
		return
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
		cfg.save(resolved_path())


func capture_from(camera: OrbitCamera) -> void:
	if camera == null:
		return
	distance = camera.distance
	yaw_degrees = camera.yaw_degrees
	pitch_degrees = camera.pitch_degrees
	pan_offset = camera.pan_offset


func apply_to(camera: OrbitCamera) -> void:
	## 未保存なら何もしない(OrbitCamera の既定構図をそのまま使う)。
	if camera == null or not has_saved_view():
		return
	camera.set_orbit(yaw_degrees, pitch_degrees)
	camera.set_pan(pan_offset)
	camera.set_distance(distance)
