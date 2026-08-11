extends "res://tests/case.gd"

## Issue #3: チェスのルールエンジン。
##
## シーム:
## - Board.legal_moves() / apply(move) (不変)
## - is_checkmate() / is_stalemate()
## - perft(depth)
## - width/height + hands (将棋拡張の足場)


func test_starting_position_has_20_legal_moves() -> void:
	var board := Board.chess_start()
	check_eq(board.legal_moves().size(), 20, "初期局面の合法手数")


func test_apply_does_not_mutate_original() -> void:
	var board := Board.chess_start()
	var moves := board.legal_moves()
	check(moves.size() > 0, "初期局面に手がある")
	var e2e4: Move = null
	for m in moves:
		if (m as Move).to_uci() == "e2e4":
			e2e4 = m as Move
			break
	check(e2e4 != null, "e2e4 が列挙される")
	var next := board.apply(e2e4)
	check_eq(board.piece_at(Vector2i(4, 1)).kind, Piece.Kind.PAWN, "元盤の e2 はポーンのまま")
	check(board.piece_at(Vector2i(4, 3)) == null, "元盤の e4 は空のまま")
	check(next.piece_at(Vector2i(4, 1)) == null, "新手番盤の e2 は空")
	check_eq(next.piece_at(Vector2i(4, 3)).kind, Piece.Kind.PAWN, "新手番盤の e4 にポーン")
	check_eq(next.side_to_move, Piece.Side.BLACK, "手番が黒に移る")
	check_eq(board.side_to_move, Piece.Side.WHITE, "元盤の手番は白のまま")


func test_all_piece_kinds_can_move_or_capture() -> void:
	# 中央に各駒を置いて、少なくとも1手は生えること + 取りがあること
	var cases := [
		{"fen": "8/8/8/3N4/8/8/8/4K2k w - - 0 1", "min": 8, "label": "knight"},
		{"fen": "8/8/8/3B4/8/8/8/4K2k w - - 0 1", "min": 13, "label": "bishop"},
		{"fen": "8/8/8/3R4/8/8/8/4K2k w - - 0 1", "min": 14, "label": "rook"},
		{"fen": "8/8/8/3Q4/8/8/8/4K2k w - - 0 1", "min": 27, "label": "queen"},
		{"fen": "8/8/8/3P4/8/8/8/4K2k w - - 0 1", "min": 1, "label": "pawn"},
		{"fen": "8/8/8/8/8/8/8/4K2k w - - 0 1", "min": 5, "label": "king"},
	]
	for c in cases:
		var b := Board.from_fen(c["fen"])
		check(
			b.legal_moves().size() >= int(c["min"]),
			"%s が動ける (got %d)" % [c["label"], b.legal_moves().size()]
		)
	# 駒取り: 白ナイト d4 が黒ポーン e6 を取れる (デルタ +1,+2)
	var cap := Board.from_fen("8/8/4p3/8/3N4/8/8/4K2k w - - 0 1")
	var ucis := cap.legal_move_ucis()
	check(ucis.has("d4e6"), "ナイトが e6 のポーンを取れる")


func test_moves_that_leave_own_king_in_check_are_illegal() -> void:
	# 白キング e1、白ルーク a2、黒ルーク e8 — ルークを動かすと王手が残るので a ファイル以外不可
	# より単純: ピン。白キング e1、白ビショップ e2、黒ルーク e8。
	var b := Board.from_fen("4r2k/8/8/8/8/8/4B3/4K3 w - - 0 1")
	for m in b.legal_moves():
		var move := m as Move
		if move.from == Vector2i(4, 1):  # e2 bishop
			check(
				move.to.x == 4,
				"ピンされたビショップは e ファイル以外に動けない (got %s)" % move.to_uci()
			)


