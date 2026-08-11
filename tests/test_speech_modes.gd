extends "res://tests/case.gd"

## Issue #9: 発話モード(定型 / 音声 / 生成)とフォールバック。
##
## シーム:
## - SpeechSettings: モードと通常手確率の永続化(API キーは保存しない)
## - LlmSpeechClient: キー未設定・時間切れ・失敗の 3 種フォールバック
## - SpeechDirector: TTS で表示と同じ本文を読む / LLM で生成文を表示
##
## 実 API・実 TTS はモック差し替えで検証(ヘッドレスで完結)。


func test_speech_settings_persist_mode_and_probability() -> void:
	var path := "user://test_speech_settings_%d.cfg" % Time.get_ticks_usec()
	var s := SpeechSettings.new()
	s.config_path = path
	s.mode = SpeechSettings.Mode.LLM
	s.move_probability = 0.75
	s.save_to_disk()

	var loaded := SpeechSettings.load_or_default(path)
	check_eq(loaded.mode, SpeechSettings.Mode.LLM, "モードが保持される")
	check_eq(loaded.move_probability, 0.75, "通常手確率が保持される")

	# 再保存しても他セクションを壊さない(ai セクションが残る)
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ai", "enabled", true)
	cfg.save(path)
	s.mode = SpeechSettings.Mode.TTS
	s.move_probability = 0.1
	s.save_to_disk()
	cfg.load(path)
	check_eq(bool(cfg.get_value("ai", "enabled", false)), true, "ai セクション維持")
	check_eq(int(cfg.get_value("speech", "mode", -1)), SpeechSettings.Mode.TTS, "speech.mode")
	check_eq(float(cfg.get_value("speech", "move_probability", -1.0)), 0.1, "speech.prob")

	# 掃除
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_api_key_never_saved_in_settings_file() -> void:
	var path := "user://test_speech_no_key_%d.cfg" % Time.get_ticks_usec()
	var s := SpeechSettings.new()
	s.config_path = path
	s.mode = SpeechSettings.Mode.LLM
	s.save_to_disk()

	var cfg := ConfigFile.new()
	cfg.load(path)
	check(not cfg.has_section_key("speech", "api_key"), "api_key キーが無い")
	check(not cfg.has_section_key("speech", "openai_api_key"), "openai_api_key も無い")
	# 値が紛れ込んでいないか全文スキャン
	var raw := FileAccess.get_file_as_string(path)
	check(not raw.contains("api_key"), "ファイル本文に api_key が無い")
	check(not raw.contains("sk-"), "ファイル本文に sk- が無い")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_llm_fallback_when_api_key_missing() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return ""
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		# キー無しなら transport は呼ばれない想定だが、呼ばれても成功させない。
		return {"ok": true, "text": "生成されてはいけない", "timed_out": false, "error": ""}

	var result := client.generate_or_fallback({
		"fallback_text": "定型フォールバック",
		"personality": "熱血",
		"event_key": "captured",
		"display_name": "アタッカー",
	})
	check_eq(result["reason"], LlmSpeechClient.REASON_NO_KEY, "理由は no_key")
	check_eq(result["used_fallback"], true, "フォールバック使用")
	check_eq(result["text"], "定型フォールバック", "定型セリフで進む")
	check(not client.has_api_key(), "キー未設定")


func test_llm_fallback_on_timeout() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key-not-real"
	client.timeout_ms = 100
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		return {"ok": false, "text": "", "timed_out": true, "error": "timeout"}

	var result := client.generate_or_fallback({
		"fallback_text": "時間切れ定型",
		"personality": "冷静",
		"event_key": "moved",
	})
	check_eq(result["reason"], LlmSpeechClient.REASON_TIMEOUT, "理由は timeout")
	check_eq(result["used_fallback"], true, "フォールバック")
	check_eq(result["text"], "時間切れ定型", "定型で進む")


func test_llm_fallback_on_failure() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key-not-real"
	client.transport = func(_prompt: String, _timeout_ms: int) -> Dictionary:
		return {"ok": false, "text": "", "timed_out": false, "error": "http_500"}

	var result := client.generate_or_fallback({
		"fallback_text": "失敗時定型",
		"personality": "ツンデレ",
		"event_key": "check",
	})
	check_eq(result["reason"], LlmSpeechClient.REASON_ERROR, "理由は error")
	check_eq(result["used_fallback"], true, "フォールバック")
	check_eq(result["text"], "失敗時定型", "定型で進む")


