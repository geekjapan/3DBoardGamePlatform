extends "res://tests/case.gd"

## Issue #17: 着手イベントの発行と駒ノードの同一性維持(prefactor)。
##
## シーム:
## - GameSession.apply_move / last_move_event: 選択なし着手と観測可能な結果
## - BoardView.sync_pieces: 駒ノードの再利用・取り・成り・特殊手・待った
##
## 見た目の質・操作感は手動確認(対局の挙動は変えない prefactor)。


func test_piece_node_identity_preserved_across_move() -> void:
	var session := GameSession.start()
	var view := BoardView.new()
	view.build_from(session.board())

	var e2_before := view.piece_node_at(Vector2i(4, 1))
	check(e2_before != null, "e2 にポーンがある")
	var id_before := e2_before.get_instance_id()

	session.select(Vector2i(4, 1))
	check(session.try_move_to(Vector2i(4, 3)), "e2e4")
	view.apply_board(session.board())

	check(view.piece_node_at(Vector2i(4, 1)) == null, "移動元は空")
	var e4 := view.piece_node_at(Vector2i(4, 3))
	check(e4 != null, "e4 にポーン")
	check_eq(e4.get_instance_id(), id_before, "移動した駒は同一インスタンス")
	check(is_instance_valid(e2_before), "元ノードはまだ生きている")
	check_eq(view.piece_count(), 32, "駒数は変わらない")
	view.free()


func test_capture_removes_only_captured_node() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())

	var knight := view.piece_node_at(Vector2i(2, 2))
	var pawn := view.piece_node_at(Vector2i(1, 4))
	var king_w := view.piece_node_at(Vector2i(4, 0))
	var king_b := view.piece_node_at(Vector2i(4, 7))
	var knight_id := knight.get_instance_id()
	var pawn_id := pawn.get_instance_id()
	var kw_id := king_w.get_instance_id()
	var kb_id := king_b.get_instance_id()

	session.select(Vector2i(2, 2))
	check(session.try_move_to(Vector2i(1, 4)), "c3b5 取り")
	view.apply_board(session.board())

	check_eq(view.piece_count(), 3, "取られた 1 駒だけ減る")
	var at_b5 := view.piece_node_at(Vector2i(1, 4))
	check(at_b5 != null, "b5 にナイト")
	check_eq(at_b5.get_instance_id(), knight_id, "ナイト同一")
	check(not is_instance_valid(pawn), "取られたポーンノードは破棄")
	check_eq(view.piece_node_at(Vector2i(4, 0)).get_instance_id(), kw_id, "白王同一")
	check_eq(view.piece_node_at(Vector2i(4, 7)).get_instance_id(), kb_id, "黒王同一")
	check_eq(pawn_id, pawn_id, "参照保持")  # 未使用警告避け
	view.free()


func test_promotion_keeps_node_and_swaps_appearance() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())

	var pawn := view.piece_node_at(Vector2i(6, 6))
	var pawn_id := pawn.get_instance_id()
	check_eq(pawn.piece_kind, Piece.Kind.PAWN, "成り前はポーン")

	session.select(Vector2i(6, 6))
	check(session.try_move_to(Vector2i(6, 7)), "g7g8 昇格")
	view.apply_board(session.board())

	var queen := view.piece_node_at(Vector2i(6, 7))
	check(queen != null, "g8 に駒")
	check_eq(queen.get_instance_id(), pawn_id, "成り後も同一ノード")
	check_eq(queen.piece_kind, Piece.Kind.QUEEN, "kind がクイーン")
	check(queen.has_model(), "見た目あり")
	var visual := queen.model_slot().get_child(0)
	check_eq(visual.get_meta(PlaceholderVisual.META_KIND), Piece.Kind.QUEEN, "見た目メタがクイーン")
	view.free()


func test_castling_keeps_king_and_rook_identity() -> void:
	var session := GameSession.from_board(
		Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())

	var king := view.piece_node_at(Vector2i(4, 0))
	var rook := view.piece_node_at(Vector2i(7, 0))
	var king_id := king.get_instance_id()
	var rook_id := rook.get_instance_id()

	session.select(Vector2i(4, 0))
	check(session.try_move_to(Vector2i(6, 0)), "王翼キャスリング")
	view.apply_board(session.board())

	check_eq(view.piece_node_at(Vector2i(6, 0)).get_instance_id(), king_id, "王同一 g1")
	check_eq(view.piece_node_at(Vector2i(5, 0)).get_instance_id(), rook_id, "ルーク同一 f1")
	check(view.piece_node_at(Vector2i(4, 0)) == null, "e1 空")
	check(view.piece_node_at(Vector2i(7, 0)) == null, "h1 空")
	_assert_view_matches_board(view, session.board(), "キャスリング後")
	view.free()


