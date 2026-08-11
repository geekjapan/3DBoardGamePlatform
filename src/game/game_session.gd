class_name GameSession
extends RefCounted

## 2 人対局の操作状態。Board(ルール)の上に選択・着手・待った・終局を載せる。
## 見た目や入力デバイスは持たない(presentation がこの API を叩く)。
## 着手のたびに MoveEvent を発行し、選択経由 / 直接適用のどちらでも同じ内容を観測できる。

const NO_SQUARE := Vector2i(-1, -1)

## 待ったは「1 往復」= 2 プライ(自分の手 + 相手の応手)。
const UNDO_PLIES := 2


const _BOARD_METHODS := [
	"legal_moves",
	"apply",
	"piece_at",
	"in_check",
	"is_checkmate",
	"is_stalemate",
]


var _board: Object
## 着手前の盤を積む。undo で 2 枚戻す。
var _history: Array = []
var _selected: Vector2i = NO_SQUARE
## 選択中の持ち駒Kind。盤上選択とは排他的で、未選択は -1。
var _selected_drop_kind: int = -1
## selected 中の合法手キャッシュ。select / 盤更新で張り直す。
var _legal_from_selected: Array = []
## 直近の成功した着手。失敗や未着手では null。
var _last_move_event: MoveEvent = null


static func start() -> GameSession:
	return from_board(Board.chess_start())


static func from_board(board: Object) -> GameSession:
	var validated := _validated_board(board)
	if validated == null:
		return null
	var s := GameSession.new()
	s._board = validated
	return s


func board() -> Object:
	## 実体は生成時と apply 後に検証済みの盤 Object。
	return _board


func side_to_move() -> int:
	return _board.side_to_move


func selected_square() -> Vector2i:
	return _selected


func selected_drop_kind() -> int:
	return _selected_drop_kind


func is_selected() -> bool:
	return _selected != NO_SQUARE or _selected_drop_kind >= 0


func legal_targets() -> Array:
	## Vector2i の配列(重複なし)。
	var out: Array = []
	var seen := {}
	for m in _legal_from_selected:
		var to: Vector2i = (m as Move).to
		if not seen.has(to):
			seen[to] = true
			out.append(to)
	return out


func legal_moves_to(to: Vector2i) -> Array:
	## 選択中の from から同じ to へ行く完全 Move をすべて返す。
	var out: Array = []
	for candidate in _legal_from_selected:
		var move := candidate as Move
		if move.to == to:
			out.append(move)
	return out


func legal_drop_kinds() -> Array:
	## 現在手番で1マス以上へ打てる持ち駒Kind(重複なし)。
	var out: Array = []
	for candidate in _board.legal_moves():
		var move := candidate as Move
		if move.is_drop and not out.has(move.drop_kind):
			out.append(move.drop_kind)
	return out


func in_check() -> bool:
	return _board.in_check()


func is_checkmate() -> bool:
	return _board.is_checkmate()


func is_stalemate() -> bool:
	return _board.is_stalemate()


func is_over() -> bool:
	return is_checkmate() or is_stalemate()


func result_text() -> String:
	if is_checkmate():
		var is_shogi := _board is ShogiBoard
		var winner := "後手" if side_to_move() == Piece.Side.WHITE else "先手"
		if not is_shogi:
			winner = "黒" if side_to_move() == Piece.Side.WHITE else "白"
		var reason := "詰み" if is_shogi else "チェックメイト"
		return "%sの勝ち (%s)" % [winner, reason]
	if is_stalemate():
		return "引き分け (ステイルメイト)"
	return ""


func last_move_event() -> MoveEvent:
	## 直近の成功した着手。選択失敗や非合法手では更新されない。
	return _last_move_event


func select(pos: Vector2i) -> bool:
	if is_over():
		return false
	var piece: Piece = _board.piece_at(pos)
	if piece == null or piece.side != _board.side_to_move:
		return false
	_selected_drop_kind = -1
	_selected = pos
	_cache_legal_from_selected()
	return true


func select_drop(kind: int) -> bool:
	## 現在の合法手に存在する完全な打つ手だけを選択キャッシュへ保持する。
	if is_over():
		return false
	var candidates: Array = []
	for candidate in _board.legal_moves():
		var move := candidate as Move
		if move.is_drop and move.drop_kind == kind:
			candidates.append(move)
	if candidates.is_empty():
		return false
	_selected = NO_SQUARE
	_selected_drop_kind = kind
	_legal_from_selected = candidates
	return true


