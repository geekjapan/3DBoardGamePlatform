class_name BoardView
extends Node3D

## 3D 盤と駒の見た目。配置の唯一のソースは渡された Board(二重に持たない)。
## タイルはコード生成(シーンファイルは作らない)。
## 着手のたびに駒ノードを全破棄せず、移動は同一インスタンスを再利用する。
## 移動・駒取りは tween 演出。待機は PieceNode 側。操作中断でも論理盤に再同期する。

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
## 取られ演出中で盤マップからは外れているノード。
var _capturing_nodes: Array = []
## 次の sync で演出するか。build_from は false、apply_board は true。
var _animate_next_sync: bool = false


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


## 駒の見た目を作る差し替え口。(side: int, kind: int) -> Node3D を返す。
## 未設定なら仮の見た目。presentation が Character や Team を知らずに済むよう、
## キャラクターモデルの解決は呼び出し側(main.gd)が Callable で差し込む。
var visual_factory: Callable = Callable()


func board() -> Board:
	return _board


func _apply_visual(node: PieceNode, piece: Piece) -> void:
	var visual: Node3D = null
	if visual_factory.is_valid():
		visual = visual_factory.call(piece.side, piece.kind) as Node3D
	if visual == null:
		visual = PlaceholderVisual.create(piece.side, piece.kind)
	node.set_model(visual)
	if visual.has_meta(CharacterModel.META_NEEDS_FIT):
		CharacterModel.fit_to_square(visual, square_size)
		# 盤は白側(rank 0)が +Z。白は -Z を、黒は +Z を向けば向かい合う。
		# モデルの素の向きは規約(-Z)を信じず実測する。MMD から変換したものは
		# +Z を向いたままで、決め打ちにすると全員が盤の外を向く。
		var wants_plus_z := piece.side == Piece.Side.BLACK
		var model_faces_plus_z := CharacterAnimator.faces_plus_z(visual)
		visual.rotation.y = 0.0 if wants_plus_z == model_faces_plus_z else PI


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


func is_animating() -> bool:
	## 移動中または取られ演出中の駒があるか。
	for pos in _piece_nodes:
		var node: PieceNode = _piece_nodes[pos]
		if node.is_animating():
			return true
	if not _capturing_nodes.is_empty():
		return true
	return false


func finish_animations() -> void:
	## 進行中の演出をすべて打ち切る。再操作・テストの確定同期用。
	for pos in _piece_nodes:
		var node: PieceNode = _piece_nodes[pos]
		if node.is_animating():
			node.finish_animations_now()
	_force_finish_captures()


func build_from(board: Board) -> void:
	## 盤を与えてタイルと駒を構築する。以降の配置はこの board に従う。
	_force_finish_captures()
	_board = board
	_animate_next_sync = false
	_rebuild_tiles()
	sync_pieces()
	clear_highlights()


func apply_board(board: Board) -> void:
	## 対局中の盤更新。タイルは作り直さず駒だけ同期する。移動・取りを演出する。
	## 演出中の再呼び出しでも中断して新しい盤へ安全に合わせる。
	_interrupt_for_resync()
	_board = board
	_animate_next_sync = is_inside_tree()
	sync_pieces()


func apply_move_event(board: Board, _event: MoveEvent) -> void:
	## MoveEvent を観測して演出する入口。現状は apply_board と同じ経路
	## (同一性マッチで移動・取りを判定)。将来イベント固有の順序付け用に残す。
	apply_board(board)