func test_en_passant_keeps_mover_and_removes_captured() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/3p4/8/2P5/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())

	session.select(Vector2i(2, 1))
	session.try_move_to(Vector2i(2, 3))  # c2c4
	view.apply_board(session.board())

	var black_pawn := view.piece_node_at(Vector2i(3, 3))
	var white_pawn := view.piece_node_at(Vector2i(2, 3))
	var black_id := black_pawn.get_instance_id()
	var white_id := white_pawn.get_instance_id()

	session.select(Vector2i(3, 3))
	check(session.try_move_to(Vector2i(2, 2)), "d4xc3 e.p.")
	view.apply_board(session.board())

	check_eq(view.piece_node_at(Vector2i(2, 2)).get_instance_id(), black_id, "黒ポーン同一")
	check(not is_instance_valid(white_pawn), "取られた白ポーン破棄")
	check(view.piece_node_at(Vector2i(2, 3)) == null, "c4 空")
	check_eq(white_id, white_id, "参照")
	_assert_view_matches_board(view, session.board(), "アンパッサン後")
	view.free()


func test_undo_preserves_piece_board_correspondence() -> void:
	var session := GameSession.start()
	var view := BoardView.new()
	view.build_from(session.board())

	var e2 := view.piece_node_at(Vector2i(4, 1))
	var e7 := view.piece_node_at(Vector2i(4, 6))
	var e2_id := e2.get_instance_id()
	var e7_id := e7.get_instance_id()

	session.select(Vector2i(4, 1))
	session.try_move_to(Vector2i(4, 3))
	view.apply_board(session.board())
	session.select(Vector2i(4, 6))
	session.try_move_to(Vector2i(4, 4))
	view.apply_board(session.board())

	check(session.undo(), "待った")
	view.apply_board(session.board())

	check_eq(view.piece_node_at(Vector2i(4, 1)).get_instance_id(), e2_id, "待った後 e2 同一")
	check_eq(view.piece_node_at(Vector2i(4, 6)).get_instance_id(), e7_id, "待った後 e7 同一")
	check(view.piece_node_at(Vector2i(4, 3)) == null, "e4 クリア")
	check(view.piece_node_at(Vector2i(4, 4)) == null, "e5 クリア")
	_assert_view_matches_board(view, session.board(), "待った後")
	view.free()


func test_move_event_exposes_from_to_capture_promo_check_result() -> void:
	# 取り + 王手
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/8/4r3/4K3 b - - 0 1")
	)
	# 黒ルーク e2 が白王 e1 を取るとチェックメイトではないが… 別局面で確認
	# まず通常取り
	session = GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	session.select(Vector2i(2, 2))
	check(session.try_move_to(Vector2i(1, 4)), "取り")
	var ev := session.last_move_event()
	check(ev != null, "イベントあり")
	check_eq(ev.from_square(), Vector2i(2, 2), "from")
	check_eq(ev.to_square(), Vector2i(1, 4), "to")
	check(ev.was_capture(), "取り")
	check_eq(ev.captured.kind, Piece.Kind.PAWN, "取ったのはポーン")
	check_eq(ev.captured.side, Piece.Side.BLACK, "黒")
	check_eq(ev.captured_square, Vector2i(1, 4), "取りマス")
	check(not ev.was_promotion(), "成りではない")
	check(not ev.is_over, "未終局")

	# 成り
	session = GameSession.from_board(
		Board.from_fen("4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
	)
	session.select(Vector2i(6, 6))
	session.try_move_to(Vector2i(6, 7))
	ev = session.last_move_event()
	check(ev.was_promotion(), "成り")
	check_eq(ev.promotion(), Piece.Kind.QUEEN, "クイーン成り")
	check_eq(ev.mover_kind, Piece.Kind.PAWN, "成り前はポーン")

	# 王手(メイトではない)
	session = GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1")
	)
	session.select(Vector2i(4, 1))
	session.try_move_to(Vector2i(4, 6))  # Qe2e7+
	ev = session.last_move_event()
	check(ev != null, "イベント")
	check(ev.is_check, "王手")
	check(not ev.is_checkmate, "メイトではない")
	check(not ev.is_over, "続行可")

	# 決着(メイト)
	session = GameSession.from_board(
		Board.from_fen("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1")
	)
	# 白手番で Qf7-f8# など。局面がすでにほぼ詰みなら一手で。
	# f7 クイーンを g7 へ? シンプルに f7->h7 メイト: 黒王 h8、白 Qf7, 白 Kg6
	session.select(Vector2i(5, 6))
	check(session.try_move_to(Vector2i(7, 6)), "Qf7h7#")
	ev = session.last_move_event()
	check(ev.is_checkmate, "チェックメイト")
	check(ev.is_over, "終局")
	check(ev.result_text.contains("チェックメイト"), "結果文")


