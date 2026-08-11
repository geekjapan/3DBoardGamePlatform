class_name GameSession
extends RefCounted

## 2 人対局の操作状態。Board(ルール)の上に選択・着手・待った・終局を載せる。
## 見た目や入力デバイスは持たない(presentation がこの API を叩く)。
## 着手のたびに MoveEvent を発行し、選択経由 / 直接適用のどちらでも同じ内容を観測できる。

const NO_SQUARE := Vector2i(-1, -1)

## 待ったは「1 往復」= 2 プライ(自分の手 + 相手の応手)。
const UNDO_PLIES := 2


var _board: Board
## 着手前の盤を積む。undo で 2 枚戻す。
var _history: Array = []
var _selected: Vector2i = NO_SQUARE
## selected 中の合法手キャッシュ。select / 盤更新で張り直す。
var _legal_from_selected: Array = []
## 直近の成功した着手。失敗や未着手では null。
var _last_move_event: MoveEvent = null


static func start() -> GameSession:
	return from_board(Board.chess_start())


static func from_board(board: Board) -> GameSession:
	var s := GameSession.new()
	s._board = board
	return s


func board() -> Board:
	return _board


func side_to_move() -> int:
	return _board.side_to_move


func selected_square() -> Vector2i:
	return _selected


func is_selected() -> bool:
	return _selected != NO_SQUARE


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
		var winner := "黒" if side_to_move() == Piece.Side.WHITE else "白"
		return "%sの勝ち (チェックメイト)" % winner
	if is_stalemate():
		return "引き分け (ステイルメイト)"
	return ""


func last_move_event() -> MoveEvent:
	## 直近の成功した着手。選択失敗や非合法手では更新されない。
	return _last_move_event


func select(pos: Vector2i) -> bool:
	if is_over():
		return false
	var piece := _board.piece_at(pos)
	if piece == null or piece.side != _board.side_to_move:
		return false
	_selected = pos
	_cache_legal_from_selected()
	return true


func deselect() -> void:
	_selected = NO_SQUARE
	_legal_from_selected.clear()


func try_move_to(pos: Vector2i) -> bool:
	if is_over() or not is_selected():
		return false
	var move := _find_legal_move(pos)
	if move == null:
		return false
	return _commit_move(move) != null


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
	var piece := _board.piece_at(pos)
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
	_board = _history.pop_back() as Board
	deselect()
	return true


func _commit_move(move: Move) -> MoveEvent:
	var event := _build_move_event(move)
	_history.append(_board)
	_board = _board.apply(move)
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
	var mover := _board.piece_at(move.from)
	assert(mover != null, "合法手なのに from に駒が無い")
	event.mover_side = mover.side
	event.mover_kind = mover.kind
	if move.is_en_passant:
		var cap_pos := Vector2i(move.to.x, move.from.y)
		var cap := _board.piece_at(cap_pos)
		if cap != null:
			event.captured = cap.duplicate_piece()
			event.captured_square = cap_pos
	else:
		var cap2 := _board.piece_at(move.to)
		if cap2 != null:
			event.captured = cap2.duplicate_piece()
			event.captured_square = move.to
	return event


func _cache_legal_from_selected() -> void:
	_legal_from_selected.clear()
	if not is_selected():
		return
	for m in _board.legal_moves():
		var move := m as Move
		if move.from == _selected:
			_legal_from_selected.append(move)


func _find_legal_move(to: Vector2i) -> Move:
	for m in _legal_from_selected:
		var move := m as Move
		if move.to == to:
			return move
	return null


func _find_matching_legal(want: Move) -> Move:
	## from / to / promotion で合法手を探す(UCI 相当)。フラグの有無に依存しない。
	for m in _board.legal_moves():
		var move := m as Move
		if move.from == want.from and move.to == want.to and move.promotion == want.promotion:
			return move
	return null
