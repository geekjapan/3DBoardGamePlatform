class_name BoardView
extends Node3D

## 3D 盤と駒の見た目。配置の唯一のソースは渡された Board(二重に持たない)。
## タイルはコード生成(シーンファイルは作らない)。

const LIGHT_COLOR := Color(0.91, 0.82, 0.65)
const DARK_COLOR := Color(0.48, 0.32, 0.20)
const TILE_HEIGHT := 0.12
const SELECT_COLOR := Color(0.95, 0.85, 0.2, 0.55)
const TARGET_COLOR := Color(0.25, 0.75, 0.35, 0.5)
const CHECK_COLOR := Color(0.9, 0.2, 0.15, 0.55)
const HIGHLIGHT_Y := 0.02

var square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE

var _tiles_root: Node3D
var _pieces_root: Node3D
var _highlights_root: Node3D
## Vector2i -> PieceNode
var _piece_nodes: Dictionary = {}
## Vector2i -> MeshInstance3D (ハイライト)
var _highlight_nodes: Dictionary = {}
var _board: Board


func _init() -> void:
	name = "BoardView"
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)
	_highlights_root = Node3D.new()
	_highlights_root.name = "Highlights"
	add_child(_highlights_root)
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)


func board() -> Board:
	return _board


func piece_count() -> int:
	return _piece_nodes.size()


func piece_node_at(pos: Vector2i) -> PieceNode:
	if not _piece_nodes.has(pos):
		return null
	return _piece_nodes[pos] as PieceNode


func highlight_count() -> int:
	return _highlight_nodes.size()


func has_highlight_at(pos: Vector2i) -> bool:
	return _highlight_nodes.has(pos)


func build_from(board: Board) -> void:
	## 盤を与えてタイルと駒を構築する。以降の配置はこの board に従う。
	_board = board
	_rebuild_tiles()
	sync_pieces()
	clear_highlights()


func apply_board(board: Board) -> void:
	## 対局中の盤更新。タイルは作り直さず駒だけ同期する。
	_board = board
	sync_pieces()


func sync_pieces() -> void:
	## 現在の Board 状態に合わせて駒ノードを作り直す。
	assert(_board != null, "build_from を先に呼ぶ")
	_clear_pieces()
	for y in range(_board.height):
		for x in range(_board.width):
			var pos := Vector2i(x, y)
			var piece := _board.piece_at(pos)
			if piece == null:
				continue
			var node := PieceNode.new(piece.side, piece.kind, pos)
			node.name = "Piece_%d_%d" % [x, y]
			node.position = BoardLayout.square_to_world(pos, square_size)
			node.set_model(PlaceholderVisual.create(piece.side, piece.kind))
			_pieces_root.add_child(node)
			_piece_nodes[pos] = node


func set_highlights(selected: Vector2i, targets: Array, check_square: Vector2i = BoardLayout.INVALID_SQUARE) -> void:
	clear_highlights()
	if selected != BoardLayout.INVALID_SQUARE:
		_add_highlight(selected, SELECT_COLOR)
	for t in targets:
		var pos: Vector2i = t
		if pos == selected:
			continue
		_add_highlight(pos, TARGET_COLOR)
	if check_square != BoardLayout.INVALID_SQUARE:
		if not _highlight_nodes.has(check_square):
			_add_highlight(check_square, CHECK_COLOR)
		else:
			# 選択/移動先と重なる場合は王手色を優先
			_highlight_nodes[check_square].material_override.albedo_color = CHECK_COLOR


func clear_highlights() -> void:
	_highlight_nodes.clear()
	while _highlights_root.get_child_count() > 0:
		var child: Node = _highlights_root.get_child(0)
		_highlights_root.remove_child(child)
		child.free()


func _add_highlight(pos: Vector2i, color: Color) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "HL_%d_%d" % [pos.x, pos.y]
	var box := BoxMesh.new()
	box.size = Vector3(square_size * 0.92, 0.03, square_size * 0.92)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	var world := BoardLayout.square_to_world(pos, square_size)
	mesh_inst.position = Vector3(world.x, HIGHLIGHT_Y, world.z)
	_highlights_root.add_child(mesh_inst)
	_highlight_nodes[pos] = mesh_inst


func _rebuild_tiles() -> void:
	while _tiles_root.get_child_count() > 0:
		var child: Node = _tiles_root.get_child(0)
		_tiles_root.remove_child(child)
		child.free()

	var width := _board.width if _board != null else 8
	var height := _board.height if _board != null else 8
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			var tile := MeshInstance3D.new()
			tile.name = "Tile_%d_%d" % [x, y]
			var box := BoxMesh.new()
			box.size = Vector3(square_size * 0.98, TILE_HEIGHT, square_size * 0.98)
			tile.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = LIGHT_COLOR if BoardLayout.is_light_square(pos) else DARK_COLOR
			mat.roughness = 0.85
			tile.material_override = mat
			var world := BoardLayout.square_to_world(pos, square_size)
			tile.position = Vector3(world.x, -TILE_HEIGHT * 0.5, world.z)
			_tiles_root.add_child(tile)


func _clear_pieces() -> void:
	_piece_nodes.clear()
	while _pieces_root.get_child_count() > 0:
		var child: Node = _pieces_root.get_child(0)
		_pieces_root.remove_child(child)
		child.free()
