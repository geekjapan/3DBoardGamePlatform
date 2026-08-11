class_name PlaceholderVisual
extends RefCounted

## 外部アセットなしで駒種を形状識別できる仮の3D見た目。
## チェスの既存形状を維持し、将棋は共通台座と駒種別プリミティブを合成する。

const META_SIDE := &"piece_side"
const META_KIND := &"piece_kind"
const PROMOTION_MARKER_NAME := &"PromotionMarker"

const _WHITE_COLOR := Color(0.93, 0.91, 0.86)
const _BLACK_COLOR := Color(0.18, 0.16, 0.15)


static func create(side: int, kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder_%s_%s" % [_side_name(side), _kind_name(kind)]
	root.set_meta(META_SIDE, side)
	root.set_meta(META_KIND, kind)

	if kind >= Piece.Kind.PAWN and kind <= Piece.Kind.KING:
		_add_chess_shape(root, side, kind)
		return root

	var base_kind := Piece.base_kind_for_promoted(kind)
	var shape_kind := base_kind if base_kind >= 0 else kind
	if shape_kind >= Piece.Kind.SHOGI_PAWN and shape_kind <= Piece.Kind.SHOGI_KING:
		_add_shogi_shape(root, side, shape_kind)
		if base_kind >= 0:
			_add_promotion_marker(root, side)
	else:
		_add_box(root, "Unknown", Vector3(0.0, 0.15, 0.0), Vector3(0.3, 0.3, 0.3), side)
	return root


static func _add_chess_shape(root: Node3D, side: int, kind: int) -> void:
	## 既存チェスplaceholderの形状と寸法をそのまま保つ。
	match kind:
		Piece.Kind.PAWN:
			_add_cylinder(root, "Pawn", Vector3(0.0, 0.225, 0.0), 0.16, 0.22, 0.45, side)
		Piece.Kind.KNIGHT:
			_add_box(root, "Knight", Vector3(0.0, 0.275, 0.0), Vector3(0.32, 0.55, 0.42), side)
		Piece.Kind.BISHOP:
			_add_cylinder(root, "Bishop", Vector3(0.0, 0.35, 0.0), 0.02, 0.22, 0.7, side)
		Piece.Kind.ROOK:
			_add_box(root, "Rook", Vector3(0.0, 0.275, 0.0), Vector3(0.38, 0.55, 0.38), side)
		Piece.Kind.QUEEN:
			_add_sphere(root, "Queen", Vector3(0.0, 0.26, 0.0), 0.26, side)
		Piece.Kind.KING:
			_add_cylinder(root, "King", Vector3(0.0, 0.425, 0.0), 0.18, 0.24, 0.85, side)


static func _add_shogi_shape(root: Node3D, side: int, kind: int) -> void:
	_add_box(root, "ShogiBase", Vector3(0.0, 0.12, 0.0), Vector3(0.52, 0.24, 0.64), side)
	match kind:
		Piece.Kind.SHOGI_PAWN:
			_add_sphere(root, "PawnOrb", Vector3(0.0, 0.39, 0.02), 0.12, side)
		Piece.Kind.SHOGI_LANCE:
			_add_cylinder(root, "LanceTower", Vector3(0.0, 0.44, 0.0), 0.025, 0.11, 0.40, side)
		Piece.Kind.SHOGI_KNIGHT:
			_add_box(
				root,
				"KnightNeck",
				Vector3(0.0, 0.42, 0.04),
				Vector3(0.15, 0.32, 0.18),
				side,
				Vector3(20.0, 0.0, 0.0),
			)
			_add_sphere(root, "KnightHead", Vector3(0.0, 0.59, -0.02), 0.095, side)
		Piece.Kind.SHOGI_SILVER:
			_add_cylinder(root, "SilverBell", Vector3(0.0, 0.42, 0.0), 0.065, 0.17, 0.28, side)
			_add_sphere(root, "SilverCap", Vector3(0.0, 0.58, 0.0), 0.07, side)
		Piece.Kind.SHOGI_GOLD:
			_add_sphere(root, "GoldCenter", Vector3(0.0, 0.40, 0.0), 0.145, side)
			_add_sphere(root, "GoldLeft", Vector3(-0.17, 0.38, 0.0), 0.07, side)
			_add_sphere(root, "GoldRight", Vector3(0.17, 0.38, 0.0), 0.07, side)
		Piece.Kind.SHOGI_BISHOP:
			_add_box(
				root,
				"BishopDiagonal",
				Vector3(0.0, 0.41, 0.0),
				Vector3(0.11, 0.38, 0.11),
				side,
				Vector3(0.0, 0.0, -43.0),
			)
		Piece.Kind.SHOGI_ROOK:
			for x in [-0.17, 0.17]:
				for z in [-0.16, 0.16]:
					_add_box(root, "RookPost", Vector3(x, 0.41, z), Vector3(0.10, 0.32, 0.10), side)
		Piece.Kind.SHOGI_KING:
			_add_box(root, "KingStem", Vector3(0.0, 0.43, 0.0), Vector3(0.10, 0.40, 0.10), side)
			_add_box(root, "KingCrossbar", Vector3(0.0, 0.47, 0.0), Vector3(0.36, 0.10, 0.10), side)


static func _add_promotion_marker(root: Node3D, side: int) -> void:
	## 全成駒で共通の、三軸に厚みを持つ立体マーカー。
	_add_sphere(root, str(PROMOTION_MARKER_NAME), Vector3(0.0, 0.73, 0.21), 0.075, side)


static func _add_box(
	root: Node3D,
	part_name: String,
	position: Vector3,
	size: Vector3,
	side: int,
	rotation_degrees: Vector3 = Vector3.ZERO,
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(root, part_name, mesh, position, side, rotation_degrees)


static func _add_sphere(root: Node3D, part_name: String, position: Vector3, radius: float, side: int) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	_add_mesh(root, part_name, mesh, position, side)


static func _add_cylinder(
	root: Node3D,
	part_name: String,
	position: Vector3,
	top_radius: float,
	bottom_radius: float,
	height: float,
	side: int,
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	_add_mesh(root, part_name, mesh, position, side)


static func _add_mesh(
	root: Node3D,
	part_name: String,
	mesh: Mesh,
	position: Vector3,
	side: int,
	rotation_degrees: Vector3 = Vector3.ZERO,
) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.material_override = _material_for_side(side)
	root.add_child(instance)


static func _material_for_side(side: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _WHITE_COLOR if side == Piece.Side.WHITE else _BLACK_COLOR
	material.roughness = 0.55
	material.metallic = 0.05
	return material


static func _side_name(side: int) -> String:
	return "white" if side == Piece.Side.WHITE else "black"


static func _kind_name(kind: int) -> String:
	var stable_name := SpeechCatalog.kind_name(kind)
	return stable_name if stable_name != "" else "unknown"
