extends "res://tests/case.gd"

## Issue #6: 移動・駒取り・待機のアニメーション。
##
## シーム(自動化できる範囲):
## - PieceNode: 移動 / 取られ / 待機の状態遷移、モデルクリップの有無分岐
## - BoardView.apply_board / apply_move_event: 論理盤への同期、演出中断後も壊れない
## - finish_animations: 確定同期(テストと再操作)
##
## 見た目の滑らかさ・浮遊感は手動確認。


func test_piece_node_snap_sets_rest_and_idle() -> void:
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.PAWN, Vector2i(0, 1))
	var target := Vector3(1.5, 0.0, -2.0)
	node.snap_to(target)
	check_eq(node.anim_state(), PieceNode.AnimState.IDLE, "スナップ後は待機")
	check(node.position.is_equal_approx(target), "位置が一致")
	check(node.rest_position().is_equal_approx(target), "rest も一致")
	check(not node.is_animating(), "演出中ではない")
	node.free()


func test_piece_node_move_without_tree_snaps_immediately() -> void:
	## ツリー外では tween せず即着地(ヘッドレステスト互換)。
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.KNIGHT, Vector2i(1, 0))
	node.snap_to(Vector3.ZERO)
	var target := Vector3(3.0, 0.0, 1.0)
	node.animate_move_to(target)
	check_eq(node.anim_state(), PieceNode.AnimState.IDLE, "ツリー外移動は即 IDLE")
	check(node.position.is_equal_approx(target), "即着地")
	node.free()


func test_piece_node_capture_without_tree_emits_immediately() -> void:
	var node := PieceNode.new(Piece.Side.BLACK, Piece.Kind.PAWN, Vector2i(2, 2))
	var emitted := [false]
	node.capture_finished.connect(func() -> void: emitted[0] = true)
	node.play_capture()
	check(emitted[0], "ツリー外の取られは即完了シグナル")
	check(not node.is_animating(), "演出中ではない")
	node.free()


func test_piece_node_detects_model_animation_clips() -> void:
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.ROOK, Vector2i(0, 0))
	check(not node.has_model_animation(PieceNode.MOVE_CLIP_CANDIDATES), "モデル無しはクリップ無し")

	var visual := Node3D.new()
	var player := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 0.5
	var lib := AnimationLibrary.new()
	lib.add_animation("walk", anim)
	player.add_animation_library("", lib)
	visual.add_child(player)
	node.set_model(visual)

	check(node.has_model_animation(PieceNode.MOVE_CLIP_CANDIDATES), "walk は移動候補に一致")
	check(not node.has_model_animation(PieceNode.IDLE_CLIP_CANDIDATES), "idle は無い")
	check(not node.has_model_animation(PieceNode.CAPTURE_CLIP_CANDIDATES), "capture は無い")
	node.free()


func test_piece_node_fallback_when_model_has_no_clips() -> void:
	## プレースホルダ(クリップ無し)でも移動・取られ API が落ちない。
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.BISHOP, Vector2i(2, 0))
	node.set_model(PlaceholderVisual.create(Piece.Side.WHITE, Piece.Kind.BISHOP))
	check(not node.has_model_animation(PieceNode.MOVE_CLIP_CANDIDATES), "プレースホルダに move 無し")
	node.snap_to(Vector3.ZERO)
	node.animate_move_to(Vector3(1, 0, 0))
	check(node.position.is_equal_approx(Vector3(1, 0, 0)), "代替移動で着地")
	node.play_capture()
	check(not node.is_animating(), "代替取られもツリー外は即完了")
	node.free()


func test_board_view_move_preserves_identity_and_lands() -> void:
	var session := GameSession.start()
	var view := BoardView.new()
	view.build_from(session.board())
	var before := view.piece_node_at(Vector2i(4, 1))
	var id_before := before.get_instance_id()

	session.select(Vector2i(4, 1))
	check(session.try_move_to(Vector2i(4, 3)), "e2e4")
	view.apply_board(session.board())
	view.finish_animations()

	var after := view.piece_node_at(Vector2i(4, 3))
	check(after != null, "e4 に駒")
	check_eq(after.get_instance_id(), id_before, "同一インスタンス")
	var expected := BoardLayout.square_to_world(Vector2i(4, 3))
	check(after.rest_position().is_equal_approx(expected), "rest が移動先")
	check(after.position.is_equal_approx(expected), "見た目位置も移動先(ツリー外)")
	check(not view.is_animating(), "演出完了")
	_assert_view_matches_board(view, session.board(), "移動後")
	view.free()


