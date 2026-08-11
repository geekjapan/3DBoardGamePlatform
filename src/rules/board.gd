class_name Board
extends RefCounted

## 盤面状態と合法手生成。
##
## チェス専用ロジックを含むが、width/height と hands(持ち駒)を持つので
## 後から 9x9 + 持ち駒の将棋を同じ抽象の上に載せられる。
## apply は元盤を変えず新しい Board を返す。

## 無効マス(アンパッサンなし・玉未発見・后翼の追加空きマスなし)。Move.NO_SQUARE と同値。
const NO_SQUARE := Vector2i(-1, -1)

## キャスリング権利ビット: 白王翼, 白后翼, 黒王翼, 黒后翼
const CR_WK := 1
const CR_WQ := 2
const CR_BK := 4
const CR_BQ := 8


var width: int = 8
var height: int = 8
## 各マス: Piece または null。index = y * width + x。a1 = (0,0)。
var _squares: Array = []
## Piece.Side の値
var side_to_move: int = Piece.Side.WHITE
var castling_rights: int = 0
var en_passant_target: Vector2i = NO_SQUARE
var halfmove_clock: int = 0
var fullmove_number: int = 1
## side(int) -> { kind(int) -> count(int) }。チェスでは常に空。
var hands: Dictionary = {}


func _init() -> void:
	_squares.resize(width * height)
	_squares.fill(null)
	hands[Piece.Side.WHITE] = {}
	hands[Piece.Side.BLACK] = {}


static func chess_start() -> Board:
	return from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")


static func empty(p_width: int = 8, p_height: int = 8) -> Board:
	var b := Board.new()
	b.width = p_width
	b.height = p_height
	b._squares.resize(p_width * p_height)
	b._squares.fill(null)
	b.castling_rights = 0
	b.en_passant_target = NO_SQUARE
	return b


static func from_fen(fen: String) -> Board:
	var parts := fen.strip_edges().split(" ")
	assert(parts.size() >= 4, "invalid FEN")
	var b := Board.new()
	var ranks := parts[0].split("/")
	assert(ranks.size() == 8, "chess FEN must have 8 ranks")
	for r in range(8):
		var rank_y := 7 - r
		var file_x := 0
		for ch in ranks[r]:
			if ch >= "1" and ch <= "8":
				file_x += int(ch)
			else:
				var side: int = Piece.Side.WHITE if ch == ch.to_upper() else Piece.Side.BLACK
				var kind: int = _fen_char_to_kind(ch.to_lower())
				b._put(Vector2i(file_x, rank_y), Piece.new(side, kind))
				file_x += 1
	b.side_to_move = Piece.Side.WHITE if parts[1] == "w" else Piece.Side.BLACK
	b.castling_rights = 0
	if parts[2] != "-":
		if "K" in parts[2]:
			b.castling_rights |= CR_WK
		if "Q" in parts[2]:
			b.castling_rights |= CR_WQ
		if "k" in parts[2]:
			b.castling_rights |= CR_BK
		if "q" in parts[2]:
			b.castling_rights |= CR_BQ
	if parts[3] == "-":
		b.en_passant_target = NO_SQUARE
	else:
		b.en_passant_target = _parse_square(parts[3])
	if parts.size() >= 5:
		b.halfmove_clock = int(parts[4])
	if parts.size() >= 6:
		b.fullmove_number = int(parts[5])
	return b


func piece_at(pos: Vector2i) -> Piece:
	if not _in_bounds(pos):
		return null
	return _squares[_index(pos)]


func set_piece(pos: Vector2i, piece: Piece) -> void:
	## テスト構築用。本番対局では apply 経由を使う。
	_put(pos, piece)


func clone() -> Board:
	var b := Board.new()
	b.width = width
	b.height = height
	b._squares.resize(width * height)
	for i in range(_squares.size()):
		var p: Piece = _squares[i]
		b._squares[i] = p.duplicate_piece() if p != null else null
	b.side_to_move = side_to_move
	b.castling_rights = castling_rights
	b.en_passant_target = en_passant_target
	b.halfmove_clock = halfmove_clock
	b.fullmove_number = fullmove_number
	b.hands = _clone_hands()
	return b


