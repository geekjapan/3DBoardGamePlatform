extends "res://tests/case.gd"

## T28: SFEN/USI の将棋盤境界。


func test_start_sfen_is_exact_and_roundtrips() -> void:
	var board := ShogiBoard.start()
	check_eq(ShogiUsiCodec.to_sfen(board), ShogiUsiCodec.START_SFEN, "標準初期SFEN")
	var again := ShogiUsiCodec.from_sfen(ShogiUsiCodec.START_SFEN)
	check(again != null, "初期SFENを復元")
	check_eq(ShogiUsiCodec.to_sfen(again), ShogiUsiCodec.START_SFEN, "初期SFEN往復")
	check_eq(again.side_to_move, Piece.Side.WHITE, "b は先手")


func test_asymmetric_board_turn_and_hands_use_standard_orientation() -> void:
	var sfen := "3k5/9/2+p6/9/9/9/9/9/7R1 w 2R3BGSNLP3l2p 42"
	var board := ShogiUsiCodec.from_sfen(sfen)
	check(board != null, "非対称SFENを復元")
	check_eq(board.side_to_move, Piece.Side.BLACK, "w は後手")
	check_eq(board.piece_at(Vector2i(3, 8)).kind, Piece.Kind.SHOGI_KING, "上段 file 6 の王")
	check_eq(board.piece_at(Vector2i(3, 8)).side, Piece.Side.BLACK, "上段王の陣営")
	check_eq(board.piece_at(Vector2i(2, 6)).kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "上段寄りの成歩")
	check_eq(board.piece_at(Vector2i(7, 0)).kind, Piece.Kind.SHOGI_ROOK, "下段 file 2 の飛")
	check_eq(board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_ROOK], 2, "先手飛2枚")
	check_eq(board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_BISHOP], 3, "先手角3枚")
	check_eq(board.hands[Piece.Side.BLACK][Piece.Kind.SHOGI_PAWN], 2, "後手歩2枚")
	check_eq(board.hands[Piece.Side.BLACK][Piece.Kind.SHOGI_LANCE], 3, "後手香3枚")
	check_eq(ShogiUsiCodec.to_sfen(board), sfen, "非対称SFEN往復")


func test_position_commands_support_startpos_sfen_and_moves() -> void:
	check_eq(
		ShogiUsiCodec.position_startpos(),
		"position startpos",
		"startpos command",
	)
	check_eq(
		ShogiUsiCodec.position_startpos(["7g7f", "3c3d"]),
		"position startpos moves 7g7f 3c3d",
		"startpos moves command",
	)
	check_eq(
		ShogiUsiCodec.position_sfen(ShogiUsiCodec.START_SFEN, ["7g7f"]),
		"position sfen %s moves 7g7f" % ShogiUsiCodec.START_SFEN,
		"sfen moves command",
	)
	check_eq(
		ShogiUsiCodec.position(ShogiBoard.start()),
		"position startpos",
		"initial board uses startpos",
	)


func test_bestmove_matches_legal_normal_promotion_and_drop() -> void:
	var start := ShogiBoard.start()
	var normal := ShogiUsiCodec.parse_bestmove(start, "bestmove 7g7f")
	check(normal != null, "合法通常手")
	check_eq(normal.from, Vector2i(2, 2), "7g は内部 file 3/rank c")
	check_eq(normal.to, Vector2i(2, 3), "7f は内部 rank d")
	check(not normal.is_drop and normal.promotion < 0, "通常手の完全Move")

	var promotion_board := ShogiBoard.empty()
	promotion_board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	promotion_board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	promotion_board.set_piece(Vector2i(2, 5), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
	var promotion := ShogiUsiCodec.parse_bestmove(promotion_board, "bestmove 7d7c+")
	check(promotion != null, "合法成り")
	check_eq(promotion.promotion, Piece.Kind.SHOGI_PROMOTED_PAWN, "成りKind")

	var drop_board := ShogiBoard.empty()
	drop_board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	drop_board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	drop_board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 1
	var drop := ShogiUsiCodec.parse_bestmove("bestmove S*5e", drop_board)
	check(drop != null, "合法打ち")
	check(drop.is_drop, "打つ手flag")
	check_eq(drop.drop_kind, Piece.Kind.SHOGI_SILVER, "打つ駒種")
	check_eq(drop.to, Vector2i(4, 4), "5e の配置先")


func test_bestmove_rejects_malformed_and_illegal_moves() -> void:
	var board := ShogiBoard.start()
	check(ShogiUsiCodec.parse_bestmove(board, "bestmove 7g7g") == null, "同一マスは非合法")
	check(ShogiUsiCodec.parse_bestmove(board, "bestmove 7g7f++") == null, "成り記号過多")
	check(ShogiUsiCodec.parse_bestmove(board, "bestmove p*5e") == null, "小文字打ち")
	check(ShogiUsiCodec.parse_bestmove(board, "bestmove") == null, "手なし")
	check(ShogiUsiCodec.parse_bestmove(board, "info bestmove 7g7f") == null, "bestmove行以外")
	check(ShogiUsiCodec.from_sfen("9/9/9/9/9/9/9/9/9 x - 1") == null, "不正手番")
	check(ShogiUsiCodec.from_sfen("10/9/9/9/9/9/9/9/9 b - 1") == null, "幅超過")
	check(ShogiUsiCodec.from_sfen("9P/9/9/9/9/9/9/9/9 b - 1") == null, "満杯rank後の駒を拒否")
