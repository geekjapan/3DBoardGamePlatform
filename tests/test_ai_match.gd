extends "res://tests/case.gd"

## T28: AiMatch の対局ライフサイクル契約。
##
## 外部プロセスを起動せず、EngineAdapter の structured-result seam を制御する。
## 探索スレッドは worker の終了を待ってから main-thread の apply を直接呼ぶため、
## wall-clock timeout や実エンジンの有無に依存しない。


class ControlledAdapter extends EngineAdapter:
	var results: Array = []
	var search_count: int = 0
	var process_count: int = 0
	var cancel_count: int = 0
	var _hold: bool = false
	var _gate := Semaphore.new()


	func queue_result(status: int, move_text: String = "", message: String = "") -> void:
		results.append(make_search_result(status, move_text, message))


	func hold_next_search() -> void:
		_hold = true


	func release_search() -> void:
		if _hold:
			_hold = false
			_gate.post()


	func search_best_move_result_sync(
		_engine_path: String,
		_position: String,
		_strength: int,
		_movetime_ms: int = -1,
	) -> Dictionary:
		search_count += 1
		process_count += 1
		if _hold:
			_gate.wait()
		if results.is_empty():
			return make_search_result(
				EngineAdapter.SearchStatus.PROTOCOL_ERROR,
				"",
				"controlled adapter result queue is empty",
			)
		return results.pop_front() as Dictionary


	func cancel_running() -> void:
		cancel_count += 1
		release_search()


class CountingMatch extends AiMatch:
	var cancel_count: int = 0
	var position_changed_count: int = 0


	func cancel_search() -> void:
		cancel_count += 1


	func on_position_changed(_from_undo: bool = false) -> void:
		position_changed_count += 1


var _factory_adapter: EngineAdapter


func test_ai_thinking_blocks_controller_input_and_updates_overlay() -> void:
	var stub := ControlledAdapter.new()
	stub.hold_next_search()
	stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var session := GameSession.from_board(ShogiBoard.start())
	var ai := _new_match(session, stub)
	var view := BoardView.new()
	view.build_from(session.board())
	var hud := GameHud.new()
	var orbit := OrbitCamera.new()
	var controller := GameController.new()
	controller.setup(session, view, hud, orbit, ai)

	check(_apply_legal(session, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3))), "人の手を適用")
	ai.on_position_changed()
	check(ai.is_thinking(), "AI思考中")
	check(ai.blocks_human_input(), "AI思考中は入力を止める")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(120.0, 120.0)
	controller._unhandled_input(click)
	check(not session.is_selected(), "AI思考中のクリックを無視")

	var overlay := AiOverlay.new()
	overlay.set_thinking(true)
	check(overlay._thinking_label.visible, "思考中ラベルを表示")
	overlay.set_failed("PROCESS_EXITED", "engine stopped", true)
	check(overlay._failure_panel.visible, "障害パネルを表示")
	check(overlay._failure_label.text.contains("PROCESS_EXITED"), "障害分類を表示")
	overlay.set_retrying(true)
	check(overlay._retry_button.disabled, "再試行中は再試行ボタンを止める")
	overlay.clear_failure()
	check(not overlay._failure_panel.visible, "障害解除でパネルを隠す")
	_check_ai_mode_text(overlay)

	_finish_pending(ai, stub)
	_cleanup_match(ai, stub)
	overlay.free()
	_free_controller_fixture(controller, view, hud, orbit)


