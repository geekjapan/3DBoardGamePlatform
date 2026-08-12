extends "res://tests/case.gd"

## Strict fake USI contract tests. The fixture rejects movetime and malformed
## byoyomi, so all wire-level acceptance cases are deterministic and mandatory.

const FAKE := "res://tests/fake_usi_engine.sh"


func test_strict_fake_probe_and_transcript() -> void:
	_set_fake("normal", "valid")
	var engine := UsiEngine.new()
	var result := engine.probe(ProjectSettings.globalize_path(FAKE))
	check_eq(int(result.get("availability", -1)), EngineAdapter.Availability.AVAILABLE, "strict fake probe が利用可能")
	check_eq(str(result.get("engine_id", "")), "Strict Fake USI", "engine id")
	check(str(result.get("transcript", "")).contains("usi") and str(result.get("transcript", "")).contains("usiok"), "probe transcript")
	_set_fake("no_usiok", "valid")
	var unavailable := engine.probe(ProjectSettings.globalize_path(FAKE))
	check(int(unavailable.get("availability", -1)) != EngineAdapter.Availability.AVAILABLE, "usiok 欠落 probe は利用可能にしない")
	_set_fake("exit_handshake", "valid")
	var exited := engine.probe(ProjectSettings.globalize_path(FAKE))
	check(int(exited.get("availability", -1)) != EngineAdapter.Availability.AVAILABLE, "handshake exit probe は利用可能にしない")
	_set_fake("no_ready", "valid")
	var not_ready := engine.probe(ProjectSettings.globalize_path(FAKE))
	check(int(not_ready.get("availability", -1)) != EngineAdapter.Availability.AVAILABLE, "readyok 欠落 probe は利用可能にしない")


func test_strict_fake_wire_order_and_case_spelling_for_strengths() -> void:
	_set_fake("normal", "valid")
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	var positions := "startpos"
	var weak := engine.search_best_move_result_sync(path, positions, EngineAdapter.Strength.WEAK)
	var medium := engine.search_best_move_result_sync(path, positions, EngineAdapter.Strength.MEDIUM)
	var strong := engine.search_best_move_result_sync(path, positions, EngineAdapter.Strength.STRONG)
	for result in [weak, medium, strong]:
		check_eq(int(result.get("status", -1)), EngineAdapter.SearchStatus.OK, "strict fake は OK")
		var transcript := str(result.get("transcript", ""))
		check(transcript.find("usi\nid name") >= 0, "usi handshake が先")
		check(transcript.find("usiok\n") >= 0, "usiok")
		check(transcript.find("position startpos") >= 0, "position")
		check(transcript.find("go btime 0 wtime 0 byoyomi ") >= 0, "USI btime/wtime/byoyomi")
		check(not transcript.contains("movetime"), "movetime を送らない")
		check(not transcript.contains("byoyomi -1"), "-1 sentinel を送らない")
		check(transcript.find("position startpos") < transcript.find("go btime"), "position は go より前")
		var usiok_index := transcript.find("usiok")
		var setoption_index := transcript.find("setoption")
		var first_ready_index := transcript.find("isready")
		var first_readyok_index := transcript.find("readyok")
		var newgame_index := transcript.find("usinewgame")
		var second_ready_index := transcript.find("isready", first_ready_index + 1)
		var second_readyok_index := transcript.find("readyok", first_readyok_index + 1)
		var position_index := transcript.find("position startpos")
		var go_index := transcript.find("go btime")
		var bestmove_index := transcript.find("bestmove")
		check(usiok_index >= 0 and first_ready_index > usiok_index, "usi→usiok→isready")
		if setoption_index >= 0:
			check(setoption_index > usiok_index and first_ready_index > setoption_index, "optional setoption は usiok と ready の間")
		check(first_readyok_index > first_ready_index and newgame_index > first_readyok_index, "readyok→usinewgame")
		check(second_ready_index > newgame_index and second_readyok_index > second_ready_index, "usinewgame→ready/readyok")
		check(position_index > second_readyok_index and go_index > position_index and bestmove_index > go_index, "readyok→position→go→bestmove")
	check(str(weak["transcript"]).contains("setoption name uSi_LimitStrength value true"), "弱: advertised limit spelling")
	check(str(weak["transcript"]).contains("setoption name uSi_Strength value -2"), "弱: -5 を min -2 へ clamp")
	check(str(medium["transcript"]).contains("setoption name uSi_Strength value 1"), "中: strength=1")
	check(str(strong["transcript"]).contains("setoption name uSi_LimitStrength value false"), "強: limit false")
	check(not str(strong["transcript"]).contains("setoption name uSi_Strength"), "強: strength option は変更しない")
	check(str(weak["transcript"]).contains("byoyomi 200"), "弱: 200ms")
	check(str(medium["transcript"]).contains("byoyomi 500"), "中: 500ms")
	check(str(strong["transcript"]).contains("byoyomi 1000"), "強: 1000ms")


func test_strict_fake_positive_override_and_negative_sentinel() -> void:
	_set_fake("normal", "valid")
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	var override := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.WEAK, 777)
	var sentinel := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.WEAK, -1)
	check_eq(int(override.get("status", -1)), EngineAdapter.SearchStatus.OK, "positive override は OK")
	check_eq(int(sentinel.get("status", -1)), EngineAdapter.SearchStatus.OK, "-1 は sentinel として OK")
	check(str(override["transcript"]).contains("go btime 0 wtime 0 byoyomi 777"), "正の override")
	check(str(sentinel["transcript"]).contains("go btime 0 wtime 0 byoyomi 200"), "-1 はプリセットへ戻る")
	check(not str(override["transcript"]).contains("byoyomi -1"), "負値を wire に出さない")
	check(not str(override["transcript"]).contains("movetime"), "override でも movetime fallback なし")


