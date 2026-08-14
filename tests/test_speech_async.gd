extends "res://tests/case.gd"


func test_llm_request_defers_transport_and_updates_fixed_bubble_on_poll() -> void:
	var catalog := _catalog_with_single("speaker", {"moved": ["定型セリフ"]})
	catalog.team.assign(Piece.Kind.PAWN, "speaker")
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.LLM
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key"
	var transport_state := {"calls": 0}
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		transport_state["calls"] = int(transport_state["calls"]) + 1
		return {"ok": true, "text": "生成セリフ", "timed_out": false, "error": ""}
	var director := SpeechDirector.new()
	director.setup(null, null, resolver, 1.0, settings, client, null)

	var bubbles: Array = director.present_event(_quiet_move())
	check_eq(transport_state["calls"], 0, "present_event 中に生成I/Oを開始しない")
	check_eq(bubbles.size(), 1, "定型吹き出しを即時表示")
	var bubble := bubbles[0] as SpeechBubble
	check_eq(bubble.text(), "定型セリフ", "生成前は定型文")

	director.poll_pending_llm_requests()
	check_eq(transport_state["calls"], 1, "フレーム更新側で生成を開始")
	check_eq(bubble.text(), "生成セリフ", "成功結果だけが対応する吹き出しを更新")
	director.free()


func test_llm_failure_leaves_immediate_fixed_bubble_unchanged() -> void:
	var catalog := _catalog_with_single("speaker", {"moved": ["定型セリフ"]})
	catalog.team.assign(Piece.Kind.PAWN, "speaker")
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.LLM
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key"
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		return {"ok": false, "text": "", "timed_out": false, "error": "network"}
	var director := SpeechDirector.new()
	director.setup(null, null, resolver, 1.0, settings, client, null)

	var bubbles: Array = director.present_event(_quiet_move())
	var bubble := bubbles[0] as SpeechBubble
	director.poll_pending_llm_requests()
	check_eq(bubble.text(), "定型セリフ", "通信失敗時は定型文を維持")
	director.free()


func test_new_event_cancels_older_pending_llm_update() -> void:
	var catalog := _catalog_with_single("speaker", {"moved": ["定型セリフ"]})
	catalog.team.assign(Piece.Kind.PAWN, "speaker")
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.LLM
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key"
	var transport_state := {"calls": 0}
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		transport_state["calls"] = int(transport_state["calls"]) + 1
		return {"ok": true, "text": "最新の生成文", "timed_out": false, "error": ""}
	var director := SpeechDirector.new()
	director.setup(null, null, resolver, 1.0, settings, client, null)

	var first: Array = director.present_event(_quiet_move())
	var second: Array = director.present_event(_quiet_move())
	director.poll_pending_llm_requests()
	check_eq(transport_state["calls"], 1, "取消済みの古い要求は生成しない")
	check_eq((first[0] as SpeechBubble).text(), "定型セリフ", "古い吹き出しを更新しない")
	check_eq((second[0] as SpeechBubble).text(), "最新の生成文", "最新の吹き出しだけ更新")
	director.free()


func test_shogi_context_and_prompt_use_game_specific_terms_and_coordinates() -> void:
	var session := GameSession.from_board(ShogiBoard.start())
	var director := SpeechDirector.new()
	director.setup(session, null, null, 1.0, SpeechSettings.new(), LlmSpeechClient.new(), null)
	var utterance := SpeechUtterance.new()
	utterance.character_id = "shogi-speaker"
	utterance.side = Piece.Side.WHITE
	utterance.kind = Piece.Kind.SHOGI_PAWN
	utterance.event_key = "dropped"
	var drop_event := MoveEvent.new()
	drop_event.move = Move.drop(Piece.Kind.SHOGI_PAWN, Vector2i(4, 4))
	drop_event.mover_side = Piece.Side.WHITE
	drop_event.mover_kind = Piece.Kind.SHOGI_PAWN

	var drop_context := director.build_llm_context(utterance, drop_event, "定型セリフ")
	check_eq(drop_context.get("game_id"), SpeechCatalog.GAME_SHOGI, "将棋を明示")
	check(str(drop_context.get("board_hint", "")).contains("打つ"), "打つ手を説明")
	check(str(drop_context.get("board_hint", "")).contains("５五"), "将棋の中心座標を使う")
	check(not str(drop_context.get("board_hint", "")).contains("e5"), "チェス座標を使わない")

	var promotion_event := MoveEvent.new()
	promotion_event.move = Move.new(
		Vector2i(4, 3),
		Vector2i(4, 4),
		Piece.Kind.SHOGI_PROMOTED_PAWN
	)
	promotion_event.mover_side = Piece.Side.WHITE
	promotion_event.mover_kind = Piece.Kind.SHOGI_PAWN
	var promotion_context := director.build_llm_context(utterance, promotion_event, "定型セリフ")
	check(str(promotion_context.get("board_hint", "")).contains("成り"), "成りを説明")

	var client := LlmSpeechClient.new()
	var prompt := client.build_prompt(drop_context)
	check(prompt.contains("ゲーム種別: shogi"), "ゲームIDをプロンプトに含める")
	check(prompt.contains("将棋の駒キャラクター"), "将棋用ロール指示")
	director.free()


func _catalog_with_single(id: String, lines_map: Dictionary) -> SpeechCatalog:
	var catalog := SpeechCatalog.new()
	var definition := CharacterDef.new()
	definition.id = id
	definition.display_name = id
	definition.personality = "test personality"
	var normalized: Dictionary = {}
	for key in lines_map:
		var lines := PackedStringArray()
		for item in lines_map[key]:
			lines.append(str(item))
		normalized[str(key)] = lines
	definition.lines = normalized
	catalog.characters[id] = definition
	return catalog


func _quiet_move() -> MoveEvent:
	var event := MoveEvent.new()
	event.move = Move.new(Vector2i(0, 1), Vector2i(0, 2))
	event.mover_side = Piece.Side.WHITE
	event.mover_kind = Piece.Kind.PAWN
	return event
