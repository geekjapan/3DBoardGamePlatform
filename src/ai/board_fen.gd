class_name BoardFen
extends RefCounted

## Board の公開 API だけから FEN を組み立てる。
## rules/board.gd をいじらずに UCI の position fen へ渡すための変換。


static func to_fen(board: Board) -> String:
	var ranks: PackedStringArray = PackedStringArray()
	for r in range(8):
		var rank_y := 7 - r
		var empty := 0
		var row := ""
		for x in range(8):
			var p := board.piece_at(Vector2i(x, rank_y))
			if p == null:
				empty += 1
			else:
				if empty > 0:
					row += str(empty)
					empty = 0
				row += _piece_char(p)
		if empty > 0:
			row += str(empty)
		ranks.append(row)
	var placement := "/".join(ranks)
	var stm := "w" if board.side_to_move == Piece.Side.WHITE else "b"
	var castling := _castling_fen(board.castling_rights)
	var ep := "-"
	if board.en_passant_target != Board.NO_SQUARE:
		ep = _sq(board.en_passant_target)
	return "%s %s %s %s %d %d" % [
		placement, stm, castling, ep, board.halfmove_clock, board.fullmove_number
	]


static func _piece_char(p: Piece) -> String:
	var ch := "?"
	match p.kind:
		Piece.Kind.PAWN:
			ch = "p"
		Piece.Kind.KNIGHT:
			ch = "n"
		Piece.Kind.BISHOP:
			ch = "b"
		Piece.Kind.ROOK:
			ch = "r"
		Piece.Kind.QUEEN:
			ch = "q"
		Piece.Kind.KING:
			ch = "k"
	if p.side == Piece.Side.WHITE:
		return ch.to_upper()
	return ch


static func _castling_fen(rights: int) -> String:
	var s := ""
	if rights & Board.CR_WK:
		s += "K"
	if rights & Board.CR_WQ:
		s += "Q"
	if rights & Board.CR_BK:
		s += "k"
	if rights & Board.CR_BQ:
		s += "q"
	if s.is_empty():
		return "-"
	return s


static func _sq(pos: Vector2i) -> String:
	return "%s%d" % [char(97 + pos.x), pos.y + 1]