func test_strict_fake_missing_invalid_and_unknown_options_fallback_to_time_only() -> void:
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	for option_mode in ["missing", "invalid", "invalid_integer", "unknown", "wrong_type"]:
		_set_fake("normal", option_mode)
		var result := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.WEAK)
		check_eq(int(result.get("status", -1)), EngineAdapter.SearchStatus.OK, "%s option fallback" % option_mode)
		var transcript := str(result.get("transcript", ""))
		check(not transcript.contains("setoption"), "%s: 不完全/未知 option は推測利用しない" % option_mode)
		check(transcript.contains("go btime 0 wtime 0 byoyomi 200"), "%s: 時間 fallback" % option_mode)
	# option 非対応時も3プリセットすべてを時間だけで区別する。
	_set_fake("normal", "missing")
	for entry in [
		[EngineAdapter.Strength.MEDIUM, 500],
		[EngineAdapter.Strength.STRONG, 1000],
	]:
		var fallback := engine.search_best_move_result_sync(path, "startpos", int(entry[0]))
		var fallback_transcript := str(fallback.get("transcript", ""))
		check_eq(fallback.get("status"), EngineAdapter.SearchStatus.OK, "option非対応 preset")
		check(not fallback_transcript.contains("setoption"), "option非対応 setoption 0件")
		check(
			fallback_transcript.contains("go btime 0 wtime 0 byoyomi %d" % int(entry[1])),
			"option非対応 byoyomi %d" % int(entry[1]),
		)


func test_strict_fake_normal_promotion_drop_and_resign_results() -> void:
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	for entry in [["normal", EngineAdapter.SearchStatus.OK, "7g7f"], ["promotion", EngineAdapter.SearchStatus.OK, "2b3c+"], ["drop", EngineAdapter.SearchStatus.OK, "P*7f"], ["resign", EngineAdapter.SearchStatus.RESIGNED, ""]]:
		_set_fake(str(entry[0]), "valid")
		var result := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.MEDIUM)
		check_eq(int(result.get("status", -1)), int(entry[1]), "%s status" % entry[0])
		check_eq(str(result.get("move_text", "")), str(entry[2]), "%s move" % entry[0])


func test_strict_fake_win_malformed_and_invalid_results() -> void:
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	_set_fake("win", "valid")
	var win := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.MEDIUM)
	check_eq(int(win.get("status", -1)), EngineAdapter.SearchStatus.PROTOCOL_ERROR, "win は protocol error")
	check_eq(str(win.get("detail_code", "")), "UNSUPPORTED_WIN_DECLARATION", "win detail code")
	for mode in ["invalid", "none"]:
		_set_fake(mode, "valid")
		var invalid := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.MEDIUM)
		check_eq(int(invalid.get("status", -1)), EngineAdapter.SearchStatus.INVALID_MOVE, "%s は invalid move" % mode)
	_set_fake("malformed", "valid")
	var malformed := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.MEDIUM)
	check_eq(int(malformed.get("status", -1)), EngineAdapter.SearchStatus.PROTOCOL_ERROR, "bestmove 欠落 token")
	check_eq(str(malformed.get("detail_code", "")), "MALFORMED_BESTMOVE", "malformed detail code")


func test_strict_fake_timeout_and_process_exit_are_distinct() -> void:
	var engine := UsiEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	_set_fake("timeout", "valid")
	var timed_out := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.WEAK, 1)
	check_eq(int(timed_out.get("status", -1)), EngineAdapter.SearchStatus.SEARCH_TIMEOUT, "bestmove timeout")
	_set_fake("exit", "valid")
	var exited := engine.search_best_move_result_sync(path, "startpos", EngineAdapter.Strength.WEAK)
	check_eq(int(exited.get("status", -1)), EngineAdapter.SearchStatus.PROCESS_EXITED, "process exit")


func test_explicit_real_usi_engine_smoke_is_gating() -> void:
	var path := OS.get_environment("USI_ENGINE_PATH")
	if path.is_empty():
		path = OS.get_environment("BOARDGAME_USI_ENGINE")
	if path.is_empty():
		print("SKIP test_explicit_real_usi_engine_smoke_is_gating — USI_ENGINE_PATH/BOARDGAME_USI_ENGINE unset")
		return
	var engine := UsiEngine.new()
	var position := ShogiUsiCodec.position_startpos()
	for strength in [EngineAdapter.Strength.WEAK, EngineAdapter.Strength.MEDIUM, EngineAdapter.Strength.STRONG]:
		var result := engine.search_best_move_result_sync(path, position, strength, -1)
		print("USI smoke strength=%d engine_id=%s elapsed_ms=%s move=%s transcript=%s" % [strength, result.get("engine_id", ""), result.get("elapsed_ms", 0), result.get("move_text", ""), result.get("transcript", "")])
		check_eq(int(result.get("status", -1)), EngineAdapter.SearchStatus.OK, "明示実USIの strength=%d 探索" % strength)
		check(str(result.get("engine_id", "")) != "", "明示実USIの engine id")
		check(int(result.get("elapsed_ms", -1)) >= 0, "明示実USIの elapsed")
		var board := ShogiBoard.start()
		var move := ShogiUsiCodec.parse_legal_move(board, str(result.get("move_text", "")))
		check(move != null, "明示実USIの strength=%d 合法手" % strength)
		if move != null:
			check(board.apply(move) != null, "明示実USIの strength=%d 適用可能" % strength)


func _set_fake(mode: String, option_mode: String) -> void:
	OS.set_environment("FAKE_USI_MODE", mode)
	OS.set_environment("FAKE_USI_OPTIONS", option_mode)