func test_usi_normal_move_promotion_and_drop_are_applied_as_legal_moves() -> void:
	var normal_board := ShogiBoard.start()
	var normal_session := GameSession.from_board(normal_board)
	var normal_stub := ControlledAdapter.new()
	normal_stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var normal_match := _new_match(normal_session, normal_stub)
	_advance_to_ai(normal_session, normal_match, _move_by_squares(normal_board, Vector2i(2, 2), Vector2i(2, 3)))
	_finish_pending(normal_match, normal_stub)
	check_eq(normal_session.side_to_move(), Piece.Side.WHITE, "通常USI手の後は人手番")
	check(normal_session.last_move_event() != null, "通常USI手でevent")
	var normal_piece: Piece = normal_session.board().piece_at(Vector2i(6, 5))
	check(normal_piece != null, "通常USI手の到着先に駒")
	if normal_piece != null:
		check_eq(normal_piece.kind, Piece.Kind.SHOGI_PAWN, "通常USI手を適用")
	_cleanup_match(normal_match, normal_stub)

	var promotion_board := _minimal_shogi_board()
	promotion_board.set_piece(Vector2i(4, 2), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_PAWN))
	promotion_board.set_piece(Vector2i(1, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_GOLD))
	var promotion_session := GameSession.from_board(promotion_board)
	var promotion_stub := ControlledAdapter.new()
	promotion_stub.queue_result(EngineAdapter.SearchStatus.OK, "5g5h+")
	var promotion_match := _new_match(promotion_session, promotion_stub)
	_advance_to_ai(
		promotion_session,
		promotion_match,
		_move_by_squares(promotion_board, Vector2i(1, 0), Vector2i(1, 1)),
	)
	_finish_pending(promotion_match, promotion_stub)
	var promoted_piece: Piece = promotion_session.board().piece_at(Vector2i(4, 1))
	check(promoted_piece != null, "USI成りの到着先に駒")
	if promoted_piece != null:
		check_eq(promoted_piece.kind, Piece.Kind.SHOGI_PROMOTED_PAWN, "USI成りを適用")
	_cleanup_match(promotion_match, promotion_stub)

	var drop_board := _minimal_shogi_board()
	drop_board.hands[Piece.Side.BLACK][Piece.Kind.SHOGI_SILVER] = 1
	drop_board.set_piece(Vector2i(1, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_GOLD))
	var drop_session := GameSession.from_board(drop_board)
	var drop_stub := ControlledAdapter.new()
	drop_stub.queue_result(EngineAdapter.SearchStatus.OK, "S*5e")
	var drop_match := _new_match(drop_session, drop_stub)
	_advance_to_ai(
		drop_session,
		drop_match,
		_move_by_squares(drop_board, Vector2i(1, 0), Vector2i(1, 1)),
	)
	_finish_pending(drop_match, drop_stub)
	var dropped_piece: Piece = drop_session.board().piece_at(Vector2i(4, 4))
	check(dropped_piece != null, "USI打ちを適用")
	if dropped_piece != null:
		check_eq(dropped_piece.kind, Piece.Kind.SHOGI_SILVER, "打った駒種")
	check_eq(
		int(drop_session.board().hands[Piece.Side.BLACK].get(Piece.Kind.SHOGI_SILVER, 0)),
		0,
		"打った後に持ち駒を消費",
	)
	_cleanup_match(drop_match, drop_stub)


