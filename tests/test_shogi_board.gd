extends "res://tests/case.gd"

## Issue #25: 将棋ルールエンジン。
##
## シーム:
## - ShogiBoard.legal_moves / apply / piece_at / in_check / is_checkmate / is_stalemate
## - GameSession の Board / ShogiBoard 共通盤境界


func test_starting_position_is_9x9_with_30_legal_moves() -> void:
	var board := ShogiBoard.start()
	check_eq(board.width, 9, "盤幅")
	check_eq(board.height, 9, "盤高")
	check_eq(board._squares.size(), 81, "一次元81要素")
	check_eq(board.side_to_move, Piece.Side.WHITE, "先手から開始")
	check_eq(board.piece_at(Vector2i(4, 0)).kind, Piece.Kind.SHOGI_KING, "先手玉")
	check_eq(board.piece_at(Vector2i(1, 1)).kind, Piece.Kind.SHOGI_BISHOP, "先手角")
	check_eq(board.piece_at(Vector2i(7, 1)).kind, Piece.Kind.SHOGI_ROOK, "先手飛")
	check_eq(board.piece_at(Vector2i(4, 8)).kind, Piece.Kind.SHOGI_KING, "後手玉")
	check_eq(board.piece_at(Vector2i(1, 7)).kind, Piece.Kind.SHOGI_ROOK, "後手飛")
	check_eq(board.piece_at(Vector2i(7, 7)).kind, Piece.Kind.SHOGI_BISHOP, "後手角")
	check_eq(board.legal_moves().size(), 30, "初期合法手")


func test_promotion_zone_move_has_complete_promoted_and_unpromoted_candidates() -> void:
	var white := ShogiBoard.empty()
	white.set_piece(Vector2i(4, 5), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
	var white_moves := _moves_from_to(white, Vector2i(4, 5), Vector2i(4, 6))
	check_eq(white_moves.size(), 2, "先手が敵陣へ入る歩は2候補")
	check(_has_promotion(white_moves, -1), "先手歩の不成")
	check(_has_promotion(white_moves, Piece.Kind.SHOGI_PROMOTED_PAWN), "先手歩の成り")

	var black := ShogiBoard.empty()
	black.side_to_move = Piece.Side.BLACK
	black.set_piece(Vector2i(4, 3), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_PAWN))
	var black_moves := _moves_from_to(black, Vector2i(4, 3), Vector2i(4, 2))
	check_eq(black_moves.size(), 2, "後手が敵陣へ入る歩は2候補")
	check(_has_promotion(black_moves, -1), "後手歩の不成")
	check(_has_promotion(black_moves, Piece.Kind.SHOGI_PROMOTED_PAWN), "後手歩の成り")