func test_board_view_apply_move_event_matches_board() -> void:
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())
	var knight_id := view.piece_node_at(Vector2i(2, 2)).get_instance_id()

	session.select(Vector2i(2, 2))
	check(session.try_move_to(Vector2i(1, 4)), "取り")
	var ev := session.last_move_event()
	view.apply_move_event(session.board(), ev)
	view.finish_animations()

	check_eq(view.piece_count(), 3, "取られた 1 駒だけ減る")
	check_eq(view.piece_node_at(Vector2i(1, 4)).get_instance_id(), knight_id, "ナイト同一")
	check(ev.was_capture(), "イベントは取り")
	_assert_view_matches_board(view, session.board(), "取り後")
	view.free()


func test_board_view_interrupt_mid_animation_keeps_board_consistent() -> void:
	## 移動演出の途中で次の着手が来ても、最終的に論理盤と一致し壊れない。
	var tree := Engine.get_main_loop() as SceneTree
	check(tree != null, "SceneTree がある")

	var session := GameSession.start()
	var view := BoardView.new()
	tree.root.add_child(view)
	view.build_from(session.board())

	session.select(Vector2i(4, 1))
	check(session.try_move_to(Vector2i(4, 3)), "e2e4")
	view.apply_board(session.board())
	# ツリー内なので移動 tween が走る想定。走らなくても中断 API は安全。
	check(view.piece_node_at(Vector2i(4, 3)) != null, "論理マップは移動先")

	session.select(Vector2i(6, 7))
	check(session.try_move_to(Vector2i(5, 5)), "黒ナイト g8f6")
	view.apply_board(session.board())
	view.finish_animations()

	check(not view.is_animating(), "中断後は演出無し")
	_assert_view_matches_board(view, session.board(), "連続着手後")
	check_eq(view.piece_count(), 32, "駒数維持")

	# 取りを挟んでも中断できる
	session = GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	view.build_from(session.board())
	session.select(Vector2i(2, 2))
	session.try_move_to(Vector2i(1, 4))
	view.apply_board(session.board())
	# すぐ次の同期(待った相当の再適用)
	view.apply_board(session.board())
	view.finish_animations()
	_assert_view_matches_board(view, session.board(), "取り中断後")
	check_eq(view.piece_count(), 3, "取り後の駒数")

	view.queue_free()


func test_board_view_idle_rest_position_stable() -> void:
	## 待機は rest を基準にわずかに動くが、rest 自体はマス座標のまま。
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.KING, Vector2i(4, 0))
	var world := BoardLayout.square_to_world(Vector2i(4, 0))
	node.snap_to(world)
	check(node.rest_position().is_equal_approx(world), "待機の rest はマス中心")
	# _process を直接呼べないため、状態が IDLE であることだけ固定する。
	check_eq(node.anim_state(), PieceNode.AnimState.IDLE, "待機状態")
	node.free()


func test_full_game_can_complete_with_animations_api() -> void:
	## アニメ API を挟んでも対局を終局まで進められる(フールズメイト)。
	var session := GameSession.start()
	var view := BoardView.new()
	view.build_from(session.board())

	var moves := ["f2f3", "e7e5", "g2g4", "d8h4"]
	for uci in moves:
		_play_uci(session, uci)
		view.apply_move_event(session.board(), session.last_move_event())
		view.finish_animations()
		_assert_view_matches_board(view, session.board(), "手 %s の後" % uci)

	check(session.is_over(), "終局")
	check(session.is_checkmate(), "チェックメイト")
	_assert_view_matches_board(view, session.board(), "終局時")
	view.free()


func _play_uci(session: GameSession, uci: String) -> void:
	for m in session.board().legal_moves():
		var move := m as Move
		if move.to_uci() == uci:
			var ev := session.apply_move(move)
			check(ev != null, "適用できた: %s" % uci)
			return
	check(false, "合法手に無い UCI: %s" % uci)


func _assert_view_matches_board(view: BoardView, board: Board, label: String) -> void:
	var count := 0
	for y in range(board.height):
		for x in range(board.width):
			var pos := Vector2i(x, y)
			var piece := board.piece_at(pos)
			var node := view.piece_node_at(pos)
			if piece == null:
				check(node == null, "%s: 空マス %s にノードが無い" % [label, str(pos)])
			else:
				count += 1
				check(node != null, "%s: 駒マス %s にノード" % [label, str(pos)])
				if node != null:
					check_eq(node.piece_side, piece.side, "%s: %s side" % [label, str(pos)])
					check_eq(node.piece_kind, piece.kind, "%s: %s kind" % [label, str(pos)])
					check_eq(node.board_pos, pos, "%s: %s board_pos" % [label, str(pos)])
	check_eq(view.piece_count(), count, "%s: piece_count" % label)
