class_name ShogiUsiCodec
extends RefCounted

## 将棋盤と USI の境界。
##
## Piece.Side.WHITE は先手(sente)、BLACK は後手(gote)である。USI/SFEN の
## 手番 token はこのプロジェクトの境界では先手="b"、後手="w" とし、
## SFEN の大文字駒も先手を表す。

const START_SFEN := "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"
const STARTPOS_SFEN := START_SFEN

const _MOVE_NUMBER_META := "shogi_usi_sfen_move_number"
const _HAND_ORDER := [
	Piece.Kind.SHOGI_ROOK,
	Piece.Kind.SHOGI_BISHOP,
	Piece.Kind.SHOGI_GOLD,
	Piece.Kind.SHOGI_SILVER,
	Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_LANCE,
	Piece.Kind.SHOGI_PAWN,
]
const _HAND_CHARS := {
	Piece.Kind.SHOGI_ROOK: "R",
	Piece.Kind.SHOGI_BISHOP: "B",
	Piece.Kind.SHOGI_GOLD: "G",
	Piece.Kind.SHOGI_SILVER: "S",
	Piece.Kind.SHOGI_KNIGHT: "N",
	Piece.Kind.SHOGI_LANCE: "L",
	Piece.Kind.SHOGI_PAWN: "P",
}
const _BASE_CHARS := {
	Piece.Kind.SHOGI_PAWN: "P",
	Piece.Kind.SHOGI_LANCE: "L",
	Piece.Kind.SHOGI_KNIGHT: "N",
	Piece.Kind.SHOGI_SILVER: "S",
	Piece.Kind.SHOGI_GOLD: "G",
	Piece.Kind.SHOGI_BISHOP: "B",
	Piece.Kind.SHOGI_ROOK: "R",
	Piece.Kind.SHOGI_KING: "K",
}
const _CHAR_TO_KIND := {
	"P": Piece.Kind.SHOGI_PAWN,
	"L": Piece.Kind.SHOGI_LANCE,
	"N": Piece.Kind.SHOGI_KNIGHT,
	"S": Piece.Kind.SHOGI_SILVER,
	"G": Piece.Kind.SHOGI_GOLD,
	"B": Piece.Kind.SHOGI_BISHOP,
	"R": Piece.Kind.SHOGI_ROOK,
	"K": Piece.Kind.SHOGI_KING,
}
const _PROMOTED_KIND := {
	Piece.Kind.SHOGI_PAWN: Piece.Kind.SHOGI_PROMOTED_PAWN,
	Piece.Kind.SHOGI_LANCE: Piece.Kind.SHOGI_PROMOTED_LANCE,
	Piece.Kind.SHOGI_KNIGHT: Piece.Kind.SHOGI_PROMOTED_KNIGHT,
	Piece.Kind.SHOGI_SILVER: Piece.Kind.SHOGI_PROMOTED_SILVER,
	Piece.Kind.SHOGI_BISHOP: Piece.Kind.SHOGI_HORSE,
	Piece.Kind.SHOGI_ROOK: Piece.Kind.SHOGI_DRAGON,
}
const _DROP_CHAR_TO_KIND := {
	"P": Piece.Kind.SHOGI_PAWN,
	"L": Piece.Kind.SHOGI_LANCE,
	"N": Piece.Kind.SHOGI_KNIGHT,
	"S": Piece.Kind.SHOGI_SILVER,
	"G": Piece.Kind.SHOGI_GOLD,
	"B": Piece.Kind.SHOGI_BISHOP,
	"R": Piece.Kind.SHOGI_ROOK,
}


static func to_sfen(board: ShogiBoard) -> String:
	## board の状態を標準 9x9 SFEN へ変換する。
	if board == null or board.width != ShogiBoard.WIDTH or board.height != ShogiBoard.HEIGHT:
		return ""
	var ranks := PackedStringArray()
	for row in range(ShogiBoard.HEIGHT):
		var rank_y := ShogiBoard.HEIGHT - 1 - row
		var empty := 0
		var rank := ""
		for column in range(ShogiBoard.WIDTH):
			# SFEN is written from file 9 to file 1. The shogi rule board follows
			# that visual orientation: x=0 is the file-9 edge, x=8 is file 1.
			var file_x := column
			var piece: Piece = board.piece_at(Vector2i(file_x, rank_y))
			if piece == null:
				empty += 1
				continue
			if empty > 0:
				rank += str(empty)
				empty = 0
			rank += _piece_sfen_char(piece)
		if empty > 0:
			rank += str(empty)
		ranks.append(rank)

	var side := "b" if board.side_to_move == Piece.Side.WHITE else "w"
	var move_number := 1
	if board.has_meta(_MOVE_NUMBER_META):
		move_number = maxi(1, int(board.get_meta(_MOVE_NUMBER_META)))
	return "%s %s %s %d" % [
		"/".join(ranks),
		side,
		_hands_to_sfen(board),
		move_number,
	]


