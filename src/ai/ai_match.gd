class_name AiMatch
extends Node

## 外部エンジンとの1対局分の調停。探索は worker thread、状態適用は main thread。
## エンジン障害時は AI 手番を維持したまま fail closed で停止する。

signal thinking_changed(is_thinking: bool)
signal board_updated
signal status_message(text: String)
signal failure_changed(details: Dictionary)
signal failure_cleared
signal ai_disabled_for_match

enum RuntimeState {
	ACTIVE,
	FAILED,
	DISABLED_FOR_MATCH,
}

var session: GameSession
var settings: AiSettings
var protocol: String = "uci"
## テスト用の生成 seam。空なら settings.create_adapter(protocol) を使う。
var adapter_factory: Callable

var _adapter: EngineAdapter
var _thinking: bool = false
var _thread: Thread
var _workers: Array[Thread] = []
var _completed_results: Array = []
var _completed_mutex := Mutex.new()
var _search_token: int = 0
var _runtime_state: int = RuntimeState.ACTIVE
var _failure: Dictionary = {}
var _failed_board: Object


func setup(p_session: GameSession, p_settings: AiSettings, p_protocol: String = "uci") -> void:
	session = p_session
	settings = p_settings
	protocol = "usi" if p_protocol == "usi" else "uci"
	_adapter = _create_adapter()


func is_thinking() -> bool:
	return _thinking


func is_failed() -> bool:
	return _runtime_state == RuntimeState.FAILED


func failure_details() -> Dictionary:
	return _failure.duplicate(true)


func is_ai_enabled() -> bool:
	return _runtime_state != RuntimeState.DISABLED_FOR_MATCH and _profile_can_play_ai()


func is_ai_turn() -> bool:
	if session == null or settings == null or not is_ai_enabled() or session.is_over():
		return false
	return session.side_to_move() != _profile_human_side()


func blocks_human_input() -> bool:
	return is_thinking() or is_ai_turn()


## 人の成功着手、または成功した2プライundo後に呼ぶ。
func on_position_changed(from_undo: bool = false) -> void:
	# Controller は undo 成功が確定した場合だけ先に cancel している。
	if not from_undo:
		cancel_search()
	if from_undo or _runtime_state == RuntimeState.FAILED:
		_clear_failure()
	if is_ai_turn():
		_start_search()


func cancel_search() -> void:
	_search_token += 1
	if _adapter != null:
		_adapter.cancel_running()
	_set_thinking(false)


## 設定保存・probeだけでは障害局面の探索を自動再開しない。
func rebind_settings(p_settings: AiSettings) -> void:
	cancel_search()
	settings = p_settings
	_adapter = _create_adapter()
	if _runtime_state == RuntimeState.ACTIVE and is_ai_turn():
		_start_search()


func retry_failed_search() -> bool:
	if _runtime_state != RuntimeState.FAILED or _thinking:
		return false
	if session == null or session.board() != _failed_board or not is_ai_turn():
		return false
	_start_search(true)
	return true


func disable_ai_for_match() -> void:
	if _runtime_state == RuntimeState.DISABLED_FOR_MATCH:
		return
	cancel_search()
	_runtime_state = RuntimeState.DISABLED_FOR_MATCH
	_failure.clear()
	_failed_board = null
	failure_cleared.emit()
	ai_disabled_for_match.emit()


func _start_search(is_retry: bool = false) -> void:
	if session == null or settings == null or _thinking:
		return
	if not _profile_engine_available():
		_fail({
			"status": EngineAdapter.SearchStatus.UNAVAILABLE,
			"message": _profile_engine_message(),
		})
		return
	if not is_retry:
		_clear_failure()
	_search_token += 1
	var token := _search_token
	var board := session.board()
	var position := _position_for(board)
	if position.is_empty():
		_fail({
			"status": EngineAdapter.SearchStatus.PROTOCOL_ERROR,
			"message": "局面をエンジン形式へ変換できません",
		})
		return
	var path := _profile_engine_path()
	var strength := _profile_strength()
	var adapter := _create_adapter()
	_adapter = adapter
	_set_thinking(true)
	status_message.emit("AI 思考中… (%s)" % _strength_label(strength))
	var worker := Thread.new()
	_thread = worker
	_workers.append(worker)
	worker.start(_thread_search.bind(adapter, path, position, strength, token, board, worker))


func _thread_search(
	adapter: EngineAdapter,
	path: String,
	position: String,
	strength: int,
	token: int,
	board: Object,
	worker: Thread,
) -> void:
	var result := adapter.search_best_move_result_sync(path, position, strength, -1)
	_completed_mutex.lock()
	_completed_results.append({
		"result": result,
		"token": token,
		"board": board,
		"worker": worker,
	})
	_completed_mutex.unlock()
	call_deferred("_apply_pending_result")