func test_structured_failures_preserve_position_history_turn_and_persisted_enabled() -> void:
	var statuses := [
		EngineAdapter.SearchStatus.UNAVAILABLE,
		EngineAdapter.SearchStatus.PROTOCOL_ERROR,
		EngineAdapter.SearchStatus.SEARCH_TIMEOUT,
		EngineAdapter.SearchStatus.PROCESS_EXITED,
		EngineAdapter.SearchStatus.INVALID_MOVE,
	]
	for status in statuses:
		var path := "user://test_ai_match_failure_%d_%d.cfg" % [status, Time.get_ticks_usec()]
		var settings := _settings_with_path(path)
		var profile := settings.profile("usi")
		profile.enabled = true
		profile.engine_available = true
		settings.save_to_disk()
		var session := GameSession.from_board(ShogiBoard.start())
		var before_board := session.board()
		var before_turn := session.side_to_move()
		var before_undo := session.can_undo()
		var stub := ControlledAdapter.new()
		stub.queue_result(status, "not-a-legal-move", "structured failure")
		var ai := _new_match(session, stub, "usi", settings)
		var human_move := _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3))
		_advance_to_ai(session, ai, human_move)
		var after_human_board := session.board()
		_finish_pending(ai, stub)

		check(ai.is_failed(), "status %s は停止状態" % EngineAdapter.search_status_name(status))
		var details := ai.failure_details()
		check_eq(details.get("classification", ""), EngineAdapter.search_status_name(status), "status分類")
		check_eq(session.board(), after_human_board, "失敗後も人の手以降の盤を保持")
		check_eq(session.side_to_move(), Piece.Side.BLACK, "失敗後もAI手番を保持")
		check_eq(session.can_undo(), before_undo, "失敗後も履歴可否を保持")
		check(profile.enabled, "runtime failureで保存設定をオフにしない")
		var loaded := AiSettings.load_or_default(path)
		check(loaded.profile("usi").enabled, "persisted enabledを保持")

		_cleanup_match(ai, stub)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_retry_same_revision_is_one_search_and_repeated_click_is_blocked() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.queue_result(EngineAdapter.SearchStatus.PROCESS_EXITED, "", "first failure")
	stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var ai := _new_match(session, stub)
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	_finish_pending(ai, stub)
	var failed_board := session.board()
	check(ai.is_failed(), "初回探索は失敗")
	check_eq(stub.search_count, 1, "初回は探索1回")

	stub.hold_next_search()
	check(ai.retry_failed_search(), "同じ盤面の再試行を受理")
	check(not ai.retry_failed_search(), "思考中の連打を拒否")
	check_eq(stub.search_count, 1, "連打で探索を増やさない")
	check_eq(session.board(), failed_board, "再試行前の盤面revisionを固定")
	_finish_pending(ai, stub)
	check_eq(stub.search_count, 2, "再試行は探索1回だけ")
	check(not ai.is_failed(), "成功再試行で障害解除")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "再試行成功で人手番")
	_cleanup_match(ai, stub)


func test_retry_failure_remains_failed_without_mutating_position() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.queue_result(EngineAdapter.SearchStatus.PROCESS_EXITED, "", "first failure")
	stub.queue_result(EngineAdapter.SearchStatus.SEARCH_TIMEOUT, "", "retry failure")
	var ai := _new_match(session, stub)
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	_finish_pending(ai, stub)
	var failed_board := session.board()
	check(ai.retry_failed_search(), "失敗後の再試行")
	_finish_pending(ai, stub)
	check(ai.is_failed(), "再試行失敗も停止状態")
	check_eq(ai.failure_details().get("classification", ""), "SEARCH_TIMEOUT", "再試行失敗分類")
	check_eq(session.board(), failed_board, "再試行失敗で盤面不変")
	check_eq(session.side_to_move(), Piece.Side.BLACK, "再試行失敗でAI手番維持")
	check_eq(stub.search_count, 2, "失敗再試行は探索2回")
	_cleanup_match(ai, stub)


