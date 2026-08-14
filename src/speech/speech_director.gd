class_name SpeechDirector
extends Node
## GameEvent に応じて SpeechUtterance を表示・音声化する。
## LLM モードでは定型文を即時表示し、生成結果は後続フレームで反映する。

var session: GameSession
var board_view: BoardView
var resolver: SpeechResolver
var square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE
var speech_settings: SpeechSettings
var llm_client: LlmSpeechClient
var tts_speaker: TtsSpeaker
## 取られた駒など、親にできない吹き出しの置き場。
var _world_bubbles: Node3D
var _last_event: MoveEvent = null
## 直近 present のフォールバック理由(テスト用)。utterance ごとの reason 配列。
var last_resolve_reasons: PackedStringArray = PackedStringArray()

var _active_llm_token := 0
var _next_llm_request_id := 0
var _test_pending_requests: Array = []
var _request_targets: Dictionary = {}
var _completed_llm_results: Array = []
var _completed_mutex := Mutex.new()
var _workers: Dictionary = {}


func setup(
	p_session: GameSession,
	p_board_view: BoardView,
	p_resolver: SpeechResolver,
	p_square_size: float = BoardLayout.DEFAULT_SQUARE_SIZE,
	p_settings: SpeechSettings = null,
	p_llm: LlmSpeechClient = null,
	p_tts: TtsSpeaker = null,
) -> void:
	session = p_session
	board_view = p_board_view
	resolver = p_resolver
	square_size = p_square_size
	speech_settings = p_settings if p_settings != null else SpeechSettings.new()
	llm_client = p_llm if p_llm != null else LlmSpeechClient.new()
	tts_speaker = p_tts if p_tts != null else TtsSpeaker.new()
	if speech_settings != null:
		llm_client.timeout_ms = speech_settings.llm_timeout_ms
	if _world_bubbles == null:
		_world_bubbles = Node3D.new()
		_world_bubbles.name = "WorldSpeechBubbles"
		add_child(_world_bubbles)
	set_process(true)


func apply_speech_settings(settings: SpeechSettings) -> void:
	speech_settings = settings if settings != null else SpeechSettings.new()
	if resolver != null:
		speech_settings.apply_to_resolver(resolver)
	if llm_client != null:
		llm_client.timeout_ms = speech_settings.llm_timeout_ms
	if speech_settings.mode != SpeechSettings.Mode.LLM:
		_cancel_pending_llm_requests()


func _process(_delta: float) -> void:
	# 新着手を先に検知して旧要求を取り消す。こうすれば、現在の対局状態より
	# 前の GameEvent に対する完了結果が新着手後に吹き出しを更新しない。
	if session != null and resolver != null:
		var event := session.last_move_event()
		if event != null and event != _last_event:
			_last_event = event
			present_event(event)
			return
	# 新規要求は次フレーム以降に処理するため、定型文を必ず先に表示できる。
	poll_pending_llm_requests()


func present_event(event: MoveEvent) -> Array:
	## テストからも呼べる入口。定型の SpeechBubble 配列を直ちに返す。
	var shown: Array = []
	last_resolve_reasons = PackedStringArray()
	if resolver == null:
		return shown
	_cancel_pending_llm_requests()
	var plan: Array = resolver.plan(event)
	var mode := SpeechSettings.Mode.LINES
	if speech_settings != null:
		mode = speech_settings.mode
	var token := _active_llm_token
	for item in plan:
		var utterance := item as SpeechUtterance
		if utterance == null or utterance.text == "":
			continue
		var fixed_text := utterance.text
		var bubble := _spawn_bubble(utterance)
		if bubble != null:
			shown.append(bubble)
		if mode == SpeechSettings.Mode.LLM:
			var reason := LlmSpeechClient.REASON_ERROR
			if llm_client != null and llm_client.has_api_key():
				var reason_index := last_resolve_reasons.size()
				last_resolve_reasons.append("pending")
				if bubble != null:
					_queue_llm_request(utterance, event, fixed_text, bubble, token, reason_index)
				else:
					last_resolve_reasons[reason_index] = LlmSpeechClient.REASON_ERROR
			else:
				reason = LlmSpeechClient.REASON_NO_KEY if llm_client != null else LlmSpeechClient.REASON_ERROR
				last_resolve_reasons.append(reason)
		# 音声モード: 表示と同じ本文を読み上げる。
		if mode == SpeechSettings.Mode.TTS and tts_speaker != null:
			tts_speaker.speak(fixed_text)
	return shown


