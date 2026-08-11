extends "res://tests/case.gd"

## Issue #5: クリック操作で 2 人対局が最後まで遊べる。
##
## シーム:
## - GameSession: 選択 / 合法手 / 着手 / 手番 / 王手 / 終局 / 待った
## - BoardView.set_highlights / sync: 見た目のハイライトと配置同期
##
## 入力の感触(クリック vs ドラッグ)と HUD の見やすさは手動確認。


func test_selects_only_side_to_move_piece() -> void:
	var session := GameSession.start()
	check(session.select(Vector2i(4, 1)), "白ポーン e2 を選択できる")
	check_eq(session.selected_square(), Vector2i(4, 1), "選択マス")
	session.deselect()
	check(not session.is_selected(), "解除できる")
	check(not session.select(Vector2i(4, 6)), "相手の黒ポーン e7 は選択できない")
	check(not session.is_selected(), "相手駒クリック後も未選択")
	check(not session.select(Vector2i(4, 3)), "空きマスは選択できない")


func test_legal_targets_for_selected_piece() -> void:
	var session := GameSession.start()
	session.select(Vector2i(4, 1))  # e2
	var targets := session.legal_targets()
	check(targets.has(Vector2i(4, 2)), "e3 が合法")
	check(targets.has(Vector2i(4, 3)), "e4 が合法")
	check_eq(targets.size(), 2, "初期 e2 の合法手は 2")


func test_move_to_legal_square_and_switch_turn() -> void:
	var session := GameSession.start()
	session.select(Vector2i(4, 1))
	check(session.try_move_to(Vector2i(4, 3)), "e2e4 できる")
	check(not session.is_selected(), "着手後は選択解除")
	check_eq(session.side_to_move(), Piece.Side.BLACK, "手番が黒へ")
	check(session.board().piece_at(Vector2i(4, 1)) == null, "e2 は空")
	check_eq(session.board().piece_at(Vector2i(4, 3)).kind, Piece.Kind.PAWN, "e4 にポーン")


func test_illegal_target_does_not_move() -> void:
	var session := GameSession.start()
	session.select(Vector2i(4, 1))
	check(not session.try_move_to(Vector2i(4, 4)), "e5 は非合法")
	check_eq(session.selected_square(), Vector2i(4, 1), "選択は維持")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "手番は白のまま")
	check_eq(session.board().piece_at(Vector2i(4, 1)).kind, Piece.Kind.PAWN, "e2 にポーン残る")


func test_click_reselects_own_piece_and_deselects_on_empty() -> void:
	var session := GameSession.start()
	session.click(Vector2i(4, 1))  # select e2
	check_eq(session.selected_square(), Vector2i(4, 1), "e2 選択")
	session.click(Vector2i(3, 1))  # reselect d2
	check_eq(session.selected_square(), Vector2i(3, 1), "d2 に再選択")
	session.click(Vector2i(4, 3))  # empty, not legal for d2
	check(not session.is_selected(), "非合法空きマスで解除")


func test_click_same_square_deselects() -> void:
	var session := GameSession.start()
	session.click(Vector2i(1, 0))  # b1 knight
	check(session.is_selected(), "選択される")
	session.click(Vector2i(1, 0))
	check(not session.is_selected(), "同じマス再クリックで解除")


func test_capture_removes_opponent_piece() -> void:
	# 白ナイト c3 が黒ポーン b5 を取る (デルタ -1,+2)
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	session.click(Vector2i(2, 2))
	check(session.try_move_to(Vector2i(1, 4)), "c3b5 で黒ポーン取り")
	check(session.board().piece_at(Vector2i(1, 4)) != null, "b5 に白ナイト")
	check_eq(session.board().piece_at(Vector2i(1, 4)).kind, Piece.Kind.KNIGHT, "ナイト")
	check_eq(session.board().piece_at(Vector2i(1, 4)).side, Piece.Side.WHITE, "白")
	check(session.board().piece_at(Vector2i(2, 2)) == null, "c3 は空")


func test_castling_via_session() -> void:
	var session := GameSession.from_board(
		Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	)
	session.select(Vector2i(4, 0))
	check(session.legal_targets().has(Vector2i(6, 0)), "g1 がハイライト対象")
	check(session.try_move_to(Vector2i(6, 0)), "王翼キャスリング")
	check_eq(session.board().piece_at(Vector2i(6, 0)).kind, Piece.Kind.KING, "王 g1")
	check_eq(session.board().piece_at(Vector2i(5, 0)).kind, Piece.Kind.ROOK, "ルーク f1")


func test_en_passant_via_session() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/3p4/8/2P5/4K3 w - - 0 1")
	)
	session.select(Vector2i(2, 1))
	session.try_move_to(Vector2i(2, 3))  # c2c4
	session.select(Vector2i(3, 3))
	check(session.legal_targets().has(Vector2i(2, 2)), "アンパッサン先 c3")
	check(session.try_move_to(Vector2i(2, 2)), "d4xc3 e.p.")
	check(session.board().piece_at(Vector2i(2, 3)) == null, "取られた c4 ポーン消滅")
	check_eq(session.board().piece_at(Vector2i(2, 2)).side, Piece.Side.BLACK, "黒ポーン c3")


func test_promotion_via_session() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/6P1/8/8/8/8/8/4K3 w - - 0 1")
	)
	session.select(Vector2i(6, 6))
	check(session.try_move_to(Vector2i(6, 7)), "g7g8 昇格")
	check_eq(session.board().piece_at(Vector2i(6, 7)).kind, Piece.Kind.QUEEN, "クイーンに成る")