func legal_moves() -> Array:
	var moves: Array = []
	var side := side_to_move
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			var p := piece_at(pos)
			if p == null or p.side != side:
				continue
			_gen_piece_moves(pos, p, moves)
	var legal: Array = []
	for m in moves:
		var next := _apply_unchecked(m as Move)
		# 移動後の盤で、移動後の自玉位置が攻撃されていないこと
		if not next._is_square_attacked(next._find_king(side), side):
			legal.append(m)
	return legal


func apply(move: Move) -> Board:
	## 合法手前提。元の盤面は変更しない。
	var next := _apply_unchecked(move)
	next.side_to_move = Piece.opposite(side_to_move)
	if side_to_move == Piece.Side.BLACK:
		next.fullmove_number = fullmove_number + 1
	else:
		next.fullmove_number = fullmove_number
	return next


func in_check(side: int = -1) -> bool:
	var s := side_to_move if side < 0 else side
	var king_pos := _find_king(s)
	if king_pos == NO_SQUARE:
		return false
	return _is_square_attacked(king_pos, s)


func is_checkmate() -> bool:
	return legal_moves().is_empty() and in_check()


func is_stalemate() -> bool:
	return legal_moves().is_empty() and not in_check()


func king_square(side: int = -1) -> Vector2i:
	## 指定側(省略時は手番側)の玉位置。いなければ NO_SQUARE。
	var s := side_to_move if side < 0 else side
	return _find_king(s)


func perft(depth: int) -> int:
	if depth == 0:
		return 1
	var moves := legal_moves()
	if depth == 1:
		return moves.size()
	var nodes := 0
	for m in moves:
		nodes += apply(m as Move).perft(depth - 1)
	return nodes


func legal_move_ucis() -> PackedStringArray:
	var out := PackedStringArray()
	for m in legal_moves():
		out.append((m as Move).to_uci())
	out.sort()
	return out


# --- generation ---


func _gen_piece_moves(from: Vector2i, piece: Piece, out: Array) -> void:
	match piece.kind:
		Piece.Kind.PAWN:
			_gen_pawn(from, piece.side, out)
		Piece.Kind.KNIGHT:
			_gen_leaper(from, piece.side, _KNIGHT_DELTAS, out)
		Piece.Kind.BISHOP:
			_gen_slider(from, piece.side, _BISHOP_DIRS, out)
		Piece.Kind.ROOK:
			_gen_slider(from, piece.side, _ROOK_DIRS, out)
		Piece.Kind.QUEEN:
			_gen_slider(from, piece.side, _QUEEN_DIRS, out)
		Piece.Kind.KING:
			_gen_leaper(from, piece.side, _KING_DELTAS, out)
			_gen_castling(from, piece.side, out)


