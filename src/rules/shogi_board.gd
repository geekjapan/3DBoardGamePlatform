class_name ShogiBoard
extends RefCounted

## 9x9 将棋盤。既存のチェス Board とは独立したルール実装。
## WHITE は先手で +Y、BLACK は後手で -Y へ進む。

const WIDTH := 9
const HEIGHT := 9
const NO_SQUARE := Vector2i(-1, -1)

const _BACK_RANK := [
	Piece.Kind.SHOGI_LANCE,
	Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_SILVER,
	Piece.Kind.SHOGI_GOLD,
	Piece.Kind.SHOGI_KING,
	Piece.Kind.SHOGI_GOLD,
	Piece.Kind.SHOGI_SILVER,
	Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_LANCE,
]
const _PROMOTED_KIND := {
	Piece.Kind.SHOGI_PAWN: Piece.Kind.SHOGI_PROMOTED_PAWN,
	Piece.Kind.SHOGI_LANCE: Piece.Kind.SHOGI_PROMOTED_LANCE,
	Piece.Kind.SHOGI_KNIGHT: Piece.Kind.SHOGI_PROMOTED_KNIGHT,
	Piece.Kind.SHOGI_SILVER: Piece.Kind.SHOGI_PROMOTED_SILVER,
	Piece.Kind.SHOGI_BISHOP: Piece.Kind.SHOGI_HORSE,
	Piece.Kind.SHOGI_ROOK: Piece.Kind.SHOGI_DRAGON,
}

var width: int = WIDTH
var height: int = HEIGHT
## Piece|null。index = y * 9 + x。
var _squares: Array = []
var side_to_move: int = Piece.Side.WHITE
## side(int) -> { basic kind(int) -> count(int) }。
var hands: Dictionary = {}


func _init() -> void:
	_squares.resize(WIDTH * HEIGHT)
	_squares.fill(null)
	hands = {
		Piece.Side.WHITE: {},
		Piece.Side.BLACK: {},
	}


