class_name AiMatch
extends Node

## AI 対戦の手番オーケストレーション。
## 人の着手・待ったのあとに呼ばれ、AI 手番なら別スレッドでエンジンに問い合わせて
## GameSession.apply_move で合法手を載せる。メインスレッドはブロックしない。

signal thinking_changed(is_thinking: bool)
## AI が着手した、または探索を打ち切ったあとに盤面同期を促す。
signal board_updated
signal status_message(text: String)

var session: GameSession
var settings: AiSettings
var _adapter: EngineAdapter
var _thinking: bool = false
var _thread: Thread
var _search_token: int = 0
var _pending_result: String = ""
var _pending_token: int = -1
var _result_mutex := Mutex.new()


func setup(p_session: GameSession, p_settings: AiSettings) -> void:
	session = p_session
	settings = p_settings
	_adapter = settings.create_adapter() if settings != null else UciEngine.new()


func is_thinking() -> bool:
	return _thinking


func is_ai_enabled() -> bool:
	return settings != null and settings.can_play_ai()


func is_ai_turn() -> bool:
	if session == null or settings == null:
		return false
	if not settings.can_play_ai():
		return false
	if session.is_over():
		return false
	return session.side_to_move() != settings.human_side


func blocks_human_input() -> bool:
	## AI 手番中・思考中は人のクリックを受けない。
	return is_thinking() or is_ai_turn()


## 人の着手・待った・設定変更のあとに呼ぶ。
func on_position_changed() -> void:
	cancel_search()
	if is_ai_turn():
		_start_search()


func cancel_search() -> void:
	_search_token += 1
	if _adapter != null:
		_adapter.cancel_running()
	_set_thinking(false)


func rebind_settings(p_settings: AiSettings) -> void:
	cancel_search()
	settings = p_settings
	_adapter = settings.create_adapter() if settings != null else UciEngine.new()
	on_position_changed()


func _start_search() -> void:
	if session == null or settings == null:
		return
	if not settings.engine_available:
		status_message.emit(settings.engine_message)
		return
	_search_token += 1
	var token := _search_token
	var fen := BoardFen.to_fen(session.board())
	var path := settings.engine_path
	var strength := settings.strength
	var adapter := settings.create_adapter()
	_adapter = adapter
	_set_thinking(true)
	status_message.emit("AI 思考中… (%s)" % settings.strength_label())
	_thread = Thread.new()
	_thread.start(_thread_search.bind(adapter, path, fen, strength, token))


func _thread_search(
	adapter: EngineAdapter,
	path: String,
	fen: String,
	strength: int,
	token: int,
) -> void:
	var uci := adapter.search_best_move_sync(path, fen, strength, -1)
	_result_mutex.lock()
	_pending_result = uci
	_pending_token = token
	_result_mutex.unlock()
	# メインスレッドで適用する(ノード操作・シグナルはメイン限定)。
	call_deferred("_apply_pending_result")


func _apply_pending_result() -> void:
	_result_mutex.lock()
	var uci := _pending_result
	var token := _pending_token
	_pending_result = ""
	_pending_token = -1
	_result_mutex.unlock()

	if token != _search_token:
		# キャンセル済み
		_join_thread()
		return
	_set_thinking(false)
	_join_thread()

	if session == null or session.is_over():
		return
	if not is_ai_turn():
		return
	if uci.is_empty():
		status_message.emit("AI が手を返せませんでした")
		return
	var move := UciMoveParser.parse(uci)
	if move == null:
		status_message.emit("AI の手が解釈できません: %s" % uci)
		return
	var event := session.apply_move(move)
	if event == null:
		status_message.emit("AI の手が非合法でした: %s" % uci)
		return
	status_message.emit("AI: %s" % uci)
	board_updated.emit()
	# 人対 AI では通常ここで人手番に戻る。連続で AI 側になることは無い。


func _set_thinking(v: bool) -> void:
	if _thinking == v:
		return
	_thinking = v
	thinking_changed.emit(_thinking)


func _join_thread() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _exit_tree() -> void:
	cancel_search()
	_join_thread()