func test_rebind_disabled_profile_clears_failed_runtime_without_mutating_session() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.queue_result(EngineAdapter.SearchStatus.PROCESS_EXITED, "", "engine stopped")
	var ai := _new_match(session, stub)
	var status_messages: Array[String] = []
	var failure_cleared_events: Array[bool] = []
	ai.status_message.connect(func(text: String) -> void: status_messages.append(text))
	ai.failure_cleared.connect(func() -> void: failure_cleared_events.append(true))
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	_finish_pending(ai, stub)
	check(ai.is_failed(), "rebind前はFAILED")
	var failed_board := session.board()
	var failed_turn := session.side_to_move()
	var failed_result := session.result()
	var failed_result_text := session.result_text()
	var status_count := status_messages.size()
	var search_count := stub.search_count
	var cancel_count := stub.cancel_count

	var disabled_settings := _settings("usi")
	disabled_settings.profile("usi").enabled = false
	ai.rebind_settings(disabled_settings)

	check(not ai.is_ai_enabled(), "disabled profileへのrebind後はAI無効")
	check(not ai.is_failed(), "disabled profileへのrebindでFAILEDをclear")
	check(ai.failure_details().is_empty(), "retry不能なfailure detailsをclear")
	check(not ai.is_ai_turn(), "disabled profileへのrebind後はAI手番でない")
	check(not ai.is_thinking(), "disabled profileへのrebind後はthinking解除")
	check(not ai.retry_failed_search(), "clear後はstale failureをretryできない")
	check_eq(failure_cleared_events.size(), 1, "failure UIへclearを通知")
	check_eq(stub.cancel_count, cancel_count + 1, "rebindでadapter runtimeをcancel")
	check_eq(stub.search_count, search_count, "disabled rebindで探索を開始しない")
	check_eq(status_messages.size(), status_count, "rebindでstatus_message正本を上書きしない")
	check_eq(session.board(), failed_board, "rebindで盤面不変")
	check_eq(session.side_to_move(), failed_turn, "rebindで手番不変")
	check_eq(session.result(), failed_result, "rebindでGameResult不変")
	check_eq(session.result_text(), failed_result_text, "rebindでGameSession.result_text不変")
	_cleanup_match(ai, stub)


func test_cancelled_and_stale_results_are_ignored() -> void:
	for status in [EngineAdapter.SearchStatus.CANCELLED, EngineAdapter.SearchStatus.STALE]:
		var session := GameSession.from_board(ShogiBoard.start())
		var stub := ControlledAdapter.new()
		stub.queue_result(status)
		var ai := _new_match(session, stub)
		_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
		var before := session.board()
		_finish_pending(ai, stub)
		check(not ai.is_failed(), "status %s は障害にしない" % EngineAdapter.search_status_name(status))
		check_eq(session.board(), before, "status %s は盤面不変" % EngineAdapter.search_status_name(status))
		check_eq(session.side_to_move(), Piece.Side.BLACK, "status %s は手番不変" % EngineAdapter.search_status_name(status))
		_cleanup_match(ai, stub)

	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.hold_next_search()
	stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var ai := _new_match(session, stub)
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	var before := session.board()
	var cancel_before := stub.cancel_count
	ai.cancel_search()
	_finish_pending(ai, stub)
	check_eq(stub.cancel_count, cancel_before + 1, "cancelをadapterへ伝える")
	check(not ai.is_failed(), "cancel後のstale結果を無視")
	check_eq(session.board(), before, "cancel後のstale結果で盤面不変")
	check(not ai.is_thinking(), "cancel後は思考解除")
	_cleanup_match(ai, stub)


func test_disable_for_match_allows_ai_side_and_new_match_restores_profile() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.hold_next_search()
	stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var settings := _settings("usi")
	var ai := _new_match(session, stub, "usi", settings)
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	check(ai.is_ai_turn(), "解除前はAI手番")
	ai.disable_ai_for_match()
	check(not ai.is_ai_enabled(), "この対局だけAIを解除")
	check(not ai.blocks_human_input(), "解除後は元AI側も入力可能")
	check(settings.profile("usi").enabled, "解除で保存値を変更しない")
	check(_apply_legal(session, _move_by_squares(session.board(), Vector2i(6, 6), Vector2i(6, 5))), "解除後に元AI側を人が指せる")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "解除後の手番")
	_cleanup_match(ai, stub)

	var new_match := _new_match(session, stub, "usi", settings)
	check(new_match.is_ai_enabled(), "新しいAiMatchは保存設定から復元")
	check(not new_match.is_ai_turn(), "新しい対局は現在の人手番")
	_cleanup_match(new_match, stub)