func test_check_and_legal_moves_filter_pins_and_king_danger() -> void:
	var checked := ShogiBoard.empty()
	checked.set_piece(Vector2i(4, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	checked.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_SILVER))
	checked.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	checked.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	check(checked.in_check(Piece.Side.WHITE), "飛車の縦利きで先手玉が王手")
	for candidate in checked.legal_moves():
		var move := candidate as Move
		check(move.from == Vector2i(4, 0), "王手中に無関係な駒は動かせない")
		check(move.to.x != 4, "玉は飛車の利きが残る筋へ動けない")

	var pinned := ShogiBoard.empty()
	pinned.set_piece(Vector2i(4, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	pinned.set_piece(Vector2i(4, 1), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_GOLD))
	pinned.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	pinned.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	check(not pinned.in_check(Piece.Side.WHITE), "遮蔽中は王手ではない")
	for candidate in pinned.legal_moves():
		var move := candidate as Move
		if move.from == Vector2i(4, 1):
			check_eq(move.to.x, 4, "ピンされた金は飛車筋を開けない")


func test_all_fourteen_kinds_move_for_both_sides() -> void:
	var expected := {
		Piece.Kind.SHOGI_PAWN: 1,
		Piece.Kind.SHOGI_LANCE: 4,
		Piece.Kind.SHOGI_KNIGHT: 2,
		Piece.Kind.SHOGI_SILVER: 5,
		Piece.Kind.SHOGI_GOLD: 6,
		Piece.Kind.SHOGI_BISHOP: 16,
		Piece.Kind.SHOGI_ROOK: 16,
		Piece.Kind.SHOGI_KING: 8,
		Piece.Kind.SHOGI_PROMOTED_PAWN: 6,
		Piece.Kind.SHOGI_PROMOTED_LANCE: 6,
		Piece.Kind.SHOGI_PROMOTED_KNIGHT: 6,
		Piece.Kind.SHOGI_PROMOTED_SILVER: 6,
		Piece.Kind.SHOGI_HORSE: 20,
		Piece.Kind.SHOGI_DRAGON: 20,
	}
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		for kind in expected:
			var board := ShogiBoard.empty()
			board.side_to_move = side
			var from := Vector2i(4, 4)
			board.set_piece(from, Piece.new(side, kind))
			check_eq(
				_unique_targets(_moves_from(board, from)).size(),
				int(expected[kind]),
				"side=%d kind=%d の中央移動数" % [side, kind]
			)


func test_sliders_capture_enemy_and_stop_at_all_blockers() -> void:
	var board := ShogiBoard.empty()
	var from := Vector2i(4, 4)
	board.set_piece(from, Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
	board.set_piece(Vector2i(4, 2), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_SILVER))
	board.set_piece(Vector2i(4, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_GOLD))
	var targets := _targets(_moves_from(board, from))
	check(targets.has(Vector2i(4, 2)), "敵駒は取れる")
	check(not targets.has(Vector2i(4, 1)), "敵駒を通過しない")
	check(not targets.has(Vector2i(4, 6)), "自駒マスへ進まない")
	check(not targets.has(Vector2i(4, 7)), "自駒を通過しない")


func test_forced_promotion_removes_dead_unpromoted_candidates() -> void:
	var cases := [
		_promotion_case(
			Piece.Side.WHITE,
			Piece.Kind.SHOGI_PAWN,
			Vector2i(2, 7),
			Vector2i(2, 8),
			Piece.Kind.SHOGI_PROMOTED_PAWN
		),
		_promotion_case(
			Piece.Side.WHITE,
			Piece.Kind.SHOGI_LANCE,
			Vector2i(3, 7),
			Vector2i(3, 8),
			Piece.Kind.SHOGI_PROMOTED_LANCE
		),
		_promotion_case(
			Piece.Side.WHITE,
			Piece.Kind.SHOGI_KNIGHT,
			Vector2i(4, 5),
			Vector2i(3, 7),
			Piece.Kind.SHOGI_PROMOTED_KNIGHT
		),
		_promotion_case(
			Piece.Side.BLACK,
			Piece.Kind.SHOGI_PAWN,
			Vector2i(2, 1),
			Vector2i(2, 0),
			Piece.Kind.SHOGI_PROMOTED_PAWN
		),
		_promotion_case(
			Piece.Side.BLACK,
			Piece.Kind.SHOGI_LANCE,
			Vector2i(3, 1),
			Vector2i(3, 0),
			Piece.Kind.SHOGI_PROMOTED_LANCE
		),
		_promotion_case(
			Piece.Side.BLACK,
			Piece.Kind.SHOGI_KNIGHT,
			Vector2i(4, 3),
			Vector2i(3, 1),
			Piece.Kind.SHOGI_PROMOTED_KNIGHT
		),
	]
	for case in cases:
		var board := ShogiBoard.empty()
		board.side_to_move = int(case["side"])
		board.set_piece(case["from"], Piece.new(case["side"], case["kind"]))
		var moves := _moves_from_to(board, case["from"], case["to"])
		check_eq(moves.size(), 1, "行き所のない駒は強制成り")
		check_eq((moves[0] as Move).promotion, case["promotion"], "固定された成駒Kind")


func test_promotion_applies_when_entering_leaving_or_moving_inside_zone_only() -> void:
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var inside_y := 6 if side == Piece.Side.WHITE else 2
		var deeper_y := 7 if side == Piece.Side.WHITE else 1
		var outside_y := 5 if side == Piece.Side.WHITE else 3
		var board := ShogiBoard.empty()
		board.side_to_move = side
		board.set_piece(Vector2i(4, inside_y), Piece.new(side, Piece.Kind.SHOGI_SILVER))
		check_eq(_moves_from_to(board, Vector2i(4, inside_y), Vector2i(4, deeper_y)).size(), 2, "敵陣内")
		check_eq(_moves_from_to(board, Vector2i(4, inside_y), Vector2i(3, outside_y)).size(), 2, "敵陣から出る")

	for kind in [
		Piece.Kind.SHOGI_GOLD,
		Piece.Kind.SHOGI_KING,
		Piece.Kind.SHOGI_PROMOTED_PAWN,
		Piece.Kind.SHOGI_HORSE,
	]:
		var board := ShogiBoard.empty()
		board.set_piece(Vector2i(4, 6), Piece.new(Piece.Side.WHITE, kind))
		for move in _moves_from(board, Vector2i(4, 6)):
			check_eq((move as Move).promotion, -1, "成れない/既成駒 kind=%d は再成りしない" % kind)


func test_in_check_uses_every_piece_attack_for_both_sides() -> void:
	var kinds := [
		Piece.Kind.SHOGI_PAWN,
		Piece.Kind.SHOGI_LANCE,
		Piece.Kind.SHOGI_KNIGHT,
		Piece.Kind.SHOGI_SILVER,
		Piece.Kind.SHOGI_GOLD,
		Piece.Kind.SHOGI_BISHOP,
		Piece.Kind.SHOGI_ROOK,
		Piece.Kind.SHOGI_KING,
		Piece.Kind.SHOGI_PROMOTED_PAWN,
		Piece.Kind.SHOGI_PROMOTED_LANCE,
		Piece.Kind.SHOGI_PROMOTED_KNIGHT,
		Piece.Kind.SHOGI_PROMOTED_SILVER,
		Piece.Kind.SHOGI_HORSE,
		Piece.Kind.SHOGI_DRAGON,
	]
	for attacker_side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var checked_side := Piece.opposite(attacker_side)
		for kind in kinds:
			var board := ShogiBoard.empty()
			board.set_piece(Vector2i(4, 4), Piece.new(checked_side, Piece.Kind.SHOGI_KING))
			board.set_piece(_attack_origin(kind, attacker_side), Piece.new(attacker_side, kind))
			check(board.in_check(checked_side), "side=%d kind=%d の利き" % [attacker_side, kind])


func test_capture_demotes_into_hand_and_apply_is_deeply_immutable() -> void:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 4), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
	board.set_piece(Vector2i(4, 5), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_PROMOTED_PAWN))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 2

	var next := board.apply(Move.new(Vector2i(4, 4), Vector2i(4, 5)))
	check_eq(next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN], 1, "と金は歩へ戻って先手持ち駒")
	check_eq(next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER], 2, "既存持ち駒数をコピー")
	check_eq(next.piece_at(Vector2i(4, 5)).side, Piece.Side.WHITE, "取った駒位置は先手飛車")
	check_eq(next.side_to_move, Piece.Side.BLACK, "手番反転")
	check_eq(board.side_to_move, Piece.Side.WHITE, "元手番不変")
	check_eq(board.piece_at(Vector2i(4, 4)).kind, Piece.Kind.SHOGI_ROOK, "元盤の飛車不変")
	check_eq(board.piece_at(Vector2i(4, 5)).kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "元盤のと金不変")
	check(board.piece_at(Vector2i(0, 0)) != next.piece_at(Vector2i(0, 0)), "先手玉Pieceを複製")
	check(board.piece_at(Vector2i(8, 8)) != next.piece_at(Vector2i(8, 8)), "後手玉Pieceを複製")

	next.piece_at(Vector2i(0, 0)).kind = Piece.Kind.SHOGI_GOLD
	next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 99
	check_eq(board.piece_at(Vector2i(0, 0)).kind, Piece.Kind.SHOGI_KING, "全Pieceを共有しない")
	check_eq(board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER], 2, "内側辞書を共有しない")
	next.hands[Piece.Side.BLACK][Piece.Kind.SHOGI_PAWN] = 7
	check(not board.hands[Piece.Side.BLACK].has(Piece.Kind.SHOGI_PAWN), "両陣営辞書を共有しない")
	next.hands[99] = {}
	check(not board.hands.has(99), "外側辞書を共有しない")
	next._squares[0] = null
	check(board.piece_at(Vector2i(0, 0)) != null, "81要素配列を共有しない")
	check_eq(next._squares.size(), 81, "返却盤も81要素")

	for promoted_kind in Piece.PROMOTED_TO_BASE:
		var capture_board := ShogiBoard.empty()
		capture_board.set_piece(Vector2i(4, 4), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
		capture_board.set_piece(Vector2i(4, 5), Piece.new(Piece.Side.BLACK, promoted_kind))
		var captured := capture_board.apply(Move.new(Vector2i(4, 4), Vector2i(4, 5)))
		var base_kind: int = Piece.PROMOTED_TO_BASE[promoted_kind]
		check_eq(captured.hands[Piece.Side.WHITE][base_kind], 1, "成駒%dは元駒%dで持ち駒" % [promoted_kind, base_kind])


func test_move_drop_factory_and_identity_include_drop_kind() -> void:
	var to := Vector2i(4, 4)
	var pawn := Move.drop(Piece.Kind.SHOGI_PAWN, to)
	var silver := Move.drop(Piece.Kind.SHOGI_SILVER, to)
	check_eq(pawn.from, Move.NO_SQUARE, "打つ手from")
	check_eq(pawn.to, to, "打つ手to")
	check(pawn.is_drop, "打つ手flag")
	check_eq(pawn.drop_kind, Piece.Kind.SHOGI_PAWN, "打つ駒Kind")
	check_eq(pawn.promotion, -1, "打つ手は成らない")
	check(not pawn.is_castling and not pawn.is_en_passant, "チェス特殊手ではない")
	check(not pawn.equals(silver), "同じtoでも異なるdrop_kindは別Move")
	check(pawn.equals(Move.drop(Piece.Kind.SHOGI_PAWN, to)), "同じ打つ手は一致")
	check_eq(Move.new(Vector2i(1, 1), to).drop_kind, -1, "通常手のdrop_kind既定値")


func test_drop_applies_immutably_and_decrements_exact_hand_kind() -> void:
	var board := _valid_empty_board()
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 2
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 1
	var move := Move.drop(Piece.Kind.SHOGI_SILVER, Vector2i(4, 4))
	check(_has_drop(board, move.drop_kind, move.to), "銀打ちが合法手にある")
	var next := board.apply(move)
	check_eq(next.piece_at(move.to).side, Piece.Side.WHITE, "自軍色で出現")
	check_eq(next.piece_at(move.to).kind, Piece.Kind.SHOGI_SILVER, "選んだ銀が出現")
	check_eq(next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER], 1, "銀だけ1枚減る")
	check_eq(next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD], 1, "金は不変")
	check_eq(next.side_to_move, Piece.Side.BLACK, "手番反転")
	check(board.piece_at(move.to) == null, "元盤は空のまま")
	check_eq(board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER], 2, "元の持ち駒不変")
	next.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 99
	check_eq(board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD], 1, "hands深い不変性")


