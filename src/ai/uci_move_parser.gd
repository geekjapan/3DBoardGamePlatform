class_name UciMoveParser
extends RefCounted

## UCI 手文字列(e2e4 / e7e8q)を Move に変換する。
## フラグ(castling / en passant)は GameSession.apply_move が合法手照合で補完する。


static func parse(uci: String) -> Move:
	var s := uci.strip_edges()
	if s.length() < 4:
		return null
	var from := _parse_sq(s.substr(0, 2))
	var to := _parse_sq(s.substr(2, 2))
	if from.x < 0 or to.x < 0:
		return null
	var promo := -1
	if s.length() >= 5:
		promo = _promo_kind(s.substr(4, 1))
	return Move.new(from, to, promo)


static func is_legal_on(board: Board, uci: String) -> bool:
	var want := parse(uci)
	if want == null:
		return false
	for m in board.legal_moves():
		var move := m as Move
		if move.from == want.from and move.to == want.to and move.promotion == want.promotion:
			return true
		# 昇格未指定でクイーン成りの合法手だけがある場合は UCI 側に文字が付く想定。
		if (
			want.promotion < 0
			and move.from == want.from
			and move.to == want.to
			and move.promotion >= 0
		):
			# エンジンは必ず昇格先を付けるので通常ここには来ない。
			pass
	return false


static func _parse_sq(s: String) -> Vector2i:
	if s.length() < 2:
		return Vector2i(-1, -1)
	var file_ch := s.unicode_at(0)
	var rank_ch := s.unicode_at(1)
	if file_ch < 97 or file_ch > 104:
		return Vector2i(-1, -1)
	if rank_ch < 49 or rank_ch > 56:
		return Vector2i(-1, -1)
	return Vector2i(file_ch - 97, rank_ch - 49)


static func _promo_kind(ch: String) -> int:
	match ch.to_lower():
		"q":
			return Piece.Kind.QUEEN
		"r":
			return Piece.Kind.ROOK
		"b":
			return Piece.Kind.BISHOP
		"n":
			return Piece.Kind.KNIGHT
		_:
			return -1
