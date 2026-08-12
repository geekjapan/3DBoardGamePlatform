extends "res://tests/case.gd"

const FAKE := "res://tests/fake_uci_engine.sh"


func test_uci_explicit_resign_is_normalized_but_empty_moves_are_not() -> void:
	var engine := UciEngine.new()
	var path := ProjectSettings.globalize_path(FAKE)
	OS.set_environment("FAKE_UCI_MODE", "resign")
	var resigned := engine.search_best_move_result_sync(
		path, "startpos", EngineAdapter.Strength.MEDIUM, 1
	)
	check_eq(resigned.get("status"), EngineAdapter.SearchStatus.RESIGNED, "明示 resign は投了")

	for mode in ["zero", "none"]:
		OS.set_environment("FAKE_UCI_MODE", mode)
		var empty_move := engine.search_best_move_result_sync(
			path, "startpos", EngineAdapter.Strength.MEDIUM, 1
		)
		check_eq(
			empty_move.get("status"),
			EngineAdapter.SearchStatus.INVALID_MOVE,
			"UCI %s は投了へ推定しない" % mode,
		)


func test_uci_structured_normal_move_preserves_chess_path() -> void:
	OS.set_environment("FAKE_UCI_MODE", "normal")
	var result := UciEngine.new().search_best_move_result_sync(
		ProjectSettings.globalize_path(FAKE),
		"startpos",
		EngineAdapter.Strength.WEAK,
		1,
	)
	check_eq(result.get("status"), EngineAdapter.SearchStatus.OK, "UCI 通常探索")
	check_eq(result.get("move_text"), "e2e4", "UCI 手文字列")
	var session := GameSession.start()
	var move := UciMoveParser.parse(str(result.get("move_text", "")))
	check(move != null and session.apply_move(move) != null, "UCI chess AI の合法手適用")