func test_apply_move_direct_without_selection() -> void:
	var session := GameSession.start()
	check(not session.is_selected(), "未選択")
	var move := Move.new(Vector2i(4, 1), Vector2i(4, 3))
	var ev := session.apply_move(move)
	check(ev != null, "直接適用成功")
	check_eq(session.side_to_move(), Piece.Side.BLACK, "手番が黒")
	check_eq(ev.from_square(), Vector2i(4, 1), "from")
	check_eq(ev.to_square(), Vector2i(4, 3), "to")
	check(session.last_move_event() == ev, "last と同じ")

	var illegal := Move.new(Vector2i(4, 1), Vector2i(4, 4))
	check(session.apply_move(illegal) == null, "非合法は拒否")
	check_eq(session.side_to_move(), Piece.Side.BLACK, "手番は変わらない")
	check(session.board().piece_at(Vector2i(4, 3)) != null, "盤は e4 のまま")

	# 終局後も拒否
	session = GameSession.from_board(
		Board.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
	)
	check(session.is_over(), "終局")
	check(session.apply_move(Move.new(Vector2i(7, 7), Vector2i(7, 6))) == null, "終局後拒否")


func test_apply_move_and_click_path_same_event() -> void:
	## 同じ局面・同じ手なら、直接適用と選択+着手で観測内容が一致する。
	var fen := "4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1"
	var move := Move.new(Vector2i(2, 2), Vector2i(1, 4))

	var direct := GameSession.from_board(Board.from_fen(fen))
	var ev_direct := direct.apply_move(move)
	check(ev_direct != null, "直接成功")

	var click_path := GameSession.from_board(Board.from_fen(fen))
	click_path.click(Vector2i(2, 2))
	click_path.click(Vector2i(1, 4))
	var ev_click := click_path.last_move_event()
	check(ev_click != null, "クリック経路でもイベント")

	_assert_events_equal(ev_direct, ev_click)

	# 成りも同様
	fen = "4k3/6P1/8/8/8/8/8/4K3 w - - 0 1"
	move = Move.new(Vector2i(6, 6), Vector2i(6, 7), Piece.Kind.QUEEN)
	direct = GameSession.from_board(Board.from_fen(fen))
	ev_direct = direct.apply_move(move)
	click_path = GameSession.from_board(Board.from_fen(fen))
	click_path.select(Vector2i(6, 6))
	click_path.try_move_to(Vector2i(6, 7))
	ev_click = click_path.last_move_event()
	_assert_events_equal(ev_direct, ev_click)


func test_en_passant_event_captures_off_target_square() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/3p4/8/2P5/4K3 w - - 0 1")
	)
	session.apply_move(Move.new(Vector2i(2, 1), Vector2i(2, 3)))
	var ev := session.apply_move(Move.new(Vector2i(3, 3), Vector2i(2, 2)))
	check(ev != null, "e.p. 成功")
	check(ev.was_en_passant(), "アンパッサン")
	check(ev.was_capture(), "取りあり")
	check_eq(ev.captured_square, Vector2i(2, 3), "取られたマスは c4")
	check_eq(ev.to_square(), Vector2i(2, 2), "移動先は c3")
	check_eq(ev.captured.kind, Piece.Kind.PAWN, "ポーン取り")


func test_castling_event_flags() -> void:
	var session := GameSession.from_board(
		Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(4, 0), Vector2i(6, 0)))
	check(ev != null, "キャスリング成功")
	check(ev.was_castling(), "キャスリング旗")
	check(not ev.was_capture(), "取りなし")


func _assert_view_matches_board(view: BoardView, board: Board, label: String) -> void:
	var count := 0
	for y in range(board.height):
		for x in range(board.width):
			var pos := Vector2i(x, y)
			var piece := board.piece_at(pos)
			var node := view.piece_node_at(pos)
			if piece == null:
				check(node == null, "%s: 空マス %s にノード無し" % [label, str(pos)])
			else:
				check(node != null, "%s: 駒マス %s にノード" % [label, str(pos)])
				check_eq(node.piece_side, piece.side, "%s: %s side" % [label, str(pos)])
				check_eq(node.piece_kind, piece.kind, "%s: %s kind" % [label, str(pos)])
				check_eq(node.board_pos, pos, "%s: %s board_pos" % [label, str(pos)])
				count += 1
	check_eq(view.piece_count(), count, "%s: 駒数一致" % label)


func _assert_events_equal(a: MoveEvent, b: MoveEvent) -> void:
	check(a != null and b != null, "両方イベントあり")
	check_eq(a.from_square(), b.from_square(), "from 一致")
	check_eq(a.to_square(), b.to_square(), "to 一致")
	check_eq(a.promotion(), b.promotion(), "promotion 一致")
	check_eq(a.mover_side, b.mover_side, "mover_side")
	check_eq(a.mover_kind, b.mover_kind, "mover_kind")
	check_eq(a.was_capture(), b.was_capture(), "capture 旗")
	if a.was_capture():
		check_eq(a.captured.side, b.captured.side, "captured side")
		check_eq(a.captured.kind, b.captured.kind, "captured kind")
		check_eq(a.captured_square, b.captured_square, "captured square")
	check_eq(a.is_check, b.is_check, "check")
	check_eq(a.is_checkmate, b.is_checkmate, "checkmate")
	check_eq(a.is_stalemate, b.is_stalemate, "stalemate")
	check_eq(a.is_over, b.is_over, "over")
	check_eq(a.result_text, b.result_text, "result_text")
	check_eq(a.was_castling(), b.was_castling(), "castling")
	check_eq(a.was_en_passant(), b.was_en_passant(), "en_passant")
