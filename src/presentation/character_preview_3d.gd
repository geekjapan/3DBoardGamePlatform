class_name CharacterPreview3D
extends SubViewportContainer

## 編成画面用の 3D プレビュー。
## キャラクター固有モデルが無い段階では、駒種プレースホルダをキャラ色で見せる。

const EMPTY_COLOR := Color(0.45, 0.48, 0.52)

var _viewport: SubViewport
var _world_root: Node3D
var _model_host: Node3D
var _camera: Camera3D
var _kind: int = Piece.Kind.PAWN
var _character_id: String = ""
var _spin: float = 0.0


func _init() -> void:
	name = "CharacterPreview3D"
	stretch = true
	custom_minimum_size = Vector2(220, 220)

	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(220, 220)
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "World"
	_viewport.add_child(_world_root)

	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_energy = 1.2
	_world_root.add_child(light)

	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(-1.2, 1.5, 1.0)
	fill.light_energy = 0.35
	_world_root.add_child(fill)

	_model_host = Node3D.new()
	_model_host.name = "ModelHost"
	_world_root.add_child(_model_host)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	# ツリー外でも安全な向き設定(look_at は inside tree 必須)。
	_camera.look_at_from_position(Vector3(0.9, 0.85, 1.35), Vector3(0, 0.35, 0), Vector3.UP)
	_world_root.add_child(_camera)

	set_process(true)
	_rebuild()


func _process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
		return
	_spin += delta * 0.7
	if _model_host != null:
		_model_host.rotation.y = _spin


func set_preview(kind: int, character_id: String) -> void:
	var next_kind := kind
	var next_id := character_id.strip_edges()
	if next_kind == _kind and next_id == _character_id:
		return
	_kind = next_kind
	_character_id = next_id
	_rebuild()


func current_kind() -> int:
	return _kind


func current_character_id() -> String:
	return _character_id


func _rebuild() -> void:
	if _model_host == null:
		return
	while _model_host.get_child_count() > 0:
		var child: Node = _model_host.get_child(0)
		_model_host.remove_child(child)
		child.free()

	# 陣営は見た目差のための便宜上 WHITE。色はキャラクター由来。
	var visual := PlaceholderVisual.create(Piece.Side.WHITE, _kind)
	_tint_visual(visual, _color_for_character(_character_id))
	_model_host.add_child(visual)


static func _color_for_character(character_id: String) -> Color:
	match character_id:
		"":
			return EMPTY_COLOR
		"hotblood":
			return Color(0.92, 0.38, 0.28)
		"calm":
			return Color(0.38, 0.58, 0.88)
		"tsundere":
			return Color(0.88, 0.48, 0.72)
		_:
			# 未知 ID も安定色になるようハッシュ。
			var h := float(absi(character_id.hash()) % 360) / 360.0
			return Color.from_hsv(h, 0.55, 0.85)


static func _tint_visual(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
		else:
			mat = mat.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		mat.roughness = 0.5
		mi.material_override = mat
	for child in root.get_children():
		_tint_visual(child, color)