func test_undo_history_zero_and_one_does_not_cancel_search() -> void:
	var zero := GameSession.from_board(ShogiBoard.start())
	var zero_match := CountingMatch.new()
	var zero_fixture := _controller_fixture(zero, zero_match)
	zero_match.cancel_count = 0
	(zero_fixture["controller"] as GameController)._on_undo()
	check_eq(zero_match.cancel_count, 0, "履歴0 undo はcancelしない")
	_free_controller_fixture(zero_fixture["controller"], zero_fixture["view"], zero_fixture["hud"], zero_fixture["orbit"])
	zero_match.free()

	var one := GameSession.from_board(ShogiBoard.start())
	check(_apply_legal(one, _move_by_squares(one.board(), Vector2i(2, 2), Vector2i(2, 3))), "履歴1を作る")
	var one_match := CountingMatch.new()
	var one_fixture := _controller_fixture(one, one_match)
	one_match.cancel_count = 0
	(one_fixture["controller"] as GameController)._on_undo()
	check_eq(one_match.cancel_count, 0, "履歴1 undo はcancelしない")
	_free_controller_fixture(one_fixture["controller"], one_fixture["view"], one_fixture["hud"], one_fixture["orbit"])
	one_match.free()


func test_undo_history_two_cancels_stale_search_and_restarts_once() -> void:
	var board := _minimal_shogi_board()
	board.side_to_move = Piece.Side.BLACK
	board.set_piece(Vector2i(7, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_GOLD))
	board.set_piece(Vector2i(1, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_GOLD))
	var session := GameSession.from_board(board)
	check(_apply_legal(session, _move_by_squares(session.board(), Vector2i(7, 8), Vector2i(7, 7))), "履歴1")
	check(_apply_legal(session, _move_by_squares(session.board(), Vector2i(1, 0), Vector2i(1, 1))), "履歴2")
	var stub := ControlledAdapter.new()
	stub.hold_next_search()
	stub.queue_result(EngineAdapter.SearchStatus.STALE)
	stub.queue_result(EngineAdapter.SearchStatus.OK, "3c3d")
	var settings := _settings("usi")
	settings.profile("usi").enabled = false
	var ai := _new_match(session, stub, "usi", settings)
	var fixture := _controller_fixture(session, ai)
	settings.profile("usi").enabled = true
	settings.profile("usi").engine_available = true
	ai.on_position_changed()
	check(ai.is_thinking(), "undo前にAI思考中")
	var controller: GameController = fixture["controller"]
	var cancel_before := stub.cancel_count
	controller._on_undo()
	check_eq(stub.cancel_count, cancel_before + 1, "履歴2 undo は探索をcancel")
	check_eq(session.side_to_move(), Piece.Side.BLACK, "undoでAI手番へ戻る")
	_finish_pending(ai, stub)
	check_eq(stub.search_count, 2, "成功undo後のrestartは1回")
	check(not ai.is_failed(), "cancel/stale結果で障害にしない")
	check_eq(stub.search_count, 2, "stale結果で二重restartしない")
	_cleanup_match(ai, stub)
	_free_controller_fixture(controller, fixture["view"], fixture["hud"], fixture["orbit"])


func test_ai_resign_finishes_session_with_human_win_and_preserves_board() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var stub := ControlledAdapter.new()
	stub.queue_result(EngineAdapter.SearchStatus.RESIGNED, "", "resign")
	var ai := _new_match(session, stub)
	var status_messages: Array[String] = []
	ai.status_message.connect(func(text: String) -> void: status_messages.append(text))
	_advance_to_ai(session, ai, _move_by_squares(session.board(), Vector2i(2, 2), Vector2i(2, 3)))
	var searched_board := session.board()
	var searched_turn := session.side_to_move()
	check_eq(searched_turn, Piece.Side.BLACK, "AI投了処理前はAI手番")
	check(session.result() == null, "AI投了処理前は進行中")
	_finish_pending(ai, stub)
	var result := session.result()
	check(result != null, "AI投了で終局")
	if result != null:
		check_eq(result.reason, GameResult.Reason.RESIGN, "投了理由")
		check_eq(result.winner_side, Piece.Side.WHITE, "AI投了で人の勝ち")
	check_eq(session.board(), searched_board, "投了で盤面不変")
	check_eq(session.side_to_move(), searched_turn, "投了で手番不変")
	check(not status_messages.is_empty(), "AI投了後にstatusを発火")
	if not status_messages.is_empty():
		check_eq(status_messages.back(), session.result_text(), "最終statusはSession結果文")
	_cleanup_match(ai, stub)