func test_pawn_drop_rejects_nifu_but_promoted_pawn_does_not_count() -> void:
	var board := _valid_empty_board()
	board.set_piece(Vector2i(4, 2), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 1
	check(not _has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, 4)), "同じ筋の二歩を除外")
	check(_has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(3, 4)), "別筋には歩を打てる")

	var promoted := _valid_empty_board()
	promoted.set_piece(Vector2i(4, 2), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PROMOTED_PAWN))
	promoted.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 1
	check(_has_drop(promoted, Piece.Kind.SHOGI_PAWN, Vector2i(4, 4)), "と金は二歩に数えない")


func test_pawn_lance_and_knight_drop_reject_dead_ranks_for_both_sides() -> void:
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var board := _valid_empty_board()
		board.side_to_move = side
		for kind in [Piece.Kind.SHOGI_PAWN, Piece.Kind.SHOGI_LANCE, Piece.Kind.SHOGI_KNIGHT]:
			board.hands[side][kind] = 1
		var last := 8 if side == Piece.Side.WHITE else 0
		var second := 7 if side == Piece.Side.WHITE else 1
		check(not _has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, last)), "歩の最奥 side=%d" % side)
		check(not _has_drop(board, Piece.Kind.SHOGI_LANCE, Vector2i(4, last)), "香の最奥 side=%d" % side)
		check(not _has_drop(board, Piece.Kind.SHOGI_KNIGHT, Vector2i(4, last)), "桂の最奥 side=%d" % side)
		check(not _has_drop(board, Piece.Kind.SHOGI_KNIGHT, Vector2i(4, second)), "桂の最後2段 side=%d" % side)
		var safe_rank := 6 if side == Piece.Side.WHITE else 2
		check(_has_drop(board, Piece.Kind.SHOGI_KNIGHT, Vector2i(4, safe_rank)), "桂の安全段 side=%d" % side)