func test_llm_success_uses_generated_text() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key-not-real"
	client.transport = func(prompt: String, _timeout_ms: int) -> Dictionary:
		check(prompt.contains("性格"), "プロンプトに性格")
		check(prompt.contains("猪突"), "性格本文が入る")
		return {"ok": true, "text": "生成セリフだ！", "timed_out": false, "error": ""}

	var result := client.generate_or_fallback({
		"fallback_text": "定型",
		"personality": "猪突猛進",
		"event_key": "captured",
		"display_name": "熱血",
		"board_hint": "ナイトがポーンを取った",
	})
	check_eq(result["reason"], LlmSpeechClient.REASON_OK, "成功")
	check_eq(result["used_fallback"], false, "フォールバックしない")
	check_eq(result["text"], "生成セリフだ！", "生成文を使う")


func test_llm_empty_response_falls_back() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "test-key"
	client.transport = func(_p: String, _t: int) -> Dictionary:
		return {"ok": true, "text": "   ", "timed_out": false, "error": ""}
	var result := client.generate_or_fallback({
		"fallback_text": "空なら定型",
		"personality": "x",
		"event_key": "moved",
	})
	check_eq(result["reason"], LlmSpeechClient.REASON_ERROR, "空本文は error")
	check_eq(result["text"], "空なら定型", "定型")


func test_director_tts_speaks_same_text_as_bubble() -> void:
	var catalog := SpeechCatalog.load_default()
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 1

	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.TTS
	var tts := TtsSpeaker.new()
	tts.use_system_tts = false  # ヘッドレスでは OS TTS を叩かない

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())
	var director := SpeechDirector.new()
	director.setup(session, view, resolver, view.square_size, settings, null, tts)

	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	view.apply_board(session.board())
	var bubbles: Array = director.present_event(ev)
	check(bubbles.size() >= 1, "吹き出しがある")
	check_eq(tts.spoken.size(), bubbles.size(), "読み上げ回数=表示数")
	for i in bubbles.size():
		var bubble := bubbles[i] as SpeechBubble
		check_eq(tts.spoken[i], bubble.text(), "表示と同じセリフが読み上げられる #%d" % i)

	director.free()
	view.free()


func test_director_llm_replaces_text_on_success() -> void:
	var catalog := _catalog_with_single("talker", {
		"captured": ["定型取り"],
		"captured_by": ["定型取られ"],
	})
	catalog.team.assign(Piece.Kind.KNIGHT, "talker")
	catalog.team.assign(Piece.Kind.PAWN, "talker")
	var resolver := SpeechResolver.new(catalog)
	resolver.rng.seed = 2

	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.LLM
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "mock-key"
	var call_count := [0]
	client.transport = func(_p: String, _t: int) -> Dictionary:
		call_count[0] = int(call_count[0]) + 1
		return {
			"ok": true,
			"text": "生成_%d" % int(call_count[0]),
			"timed_out": false,
			"error": "",
		}

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())
	var director := SpeechDirector.new()
	director.setup(session, view, resolver, view.square_size, settings, client, null)

	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	view.apply_board(session.board())
	var bubbles: Array = director.present_event(ev)
	check_eq(bubbles.size(), 2, "双方発話")
	for b in bubbles:
		var bubble := b as SpeechBubble
		check(str(bubble.text()).begins_with("生成_"), "生成文が表示される: %s" % bubble.text())
	for reason in director.last_resolve_reasons:
		check_eq(reason, LlmSpeechClient.REASON_OK, "成功 reason")

	director.free()
	view.free()


