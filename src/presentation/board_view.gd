class_name BoardView
extends Node3D

## 3D 盤と駒の見た目。配置の唯一のソースは渡された Board(二重に持たない)。
## タイルはコード生成(シーンファイルは作らない)。
## 着手のたびに駒ノードを全破棄せず、移動は同一インスタンスを再利用する。

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


func all_piece_nodes() -> Array:
	## テスト用。現在の駒ノード一覧(順序不定)。
	var out: Array = []
	for pos in _piece_nodes:
		out.append(_piece_nodes[pos])
	return out


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
	## 現在の Board に合わせて駒ノードを同期する。
	## 同じ side+kind のノードは可能な限り再利用し、移動した駒は作り直さない。
	## 取られた駒だけ free し、成りはノードを保ったまま見た目を差し替える。
	assert(_board != null, "build_from を先に呼ぶ")

	var desired: Dictionary = {}  # Vector2i -> Piece
	for y in range(_board.height):
		for x in range(_board.width):
			var pos := Vector2i(x, y)
			var piece := _board.piece_at(pos)
			if piece != null:
				desired[pos] = piece

	var free_nodes: Array = []
	for pos in _piece_nodes:
		free_nodes.append(_piece_nodes[pos])

	var next_map: Dictionary = {}  # Vector2i -> PieceNode
	var unmatched: Array = []  # Vector2i

	# Pass 1: 同じマス・同じ side・同じ kind はそのまま残す。
	for pos in desired:
		var piece: Piece = desired[pos]
		var kept: PieceNode = null
		for i in free_nodes.size():
			var node: PieceNode = free_nodes[i]
			if node.board_pos == pos and node.piece_side == piece.side and node.piece_kind == piece.kind:
				kept = node
				free_nodes.remove_at(i)
				break
		if kept != null:
			_place_node(kept, pos, piece, false)
			next_map[pos] = kept
		else:
			unmatched.append(pos)

	# Pass 2: 移動 — 同じ side+kind の空きノードを割り当てる(空いた元マスを優先)。
	for pos in unmatched.duplicate():
		var piece: Piece = desired[pos]
		var idx := _find_free_node(free_nodes, piece.side, piece.kind, true)
		if idx < 0:
			continue
		var node: PieceNode = free_nodes[idx]
		free_nodes.remove_at(idx)
		_place_node(node, pos, piece, false)
		next_map[pos] = node
		unmatched.erase(pos)

	# Pass 3: 成り — 同 side のポーンノードを非ポーンへ昇格させる。
	for pos in unmatched.duplicate():
		var piece: Piece = desired[pos]
		if piece.kind == Piece.Kind.PAWN:
			continue
		var idx := _find_free_node(free_nodes, piece.side, Piece.Kind.PAWN, true)
		if idx < 0:
			continue
		var node: PieceNode = free_nodes[idx]
		free_nodes.remove_at(idx)
		_place_node(node, pos, piece, true)
		next_map[pos] = node
		unmatched.erase(pos)

	# Pass 4: まだ足りない分は新規作成(初期配置・テスト構築)。
	for pos in unmatched:
		var piece: Piece = desired[pos]
		var node := PieceNode.new(piece.side, piece.kind, pos)
		node.set_model(PlaceholderVisual.create(piece.side, piece.kind))
		_pieces_root.add_child(node)
		_place_node(node, pos, piece, false)
		next_map[pos] = node

	# Pass 5: 余ったノードは取られた駒(または盤から消えた駒)なので破棄。
	for node in free_nodes:
		var n: PieceNode = node
		if n.get_parent() == _pieces_root:
			_pieces_root.remove_child(n)
		n.free()

	_piece_nodes = next_map


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


func _find_free_node(free_nodes: Array, side: int, kind: int, prefer_vacated: bool) -> int:
	## free_nodes から side+kind 一致を探す。prefer_vacated なら元マスが新盤で空のものを優先。
	var fallback := -1
	for i in free_nodes.size():
		var node: PieceNode = free_nodes[i]
		if node.piece_side != side or node.piece_kind != kind:
			continue
		if not prefer_vacated:
			return i
		# 元マスに今も別駒があるなら「動かなかった別人」の可能性が高いので後回し。
		if not _piece_nodes.has(node.board_pos) or _board.piece_at(node.board_pos) == null:
			return i
		if fallback < 0:
			fallback = i
	return fallback


func _place_node(node: PieceNode, pos: Vector2i, piece: Piece, appearance_changed: bool) -> void:
	node.board_pos = pos
	node.piece_side = piece.side
	var kind_changed := node.piece_kind != piece.kind
	node.piece_kind = piece.kind
	node.name = "Piece_%d_%d" % [pos.x, pos.y]
	node.position = BoardLayout.square_to_world(pos, square_size)
	if appearance_changed or kind_changed:
		node.set_model(PlaceholderVisual.create(piece.side, piece.kind))


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
