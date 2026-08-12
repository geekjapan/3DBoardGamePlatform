extends "res://tests/case.gd"

## D-020 / D-022: GameSession が終局結果と投了を一元管理する。


func test_checkmate_result_has_winner_and_loser() -> void:
	var session := GameSession.from_board(
		Board.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
	)
	var current := session.result()
	check(current != null, "詰み結果がある")
	check_eq(current.reason, GameResult.Reason.CHECKMATE, "詰み理由")
	check_eq(current.winner_side, Piece.Side.WHITE, "詰みの勝者")
	check_eq(current.loser_side, Piece.Side.BLACK, "詰みの敗者")
	check(session.result_text().contains("チェックメイト"), "詰み結果文")
	check(not session.select(Vector2i(7, 7)), "詰み後は入力拒否")


func test_stalemate_result_is_draw() -> void:
	var session := GameSession.from_board(
		Board.from_fen("k7/8/1QK5/8/8/8/8/8 b - - 0 1")
	)
	var current := session.result()
	check(current != null, "ステイルメイト結果がある")
	check_eq(current.reason, GameResult.Reason.STALEMATE, "ステイルメイト理由")
	check_eq(current.winner_side, GameResult.NO_SIDE, "ステイルメイト勝者なし")
	check_eq(current.loser_side, GameResult.NO_SIDE, "ステイルメイト敗者なし")
	check(session.result_text().contains("ステイルメイト"), "ステイルメイト結果文")


func test_resignation_accepts_current_side_and_preserves_state() -> void:
	var session := GameSession.start()
	session.select(Vector2i(4, 1))
	var board_before := session.board()
	var turn_before := session.side_to_move()
	check(session.finish_by_resignation(Piece.Side.WHITE), "現在手番の投了を受理")
	check_eq(session.board(), board_before, "投了で盤面不変")
	check_eq(session.side_to_move(), turn_before, "投了で手番不変")
	check(not session.is_selected(), "投了で選択解除")
	var current := session.result()
	check_eq(current.reason, GameResult.Reason.RESIGN, "投了理由")
	check_eq(current.winner_side, Piece.Side.BLACK, "投了の勝者")
	check_eq(current.loser_side, Piece.Side.WHITE, "投了の敗者")
	check(session.result_text().contains("投了"), "投了結果文")
	check(not session.select(Vector2i(4, 1)), "投了後は入力拒否")
	check(not session.apply_move(Move.new(Vector2i(4, 1), Vector2i(4, 2))), "投了後は直接着手拒否")


func test_resignation_rejects_invalid_side_wrong_turn_and_duplicate() -> void:
	var session := GameSession.start()
	check(not session.finish_by_resignation(GameResult.NO_SIDE), "無効 side の投了を拒否")
	check(not session.finish_by_resignation(Piece.Side.BLACK), "手番違いの投了を拒否")
	check(session.result() == null, "拒否後は進行中")
	check(session.finish_by_resignation(Piece.Side.WHITE), "正しい投了を受理")
	check(not session.finish_by_resignation(Piece.Side.WHITE), "重複投了を拒否")
	check(not session.finish_by_resignation(Piece.Side.BLACK), "終局後の反対側投了を拒否")


func test_undo_zero_or_one_ply_preserves_resignation() -> void:
	var zero := GameSession.start()
	check(zero.finish_by_resignation(Piece.Side.WHITE), "0プライ投了")
	check(not zero.undo(), "履歴0の undo は失敗")
	check(zero.result() != null, "履歴0の失敗 undo は投了維持")

	var one := GameSession.start()
	check(one.apply_move(_legal_move(one, "e2e4")) != null, "1プライを着手")
	check(one.finish_by_resignation(Piece.Side.BLACK), "1プライ投了")
	check(not one.undo(), "履歴1の undo は失敗")
	check(one.result() != null, "履歴1の失敗 undo は投了維持")


func test_successful_two_ply_undo_clears_resignation_and_restores_state() -> void:
	var session := GameSession.start()
	check(session.apply_move(_legal_move(session, "e2e4")) != null, "白の着手")
	check(session.apply_move(_legal_move(session, "e7e5")) != null, "黒の着手")
	check(session.finish_by_resignation(Piece.Side.WHITE), "2プライ後の投了")
	check(session.result() != null, "undo 前は投了中")
	check(session.undo(), "2プライ undo 成功")
	check(session.result() == null, "成功 undo は外部結果を解除")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "undo 後は白手番")
	check(session.board().piece_at(Vector2i(4, 1)) != null, "白ポーン復元")
	check(session.board().piece_at(Vector2i(4, 3)) == null, "白ポーン移動先を復元")
	check(session.board().piece_at(Vector2i(4, 6)) != null, "黒ポーン復元")
	check(session.board().piece_at(Vector2i(4, 4)) == null, "黒ポーン移動先を復元")


