extends "res://tests/case.gd"

## Issue #26: 持ち駒、打つ操作、任意成りUI、表示・入力の通し契約。

const VIEWPORT_SIZE := Vector2i(1280, 720)
const LAYOUT_TOLERANCE_PX := 2.0


func test_controller_optional_promotion_dialog_cancel_and_choose_canonical_move() -> void:
	var board := _promotion_board(false)
	var f := _fixture(board)
	var session: GameSession = f["session"]
	var controller: GameController = f["controller"]
	var orbit: OrbitCamera = f["orbit"]
	var from := Vector2i(4, 5)
	var to := Vector2i(4, 6)

	controller._handle_board_square(from)
	controller._handle_board_square(to)
	check(controller.has_pending_promotion(), "任意成り2候補でdialog表示")
	check_eq(controller.promotion_dialog().candidates().size(), 2, "完全Move 2候補を保持")
	check(not orbit.input_enabled, "dialog中はcamera入力抑止")
	var before_board := session.board()
	var before_event := session.last_move_event()
	controller._handle_board_square(Vector2i(3, 3))
	check(session.board() == before_board, "dialog中の盤入力を無視")

	controller.promotion_dialog().cancel_selection()
	check(not controller.has_pending_promotion(), "取消でdialog終了")
	check(session.board() == before_board, "取消で盤不変")
	check(session.last_move_event() == before_event, "取消でlast_move_event不変")
	check(not session.can_undo(), "取消で履歴不変")
	check_eq(session.selected_square(), from, "取消で選択維持")
	check(orbit.input_enabled, "取消後camera入力復元")

	controller._handle_board_square(to)
	var promote_move: Move = null
	for candidate in controller.promotion_dialog().candidates():
		if (candidate as Move).promotion >= 0:
			promote_move = candidate as Move
	check(promote_move != null, "成るcanonical候補")
	check(controller.promotion_dialog().choose_promotion(true), "成るを選択")
	check_eq(session.board().piece_at(to).kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "選択後だけ成り適用")
	check(session.last_move_event() != null and session.last_move_event().was_promotion(), "成りevent")
	check(not session.is_selected(), "成功着手で選択解除")
	_free_fixture(f)


func test_controller_forced_promotion_is_immediate_without_dialog() -> void:
	var f := _fixture(_promotion_board(true))
	var session: GameSession = f["session"]
	var controller: GameController = f["controller"]
	controller._handle_board_square(Vector2i(4, 7))
	controller._handle_board_square(Vector2i(4, 8))
	check(not controller.has_pending_promotion(), "強制成りはdialog無し")
	check_eq(session.board().piece_at(Vector2i(4, 8)).kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "即時成り")
	_free_fixture(f)


func test_hud_shows_both_hands_counts_turn_selection_and_consumes_input() -> void:
	var board := _drop_board()
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 2
	board.hands[Piece.Side.BLACK][Piece.Kind.SHOGI_SILVER] = 1
	var f := _fixture(board)
	var hud: GameHud = f["hud"]
	var controller: GameController = f["controller"]
	check(hud.hands_visible(), "将棋は両陣営持ち駒表示")
	var white_pawn := hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN)
	var black_silver := hud.hand_button(Piece.Side.BLACK, Piece.Kind.SHOGI_SILVER)
	check(white_pawn.text.contains("歩") and white_pawn.text.contains("x2"), "先手歩の種別と枚数")
	check(not white_pawn.disabled, "手番側の合法持ち駒だけ有効")
	check(black_silver.disabled, "手番外はdisabled")
	check_eq(white_pawn.mouse_filter, Control.MOUSE_FILTER_STOP, "ボタンが入力を消費")
	check_eq(hud.hand_panel(Piece.Side.WHITE).mouse_filter, Control.MOUSE_FILTER_STOP, "パネル余白も入力を消費")

	check(controller.select_drop(Piece.Kind.SHOGI_PAWN), "Controller経由で歩選択")
	check(white_pawn.button_pressed, "選択状態を表示")
	check(controller.select_drop(Piece.Kind.SHOGI_PAWN), "同じボタン相当で取消")
	check(not white_pawn.button_pressed, "取消表示")
	check(controller.select_drop(Piece.Kind.SHOGI_PAWN), "盤外取消前に再選択")
	controller._handle_board_square(BoardLayout.INVALID_SQUARE)
	check(not (f["session"] as GameSession).is_selected(), "盤外入力で持ち駒選択取消")

	hud.refresh(Piece.Side.WHITE, false, "", false, Board.chess_start(), -1, [])
	check(not hud.hands_visible(), "チェスでは完全非表示")
	_free_fixture(f)