func deselect() -> void:
	_selected = NO_SQUARE
	_selected_drop_kind = -1
	_legal_from_selected.clear()


func try_move_to(pos: Vector2i) -> bool:
	if is_over() or not is_selected():
		return false
	var candidates := legal_moves_to(pos)
	if candidates.size() != 1:
		return false
	return _commit_move(candidates[0] as Move) != null


func apply_move(move: Move) -> MoveEvent:
	## 選択を経由せず合法手を直接適用する。非合法・終局後は null を返し盤を変えない。
	## AI 対戦など、クリック以外の入口から同じ MoveEvent を観測するための API。
	if is_over() or move == null:
		return null
	var legal := _find_matching_legal(move)
	if legal == null:
		return null
	return _commit_move(legal)


func click(pos: Vector2i) -> void:
	## UI 用の一括ハンドラ。選択 → 移動 / 再選択 / 解除。
	if is_over():
		return
	if not is_selected():
		select(pos)
		return
	if pos == _selected:
		deselect()
		return
	if try_move_to(pos):
		return
	var piece: Piece = _board.piece_at(pos)
	if piece != null and piece.side == _board.side_to_move:
		select(pos)
		return
	deselect()


func can_undo() -> bool:
	return _history.size() >= UNDO_PLIES


func undo() -> bool:
	if not can_undo():
		return false
	# 1 往復 = 直近 2 プライを捨て、その手前の盤へ。
	_history.pop_back()
	_board = _history.pop_back() as Object
	deselect()
	_last_move_event = null
	return true


func _commit_move(move: Move) -> MoveEvent:
	var event := _build_move_event(move)
	var next_board: Variant = _board.apply(move)
	var validated_next := _validated_board(next_board)
	if validated_next == null:
		return null
	_history.append(_board)
	_board = validated_next
	event.is_check = _board.in_check()
	event.is_checkmate = _board.is_checkmate()
	event.is_stalemate = _board.is_stalemate()
	event.is_over = event.is_checkmate or event.is_stalemate
	event.result_text = result_text()
	_last_move_event = event
	deselect()
	return event


func _build_move_event(move: Move) -> MoveEvent:
	## 着手前の盤から、移動・取り・成りの事実を拾う。
	var event := MoveEvent.new()
	event.move = move
	if move.is_drop:
		event.mover_side = _board.side_to_move
		event.mover_kind = move.drop_kind
		return event
	var mover: Piece = _board.piece_at(move.from)
	assert(mover != null, "合法手なのに from に駒が無い")
	event.mover_side = mover.side
	event.mover_kind = mover.kind
	if move.is_en_passant:
		var cap_pos := Vector2i(move.to.x, move.from.y)
		var cap: Piece = _board.piece_at(cap_pos)
		if cap != null:
			event.captured = cap.duplicate_piece()
			event.captured_square = cap_pos
	else:
		var cap2: Piece = _board.piece_at(move.to)
		if cap2 != null:
			event.captured = cap2.duplicate_piece()
			event.captured_square = move.to
	return event


func _cache_legal_from_selected() -> void:
	_legal_from_selected.clear()
	if _selected == NO_SQUARE:
		return
	for m in _board.legal_moves():
		var move := m as Move
		if move.from == _selected:
			_legal_from_selected.append(move)


func _find_matching_legal(want: Move) -> Move:
	## 特殊チェス旗は既存互換のため補完するが、打つ手の種別とKindは完全一致させる。
	for m in _board.legal_moves():
		var move := m as Move
		if (
			move.from == want.from
			and move.to == want.to
			and move.promotion == want.promotion
			and move.is_drop == want.is_drop
			and move.drop_kind == want.drop_kind
		):
			return move
	return null


static func _validated_board(value: Variant) -> Object:
	if value == null:
		assert(false, "GameSession board must not be null")
		return null
	if not value is Object:
		assert(false, "GameSession board must be an Object")
		return null
	var board := value as Object
	for method_name in _BOARD_METHODS:
		if not board.has_method(method_name):
			assert(false, "GameSession board missing method: %s" % method_name)
			return null
	var has_side_to_move := false
	for property in board.get_property_list():
		if property["name"] == "side_to_move":
			has_side_to_move = true
			break
	if not has_side_to_move:
		assert(false, "GameSession board missing property: side_to_move")
		return null
	return board
