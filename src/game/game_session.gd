class_name GameSession
extends RefCounted

## 2 人対局の操作状態。Board(ルール)の上に選択・着手・待った・終局を載せる。
## 見た目や入力デバイスは持たない(presentation がこの API を叩く)。

const NO_SQUARE := Vector2i(-1, -1)

## 待ったは「1 往復」= 2 プライ(自分の手 + 相手の応手)。
const UNDO_PLIES := 2


var _board: Board
## 着手前の盤を積む。undo で 2 枚戻す。
var _history: Array = []
var _selected: Vector2i = NO_SQUARE
## selected 中の合法手キャッシュ。select / 盤更新で張り直す。
var _legal_from_selected: Array = []


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
	_history.append(_board)
	_board = _board.apply(move)
	deselect()
	return true


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