func test_capture_drop_and_undo_refresh_hand_counts_board_and_selection() -> void:
	var board := _drop_board()
	board.set_piece(Vector2i(4, 4), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_ROOK))
	board.set_piece(Vector2i(4, 5), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_SILVER))
	var f := _fixture(board)
	var session: GameSession = f["session"]
	var controller: GameController = f["controller"]
	var hud: GameHud = f["hud"]

	controller._handle_board_square(Vector2i(4, 4))
	controller._handle_board_square(Vector2i(4, 5))
	check(hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_SILVER).text.contains("x1"), "捕獲で銀1枚")
	controller._handle_board_square(Vector2i(8, 8))
	controller._handle_board_square(Vector2i(7, 8))
	check(session.can_undo(), "捕獲+応手でundo可能")
	controller._on_undo()
	check(hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_SILVER).text.contains("x0"), "undoで捕獲枚数復元")
	check_eq(session.board().piece_at(Vector2i(4, 5)).kind, Piece.Kind.SHOGI_SILVER, "undoで取られた駒復元")
	check(not session.is_selected(), "undoで選択解除")

	var drop_board := _drop_board()
	drop_board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_PAWN] = 2
	var d := _fixture(drop_board)
	var drop_controller: GameController = d["controller"]
	var drop_session: GameSession = d["session"]
	var drop_hud: GameHud = d["hud"]
	check(drop_controller.select_drop(Piece.Kind.SHOGI_PAWN), "歩を選択")
	drop_controller._handle_board_square(Vector2i(4, 4))
	check_eq(drop_session.board().piece_at(Vector2i(4, 4)).kind, Piece.Kind.SHOGI_PAWN, "歩を打つ")
	check(drop_hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN).text.contains("x1"), "打って1枚減る")
	check(not drop_session.is_selected(), "打った後の選択解除")
	drop_controller._handle_board_square(Vector2i(8, 8))
	drop_controller._handle_board_square(Vector2i(7, 8))
	drop_controller._on_undo()
	check(drop_hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN).text.contains("x2"), "打つ手のundoで枚数復元")
	check(drop_session.board().piece_at(Vector2i(4, 4)) == null, "打った駒もundo")
	_free_fixture(d)
	_free_fixture(f)


func test_board_view_draws_drop_and_preserves_shogi_promotion_identity() -> void:
	var drop_board := _drop_board()
	drop_board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 1
	var dropped := drop_board.apply(Move.drop(Piece.Kind.SHOGI_GOLD, Vector2i(4, 4)))
	var view := BoardView.new()
	view.build_from(drop_board)
	view.apply_board(dropped)
	var node := view.piece_node_at(Vector2i(4, 4))
	check(node != null, "打った駒を描画")
	check_eq(node.piece_side, Piece.Side.WHITE, "打った側の色")
	check_eq(node.piece_kind, Piece.Kind.SHOGI_GOLD, "打った駒種")

	var promo := _promotion_board(false)
	view.build_from(promo)
	var before := view.piece_node_at(Vector2i(4, 5))
	var before_id := before.get_instance_id()
	var promoted := promo.apply(Move.new(Vector2i(4, 5), Vector2i(4, 6), Piece.Kind.SHOGI_PROMOTED_PAWN))
	view.apply_board(promoted)
	check_eq(view.piece_node_at(Vector2i(4, 6)).get_instance_id(), before_id, "将棋成りでもPieceNode再利用")
	check_eq(view.piece_node_at(Vector2i(4, 6)).piece_kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "成駒表示")
	view.free()


func test_drop_move_event_and_speech_are_distinct_from_move_capture_and_promotion() -> void:
	var board := _drop_board()
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 1
	var session := GameSession.from_board(board)
	var event := session.apply_move(Move.drop(Piece.Kind.SHOGI_SILVER, Vector2i(4, 4)))
	check(event != null and event.was_drop(), "drop event")
	check_eq(event.mover_side, Piece.Side.WHITE, "着手前side_to_move")
	check_eq(event.mover_kind, Piece.Kind.SHOGI_SILVER, "drop_kindをmover_kind")
	check_eq(event.from_square(), Move.NO_SQUARE, "drop from")
	check(not event.was_capture(), "captureではない")
	check(not event.was_promotion(), "promotionではない")

	var catalog := SpeechCatalog.new()
	var character := CharacterDef.new()
	character.id = "dropper"
	character.lines = {"moved": PackedStringArray(["動く"])}
	catalog.characters[character.id] = character
	catalog.team.assign(Piece.Kind.SHOGI_SILVER, character.id)
	var resolver := SpeechResolver.new(catalog)
	var plan := resolver.plan(event)
	check_eq(plan.size(), 1, "既存moved台詞へ互換fallback")
	check_eq((plan[0] as SpeechUtterance).event_key, "dropped", "発話種別はdropped")
	check(resolver.is_important(event), "打つ手は通常移動と区別")
	var director := SpeechDirector.new()
	director.resolver = resolver
	var context := director.build_llm_context(plan[0] as SpeechUtterance, event, "動く")
	check(str(context["board_hint"]).contains("打つ:"), "Directorも通常移動でなく打つと記述")
	check(not str(context["board_hint"]).contains("? →"), "NO_SQUAREを通常移動元として発話しない")
	director.free()