static func from_sfen(sfen: String) -> ShogiBoard:
	## SFEN を ShogiBoard に変換する。不正な SFEN は null を返す。
	var parts := sfen.strip_edges().split(" ", false)
	if parts.size() != 4:
		return null
	var ranks := parts[0].split("/", false)
	if ranks.size() != ShogiBoard.HEIGHT:
		return null
	var side := _side_from_sfen(parts[1])
	if side < 0:
		return null
	var move_number := _positive_integer(parts[3])
	if move_number < 1:
		return null

	var board := ShogiBoard.empty()
	board.side_to_move = side
	for row in range(ShogiBoard.HEIGHT):
		if not _parse_rank(ranks[row], row, board):
			return null
	if not _parse_hands(parts[2], board):
		return null
	# ShogiBoard intentionally does not own SFEN's move counter. Keep it at the
	# codec boundary so a parse/serialize roundtrip remains lossless.
	board.set_meta(_MOVE_NUMBER_META, move_number)
	return board


static func position_startpos(moves: Variant = []) -> String:
	return _position_command("position startpos", moves)


static func position_sfen(sfen: String, moves: Variant = []) -> String:
	var board := from_sfen(sfen)
	if board == null:
		return ""
	return _position_command("position sfen %s" % to_sfen(board), moves)


static func position(board: ShogiBoard, moves: Variant = []) -> String:
	## 初期局面は短い startpos、それ以外は sfen 形式で組み立てる。
	var sfen := to_sfen(board)
	if sfen.is_empty():
		return ""
	if sfen == START_SFEN:
		return position_startpos(moves)
	return position_sfen(sfen, moves)


static func position_command(board: ShogiBoard, moves: Variant = []) -> String:
	return position(board, moves)


static func parse_bestmove(first: Variant, second: Variant) -> Move:
	## `parse_bestmove(board, line)` と `parse_bestmove(line, board)` の両方を
	## 受け付ける。返すのは構文から新造した Move ではなく、合法手配列の実体。
	var board: ShogiBoard = null
	var line := ""
	if first is ShogiBoard:
		board = first as ShogiBoard
		line = str(second)
	elif second is ShogiBoard:
		board = second as ShogiBoard
		line = str(first)
	if board == null:
		return null
	var parts := line.strip_edges().replace("\t", " ").split(" ", false)
	if parts.size() < 2 or parts[0] != "bestmove":
		return null
	if parts[1] in ["resign", "win", "none", "(none)", "0000"]:
		return null
	if parts.size() != 2 and (parts.size() != 4 or parts[2] != "ponder"):
		return null
	if parts.size() == 4 and _parse_usi_shape(parts[3]) == null:
		return null
	return parse_usi_move(board, parts[1])


static func parse_usi_move(board: ShogiBoard, token: String) -> Move:
	## USI の手を構文解析し、現在局面の合法手と完全一致したものだけ返す。
	if board == null:
		return null
	var wanted := _parse_usi_shape(token)
	if wanted == null:
		return null
	var normalized_token := token.strip_edges()
	var wants_promotion := normalized_token.length() == 5 and normalized_token.ends_with("+")
	for candidate in board.legal_moves():
		var move := candidate as Move
		if wants_promotion:
			if move.from == wanted.from and move.to == wanted.to and move.promotion >= 0:
				return move
		elif move.equals(wanted):
			return move
	return null


static func parse_legal_move(board: Object, token: String) -> Move:
	## AiMatch の USI 境界用別名。token は bare USI move でも bestmove 行でもよい。
	var shogi_board := board as ShogiBoard
	if shogi_board == null:
		return null
	var value := token.strip_edges()
	if value.begins_with("bestmove"):
		return parse_bestmove(shogi_board, value)
	return parse_usi_move(shogi_board, value)


static func position_for(board: Object, moves: Variant = []) -> String:
	return position(board as ShogiBoard, moves)


static func move_from_bestmove(board: ShogiBoard, line: String) -> Move:
	return parse_bestmove(board, line)


static func _position_command(prefix: String, moves: Variant) -> String:
	var command := prefix
	if moves == null:
		return command
	if moves is String:
		moves = [moves]
	var has_moves := false
	for item in moves:
		var token := str(item).strip_edges()
		if token.is_empty():
			continue
		# Prefixes already end in startpos or the final SFEN move number. Add the
		# protocol's moves separator exactly once before the first move.
		if not has_moves:
			command += " moves"
			has_moves = true
		command += " " + token
	return command


