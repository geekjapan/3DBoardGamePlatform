class_name UsiTestDiagnostics
## 実機USIテストが失敗したときだけ、CIが取得できる診断JSONを書き出す。

const ENVIRONMENT_KEY := "USI_DIAGNOSTICS_DIR"
const FILE_NAME := "usi-failure-diagnostics.json"
const MAX_TRANSCRIPT_CHARS := 2000

static var _records: Array = []


static func reset() -> void:
	_records.clear()


static func record_failure(
	scenario: String,
	position: String,
	ply: int,
	result: Dictionary,
	failure_reason: String,
) -> void:
	var directory := OS.get_environment(ENVIRONMENT_KEY).strip_edges()
	if directory.is_empty():
		return
	var transcript := str(result.get("transcript", ""))
	if transcript.length() > MAX_TRANSCRIPT_CHARS:
		transcript = transcript.substr(0, MAX_TRANSCRIPT_CHARS) + "\n...[truncated]"
	_records.append({
		"scenario": scenario,
		"ply": ply,
		"position": position,
		"failure_reason": failure_reason,
		"status": int(result.get("status", -1)),
		"detail_code": str(result.get("detail_code", "")),
		"message": str(result.get("message", "")),
		"engine_id": str(result.get("engine_id", "")),
		"elapsed_ms": int(result.get("elapsed_ms", -1)),
		"move_text": str(result.get("move_text", "")),
		"transcript_summary": transcript,
	})
	_write(directory)


static func _write(directory: String) -> void:
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_warning("USI diagnostics directory could not be created")
		return
	var path := directory.path_join(FILE_NAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("USI diagnostics file could not be opened")
		return
	file.store_string(JSON.stringify({"schema_version": 1, "failures": _records}, "\t"))
	file.store_string("\n")
	file.close()