func _apply_pending_result() -> void:
	## 完了順の worker/result を個別に処理し、旧 token が新 worker を join しない。
	_completed_mutex.lock()
	var item: Dictionary = _completed_results.pop_front() if not _completed_results.is_empty() else {}
	_completed_mutex.unlock()
	if item.is_empty():
		return
	_apply_search_result(
		item["result"] as Dictionary,
		int(item["token"]),
		item["board"] as Object,
		item["worker"] as Thread,
	)


func _apply_search_result(result: Dictionary, token: int, searched_board: Object, worker: Thread) -> void:
	_join_worker(worker)
	if token != _search_token:
		return
	_set_thinking(false)
	if session == null or session.is_over() or session.board() != searched_board or not is_ai_turn():
		return
	var status := int(result.get("status", EngineAdapter.SearchStatus.PROTOCOL_ERROR))
	if status == EngineAdapter.SearchStatus.CANCELLED or status == EngineAdapter.SearchStatus.STALE:
		return
	if status == EngineAdapter.SearchStatus.RESIGNED:
		if session.finish_by_resignation(session.side_to_move()):
			_clear_failure()
			status_message.emit(session.result_text())
			board_updated.emit()
		else:
			_fail({"status": EngineAdapter.SearchStatus.STALE, "message": "投了結果が失効しました"})
		return
	if status != EngineAdapter.SearchStatus.OK:
		_fail(result)
		return

	var move_text := str(result.get("move_text", ""))
	var move: Move
	if protocol == "usi":
		move = ShogiUsiCodec.parse_legal_move(session.board(), move_text)
	else:
		move = UciMoveParser.parse(move_text)
	if move == null:
		_fail({
			"status": EngineAdapter.SearchStatus.INVALID_MOVE,
			"message": "AI の手が解釈または合法手照合できません: %s" % move_text,
		})
		return
	var event := session.apply_move(move)
	if event == null:
		_fail({
			"status": EngineAdapter.SearchStatus.INVALID_MOVE,
			"message": "AI の手が非合法でした: %s" % move_text,
		})
		return
	_clear_failure()
	status_message.emit("AI: %s" % move_text)
	board_updated.emit()


func _fail(result: Dictionary) -> void:
	var status := int(result.get("status", EngineAdapter.SearchStatus.PROTOCOL_ERROR))
	if status == EngineAdapter.SearchStatus.CANCELLED or status == EngineAdapter.SearchStatus.STALE:
		return
	_runtime_state = RuntimeState.FAILED
	_failed_board = session.board() if session != null else null
	_failure = result.duplicate(true)
	_failure["classification"] = EngineAdapter.search_status_name(status)
	if str(_failure.get("message", "")).is_empty():
		_failure["message"] = "外部エンジンが探索を完了できませんでした"
	failure_changed.emit(_failure.duplicate(true))


func _clear_failure() -> void:
	if _runtime_state == RuntimeState.DISABLED_FOR_MATCH:
		return
	var had_failure := _runtime_state == RuntimeState.FAILED
	_runtime_state = RuntimeState.ACTIVE
	_failure.clear()
	_failed_board = null
	if had_failure:
		failure_cleared.emit()


func _position_for(board: Object) -> String:
	if protocol == "usi":
		return ShogiUsiCodec.position_for(board)
	return BoardFen.to_fen(board as Board)


func _create_adapter() -> EngineAdapter:
	if adapter_factory.is_valid():
		return adapter_factory.call() as EngineAdapter
	if settings != null:
		return settings.create_adapter(protocol)
	return EngineFactory.create(protocol)


func _profile() -> Variant:
	return settings.profile(protocol) if settings != null else null


func _profile_can_play_ai() -> bool:
	var p: Variant = _profile()
	return p != null and bool(p.engine_available) and bool(p.enabled)


func _profile_human_side() -> int:
	var p: Variant = _profile()
	return int(p.human_side) if p != null else Piece.Side.WHITE


func _profile_engine_available() -> bool:
	var p: Variant = _profile()
	return p != null and bool(p.engine_available)


func _profile_engine_message() -> String:
	var p: Variant = _profile()
	return str(p.engine_message) if p != null else "エンジン設定がありません"


func _profile_engine_path() -> String:
	var p: Variant = _profile()
	return str(p.engine_path) if p != null else ""


func _profile_strength() -> int:
	var p: Variant = _profile()
	return int(p.strength) if p != null else EngineAdapter.Strength.MEDIUM


func _strength_label(value: int) -> String:
	match value:
		EngineAdapter.Strength.WEAK: return "弱"
		EngineAdapter.Strength.STRONG: return "強"
		_: return "中"


func _set_thinking(v: bool) -> void:
	if _thinking == v:
		return
	_thinking = v
	thinking_changed.emit(_thinking)


func _join_thread() -> void:
	if _thread != null:
		_join_worker(_thread)


func _join_worker(worker: Thread) -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
	_workers.erase(worker)
	if _thread == worker:
		_thread = null


func _join_all_workers() -> void:
	for worker in _workers.duplicate():
		_join_worker(worker)


func _exit_tree() -> void:
	cancel_search()
	_join_all_workers()