func _check_ai_mode_text(overlay: AiOverlay) -> void:
	overlay.set_ai_mode(true, "強", true)
	check(overlay._ai_badge.text.contains("AI 対戦: オン"), "AIオン表示")
	overlay.set_ai_mode(false, "", true)
	check(overlay._ai_badge.text.contains("AI 対戦: オフ"), "AIオフ表示")
	overlay.set_ai_mode(false, "", false)
	check(overlay._ai_badge.text.contains("エンジンなし"), "エンジンなし表示")


func _new_match(
	session: GameSession,
	stub: ControlledAdapter,
	protocol: String = "usi",
	settings: AiSettings = null,
) -> AiMatch:
	_factory_adapter = stub
	var ai := AiMatch.new()
	ai.adapter_factory = Callable(self, "_make_adapter")
	ai.setup(session, settings if settings != null else _settings(protocol), protocol)
	return ai


func _make_adapter() -> EngineAdapter:
	return _factory_adapter


func _settings(protocol: String = "usi") -> AiSettings:
	var settings := AiSettings.new()
	var profile := settings.profile(protocol)
	profile.enabled = true
	profile.engine_available = true
	profile.engine_message = "controlled adapter"
	profile.engine_path = "/controlled"
	profile.human_side = Piece.Side.WHITE
	profile.status_checked = true
	return settings


func _settings_with_path(path: String) -> AiSettings:
	var settings := _settings("usi")
	settings.config_path = path
	return settings


func _advance_to_ai(session: GameSession, ai: AiMatch, move: Move) -> void:
	check(_apply_legal(session, move), "人の合法手")
	ai.on_position_changed()


func _apply_legal(session: GameSession, move: Move) -> bool:
	return move != null and session.apply_move(move) != null


func _finish_pending(ai: AiMatch, stub: ControlledAdapter) -> void:
	stub.release_search()
	var thread: Thread = ai._thread
	if thread != null and thread.is_started():
		thread.wait_to_finish()
	ai._apply_pending_result()


func _cleanup_match(ai: AiMatch, stub: ControlledAdapter) -> void:
	ai.cancel_search()
	stub.release_search()
	var thread: Thread = ai._thread
	if thread != null and thread.is_started():
		thread.wait_to_finish()
	ai.free()


func _controller_fixture(session: GameSession, ai: AiMatch) -> Dictionary:
	var view := BoardView.new()
	view.build_from(session.board())
	var hud := GameHud.new()
	var orbit := OrbitCamera.new()
	var controller := GameController.new()
	controller.setup(session, view, hud, orbit, ai)
	return {"controller": controller, "view": view, "hud": hud, "orbit": orbit}


func _free_controller_fixture(controller: Variant, view: Variant, hud: Variant, orbit: Variant) -> void:
	if controller != null:
		(controller as Node).free()
	if view != null:
		(view as Node).free()
	if hud != null:
		(hud as Node).free()
	if orbit != null:
		(orbit as Node).free()


func _minimal_shogi_board() -> ShogiBoard:
	var board := ShogiBoard.empty()
	board.set_piece(Vector2i(0, 0), Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_KING))
	board.set_piece(Vector2i(8, 8), Piece.new(Piece.Side.BLACK, Piece.Kind.SHOGI_KING))
	return board


func _move_by_squares(board: Object, from: Vector2i, to: Vector2i, promotion: int = -1) -> Move:
	for candidate in board.legal_moves():
		var move := candidate as Move
		if move.from == from and move.to == to and move.promotion == promotion:
			return move
	return null
