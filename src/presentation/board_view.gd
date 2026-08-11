class_name BoardView
extends Node3D

## 3D 盤と駒の見た目。配置の唯一のソースは渡された Board(二重に持たない)。
## タイルはコード生成(シーンファイルは作らない)。

const LIGHT_COLOR := Color(0.91, 0.82, 0.65)
const DARK_COLOR := Color(0.48, 0.32, 0.20)
const TILE_HEIGHT := 0.12

var square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE

var _tiles_root: Node3D
var _pieces_root: Node3D
## Vector2i -> PieceNode
var _piece_nodes: Dictionary = {}
var _board: Board


func _init() -> void:
	name = "BoardView"
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)
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


func build_from(board: Board) -> void:
	## 盤を与えてタイルと駒を構築する。以降の配置はこの board に従う。
	_board = board
	_rebuild_tiles()
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