func poll_pending_llm_requests() -> void:
	## メインスレッドで完了済み結果だけを反映する。実ネットワークは worker が処理する。
	while not _test_pending_requests.is_empty():
		var request: Dictionary = _test_pending_requests.pop_front() as Dictionary
		var client := request.get("client") as LlmSpeechClient
		var context: Dictionary = request.get("context", {}) as Dictionary
		var result := client.generate_or_fallback(context) if client != null else {
			"text": str(context.get("fallback_text", "")),
			"used_fallback": true,
			"reason": LlmSpeechClient.REASON_ERROR,
		}
		_apply_llm_result(int(request.get("request_id", -1)), int(request.get("token", -1)), result)
	_apply_completed_llm_results()


func _queue_llm_request(
	utterance: SpeechUtterance,
	event: MoveEvent,
	fallback: String,
	bubble: SpeechBubble,
	token: int,
	reason_index: int,
) -> void:
	_next_llm_request_id += 1
	var request_id := _next_llm_request_id
	var context := build_llm_context(utterance, event, fallback)
	_request_targets[request_id] = {
		"token": token,
		"bubble": weakref(bubble),
		"utterance": utterance,
		"reason_index": reason_index,
	}
	# transport はネットワークを使わない既存テスト用の seam。実HTTPは必ず worker 側へ送る。
	if llm_client.transport.is_valid():
		_test_pending_requests.append({
			"request_id": request_id,
			"token": token,
			"client": llm_client,
			"context": context,
		})
		return
	var worker := Thread.new()
	_workers[request_id] = worker
	worker.start(_thread_resolve_llm.bind(llm_client, context, token, request_id, worker))


func _thread_resolve_llm(
	client: LlmSpeechClient,
	context: Dictionary,
	token: int,
	request_id: int,
	worker: Thread,
) -> void:
	var result := client.generate_or_fallback(context)
	_completed_mutex.lock()
	_completed_llm_results.append({
		"request_id": request_id,
		"token": token,
		"result": result,
		"worker": worker,
	})
	_completed_mutex.unlock()
	call_deferred("_apply_completed_llm_results")


func _apply_completed_llm_results() -> void:
	while true:
		_completed_mutex.lock()
		var item: Dictionary = _completed_llm_results.pop_front() if not _completed_llm_results.is_empty() else {}
		_completed_mutex.unlock()
		if item.is_empty():
			return
		var worker := item.get("worker") as Thread
		if worker != null:
			worker.wait_to_finish()
		_apply_llm_result(
			int(item.get("request_id", -1)),
			int(item.get("token", -1)),
			item.get("result", {}) as Dictionary
		)


func _apply_llm_result(request_id: int, token: int, result: Dictionary) -> void:
	var target: Dictionary = _request_targets.get(request_id, {}) as Dictionary
	_request_targets.erase(request_id)
	_workers.erase(request_id)
	if target.is_empty() or token != _active_llm_token:
		return
	var reason_index := int(target.get("reason_index", -1))
	var reason := str(result.get("reason", LlmSpeechClient.REASON_ERROR))
	if reason_index >= 0 and reason_index < last_resolve_reasons.size():
		last_resolve_reasons[reason_index] = reason
	if bool(result.get("used_fallback", true)) or reason != LlmSpeechClient.REASON_OK:
		return
	var bubble_ref := target.get("bubble") as WeakRef
	var bubble := bubble_ref.get_ref() as SpeechBubble if bubble_ref != null else null
	if bubble == null or not is_instance_valid(bubble):
		return
	var text := str(result.get("text", "")).strip_edges()
	if text == "":
		return
	bubble.set_text(text)
	var utterance := target.get("utterance") as SpeechUtterance
	if utterance != null:
		utterance.text = text


func _cancel_pending_llm_requests() -> void:
	_active_llm_token += 1
	for request in _test_pending_requests:
		var item := request as Dictionary
		_request_targets.erase(int(item.get("request_id", -1)))
	_test_pending_requests.clear()