func test_shogi_fourfold_repetition_is_a_dedicated_draw_result() -> void:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	var session := GameSession.from_board(board)
	var cycle := [
		Move.new(Vector2i(0, 0), Vector2i(1, 0)),
		Move.new(Vector2i(8, 8), Vector2i(7, 8)),
		Move.new(Vector2i(1, 0), Vector2i(0, 0)),
		Move.new(Vector2i(7, 8), Vector2i(8, 8)),
	]
	var final_event: MoveEvent = null
	for repetition in range(3):
		for move in cycle:
			final_event = session.apply_move(move as Move)
			check(final_event != null, "通常反復 cycle=%d の合法手" % repetition)
		if repetition < 2:
			check(not session.is_over(), "%d 回目の同一局面では継続" % (repetition + 2))
	var current := session.result()
	check(current != null, "4 回目の同一局面で終局")
	check_eq(current.reason, GameResult.Reason.SENNICHITE, "千日手専用理由")
	check_eq(current.winner_side, GameResult.NO_SIDE, "通常千日手は勝者なし")
	check_eq(current.loser_side, GameResult.NO_SIDE, "通常千日手は敗者なし")
	check(session.result_text().contains("千日手"), "千日手結果文")
	check(final_event != null and final_event.is_over, "終端 MoveEvent は game over")


func test_shogi_continuous_check_repetition_loses_for_the_checking_side() -> void:
	for checking_side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var session_and_cycle := _continuous_check_session(checking_side)
		var session: GameSession = session_and_cycle["session"]
		var cycle: Array = session_and_cycle["cycle"]
		for repetition in range(3):
			for move in cycle:
				check(
					session.apply_move(move as Move) != null,
					"連続王手 side=%d cycle=%d の合法手" % [checking_side, repetition],
				)
		var current := session.result()
		check(current != null, "連続王手の4回同一局面で終局 side=%d" % checking_side)
		check_eq(current.reason, GameResult.Reason.SENNICHITE, "連続王手も千日手理由")
		check_eq(current.loser_side, checking_side, "王手を続けた側が反則負け")
		check_eq(current.winner_side, Piece.opposite(checking_side), "反対側が勝者")
		check(session.result_text().contains("連続王手"), "通常千日手と異なる結果文")


func test_chess_repetition_does_not_use_shogi_sennichite_result() -> void:
	var session := GameSession.from_board(
		Board.from_fen("1n2k3/8/8/8/8/8/8/1N2K3 w - - 0 1")
	)
	var cycle := [
		"b1a3",
		"b8a6",
		"a3b1",
		"a6b8",
	]
	for repetition in range(3):
		for uci in cycle:
			check(session.apply_move(_legal_move(session, uci)) != null, "chess repetition %s" % uci)
	check(not session.is_over(), "chess の既存反復挙動は変更しない")
	check(session.result() == null, "chess に千日手を適用しない")


func _continuous_check_session(checking_side: int) -> Dictionary:
	var board := ShogiBoard.empty()
	if checking_side == Piece.Side.WHITE:
		board.side_to_move = Piece.Side.WHITE
		board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
		board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
		board.set_piece(Vector2i(5, 7), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
		return {
			"session": GameSession.from_board(board),
			"cycle": [
				Move.new(Vector2i(5, 7), Vector2i(4, 7)),
				Move.new(Vector2i(4, 8), Vector2i(5, 8)),
				Move.new(Vector2i(4, 7), Vector2i(5, 7)),
				Move.new(Vector2i(5, 8), Vector2i(4, 8)),
			],
		}
	board.side_to_move = Piece.Side.BLACK
	board.set_piece(Vector2i(4, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(5, 1), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	return {
		"session": GameSession.from_board(board),
		"cycle": [
			Move.new(Vector2i(5, 1), Vector2i(4, 1)),
			Move.new(Vector2i(4, 0), Vector2i(5, 0)),
			Move.new(Vector2i(4, 1), Vector2i(5, 1)),
			Move.new(Vector2i(5, 0), Vector2i(4, 0)),
		],
	}


func _legal_move(session: GameSession, uci: String) -> Move:
	for candidate in session.board().legal_moves():
		var move := candidate as Move
		if move.to_uci() == uci:
			return move
	return null