func test_checkmating_non_pawn_drop_updates_single_session_result_and_hud() -> void:
	var board := _mating_gold_drop_board()
	var f := _fixture(board)
	var session: GameSession = f["session"]
	var controller: GameController = f["controller"]
	var hud: GameHud = f["hud"]
	check(controller.select_drop(Piece.Kind.SHOGI_GOLD), "詰みの金打ち選択")
	controller._handle_board_square(Vector2i(4, 7))
	check(session.is_checkmate(), "Sessionの既存境界が詰み")
	check(session.result_text().contains("詰み"), "Session結果文")
	var result_label := hud.get_node("Root/ResultLabel") as Label
	check(result_label.visible and result_label.text == session.result_text(), "HUDはSession結果だけを表示")
	_free_fixture(f)


func test_hud_shows_current_check_from_session_without_competing_state() -> void:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(4, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(0, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_ROOK))
	var f := _fixture(board)
	var session: GameSession = f["session"]
	var hud: GameHud = f["hud"]
	check(session.in_check() and not session.is_over(), "Session境界で王手中")
	var check_label := hud.get_node("Root/CheckLabel") as Label
	var result_label := hud.get_node("Root/ResultLabel") as Label
	check(check_label.visible and check_label.text == "王手!", "HUD王手表示")
	check(not result_label.visible, "進行中は終局表示なし")
	_free_fixture(f)


func test_1280x720_actual_board_hud_and_input_probe_has_pass_and_fail_controls() -> void:
	var output: Array = []
	var args := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--script",
		"res://tests/t26_ui_probe.gd",
	])
	var status := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	if status != 0:
		print(text)
	check_eq(status, 0, "1280x720実Viewport probe成功")
	check(text.contains("target=actual BoardLayout/BoardView/GameHud"), "測定対象を記録")
	check(text.contains("PASS control actualLayout=true actualInputStop=true"), "PASS control校正")
	check(text.contains("FAIL control overlappedLayout=false ignoreInputStop=false"), "FAIL control校正")
	check(text.contains("boardInput=true viewSync=true"), "実盤入力と表示同期")
	for line in text.split("\n"):
		if line.begins_with("T26 UI calibration:"):
			print(line)


func _fixture(board: ShogiBoard) -> Dictionary:
	var session := GameSession.from_board(board)
	var view := BoardView.new()
	view.build_from(board)
	var hud := GameHud.new()
	var orbit := OrbitCamera.new()
	var controller := GameController.new()
	controller.setup(session, view, hud, orbit)
	return {
		"session": session,
		"view": view,
		"hud": hud,
		"orbit": orbit,
		"controller": controller,
	}


func _free_fixture(f: Dictionary) -> void:
	(f["controller"] as GameController).free()
	(f["view"] as BoardView).free()
	(f["hud"] as GameHud).free()
	(f["orbit"] as OrbitCamera).free()


func _drop_board() -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	return board


func _promotion_board(forced: bool) -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.set_piece(
		Vector2i(4, 7) if forced else Vector2i(4, 5),
		Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN),
	)
	return board


func _mating_gold_drop_board() -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(4, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(3, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_LANCE))
	board.set_piece(Vector2i(5, 6), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_LANCE))
	board.set_piece(Vector2i(4, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_GOLD] = 1
	return board


func _projected_board_rect(camera: Camera3D, board_size: Vector2i) -> Rect2:
	var points: Array[Vector2] = []
	var half_x := float(board_size.x) * 0.5
	var half_z := float(board_size.y) * 0.5
	for x in [-half_x, half_x]:
		for z in [-half_z, half_z]:
			points.append(camera.unproject_position(Vector3(x, 0.0, z)))
	var min_pos := points[0]
	var max_pos := points[0]
	for point in points:
		min_pos.x = minf(min_pos.x, point.x)
		min_pos.y = minf(min_pos.y, point.y)
		max_pos.x = maxf(max_pos.x, point.x)
		max_pos.y = maxf(max_pos.y, point.y)
	return Rect2(min_pos, max_pos - min_pos)


func _panels_fit_without_board_overlap(
	board_rect: Rect2,
	left_rect: Rect2,
	right_rect: Rect2,
	tolerance: float,
) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	var expanded_board := board_rect.grow(-tolerance)
	return (
		viewport_rect.encloses(left_rect)
		and viewport_rect.encloses(right_rect)
		and not expanded_board.intersects(left_rect)
		and not expanded_board.intersects(right_rect)
	)


func _consumes_pointer(control: Control) -> bool:
	return control.mouse_filter == Control.MOUSE_FILTER_STOP
