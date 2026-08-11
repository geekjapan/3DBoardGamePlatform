extends "res://tests/case.gd"

## Issue #25 / D-005 / D-008: GameSession の共通盤境界と任意成り候補。
##
## シーム:
## - GameSession.from_board / board / apply_move / undo
## - legal_moves_to / legal_targets / try_move_to


func test_optional_promotion_is_ambiguous_until_complete_move_is_applied() -> void:
	var board := _promotion_board()
	var session := GameSession.from_board(board)
	check(session.select(Vector2i(4, 5)), "敵陣直前の歩を選択")
	var candidates := session.legal_moves_to(Vector2i(4, 6))
	check_eq(candidates.size(), 2, "同じtoへ成り・不成の完全Moveが2件")
	check_eq(session.legal_targets().size(), 1, "ハイライトは1マスへ重複排除")
	check(not session.try_move_to(Vector2i(4, 6)), "曖昧なクリック着手は拒否")
	check(session.board() == board, "曖昧時に盤参照不変")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "曖昧時に手番不変")
	check_eq(session.selected_square(), Vector2i(4, 5), "曖昧時に選択維持")
	check(session.last_move_event() == null, "曖昧時にイベント不変")
	check(not session.can_undo(), "曖昧時に履歴不変")

	for promotion in [-1, Piece.Kind.SHOGI_PROMOTED_PAWN]:
		var direct := GameSession.from_board(_promotion_board())
		var event := direct.apply_move(Move.new(Vector2i(4, 5), Vector2i(4, 6), promotion))
		check(event != null, "完全Moveなら直接適用")
		check_eq(event.promotion(), promotion, "MoveEvent.promotion")
		var expected_kind: int = Piece.Kind.SHOGI_PAWN if promotion < 0 else promotion
		check_eq(direct.board().piece_at(Vector2i(4, 6)).kind, expected_kind, "選んだ成否を盤へ反映")


func test_forced_promotion_clicks_immediately() -> void:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 7), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
	var session := GameSession.from_board(board)
	check(session.select(Vector2i(4, 7)), "最奥直前の歩を選択")
	check_eq(session.legal_moves_to(Vector2i(4, 8)).size(), 1, "強制成りは1候補")
	check(session.try_move_to(Vector2i(4, 8)), "一意なので即適用")
	check_eq(session.board().piece_at(Vector2i(4, 8)).kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "と金へ成る")
	check_eq(session.last_move_event().promotion(), Piece.Kind.SHOGI_PROMOTED_PAWN, "成りイベント")


func test_shogi_session_two_plies_and_undo_restore_original_board() -> void:
	var original := ShogiBoard.start()
	var session := GameSession.from_board(original)
	check(session.apply_move(Move.new(Vector2i(4, 2), Vector2i(4, 3))) != null, "先手歩")
	check(session.apply_move(Move.new(Vector2i(4, 6), Vector2i(4, 5))) != null, "後手歩")
	check(session.can_undo(), "2プライで待った可能")
	check(session.undo(), "将棋盤も待った成功")
	check(session.board() == original, "履歴の元盤Objectへ復元")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "先手番へ復元")
	check_eq(session.board().piece_at(Vector2i(4, 2)).kind, Piece.Kind.SHOGI_PAWN, "先手歩を復元")
	check_eq(session.board().piece_at(Vector2i(4, 6)).kind, Piece.Kind.SHOGI_PAWN, "後手歩を復元")


func test_apply_move_rechecks_promotion_identity() -> void:
	var board := _promotion_board()
	var session := GameSession.from_board(board)
	var invalid := Move.new(Vector2i(4, 5), Vector2i(4, 6), Piece.Kind.SHOGI_DRAGON)
	check(session.apply_move(invalid) == null, "合法候補に無いpromotionは拒否")
	check(session.board() == board, "不正promotionで盤不変")
	check(session.last_move_event() == null, "不正promotionでイベント不変")


func test_zero_candidate_try_move_keeps_board_history_and_last_event() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	check(session.apply_move(Move.new(Vector2i(4, 2), Vector2i(4, 3))) != null, "先手初手")
	var board_before := session.board()
	var event_before := session.last_move_event()
	check(session.select(Vector2i(4, 6)), "後手歩を選択")
	check(not session.try_move_to(Vector2i(4, 4)), "2マス進む候補は無い")
	check(session.board() == board_before, "0候補で盤不変")
	check(session.last_move_event() == event_before, "0候補でlast event不変")
	check(not session.can_undo(), "0候補で履歴不変")
	check_eq(session.selected_square(), Vector2i(4, 6), "0候補でも選択維持")


func test_board_contract_missing_members_and_invalid_apply_fail_fast() -> void:
	var null_output := _run_contract_probe("null_board")
	check(null_output.contains("GameSession board must not be null"), "null盤をfail-fast")
	check(not null_output.contains("UNEXPECTED_CONTRACT_SUCCESS"), "null盤を受理しない")
	for member in [
		"legal_moves",
		"apply",
		"piece_at",
		"in_check",
		"is_checkmate",
		"is_stalemate",
		"side_to_move",
	]:
		var output := _run_contract_probe(member)
		check(output.contains("GameSession board missing"), "%s 欠落をfail-fast" % member)
		check(output.contains(member), "%s 欠落を具体的に報告" % member)
		check(not output.contains("UNEXPECTED_CONTRACT_SUCCESS"), "%s 欠落を受理しない" % member)
	var invalid_output := _run_contract_probe("invalid_apply")
	check(invalid_output.contains("GameSession board must not be null"), "不正apply返却をfail-fast")
	check(not invalid_output.contains("UNEXPECTED_CONTRACT_SUCCESS"), "不正apply返却を状態へ反映しない")


func _promotion_board() -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 5), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN))
	return board


func _run_contract_probe(mode: String) -> String:
	var output: Array = []
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tests/game_session_contract_probe.gd",
		"--",
		mode,
	])
	OS.execute(OS.get_executable_path(), args, output, true)
	return "\n".join(output)
