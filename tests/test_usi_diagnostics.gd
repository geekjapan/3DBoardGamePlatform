extends "res://tests/case.gd"

const UsiTestDiagnostics := preload("res://tests/usi_test_diagnostics.gd")


func test_failure_diagnostics_write_redacted_json_artifact() -> void:
	var directory := ProjectSettings.globalize_path("user://usi-diagnostics-test")
	var artifact_path := directory.path_join(UsiTestDiagnostics.FILE_NAME)
	var original_directory := OS.get_environment(UsiTestDiagnostics.ENVIRONMENT_KEY)
	DirAccess.remove_absolute(artifact_path)
	OS.set_environment(UsiTestDiagnostics.ENVIRONMENT_KEY, directory)
	UsiTestDiagnostics.reset()
	UsiTestDiagnostics.record_failure(
		"S1-short-real-match",
		"position startpos moves 7g7f",
		3,
		{
			"status": EngineAdapter.SearchStatus.SEARCH_TIMEOUT,
			"detail_code": "SEARCH_TIMEOUT",
			"message": "USI search timed out",
			"engine_id": "FixtureEngine",
			"elapsed_ms": 3001,
			"move_text": "",
			"transcript": "go btime 0 wtime 0 byoyomi 300",
		},
		"elapsed-time-exceeded",
	)
	check(FileAccess.file_exists(artifact_path), "診断JSONを生成")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(artifact_path))
	check(parsed is Dictionary, "診断JSONを解析")
	if parsed is Dictionary:
		var document := parsed as Dictionary
		check_eq(int(document.get("schema_version", -1)), 1, "診断schema version")
		var failures := document.get("failures", []) as Array
		check_eq(failures.size(), 1, "失敗1件を記録")
		if failures.size() == 1:
			var record := failures[0] as Dictionary
			check_eq(str(record.get("scenario", "")), "S1-short-real-match", "scenario")
			check_eq(int(record.get("ply", -1)), 3, "ply")
			check_eq(str(record.get("position", "")), "position startpos moves 7g7f", "position")
			check_eq(str(record.get("detail_code", "")), "SEARCH_TIMEOUT", "result classification")
			check_eq(int(record.get("elapsed_ms", -1)), 3001, "elapsed")
			check(not record.has("engine_path"), "ローカル実行パスを出力しない")
	OS.set_environment(UsiTestDiagnostics.ENVIRONMENT_KEY, original_directory)
	UsiTestDiagnostics.reset()
	DirAccess.remove_absolute(artifact_path)