const _KNIGHT_DELTAS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]
const _KING_DELTAS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const _BISHOP_DIRS := [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const _ROOK_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const _QUEEN_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


func _gen_pawn(from: Vector2i, side: int, out: Array) -> void:
	var dir := 1 if side == Piece.Side.WHITE else -1
	var start_rank := 1 if side == Piece.Side.WHITE else 6
	var last_rank := 7 if side == Piece.Side.WHITE else 0
	var one := Vector2i(from.x, from.y + dir)
	if _in_bounds(one) and piece_at(one) == null:
		_push_pawn_move(from, one, last_rank, out)
		if from.y == start_rank:
			var two := Vector2i(from.x, from.y + 2 * dir)
			if piece_at(two) == null:
				out.append(Move.new(from, two))
	for dx in [-1, 1]:
		var cap := Vector2i(from.x + dx, from.y + dir)
		if not _in_bounds(cap):
			continue
		var target := piece_at(cap)
		if target != null and target.side != side:
			_push_pawn_move(from, cap, last_rank, out)
		elif cap == en_passant_target:
			out.append(Move.new(from, cap, -1, false, true))


func _push_pawn_move(from: Vector2i, to: Vector2i, last_rank: int, out: Array) -> void:
	if to.y == last_rank:
		# 仕様: クイーンに昇格
		out.append(Move.new(from, to, Piece.Kind.QUEEN))
	else:
		out.append(Move.new(from, to))


func _gen_leaper(from: Vector2i, side: int, deltas: Array, out: Array) -> void:
	for d in deltas:
		var to: Vector2i = from + d
		if not _in_bounds(to):
			continue
		var target := piece_at(to)
		if target == null or target.side != side:
			out.append(Move.new(from, to))


func _gen_slider(from: Vector2i, side: int, dirs: Array, out: Array) -> void:
	for d in dirs:
		var to: Vector2i = from + d
		while _in_bounds(to):
			var target := piece_at(to)
			if target == null:
				out.append(Move.new(from, to))
			else:
				if target.side != side:
					out.append(Move.new(from, to))
				break
			to += d


func _gen_castling(from: Vector2i, side: int, out: Array) -> void:
	if in_check(side):
		return
	var rank := 0 if side == Piece.Side.WHITE else 7
	if from != Vector2i(4, rank):
		return
	if side == Piece.Side.WHITE:
		if castling_rights & CR_WK:
			_try_castle(from, Vector2i(6, rank), Vector2i(5, rank), Vector2i(7, rank), side, out)
		if castling_rights & CR_WQ:
			_try_castle(from, Vector2i(2, rank), Vector2i(3, rank), Vector2i(0, rank), side, out, Vector2i(1, rank))
	else:
		if castling_rights & CR_BK:
			_try_castle(from, Vector2i(6, rank), Vector2i(5, rank), Vector2i(7, rank), side, out)
		if castling_rights & CR_BQ:
			_try_castle(from, Vector2i(2, rank), Vector2i(3, rank), Vector2i(0, rank), side, out, Vector2i(1, rank))


func _try_castle(
	king_from: Vector2i,
	king_to: Vector2i,
	through: Vector2i,
	rook_from: Vector2i,
	side: int,
	out: Array,
	extra_empty: Vector2i = NO_SQUARE,
) -> void:
	if piece_at(rook_from) == null:
		return
	var rook := piece_at(rook_from)
	if rook.kind != Piece.Kind.ROOK or rook.side != side:
		return
	if piece_at(king_to) != null or piece_at(through) != null:
		return
	if extra_empty != NO_SQUARE and piece_at(extra_empty) != null:
		return
	if _is_square_attacked(through, side) or _is_square_attacked(king_to, side):
		return
	out.append(Move.new(king_from, king_to, -1, true))


# --- apply ---


func _apply_unchecked(move: Move) -> Board:
	var b := clone()
	var moving: Piece = b.piece_at(move.from)
	assert(moving != null, "no piece on from")
	var captured := b.piece_at(move.to)
	var is_pawn := moving.kind == Piece.Kind.PAWN
	var is_capture := captured != null or move.is_en_passant

	if move.is_en_passant:
		var cap_pos := Vector2i(move.to.x, move.from.y)
		b._put(cap_pos, null)
		captured = null

	b._put(move.from, null)

	if move.is_castling:
		var rank := move.from.y
		if move.to.x == 6:
			var rook := b.piece_at(Vector2i(7, rank))
			b._put(Vector2i(7, rank), null)
			b._put(Vector2i(5, rank), rook)
		else:
			var rook_q := b.piece_at(Vector2i(0, rank))
			b._put(Vector2i(0, rank), null)
			b._put(Vector2i(3, rank), rook_q)

	var placed := moving.duplicate_piece()
	if move.promotion >= 0:
		placed.kind = move.promotion
	b._put(move.to, placed)

	b._update_castling_rights(move, moving)
	b._update_en_passant(move, moving)

	if is_pawn or is_capture:
		b.halfmove_clock = 0
	else:
		b.halfmove_clock = halfmove_clock + 1

	return b


func _update_castling_rights(move: Move, moving: Piece) -> void:
	if moving.kind == Piece.Kind.KING:
		if moving.side == Piece.Side.WHITE:
			castling_rights &= ~(CR_WK | CR_WQ)
		else:
			castling_rights &= ~(CR_BK | CR_BQ)
	if moving.kind == Piece.Kind.ROOK:
		_clear_rook_right(move.from)
	_clear_rook_right(move.to)


func _clear_rook_right(pos: Vector2i) -> void:
	if pos == Vector2i(0, 0):
		castling_rights &= ~CR_WQ
	elif pos == Vector2i(7, 0):
		castling_rights &= ~CR_WK
	elif pos == Vector2i(0, 7):
		castling_rights &= ~CR_BQ
	elif pos == Vector2i(7, 7):
		castling_rights &= ~CR_BK


func _update_en_passant(move: Move, moving: Piece) -> void:
	en_passant_target = NO_SQUARE
	if moving.kind == Piece.Kind.PAWN and absi(move.to.y - move.from.y) == 2:
		en_passant_target = Vector2i(move.from.x, (move.from.y + move.to.y) / 2)


# --- attacks ---


func _is_square_attacked(sq: Vector2i, by_side_friendly: int) -> bool:
	## by_side_friendly 側の駒が sq にいるとして、敵に攻撃されているか。
	var enemy: int = Piece.opposite(by_side_friendly)
	# 白ポーンは (x±1, y+1) を攻撃 → sq を攻撃する白ポーンは (sq.x±1, sq.y-1)
	var pawn_from_dy := -1 if enemy == Piece.Side.WHITE else 1
	for dx in [-1, 1]:
		var p := piece_at(Vector2i(sq.x + dx, sq.y + pawn_from_dy))
		if p != null and p.side == enemy and p.kind == Piece.Kind.PAWN:
			return true
	for d in _KNIGHT_DELTAS:
		var n := piece_at(sq + d)
		if n != null and n.side == enemy and n.kind == Piece.Kind.KNIGHT:
			return true
	for d in _KING_DELTAS:
		var k := piece_at(sq + d)
		if k != null and k.side == enemy and k.kind == Piece.Kind.KING:
			return true
	if _attacked_by_slider(sq, enemy, _BISHOP_DIRS, true):
		return true
	if _attacked_by_slider(sq, enemy, _ROOK_DIRS, false):
		return true
	return false


func _attacked_by_slider(sq: Vector2i, enemy: int, dirs: Array, diagonal: bool) -> bool:
	for d in dirs:
		var pos: Vector2i = sq + d
		while _in_bounds(pos):
			var p := piece_at(pos)
			if p != null:
				if p.side == enemy:
					if p.kind == Piece.Kind.QUEEN:
						return true
					if diagonal and p.kind == Piece.Kind.BISHOP:
						return true
					if not diagonal and p.kind == Piece.Kind.ROOK:
						return true
				break
			pos += d
	return false


func _find_king(side: int) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var p := piece_at(Vector2i(x, y))
			if p != null and p.side == side and p.kind == Piece.Kind.KING:
				return Vector2i(x, y)
	return NO_SQUARE


# --- helpers ---


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _index(pos: Vector2i) -> int:
	return pos.y * width + pos.x


func _put(pos: Vector2i, piece: Piece) -> void:
	_squares[_index(pos)] = piece


func _clone_hands() -> Dictionary:
	var h := {}
	for side in hands:
		var inner: Dictionary = {}
		var src: Dictionary = hands[side]
		for k in src:
			inner[k] = src[k]
		h[side] = inner
	return h


static func _fen_char_to_kind(ch: String) -> int:
	match ch:
		"p":
			return Piece.Kind.PAWN
		"n":
			return Piece.Kind.KNIGHT
		"b":
			return Piece.Kind.BISHOP
		"r":
			return Piece.Kind.ROOK
		"q":
			return Piece.Kind.QUEEN
		"k":
			return Piece.Kind.KING
		_:
			assert(false, "bad fen piece %s" % ch)
			return Piece.Kind.PAWN


static func _parse_square(s: String) -> Vector2i:
	return Vector2i(s.unicode_at(0) - 97, int(s.substr(1)) - 1)