static func _parse_rank(rank: String, row: int, board: ShogiBoard) -> bool:
	var column := 0
	var index := 0
	while index < rank.length():
		if column >= ShogiBoard.WIDTH:
			return false
		var ch := rank.substr(index, 1)
		if _is_ascii_digit(ch):
			var count := _digit_value(ch)
			if count < 1 or column + count > ShogiBoard.WIDTH:
				return false
			column += count
			index += 1
			continue

		var promoted := false
		if ch == "+":
			promoted = true
			index += 1
			if index >= rank.length():
				return false
			ch = rank.substr(index, 1)
		var upper := ch.to_upper()
		if not _CHAR_TO_KIND.has(upper):
			return false
		var kind := int(_CHAR_TO_KIND[upper])
		if promoted:
			if not _PROMOTED_KIND.has(kind):
				return false
			kind = int(_PROMOTED_KIND[kind])
		var side := Piece.Side.WHITE if ch == upper else Piece.Side.BLACK
		var file_x := column
		var rank_y := ShogiBoard.HEIGHT - 1 - row
		board.set_piece(Vector2i(file_x, rank_y), Piece.new(side, kind))
		column += 1
		index += 1
	return column == ShogiBoard.WIDTH


static func _parse_hands(value: String, board: ShogiBoard) -> bool:
	if value == "-":
		return true
	if value.is_empty():
		return false
	var index := 0
	var seen := {}
	while index < value.length():
		var count := 1
		if _is_ascii_digit(value.substr(index, 1)):
			var start := index
			while index < value.length() and _is_ascii_digit(value.substr(index, 1)):
				index += 1
			count = int(value.substr(start, index - start))
			if count < 1:
				return false
		if index >= value.length():
			return false
		var ch := value.substr(index, 1)
		var upper := ch.to_upper()
		if not _HAND_CHARS.values().has(upper) or seen.has(ch):
			return false
		seen[ch] = true
		var kind := int(_CHAR_TO_KIND[upper])
		var side := Piece.Side.WHITE if ch == upper else Piece.Side.BLACK
		board.hands[side][kind] = count
		index += 1
	return true


static func _parse_usi_shape(token: String) -> Move:
	var value := token.strip_edges()
	if value.length() == 4 and value.substr(1, 1) == "*":
		var drop_char := value.substr(0, 1)
		if not _DROP_CHAR_TO_KIND.has(drop_char):
			return null
		var to := _parse_usi_square(value.substr(2, 2))
		if to == Move.NO_SQUARE:
			return null
		return Move.drop(int(_DROP_CHAR_TO_KIND[drop_char]), to)
	if value.length() != 4 and value.length() != 5:
		return null
	var from := _parse_usi_square(value.substr(0, 2))
	var to_normal := _parse_usi_square(value.substr(2, 2))
	if from == Move.NO_SQUARE or to_normal == Move.NO_SQUARE:
		return null
	if value.length() == 5:
		if value.substr(4, 1) != "+":
			return null
		# A promotion's actual Piece.Kind is determined by the moving piece.
		# Keep promotion=-1 here; parse_usi_move uses the '+' marker and resolves
		# the complete canonical Move from legal_moves().
	return Move.new(from, to_normal)


static func _parse_usi_square(value: String) -> Vector2i:
	if value.length() != 2:
		return Move.NO_SQUARE
	var file := value.unicode_at(0)
	var rank := value.unicode_at(1)
	if file < 49 or file > 57 or rank < 97 or rank > 105:
		return Move.NO_SQUARE
	# USI ranks run a..i from the gote edge; the rule board's y=0 is the
	# sente edge, so the rank axis is inverted here.
	return Vector2i(57 - file, 105 - rank)


static func _side_from_sfen(value: String) -> int:
	if value == "b":
		return Piece.Side.WHITE
	if value == "w":
		return Piece.Side.BLACK
	return -1


static func _hands_to_sfen(board: ShogiBoard) -> String:
	var result := ""
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		for kind in _HAND_ORDER:
			var count := int(board.hands[side].get(kind, 0))
			if count <= 0:
				continue
			if count > 1:
				result += str(count)
			var ch := str(_HAND_CHARS[kind])
			result += ch if side == Piece.Side.WHITE else ch.to_lower()
	return "-" if result.is_empty() else result


static func _piece_sfen_char(piece: Piece) -> String:
	var kind := piece.kind
	var promoted := Piece.base_kind_for_promoted(kind)
	if promoted >= 0:
		return "+" + _case_for_side(str(_BASE_CHARS[promoted]), piece.side)
	if not _BASE_CHARS.has(kind):
		return "?"
	return _case_for_side(str(_BASE_CHARS[kind]), piece.side)


static func _case_for_side(value: String, side: int) -> String:
	return value if side == Piece.Side.WHITE else value.to_lower()


static func _positive_integer(value: String) -> int:
	if value.is_empty():
		return -1
	for index in range(value.length()):
		if not _is_ascii_digit(value.substr(index, 1)):
			return -1
	return int(value)


static func _is_ascii_digit(value: String) -> bool:
	return value.length() == 1 and value.unicode_at(0) >= 48 and value.unicode_at(0) <= 57


static func _digit_value(value: String) -> int:
	if not _is_ascii_digit(value):
		return -1
	return value.unicode_at(0) - 48