func test_check_flag_and_checkmate_ends_game() -> void:
	# 一手でメイト: 白クイーン h5 から h7? シンプルに詰み局面を載せる
	var session := GameSession.from_board(
		Board.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
	)
	check(session.in_check(), "黒は王手")
	check(session.is_checkmate(), "チェックメイト")
	check(session.is_over(), "対局終了")
	check(not session.select(Vector2i(7, 7)), "終局後は選択不可")
	check(not session.try_move_to(Vector2i(7, 6)), "終局後は移動不可")
	check(session.result_text().contains("チェックメイト"), "結果に詰み表示")


func test_stalemate_ends_game() -> void:
	var session := GameSession.from_board(
		Board.from_fen("k7/8/1QK5/8/8/8/8/8 b - - 0 1")
	)
	check(session.is_stalemate(), "ステイルメイト")
	check(session.is_over(), "対局終了")
	check(not session.in_check(), "王手ではない")
	check(session.result_text().contains("ステイルメイト"), "結果表示")


func test_undo_removes_last_full_round() -> void:
	var session := GameSession.start()
	check(not session.can_undo(), "初手より前は待った不可")
	check(not session.undo(), "効かない")

	session.select(Vector2i(4, 1))
	session.try_move_to(Vector2i(4, 3))  # e2e4
	check(not session.can_undo(), "1 手だけでは往復未完成")
	check(not session.undo(), "1 手では待った不可")

	session.select(Vector2i(4, 6))
	session.try_move_to(Vector2i(4, 4))  # e7e5
	check(session.can_undo(), "1 往復後は待った可")
	check(session.undo(), "待った成功")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "手番が白に戻る")
	check_eq(session.board().piece_at(Vector2i(4, 1)).kind, Piece.Kind.PAWN, "e2 復元")
	check(session.board().piece_at(Vector2i(4, 3)) == null, "e4 クリア")
	check_eq(session.board().piece_at(Vector2i(4, 6)).kind, Piece.Kind.PAWN, "e7 復元")
	check(session.board().piece_at(Vector2i(4, 4)) == null, "e5 クリア")
	check(not session.can_undo(), "戻したのでまた不可")


func test_undo_clears_selection() -> void:
	var session := GameSession.start()
	_play_uci(session, "e2e4")
	_play_uci(session, "e7e5")
	session.select(Vector2i(6, 0))  # g1 knight after round
	check(session.is_selected(), "選択中")
	session.undo()
	check(not session.is_selected(), "待ったで選択解除")


func test_board_view_highlights_and_sync() -> void:
	var board := Board.chess_start()
	var view := BoardView.new()
	view.build_from(board)
	view.set_highlights(Vector2i(4, 1), [Vector2i(4, 2), Vector2i(4, 3)])
	check_eq(view.highlight_count(), 3, "選択 + 2 合法手")
	check(view.has_highlight_at(Vector2i(4, 1)), "選択マス")
	check(view.has_highlight_at(Vector2i(4, 3)), "e4")

	var moved := board.apply(Move.new(Vector2i(4, 1), Vector2i(4, 3)))
	view.apply_board(moved)
	check(view.piece_node_at(Vector2i(4, 1)) == null, "移動後 e2 空")
	check_eq(view.piece_node_at(Vector2i(4, 3)).piece_kind, Piece.Kind.PAWN, "e4 ポーン")
	view.clear_highlights()
	check_eq(view.highlight_count(), 0, "ハイライト消去")
	view.free()


func test_screen_ray_to_square_hits_board_plane() -> void:
	## カメラなしでも plane 交差の数学を固定入力で検証する。
	# e4 マス中心の真上から真下へ。
	var e4_world := BoardLayout.square_to_world(Vector2i(4, 3))
	var origin := Vector3(e4_world.x, 10.0, e4_world.z)
	var direction := Vector3(0.0, -1.0, 0.0)
	var sq := BoardLayout.ray_to_square(origin, direction)
	check_eq(sq, Vector2i(4, 3), "e4 真上から真下は e4")
	var miss := BoardLayout.ray_to_square(Vector3(0, 10, 0), Vector3(0, 1, 0))
	check_eq(miss, BoardLayout.INVALID_SQUARE, "上向きレイは盤に当たらない")
	var off_board := BoardLayout.ray_to_square(Vector3(20, 10, 20), Vector3(0, -1, 0))
	check_eq(off_board, BoardLayout.INVALID_SQUARE, "盤外ヒットは無効")


func test_pick_square_prefers_piece_sphere_over_plane() -> void:
	## 平面交点が隣マスでも、駒球に当たれば駒マスを返す。
	var e2 := Vector2i(4, 1)
	var e2_world := BoardLayout.square_to_world(e2)
	# 駒の少し手前上から駒中心を狙う。
	var origin := Vector3(e2_world.x, 1.2, e2_world.z + 2.5)
	var target := e2_world + Vector3(0.0, 0.35, 0.0)
	var direction := (target - origin).normalized()
	var picked := BoardLayout.pick_square(origin, direction, [e2])
	check_eq(picked, e2, "駒球優先で e2")
	# 駒が無いときは平面フォールバック
	var empty_board_pick := BoardLayout.pick_square(
		Vector3(e2_world.x, 10.0, e2_world.z), Vector3(0, -1, 0), []
	)
	check_eq(empty_board_pick, e2, "真上平面は e2")


func test_orbit_and_controller_share_drag_threshold() -> void:
	check(OrbitCamera.DRAG_THRESHOLD_PX > 0.0, "閾値は正")
	check_eq(OrbitCamera.DRAG_THRESHOLD_PX, 6.0, "クリック/オービット共通閾値")


func _play_uci(session: GameSession, uci: String) -> void:
	for m in session.board().legal_moves():
		var move := m as Move
		if move.to_uci() == uci:
			session.select(move.from)
			session.try_move_to(move.to)
			return
	check(false, "合法手に無い UCI: %s" % uci)