func test_drop_that_leaves_own_king_in_check_is_illegal() -> void:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(4, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 1
	check(not _has_drop(board, Piece.Kind.SHOGI_GOLD, Vector2i(0, 4)), "王手を放置する打ちは除外")
	check(_has_drop(board, Piece.Kind.SHOGI_GOLD, Vector2i(4, 4)), "王手を遮る打ちは合法")


func test_pawn_drop_mate_is_illegal() -> void:
	var board := _pawn_drop_cage(true)
	check(not _has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, 7)), "打ち歩詰めを除外")


func test_pawn_drop_check_with_escape_square_is_legal() -> void:
	var board := _pawn_drop_cage(false)
	check(_has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, 7)), "逃げ道があれば歩打ち可")


func test_pawn_drop_check_capturable_by_king_is_legal() -> void:
	var board := _valid_empty_board()
	board.set_piece(Vector2i(8, 8), null)
	board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 1
	check(_has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, 7)), "玉で取れる歩打ちは合法")


func test_pawn_drop_check_capturable_by_other_piece_is_legal() -> void:
	var board := _pawn_drop_cage(true)
	board.set_piece(Vector2i(3, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_GOLD))
	check(_has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(4, 7)), "別駒で取れる歩打ちは合法")


func test_nonchecking_pawn_drop_is_not_subject_to_mate_probe() -> void:
	var board := _pawn_drop_cage(true)
	check(_has_drop(board, Piece.Kind.SHOGI_PAWN, Vector2i(0, 4)), "非王手の歩打ちは合法")