func sync_pieces() -> void:
	## 現在の Board に合わせて駒ノードを同期する。
	## 同じ side+kind のノードは可能な限り再利用し、移動した駒は作り直さない。
	## 取られた駒は演出後に free し、成りはノードを保ったまま見た目を差し替える。
	assert(_board != null, "build_from を先に呼ぶ")

	var animate := _animate_next_sync
	_animate_next_sync = false

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
			_place_node(kept, pos, piece, false, false)
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
		_place_node(node, pos, piece, false, animate)
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
		_place_node(node, pos, piece, true, animate)
		next_map[pos] = node
		unmatched.erase(pos)

	# Pass 4: まだ足りない分は新規作成(初期配置・テスト構築)。
	for pos in unmatched:
		var piece: Piece = desired[pos]
		var node := PieceNode.new(piece.side, piece.kind, pos)
		# 実寸合わせは AABB をワールドで測るため、ツリーに入れてから見た目を付ける。
		_pieces_root.add_child(node)
		_apply_visual(node, piece)
		_place_node(node, pos, piece, false, false)
		next_map[pos] = node

	# Pass 5: 余ったノードは取られた駒(または盤から消えた駒)。
	for node in free_nodes:
		var n: PieceNode = node
		if animate and is_inside_tree():
			_start_capture(n)
		else:
			_free_piece_node(n)

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


func _interrupt_for_resync() -> void:
	## 演出中の再同期前に、移動を着地させ取り演出中ノードを片付ける。
	for pos in _piece_nodes:
		var node: PieceNode = _piece_nodes[pos]
		if node.anim_state() == PieceNode.AnimState.MOVING:
			node.finish_animations_now()
	_force_finish_captures()


func _force_finish_captures() -> void:
	for node in _capturing_nodes.duplicate():
		var n: PieceNode = node
		if is_instance_valid(n):
			n.finish_animations_now()
			_free_piece_node(n)
	_capturing_nodes.clear()


func _start_capture(node: PieceNode) -> void:
	if node.get_parent() != _pieces_root and node.get_parent() != null:
		node.get_parent().remove_child(node)
		_pieces_root.add_child(node)
	if not _capturing_nodes.has(node):
		_capturing_nodes.append(node)
	if not node.capture_finished.is_connected(_on_capture_finished.bind(node)):
		node.capture_finished.connect(_on_capture_finished.bind(node), CONNECT_ONE_SHOT)
	node.play_capture()


func _on_capture_finished(node: PieceNode) -> void:
	_capturing_nodes.erase(node)
	if not is_instance_valid(node):
		return
	# ここは node 自身の capture_finished 発火中なので、free() はロックされて失敗する。
	# remove_child で表示は即座に消し、実体の解放だけフレーム末に回す。
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _free_piece_node(node: PieceNode) -> void:
	## 同期経路(盤の突き合わせ)専用。呼び出し元がロック中でないので即時解放でよい。
	if not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


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


func _place_node(
	node: PieceNode,
	pos: Vector2i,
	piece: Piece,
	appearance_changed: bool,
	animate: bool,
) -> void:
	node.board_pos = pos
	node.piece_side = piece.side
	var kind_changed := node.piece_kind != piece.kind
	node.piece_kind = piece.kind
	node.name = "Piece_%d_%d" % [pos.x, pos.y]
	var world := BoardLayout.square_to_world(pos, _board_size(), square_size)
	if appearance_changed or kind_changed:
		_apply_visual(node, piece)
	if animate:
		node.animate_move_to(world)
	else:
		node.snap_to(world)


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
	var world := BoardLayout.square_to_world(pos, _board_size(), square_size)
	mesh_inst.position = Vector3(world.x, HIGHLIGHT_Y, world.z)
	_highlights_root.add_child(mesh_inst)
	_highlight_nodes[pos] = mesh_inst


func _rebuild_tiles() -> void:
	while _tiles_root.get_child_count() > 0:
		var child: Node = _tiles_root.get_child(0)
		_tiles_root.remove_child(child)
		child.free()

	var width := _board.width
	var height := _board.height
	var board_size := Vector2i(width, height)
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
			var world := BoardLayout.square_to_world(pos, board_size, square_size)
			tile.position = Vector3(world.x, -TILE_HEIGHT * 0.5, world.z)
			_tiles_root.add_child(tile)


func _board_size() -> Vector2i:
	assert(_board != null, "build_from を先に呼ぶ")
	return Vector2i(_board.width, _board.height)