static func start() -> ShogiBoard:
	var board := ShogiBoard.new()
	for x in range(WIDTH):
		board._put(Vector2i(x, 0), Piece.new(Piece.Side.WHITE, _BACK_RANK[x]))
		board._put(Vector2i(x, 2), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
		board._put(Vector2i(x, 6), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_PAWN))
		board._put(Vector2i(x, 8), Piece.new(Piece.Side.BLACK, _BACK_RANK[x]))
	board._put(Vector2i(1, 1), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_BISHOP))
	board._put(Vector2i(7, 1), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
	board._put(Vector2i(1, 7), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	board._put(Vector2i(7, 7), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_BISHOP))
	return board


static func empty() -> ShogiBoard:
	return ShogiBoard.new()


func piece_at(pos: Vector2i) -> Piece:
	if not _in_bounds(pos):
		return null
	return _squares[_index(pos)]


func set_piece(pos: Vector2i, piece: Piece) -> void:
	## 決定的なルールテスト用の局面構築入口。
	assert(_in_bounds(pos), "square out of bounds")
	_put(pos, piece)


func clone() -> ShogiBoard:
	var board := ShogiBoard.new()
	for i in range(_squares.size()):
		var piece: Piece = _squares[i]
		board._squares[i] = piece.duplicate_piece() if piece != null else null
	board.side_to_move = side_to_move
	board.hands = _clone_hands()
	return board


func legal_moves() -> Array:
	var candidates: Array = []
	var mover_side := side_to_move
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var from := Vector2i(x, y)
			var piece := piece_at(from)
			if piece != null and piece.side == mover_side:
				_gen_piece_moves(from, piece, candidates)
	var legal: Array = []
	for candidate in candidates:
		var move := candidate as Move
		var next := _apply_unchecked(move)
		if not next.in_check(mover_side):
			legal.append(move)
	return legal


func apply(move: Move) -> ShogiBoard:
	## 合法な通常移動を不変適用する。打つ手は Issue #26 の範囲。
	return _apply_unchecked(move)


func _apply_unchecked(move: Move) -> ShogiBoard:
	var board := clone()
	var moving := board.piece_at(move.from)
	assert(moving != null, "no piece on from")
	var captured := board.piece_at(move.to)
	if captured != null:
		var hand_kind := Piece.base_kind_for_promoted(captured.kind)
		if hand_kind < 0:
			hand_kind = captured.kind
		var hand: Dictionary = board.hands[moving.side]
		hand[hand_kind] = int(hand.get(hand_kind, 0)) + 1
	board._put(move.from, null)
	if move.promotion >= 0:
		moving.kind = move.promotion
	board._put(move.to, moving)
	board.side_to_move = Piece.opposite(side_to_move)
	return board


func in_check(side: int = -1) -> bool:
	var checked_side := side_to_move if side < 0 else side
	var king := _find_king(checked_side)
	if king == NO_SQUARE:
		return false
	var attacker_side := Piece.opposite(checked_side)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var from := Vector2i(x, y)
			var piece := piece_at(from)
			if piece != null and piece.side == attacker_side:
				if _piece_attacks(from, piece, king):
					return true
	return false


func is_checkmate() -> bool:
	return in_check() and legal_moves().is_empty()


func is_stalemate() -> bool:
	## 将棋にステイルメイト終局は無い。
	return false


func perft(depth: int) -> int:
	if depth == 0:
		return 1
	var moves := legal_moves()
	if depth == 1:
		return moves.size()
	var nodes := 0
	for move in moves:
		nodes += apply(move as Move).perft(depth - 1)
	return nodes


func _gen_piece_moves(from: Vector2i, piece: Piece, out: Array) -> void:
	var forward := 1 if piece.side == Piece.Side.WHITE else -1
	if _moves_as_gold(piece.kind):
		_gen_steps(from, piece.side, _gold_steps(forward), out)
		return
	match piece.kind:
		Piece.Kind.SHOGI_PAWN:
			_gen_steps(from, piece.side, [Vector2i(0, forward)], out)
		Piece.Kind.SHOGI_LANCE:
			_gen_slides(from, piece.side, [Vector2i(0, forward)], out)
		Piece.Kind.SHOGI_KNIGHT:
			_gen_steps(
				from,
				piece.side,
				[Vector2i(-1, 2 * forward), Vector2i(1, 2 * forward)],
				out
			)
		Piece.Kind.SHOGI_SILVER:
			_gen_steps(from, piece.side, _silver_steps(forward), out)
		Piece.Kind.SHOGI_GOLD:
			_gen_steps(from, piece.side, _gold_steps(forward), out)
		Piece.Kind.SHOGI_BISHOP:
			_gen_slides(from, piece.side, _BISHOP_DIRS, out)
		Piece.Kind.SHOGI_ROOK:
			_gen_slides(from, piece.side, _ROOK_DIRS, out)
		Piece.Kind.SHOGI_KING:
			_gen_steps(from, piece.side, _KING_STEPS, out)
		Piece.Kind.SHOGI_HORSE:
			_gen_slides(from, piece.side, _BISHOP_DIRS, out)
			_gen_steps(from, piece.side, _ROOK_DIRS, out)
		Piece.Kind.SHOGI_DRAGON:
			_gen_slides(from, piece.side, _ROOK_DIRS, out)
			_gen_steps(from, piece.side, _BISHOP_DIRS, out)


func _gen_steps(from: Vector2i, side: int, deltas: Array, out: Array) -> void:
	for delta: Vector2i in deltas:
		var to := from + delta
		if not _in_bounds(to):
			continue
		var target := piece_at(to)
		if target == null or target.side != side:
			_append_moves(from, to, piece_at(from), out)


func _gen_slides(from: Vector2i, side: int, directions: Array, out: Array) -> void:
	for direction: Vector2i in directions:
		var to := from + direction
		while _in_bounds(to):
			var target := piece_at(to)
			if target == null:
				_append_moves(from, to, piece_at(from), out)
			else:
				if target.side != side:
					_append_moves(from, to, piece_at(from), out)
				break
			to += direction


func _append_moves(from: Vector2i, to: Vector2i, piece: Piece, out: Array) -> void:
	var promoted_kind := int(_PROMOTED_KIND.get(piece.kind, -1))
	var can_promote := (
		promoted_kind >= 0
		and (_is_promotion_zone(piece.side, from.y) or _is_promotion_zone(piece.side, to.y))
	)
	if not can_promote:
		out.append(Move.new(from, to))
		return
	if not _is_forced_promotion(piece, to.y):
		out.append(Move.new(from, to))
	out.append(Move.new(from, to, promoted_kind))


static func _is_promotion_zone(side: int, y: int) -> bool:
	return y >= 6 if side == Piece.Side.WHITE else y <= 2


static func _is_forced_promotion(piece: Piece, to_y: int) -> bool:
	var last_rank := 8 if piece.side == Piece.Side.WHITE else 0
	match piece.kind:
		Piece.Kind.SHOGI_PAWN, Piece.Kind.SHOGI_LANCE:
			return to_y == last_rank
		Piece.Kind.SHOGI_KNIGHT:
			return to_y >= 7 if piece.side == Piece.Side.WHITE else to_y <= 1
	return false


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT


func _find_king(side: int) -> Vector2i:
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var pos := Vector2i(x, y)
			var piece := piece_at(pos)
			if piece != null and piece.side == side and piece.kind == Piece.Kind.SHOGI_KING:
				return pos
	return NO_SQUARE


func _piece_attacks(from: Vector2i, piece: Piece, target: Vector2i) -> bool:
	var delta := target - from
	var forward := 1 if piece.side == Piece.Side.WHITE else -1
	if _moves_as_gold(piece.kind):
		return _gold_steps(forward).has(delta)
	match piece.kind:
		Piece.Kind.SHOGI_PAWN:
			return delta == Vector2i(0, forward)
		Piece.Kind.SHOGI_LANCE:
			return delta.x == 0 and delta.y * forward > 0 and _path_clear(from, target)
		Piece.Kind.SHOGI_KNIGHT:
			return delta == Vector2i(-1, 2 * forward) or delta == Vector2i(1, 2 * forward)
		Piece.Kind.SHOGI_SILVER:
			return _silver_steps(forward).has(delta)
		Piece.Kind.SHOGI_BISHOP:
			return absi(delta.x) == absi(delta.y) and delta.x != 0 and _path_clear(from, target)
		Piece.Kind.SHOGI_ROOK:
			return (delta.x == 0 or delta.y == 0) and delta != Vector2i.ZERO and _path_clear(from, target)
		Piece.Kind.SHOGI_KING:
			return _KING_STEPS.has(delta)
		Piece.Kind.SHOGI_HORSE:
			var bishop_attack := absi(delta.x) == absi(delta.y) and delta.x != 0
			return (bishop_attack and _path_clear(from, target)) or _ROOK_DIRS.has(delta)
		Piece.Kind.SHOGI_DRAGON:
			var rook_attack := (delta.x == 0 or delta.y == 0) and delta != Vector2i.ZERO
			return (rook_attack and _path_clear(from, target)) or _BISHOP_DIRS.has(delta)
	return false


static func _moves_as_gold(kind: int) -> bool:
	return kind in [
		Piece.Kind.SHOGI_GOLD,
		Piece.Kind.SHOGI_PROMOTED_PAWN,
		Piece.Kind.SHOGI_PROMOTED_LANCE,
		Piece.Kind.SHOGI_PROMOTED_KNIGHT,
		Piece.Kind.SHOGI_PROMOTED_SILVER,
	]


func _path_clear(from: Vector2i, target: Vector2i) -> bool:
	var delta := target - from
	var step := Vector2i(clampi(delta.x, -1, 1), clampi(delta.y, -1, 1))
	var pos := from + step
	while pos != target:
		if piece_at(pos) != null:
			return false
		pos += step
	return true


func _index(pos: Vector2i) -> int:
	return pos.y * WIDTH + pos.x


func _put(pos: Vector2i, piece: Piece) -> void:
	_squares[_index(pos)] = piece


func _clone_hands() -> Dictionary:
	var copy := {
		Piece.Side.WHITE: {},
		Piece.Side.BLACK: {},
	}
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var source: Dictionary = hands[side]
		var target: Dictionary = copy[side]
		for kind in source:
			target[kind] = source[kind]
	return copy


static func _silver_steps(forward: int) -> Array:
	return [
		Vector2i(-1, forward), Vector2i(0, forward), Vector2i(1, forward),
		Vector2i(-1, -forward), Vector2i(1, -forward),
	]


static func _gold_steps(forward: int) -> Array:
	return [
		Vector2i(-1, forward), Vector2i(0, forward), Vector2i(1, forward),
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -forward),
	]


const _KING_STEPS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const _BISHOP_DIRS := [
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]
const _ROOK_DIRS := [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
]