func test_non_pawn_mating_drop_is_legal() -> void:
	var board := _pawn_drop_cage(true)
	board.hands[Piece.Side.WHITE].erase(Piece.Kind.SHOGI_PAWN)
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 1
	check(_has_drop(board, Piece.Kind.SHOGI_GOLD, Vector2i(4, 7)), "歩以外の詰み打ちは合法")


func test_checkmate_and_shogi_never_stalemates() -> void:
	var mate := ShogiBoard.empty()
	mate.side_to_move = Piece.Side.BLACK
	mate.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	mate.set_piece(Vector2i(0, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
	mate.set_piece(Vector2i(2, 7), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	check(mate.in_check(), "後手玉は王手")
	check_eq(mate.legal_moves().size(), 0, "応手なし")
	check(mate.is_checkmate(), "詰み")
	check(not mate.is_stalemate(), "詰みはステイルメイトではない")
	check(not ShogiBoard.empty().is_stalemate(), "合法手なしでも将棋はステイルメイトにしない")


func test_perft_starting_position_depths_1_to_3() -> void:
	var board := ShogiBoard.start()
	check_eq(board.perft(1), 30, "shogi perft(1)")
	check_eq(board.perft(2), 900, "shogi perft(2)")
	check_eq(board.perft(3), 25470, "shogi perft(3)")


func _moves_from_to(board: ShogiBoard, from: Vector2i, to: Vector2i) -> Array:
	var found: Array = []
	for candidate in board.legal_moves():
		var move := candidate as Move
		if move.from == from and move.to == to:
			found.append(move)
	return found


func _moves_from(board: ShogiBoard, from: Vector2i) -> Array:
	var found: Array = []
	for candidate in board.legal_moves():
		var move := candidate as Move
		if move.from == from:
			found.append(move)
	return found


func _targets(moves: Array) -> Array:
	var found: Array = []
	for candidate in moves:
		found.append((candidate as Move).to)
	return found


func _unique_targets(moves: Array) -> Array:
	var found: Array = []
	for candidate in moves:
		var to := (candidate as Move).to
		if not found.has(to):
			found.append(to)
	return found


func _has_promotion(moves: Array, promotion: int) -> bool:
	for candidate in moves:
		if (candidate as Move).promotion == promotion:
			return true
	return false


func _has_drop(board: ShogiBoard, kind: int, to: Vector2i) -> bool:
	for candidate in board.legal_moves():
		var move := candidate as Move
		if move.is_drop and move.drop_kind == kind and move.to == to:
			return true
	return false


func _valid_empty_board() -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	return board


func _pawn_drop_cage(cover_left_escape: bool) -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(4, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	if cover_left_escape:
		board.set_piece(Vector2i(3, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_LANCE))
	board.set_piece(Vector2i(5, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_LANCE))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 1
	return board


func _attack_origin(kind: int, side: int) -> Vector2i:
	var forward := 1 if side == Piece.Side.WHITE else -1
	match kind:
		Piece.Kind.SHOGI_PAWN:
			return Vector2i(4, 4 - forward)
		Piece.Kind.SHOGI_LANCE, Piece.Kind.SHOGI_ROOK, Piece.Kind.SHOGI_DRAGON:
			return Vector2i(4, 4 - 3 * forward)
		Piece.Kind.SHOGI_KNIGHT:
			return Vector2i(3, 4 - 2 * forward)
		Piece.Kind.SHOGI_BISHOP, Piece.Kind.SHOGI_HORSE:
			return Vector2i(1, 1)
		_:
			return Vector2i(3, 4 - forward)


func _promotion_case(
	side: int,
	kind: int,
	from: Vector2i,
	to: Vector2i,
	promotion: int,
) -> Dictionary:
	return {
		"side": side,
		"kind": kind,
		"from": from,
		"to": to,
		"promotion": promotion,
	}
