class_name PlaceholderVisual
extends RefCounted

## 仮の駒見た目。駒種ごとに形が違い、陣営で色が違う。
## 後から VRM / glTF に差し替えるまでのプレースホルダ(ADR 0002 の「素の glTF も装着可」と同系)。

const META_SIDE := &"piece_side"
const META_KIND := &"piece_kind"

const _WHITE_COLOR := Color(0.93, 0.91, 0.86)
const _BLACK_COLOR := Color(0.18, 0.16, 0.15)


static func create(side: int, kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder_%s_%s" % [_side_name(side), _kind_name(kind)]
	root.set_meta(META_SIDE, side)
	root.set_meta(META_KIND, kind)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _mesh_for_kind(kind)
	mesh_inst.position = _offset_for_kind(kind)
	mesh_inst.material_override = _material_for_side(side)
	root.add_child(mesh_inst)
	return root


static func _material_for_side(side: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _WHITE_COLOR if side == Piece.Side.WHITE else _BLACK_COLOR
	mat.roughness = 0.55
	mat.metallic = 0.05
	return mat


static func _mesh_for_kind(kind: int) -> Mesh:
	match kind:
		Piece.Kind.PAWN:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.16
			cyl.bottom_radius = 0.22
			cyl.height = 0.45
			cyl.radial_segments = 12
			return cyl
		Piece.Kind.KNIGHT:
			var box := BoxMesh.new()
			box.size = Vector3(0.32, 0.55, 0.42)
			return box
		Piece.Kind.BISHOP:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.22
			cone.height = 0.7
			cone.radial_segments = 12
			return cone
		Piece.Kind.ROOK:
			var rook := BoxMesh.new()
			rook.size = Vector3(0.38, 0.55, 0.38)
			return rook
		Piece.Kind.QUEEN:
			var sphere := SphereMesh.new()
			sphere.radius = 0.26
			sphere.height = 0.52
			sphere.radial_segments = 12
			sphere.rings = 8
			return sphere
		Piece.Kind.KING:
			var king := CylinderMesh.new()
			king.top_radius = 0.18
			king.bottom_radius = 0.24
			king.height = 0.85
			king.radial_segments = 12
			return king
		_:
			var fallback := BoxMesh.new()
			fallback.size = Vector3(0.3, 0.3, 0.3)
			return fallback


static func _offset_for_kind(kind: int) -> Vector3:
	## メッシュ中心をマス面の少し上に置く。
	match kind:
		Piece.Kind.PAWN:
			return Vector3(0, 0.225, 0)
		Piece.Kind.KNIGHT:
			return Vector3(0, 0.275, 0)
		Piece.Kind.BISHOP:
			return Vector3(0, 0.35, 0)
		Piece.Kind.ROOK:
			return Vector3(0, 0.275, 0)
		Piece.Kind.QUEEN:
			return Vector3(0, 0.26, 0)
		Piece.Kind.KING:
			return Vector3(0, 0.425, 0)
		_:
			return Vector3(0, 0.15, 0)


static func _side_name(side: int) -> String:
	return "white" if side == Piece.Side.WHITE else "black"


static func _kind_name(kind: int) -> String:
	match kind:
		Piece.Kind.PAWN:
			return "pawn"
		Piece.Kind.KNIGHT:
			return "knight"
		Piece.Kind.BISHOP:
			return "bishop"
		Piece.Kind.ROOK:
			return "rook"
		Piece.Kind.QUEEN:
			return "queen"
		Piece.Kind.KING:
			return "king"
		_:
			return "unknown"