func _resolve_llm_text(utterance: SpeechUtterance, event: MoveEvent, fallback: String) -> Dictionary:
	if llm_client == null:
		return {
			"text": fallback,
			"used_fallback": true,
			"reason": LlmSpeechClient.REASON_ERROR,
		}
	var context := build_llm_context(utterance, event, fallback)
	return llm_client.generate_or_fallback(context)


func build_llm_context(
	utterance: SpeechUtterance,
	event: MoveEvent,
	fallback: String,
) -> Dictionary:
	var personality := ""
	var display_name := utterance.character_id
	if resolver != null and resolver.catalog != null:
		var character := resolver.catalog.character(utterance.character_id)
		if character != null:
			personality = character.personality
			if character.display_name != "":
				display_name = character.display_name
	var game_id := _game_id()
	var side_label := "先手" if utterance.side == Piece.Side.WHITE else "後手"
	var kind_label := SpeechCatalog.kind_name(utterance.kind)
	var board_hint := _board_hint(event, utterance, game_id)
	return {
		"fallback_text": fallback,
		"game_id": game_id,
		"personality": personality,
		"event_key": utterance.event_key,
		"character_name": utterance.character_id,
		"display_name": display_name,
		"side_label": side_label,
		"kind_label": kind_label,
		"board_hint": board_hint,
	}


func _game_id() -> String:
	if session != null and session.board() is ShogiBoard:
		return SpeechCatalog.GAME_SHOGI
	return SpeechCatalog.GAME_CHESS


func _board_hint(event: MoveEvent, utterance: SpeechUtterance, game_id: String) -> String:
	if event == null:
		return ""
	var parts: PackedStringArray = []
	if event.move != null:
		if event.was_drop():
			parts.append(
				"打つ: %s → %s" % [SpeechCatalog.kind_name(event.mover_kind), _square_label(event.to_square(), game_id)]
			)
		else:
			parts.append(
				"手: %s → %s" % [_square_label(event.from_square(), game_id), _square_label(event.to_square(), game_id)]
			)
	if event.was_capture() and event.captured != null:
		parts.append("取った駒: %s" % SpeechCatalog.kind_name(event.captured.kind))
	if event.is_check:
		parts.append("王手")
	if event.was_promotion():
		parts.append("成り")
	if event.is_over:
		parts.append("終局: %s" % event.result_text)
	if utterance.is_victim:
		parts.append("発話者は取られた側")
	return " / ".join(parts)


func _square_label(sq: Vector2i, game_id: String) -> String:
	if sq.x < 0 or sq.y < 0:
		return "?"
	if game_id == SpeechCatalog.GAME_SHOGI:
		var files := ["９", "８", "７", "６", "５", "４", "３", "２", "１"]
		var ranks := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
		if sq.x >= files.size() or sq.y >= ranks.size():
			return "?"
		return "%s%s" % [str(files[sq.x]), str(ranks[sq.y])]
	return "%s%d" % [char(97 + sq.x), sq.y + 1]


func _spawn_bubble(utterance: SpeechUtterance) -> SpeechBubble:
	var bubble := SpeechBubble.new(utterance.text)
	var piece_node: PieceNode = null
	if board_view != null and not utterance.is_victim:
		piece_node = board_view.piece_node_at(utterance.square)
	if piece_node != null and is_instance_valid(piece_node):
		# 駒の子に付ければ移動・カメラ回転でも追従する。
		piece_node.add_child(bubble)
		bubble.position = Vector3.ZERO
		return bubble
	# 取られた駒やノード未同期時はマスのワールド座標に置く。
	if _world_bubbles == null:
		_world_bubbles = Node3D.new()
		_world_bubbles.name = "WorldSpeechBubbles"
		add_child(_world_bubbles)
	# session が無ければ実盤寸法を確定できないため、座標変換は行わない。
	var world := Vector3.ZERO
	if session != null:
		var board := session.board()
		var board_size := Vector2i(board.width, board.height)
		world = BoardLayout.square_to_world(utterance.square, board_size, square_size)
	_world_bubbles.add_child(bubble)
	# ツリー外では global_position が使えないのでローカルで置く。
	if _world_bubbles.is_inside_tree():
		bubble.global_position = world
	else:
		bubble.position = world
	return bubble


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for worker_variant in _workers.values():
		var worker := worker_variant as Thread
		if worker != null and worker.is_started():
			worker.wait_to_finish()
