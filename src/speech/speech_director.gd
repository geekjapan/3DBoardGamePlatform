class_name SpeechDirector
extends Node

## 対局セッションの MoveEvent を監視し、発話モードに応じてセリフを出す。
## LINES: 定型文を吹き出し表示
## TTS: 定型文を表示し、同じ本文を読み上げ
## LLM: 性格と盤状況から生成。失敗・時間切れ・キー未設定は定型へフォールバック
## GameController を書き換えず、last_move_event の差分で着手を検出する。

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


func _process(_delta: float) -> void:
	if session == null or resolver == null:
		return
	var event := session.last_move_event()
	if event == null or event == _last_event:
		return
	_last_event = event
	present_event(event)


func present_event(event: MoveEvent) -> Array:
	## テストからも呼べる入口。表示した SpeechBubble の配列を返す。
	var shown: Array = []
	last_resolve_reasons = PackedStringArray()
	if resolver == null:
		return shown
	var plan: Array = resolver.plan(event)
	var mode := SpeechSettings.Mode.LINES
	if speech_settings != null:
		mode = speech_settings.mode
	for item in plan:
		var utterance := item as SpeechUtterance
		if utterance == null or utterance.text == "":
			continue
		var fixed_text := utterance.text
		var final_text := fixed_text
		var reason := "lines"
		if mode == SpeechSettings.Mode.LLM:
			var resolved := _resolve_llm_text(utterance, event, fixed_text)
			final_text = str(resolved.get("text", fixed_text))
			reason = str(resolved.get("reason", LlmSpeechClient.REASON_ERROR))
			utterance.text = final_text
		last_resolve_reasons.append(reason)
		if final_text == "":
			continue
		var bubble := _spawn_bubble(utterance)
		if bubble != null:
			shown.append(bubble)
		# 音声モード: 表示と同じ本文を読み上げる。
		if mode == SpeechSettings.Mode.TTS and tts_speaker != null:
			tts_speaker.speak(final_text)
	return shown


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
	var side_label := "先手" if utterance.side == Piece.Side.WHITE else "後手"
	var kind_label := SpeechCatalog.kind_name(utterance.kind)
	var board_hint := _board_hint(event, utterance)
	return {
		"fallback_text": fallback,
		"personality": personality,
		"event_key": utterance.event_key,
		"character_name": utterance.character_id,
		"display_name": display_name,
		"side_label": side_label,
		"kind_label": kind_label,
		"board_hint": board_hint,
	}


func _board_hint(event: MoveEvent, utterance: SpeechUtterance) -> String:
	if event == null:
		return ""
	var parts: PackedStringArray = []
	if event.move != null:
		if event.was_drop():
			parts.append(
				"打つ: %s → %s" % [SpeechCatalog.kind_name(event.mover_kind), _square_label(event.to_square())]
			)
		else:
			parts.append(
				"手: %s → %s" % [_square_label(event.from_square()), _square_label(event.to_square())]
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


func _square_label(sq: Vector2i) -> String:
	if sq.x < 0 or sq.y < 0:
		return "?"
	var file := char(97 + sq.x)  # a-i
	var rank := str(sq.y + 1)
	return "%s%s" % [file, rank]


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
	# 実対局では session の実盤寸法を必ず座標変換へ渡す。
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