func test_director_llm_three_fallbacks_keep_fixed_lines() -> void:
	## キー未設定・時間切れ・失敗の 3 種が定型で進むことを Director 経路でも確認。
	var catalog := _catalog_with_single("fixed", {
		"moved": ["固定セリフ"],
	})
	catalog.team.assign(Piece.Kind.PAWN, "fixed")
	var quiet := _event_quiet_move(Piece.Kind.PAWN)

	var cases: Array = [
		{
			"name": "no_key",
			"env": "",
			"transport": null,
			"reason": LlmSpeechClient.REASON_NO_KEY,
		},
		{
			"name": "timeout",
			"env": "key",
			"transport": func(_p: String, _t: int) -> Dictionary:
				return {"ok": false, "text": "", "timed_out": true, "error": "timeout"},
			"reason": LlmSpeechClient.REASON_TIMEOUT,
		},
		{
			"name": "error",
			"env": "key",
			"transport": func(_p: String, _t: int) -> Dictionary:
				return {"ok": false, "text": "", "timed_out": false, "error": "boom"},
			"reason": LlmSpeechClient.REASON_ERROR,
		},
	]

	for case in cases:
		var resolver := SpeechResolver.new(catalog)
		resolver.move_probability = 1.0
		resolver.rng.seed = 9
		var settings := SpeechSettings.new()
		settings.mode = SpeechSettings.Mode.LLM
		var client := LlmSpeechClient.new()
		var env_value: String = str(case["env"])
		client.env_reader = func() -> String: return env_value
		if case["transport"] != null:
			client.transport = case["transport"]
		var director := SpeechDirector.new()
		director.setup(null, null, resolver, 1.0, settings, client, null)
		var bubbles: Array = director.present_event(quiet)
		check_eq(bubbles.size(), 1, "%s: 吹き出し1" % case["name"])
		check_eq((bubbles[0] as SpeechBubble).text(), "固定セリフ", "%s: 定型で進む" % case["name"])
		check_eq(director.last_resolve_reasons.size(), 1, "%s: reason 記録" % case["name"])
		check_eq(
			director.last_resolve_reasons[0],
			str(case["reason"]),
			"%s: reason 一致" % case["name"]
		)
		director.free()


func test_settings_apply_move_probability_to_resolver() -> void:
	var catalog := SpeechCatalog.load_default()
	var resolver := SpeechResolver.new(catalog)
	var settings := SpeechSettings.new()
	settings.move_probability = 0.0
	settings.apply_to_resolver(resolver)
	check_eq(resolver.move_probability, 0.0, "確率 0 を反映")
	settings.move_probability = 1.0
	settings.apply_to_resolver(resolver)
	check_eq(resolver.move_probability, 1.0, "確率 1 を反映")


func test_api_key_read_only_from_env_reader() -> void:
	var client := LlmSpeechClient.new()
	client.env_reader = func() -> String: return "  env-only-key  "
	check_eq(client.api_key(), "env-only-key", "環境変数相当からのみ")
	check(client.has_api_key(), "キーあり")
	# 設定オブジェクトにキーを持たせても client は読まない(API が無いことを型で保証)
	var settings := SpeechSettings.new()
	settings.mode = SpeechSettings.Mode.LLM
	check(not settings.get_property_list().any(
		func(p: Dictionary) -> bool:
			return str(p.get("name", "")).contains("api_key") or str(p.get("name", "")).contains("API")
	), "SpeechSettings に api_key プロパティが無い")


func test_prompt_includes_personality_and_board() -> void:
	var client := LlmSpeechClient.new()
	var prompt := client.build_prompt({
		"display_name": "熱血アタッカー",
		"personality": "猪突猛進で声が大きい",
		"event_key": "captured",
		"side_label": "先手",
		"kind_label": "knight",
		"board_hint": "手: c3 → b5 / 取った駒: pawn",
	})
	check(prompt.contains("猪突猛進"), "性格")
	check(prompt.contains("取った") or prompt.contains("captured"), "状況")
	check(prompt.contains("c3") or prompt.contains("b5") or prompt.contains("pawn"), "盤ヒント")
	check(prompt.contains("日本語"), "日本語指定")


func test_mode_labels() -> void:
	check_eq(SpeechSettings.mode_label(SpeechSettings.Mode.LINES), "定型", "定型")
	check_eq(SpeechSettings.mode_label(SpeechSettings.Mode.TTS), "音声", "音声")
	check_eq(SpeechSettings.mode_label(SpeechSettings.Mode.LLM), "生成", "生成")


# --- helpers ---


func _catalog_with_single(id: String, lines_map: Dictionary) -> SpeechCatalog:
	var catalog := SpeechCatalog.new()
	var def := CharacterDef.new()
	def.id = id
	def.display_name = id
	def.personality = "test personality"
	var normalized: Dictionary = {}
	for key in lines_map:
		var arr := PackedStringArray()
		for item in lines_map[key]:
			arr.append(str(item))
		normalized[str(key)] = arr
	def.lines = normalized
	catalog.characters[id] = def
	return catalog


func _event_quiet_move(kind: int) -> MoveEvent:
	var ev := MoveEvent.new()
	ev.move = Move.new(Vector2i(0, 1), Vector2i(0, 2))
	ev.mover_side = Piece.Side.WHITE
	ev.mover_kind = kind
	ev.is_check = false
	ev.is_checkmate = false
	ev.is_stalemate = false
	ev.is_over = false
	return ev