func test_castling_only_when_allowed() -> void:
	# 権利あり・経路空き
	var ok := Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var ucis := ok.legal_move_ucis()
	check(ucis.has("e1g1"), "白キングサイドキャスリング可")
	check(ucis.has("e1c1"), "白クイーンサイドキャスリング可")
	var ok_black := Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	var black_ucis := ok_black.legal_move_ucis()
	check(black_ucis.has("e8g8"), "黒キングサイドキャスリング可")
	check(black_ucis.has("e8c8"), "黒クイーンサイドキャスリング可")

	# 経路に駒
	var blocked := Board.from_fen("r3k2r/8/8/8/8/8/8/R2BK2R w KQkq - 0 1")
	var blocked_ucis := blocked.legal_move_ucis()
	check(not blocked_ucis.has("e1c1"), "経路ブロックで后翼不可")
	check(blocked_ucis.has("e1g1"), "王翼は可")

	# 王手中は不可
	var in_check := Board.from_fen("r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1")
	var check_ucis := in_check.legal_move_ucis()
	check(not check_ucis.has("e1g1"), "王手中のキャスリング不可")
	check(not check_ucis.has("e1c1"), "王手中のキャスリング不可")

	# 通過マスが攻撃されている
	var through := Board.from_fen("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	var through_ucis := through.legal_move_ucis()
	check(not through_ucis.has("e1g1"), "f1 が攻撃されているので王翼不可")

	# 権利なし
	var no_rights := Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")
	var no_ucis := no_rights.legal_move_ucis()
	check(not no_ucis.has("e1g1"), "権利なしではキャスリング不可")
	check(not no_ucis.has("e1c1"), "権利なしではキャスリング不可")


func test_castling_moves_rook() -> void:
	var b := Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var castle: Move = null
	for m in b.legal_moves():
		if (m as Move).to_uci() == "e1g1":
			castle = m as Move
			break
	check(castle != null and castle.is_castling, "e1g1 はキャスリング")
	var next := b.apply(castle)
	check_eq(next.piece_at(Vector2i(6, 0)).kind, Piece.Kind.KING, "王は g1")
	check_eq(next.piece_at(Vector2i(5, 0)).kind, Piece.Kind.ROOK, "ルークは f1")
	check(next.piece_at(Vector2i(4, 0)) == null, "e1 は空")
	check(next.piece_at(Vector2i(7, 0)) == null, "h1 は空")


func test_en_passant_only_immediately() -> void:
	# 白 c2-c4 の直後 → 黒は d4xc3 アンパッサン可
	var before := Board.from_fen("4k3/8/8/8/3p4/8/2P5/4K3 w - - 0 1")
	var c2c4: Move = null
	for m in before.legal_moves():
		if (m as Move).to_uci() == "c2c4":
			c2c4 = m as Move
			break
	check(c2c4 != null, "c2c4 が指せる")
	var after_double := before.apply(c2c4)
	check_eq(after_double.en_passant_target, Vector2i(2, 2), "c2c4 直後に EP 対象が c3")
	var ucis := after_double.legal_move_ucis()
	check(ucis.has("d4c3"), "アンパッサン d4c3 が指せる")

	# 別の手を指すと EP が消える
	var quiet: Move = null
	for m in after_double.legal_moves():
		if (m as Move).to_uci() == "e8d8":
			quiet = m as Move
			break
	check(quiet != null, "黒玉 e8d8")
	var after_other := after_double.apply(quiet)
	check_eq(after_other.en_passant_target, Board.NO_SQUARE, "他手の後は EP 対象なし")
	check(not after_other.legal_move_ucis().has("d4c3"), "1 手過ぎるとアンパッサン不可")

	# EP フラグが無いと同じ配置でも不可
	var no_ep := Board.from_fen("4k3/8/8/8/2Pp4/8/8/4K3 b - - 0 1")
	check(not no_ep.legal_move_ucis().has("d4c3"), "EP 対象が無い手番ではアンパッサン不可")

	# 取ったあと相手ポーンが消える
	var ep_move: Move = null
	for m in after_double.legal_moves():
		if (m as Move).to_uci() == "d4c3":
			ep_move = m as Move
			break
	check(ep_move != null and ep_move.is_en_passant, "d4c3 はアンパッサン")
	var next := after_double.apply(ep_move)
	check(next.piece_at(Vector2i(2, 3)) == null, "取られた c4 ポーンが消える")
	check_eq(next.piece_at(Vector2i(2, 2)).kind, Piece.Kind.PAWN, "黒ポーンが c3 に")


func test_pawn_promotes_to_queen() -> void:
	var b := Board.from_fen("4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
	var promo: Move = null
	for m in b.legal_moves():
		var move := m as Move
		if move.from == Vector2i(6, 6) and move.to == Vector2i(6, 7):
			promo = move
			break
	check(promo != null, "g7g8 昇格手が列挙される")
	check_eq(promo.promotion, Piece.Kind.QUEEN, "昇格先はクイーン")
	var next := b.apply(promo)
	check_eq(next.piece_at(Vector2i(6, 7)).kind, Piece.Kind.QUEEN, "g8 にクイーン")
	check_eq(next.piece_at(Vector2i(6, 7)).side, Piece.Side.WHITE, "白のクイーン")


func test_checkmate_position() -> void:
	# 黒玉 h8、白クイーン g7、白玉 f6 — 黒手番で詰み
	var mate := Board.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
	check(mate.is_checkmate(), "チェックメイトと判定")
	check(not mate.is_stalemate(), "ステイルメイトではない")
	check_eq(mate.legal_moves().size(), 0, "合法手なし")


func test_stalemate_position() -> void:
	# 典型的ステイルメイト: 黒玉 a8、白クイーン b6、白玉 c6 — 黒手番
	var stale := Board.from_fen("k7/8/1QK5/8/8/8/8/8 b - - 0 1")
	check(stale.is_stalemate(), "ステイルメイトと判定")
	check(not stale.is_checkmate(), "チェックメイトではない")
	check(not stale.in_check(), "王手はかかっていない")
	check_eq(stale.legal_moves().size(), 0, "合法手なし")


func test_perft_starting_position_depths_1_to_4() -> void:
	var board := Board.chess_start()
	check_eq(board.perft(1), 20, "perft(1)")
	check_eq(board.perft(2), 400, "perft(2)")
	check_eq(board.perft(3), 8902, "perft(3)")
	check_eq(board.perft(4), 197281, "perft(4)")


func test_board_supports_non_8x8_and_hands() -> void:
	var b := Board.empty(9, 9)
	check_eq(b.width, 9, "9 列")
	check_eq(b.height, 9, "9 段")
	check(b.hands.has(Piece.Side.WHITE), "先手持ち駒スロット")
	check(b.hands.has(Piece.Side.BLACK), "後手持ち駒スロット")
	b.hands[Piece.Side.WHITE][Piece.Kind.PAWN] = 2
	var c := b.clone()
	check_eq(c.hands[Piece.Side.WHITE][Piece.Kind.PAWN], 2, "持ち駒が clone される")
	c.hands[Piece.Side.WHITE][Piece.Kind.PAWN] = 0
	check_eq(b.hands[Piece.Side.WHITE][Piece.Kind.PAWN], 2, "clone 後の変更は元に影響しない")
