class_name UsiEngine
extends EngineAdapter

## 将棋用 USI エンジンの標準入出力アダプタ。
##
## 各探索は新しいプロセスで行う。USI はエンジンごとの差が大きいため、
## 広告されていない option を推測せず、標準強さ option が完全に検証できる
## 場合だけ使い、それ以外は固定 byoyomi の差だけで強さを表す。

const BYOYOMI_BY_STRENGTH := {
	Strength.WEAK: 200,
	Strength.MEDIUM: 500,
	Strength.STRONG: 1000,
}
const USI_HANDSHAKE_TIMEOUT_MS := 5000
const READY_TIMEOUT_MS := 5000
const SEARCH_GRACE_MS := 1000

var _running_pid: int = 0
var _pid_mutex := Mutex.new()


func protocol_id() -> String:
	return "usi"


func display_name() -> String:
	return "USI (将棋)"


func probe(engine_path: String) -> Dictionary:
	var path := engine_path.strip_edges()
	if path.is_empty():
		return {
			"availability": Availability.MISSING,
			"message": "USI エンジンのパスが未設定です",
			"engine_id": "",
			"transcript": "",
		}
	if not _path_looks_executable(path):
		return {
			"availability": Availability.MISSING,
			"message": "USI エンジンが見つかりません: %s" % path,
			"engine_id": "",
			"transcript": "",
		}

	var started_at := Time.get_ticks_msec()
	_reset_cancel_request()
	var process := _start_process(path)
	if not bool(process.get("ok", false)):
		return {
			"availability": Availability.FAILED,
			"message": str(process.get("message", "USI エンジンを起動できませんでした")),
			"detail_code": "PROCESS_START_FAILED",
			"engine_id": "",
			"transcript": "",
			"elapsed_ms": Time.get_ticks_msec() - started_at,
		}
	var io: FileAccess = process["io"]
	var pid := int(process["pid"])
	_set_running_pid(pid)
	var transcript: Array = []
	var handshake := _perform_handshake(io, transcript, USI_HANDSHAKE_TIMEOUT_MS)
	var engine_id := str(handshake.get("engine_id", ""))
	var status_message := str(handshake.get("message", ""))
	var detail_code := str(handshake.get("detail_code", ""))
	var available := bool(handshake.get("ok", false))
	# 開始前 probe は usiok だけでなく、対局開始に必要な readyok まで校正する。
	if available:
		_send(io, "isready", transcript)
		var ready := _wait_for_token(io, "readyok", READY_TIMEOUT_MS, transcript)
		available = bool(ready.get("ok", false))
		if not available:
			status_message = str(ready.get("message", "USI readyok がありません"))
			detail_code = str(ready.get("detail_code", "READY_FAILED"))
	_finish_process(io, pid, transcript)
	_set_running_pid(0)
	return {
		"availability": Availability.AVAILABLE if available else Availability.FAILED,
		"message": "USI エンジン利用可: %s" % path if available else status_message,
		"detail_code": detail_code,
		"engine_id": engine_id,
		"transcript": _transcript_text(transcript),
		"elapsed_ms": maxi(0, Time.get_ticks_msec() - started_at),
	}


func search_best_move_result_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = -1,
) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	var path := engine_path.strip_edges()
	_reset_cancel_request()
	if path.is_empty() or not _path_looks_executable(path):
		return _result(
			SearchStatus.UNAVAILABLE,
			"",
			"USI エンジンが見つかりません: %s" % path if not path.is_empty() else "USI エンジンのパスが未設定です",
			"ENGINE_NOT_FOUND" if not path.is_empty() else "ENGINE_NOT_CONFIGURED",
			[],
			"",
			started_at,
		)

	var process := _start_process(path)
	if not bool(process.get("ok", false)):
		return _result(
			SearchStatus.UNAVAILABLE,
			"",
			str(process.get("message", "USI エンジンを起動できませんでした")),
			"PROCESS_START_FAILED",
			[],
			"",
			started_at,
		)
	var io: FileAccess = process["io"]
	var pid := int(process["pid"])
	_set_running_pid(pid)
	var transcript: Array = []
	var handshake := _perform_handshake(io, transcript, USI_HANDSHAKE_TIMEOUT_MS)
	var engine_id := str(handshake.get("engine_id", ""))
	if not bool(handshake.get("ok", false)):
		var handshake_code := "CANCELLED" if _is_cancel_requested() else str(handshake.get("detail_code", "USI_HANDSHAKE_FAILED"))
		var handshake_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if handshake_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, handshake_status, "", str(handshake.get("message", "USI handshake に失敗しました")), handshake_code, transcript, engine_id, started_at)

	# Standard strength settings are sent only as an advertised, valid pair.
	var options: Dictionary = handshake.get("options", {})
	_apply_standard_strength(options, strength, transcript, io)

	_send(io, "isready", transcript)
	var ready := _wait_for_token(io, "readyok", READY_TIMEOUT_MS, transcript)
	if not bool(ready.get("ok", false)):
		var ready_code := "CANCELLED" if _is_cancel_requested() else str(ready.get("detail_code", "READY_FAILED"))
		var ready_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if ready_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, ready_status, "", str(ready.get("message", "USI readyok がありません")), ready_code, transcript, engine_id, started_at)

	_send(io, "usinewgame", transcript)
	_send(io, "isready", transcript)
	var new_game_ready := _wait_for_token(io, "readyok", READY_TIMEOUT_MS, transcript)
	if not bool(new_game_ready.get("ok", false)):
		var new_ready_code := "CANCELLED" if _is_cancel_requested() else str(new_game_ready.get("detail_code", "READY_FAILED"))
		var new_ready_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if new_ready_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, new_ready_status, "", str(new_game_ready.get("message", "USI readyok がありません")), new_ready_code, transcript, engine_id, started_at)

	_send(io, _position_command(position), transcript)
	var byoyomi := int(BYOYOMI_BY_STRENGTH.get(strength, BYOYOMI_BY_STRENGTH[Strength.MEDIUM]))
	if movetime_ms > 0:
		byoyomi = movetime_ms
	_send(io, "go btime 0 wtime 0 byoyomi %d" % byoyomi, transcript)

	var search_timeout := maxi(1000, byoyomi + SEARCH_GRACE_MS)
	var best := _wait_for_bestmove(io, search_timeout, transcript)
	if not bool(best.get("ok", false)):
		var failed_status := int(best.get("status", SearchStatus.PROTOCOL_ERROR))
		return _finish_result(io, pid, failed_status, "", str(best.get("message", "USI bestmove がありません")), str(best.get("detail_code", "USI_SEARCH_FAILED")), transcript, engine_id, started_at)

	var move_text := str(best.get("move_text", ""))
	var lowered := move_text.to_lower()
	if lowered == "resign":
		return _finish_result(io, pid, SearchStatus.RESIGNED, "", "USI エンジンが投了しました", "RESIGNED", transcript, engine_id, started_at)
	if lowered == "win":
		return _finish_result(io, pid, SearchStatus.PROTOCOL_ERROR, "", "USI の入玉勝ち宣言は未対応です", "UNSUPPORTED_WIN_DECLARATION", transcript, engine_id, started_at)
	if not _looks_like_usi_move(move_text):
		return _finish_result(io, pid, SearchStatus.INVALID_MOVE, move_text, "USI の手文字列が不正です: %s" % move_text, "INVALID_MOVE_TEXT", transcript, engine_id, started_at)
	return _finish_result(io, pid, SearchStatus.OK, move_text, "", "", transcript, engine_id, started_at)


func cancel_running() -> void:
	_request_cancel()
	_pid_mutex.lock()
	var pid := _running_pid
	_running_pid = 0
	_pid_mutex.unlock()
	if pid != 0:
		_safe_kill(pid)


func _perform_handshake(io: FileAccess, transcript: Array, timeout_ms: int) -> Dictionary:
	_send(io, "usi", transcript)
	var deadline := Time.get_ticks_msec() + timeout_ms
	var engine_id := ""
	var options: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		if _is_cancel_requested():
			return {"ok": false, "message": "USI 探索をキャンセルしました", "detail_code": "CANCELLED"}
		var event := _read_event(io, maxi(1, deadline - Time.get_ticks_msec()))
		var kind := str(event.get("kind", ""))
		if kind == "line":
			var line := str(event.get("line", ""))
			transcript.append(line)
			var lower := line.to_lower()
			if lower.begins_with("id name "):
				engine_id = line.substr(8).strip_edges()
			elif lower.begins_with("id author ") and engine_id.is_empty():
				engine_id = line.substr(10).strip_edges()
			elif lower.begins_with("option "):
				var option := _parse_option(line)
				if not option.is_empty():
					var option_key := str(option.get("name", "")).to_lower()
					if option_key == "usi_limitstrength" and str(option.get("type", "")) == "check":
						options["limit"] = option
					elif option_key == "usi_strength" and str(option.get("type", "")) == "spin" and bool(option.get("valid_spin", false)):
						options["strength"] = option
			if lower == "usiok":
				return {"ok": true, "engine_id": engine_id, "options": options}
		elif kind == "cancelled":
			return {"ok": false, "message": "USI 探索をキャンセルしました", "detail_code": "CANCELLED"}
		elif kind == "exit":
			return {"ok": false, "message": "USI エンジンが handshake 前に終了しました", "detail_code": "PROCESS_EXITED"}
		elif kind == "timeout":
			break
	return {"ok": false, "message": "USI の usiok 応答がありません", "detail_code": "USI_HANDSHAKE_TIMEOUT"}


func _parse_option(line: String) -> Dictionary:
	var tokens := line.strip_edges().split(" ", false)
	if tokens.size() < 6 or str(tokens[0]).to_lower() != "option":
		return {}
	var type_index := -1
	for i in range(2, tokens.size()):
		if str(tokens[i]).to_lower() == "type":
			type_index = i
			break
	if type_index <= 2 or type_index + 1 >= tokens.size():
		return {}
	var name_parts := PackedStringArray()
	for i in range(2, type_index):
		name_parts.append(str(tokens[i]))
	var option_type := str(tokens[type_index + 1]).to_lower()
	var option := {"name": " ".join(name_parts), "type": option_type, "valid_spin": false}
	if option_type != "check" and option_type != "spin":
		return option
	if option_type == "check":
		return option
	var min_found := false
	var max_found := false
	var min_value := 0
	var max_value := 0
	var i := type_index + 2
	while i + 1 < tokens.size():
		var key := str(tokens[i]).to_lower()
		var parsed := _parse_integer_token(str(tokens[i + 1]))
		if key == "min" and bool(parsed.get("ok", false)):
			min_found = true
			min_value = int(parsed["value"])
		elif key == "max" and bool(parsed.get("ok", false)):
			max_found = true
			max_value = int(parsed["value"])
		i += 2
	option["min"] = min_value
	option["max"] = max_value
	option["valid_spin"] = min_found and max_found and min_value <= max_value
	return option


func _parse_integer_token(token: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^-?[0-9]+$")
	var match := regex.search(token)
	if match == null:
		return {"ok": false}
	return {"ok": true, "value": int(token)}


func _apply_standard_strength(options: Dictionary, strength: int, transcript: Array, io: FileAccess) -> void:
	if not options.has("limit") or not options.has("strength"):
		return
	var limit: Dictionary = options["limit"]
	var strength_option: Dictionary = options["strength"]
	var limit_name := str(limit.get("name", ""))
	var strength_name := str(strength_option.get("name", ""))
	if limit_name.is_empty() or strength_name.is_empty() or not bool(strength_option.get("valid_spin", false)):
		return
	if strength == Strength.STRONG:
		_send(io, "setoption name %s value false" % limit_name, transcript)
		return
	_send(io, "setoption name %s value true" % limit_name, transcript)
	var target := -5 if strength == Strength.WEAK else 1
	var clamped := clampi(target, int(strength_option.get("min", target)), int(strength_option.get("max", target)))
	_send(io, "setoption name %s value %d" % [strength_name, clamped], transcript)


func _position_command(position: String) -> String:
	var value := position.strip_edges()
	if value.begins_with("position "):
		return value
	if value == "startpos" or value.begins_with("startpos ") or value.begins_with("sfen "):
		return "position %s" % value
	return "position sfen %s" % value


func _wait_for_token(io: FileAccess, token: String, timeout_ms: int, transcript: Array) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var event := _read_event(io, maxi(1, deadline - Time.get_ticks_msec()))
		var kind := str(event.get("kind", ""))
		if kind == "line":
			var line := str(event.get("line", ""))
			transcript.append(line)
			if line.strip_edges().to_lower() == token.to_lower():
				return {"ok": true}
		elif kind == "cancelled":
			return {"ok": false, "detail_code": "CANCELLED", "message": "USI 探索をキャンセルしました"}
		elif kind == "exit":
			return {"ok": false, "detail_code": "PROCESS_EXITED", "message": "USI エンジンが ready 前に終了しました"}
		elif kind == "timeout":
			break
	return {"ok": false, "detail_code": "READY_TIMEOUT", "message": "USI の %s 応答がありません" % token}


func _wait_for_bestmove(io: FileAccess, timeout_ms: int, transcript: Array) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var event := _read_event(io, maxi(1, deadline - Time.get_ticks_msec()))
		var kind := str(event.get("kind", ""))
		if kind == "line":
			var line := str(event.get("line", ""))
			transcript.append(line)
			var parts := line.strip_edges().split(" ", false)
			if parts.size() == 0 or str(parts[0]).to_lower() != "bestmove":
				continue
			if parts.size() < 2 or str(parts[1]).strip_edges().is_empty():
				return {"ok": false, "status": SearchStatus.PROTOCOL_ERROR, "detail_code": "MALFORMED_BESTMOVE", "message": "USI bestmove の形式が不正です"}
			return {"ok": true, "move_text": str(parts[1]).strip_edges()}
		elif kind == "cancelled":
			return {"ok": false, "status": SearchStatus.CANCELLED, "detail_code": "CANCELLED", "message": "USI 探索をキャンセルしました"}
		elif kind == "exit":
			return {"ok": false, "status": SearchStatus.PROCESS_EXITED, "detail_code": "PROCESS_EXITED", "message": "USI エンジンが bestmove 前に終了しました"}
		elif kind == "timeout":
			return {"ok": false, "status": SearchStatus.SEARCH_TIMEOUT, "detail_code": "SEARCH_TIMEOUT", "message": "USI の探索がタイムアウトしました"}
	return {"ok": false, "status": SearchStatus.SEARCH_TIMEOUT, "detail_code": "SEARCH_TIMEOUT", "message": "USI の探索がタイムアウトしました"}


func _looks_like_usi_move(move_text: String) -> bool:
	if move_text.is_empty() or move_text == "0000" or move_text == "(none)":
		return false
	var regex := RegEx.new()
	regex.compile("^(?:[1-9][a-i][1-9][a-i][+]?|[PLNSGBR][*][1-9][a-i])$")
	return regex.search(move_text) != null


func _read_event(io: FileAccess, timeout_ms: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _is_cancel_requested():
			return {"kind": "cancelled"}
		if io == null:
			return {"kind": "exit"}
		var line := io.get_line()
		if not line.is_empty():
			return {"kind": "line", "line": line.strip_edges()}
		if io.eof_reached():
			return {"kind": "exit"}
		if _running_pid != 0 and not OS.is_process_running(_running_pid):
			return {"kind": "exit"}
		OS.delay_msec(2)
	return {"kind": "timeout"}


func _start_process(path: String) -> Dictionary:
	var info: Dictionary = OS.execute_with_pipe(path, PackedStringArray(), false)
	if info.is_empty() or not info.has("stdio") or not info.has("pid"):
		return {"ok": false, "message": "USI エンジンを起動できませんでした: %s" % path}
	var io: FileAccess = info["stdio"]
	if io == null:
		return {"ok": false, "message": "USI 標準入出力を開けませんでした: %s" % path}
	return {"ok": true, "io": io, "pid": int(info["pid"])}


func _send(io: FileAccess, line: String, transcript: Array) -> void:
	transcript.append(line)
	if io == null:
		return
	io.store_string(line + "\n")
	io.flush()


func _finish_result(
	io: FileAccess,
	pid: int,
	status: int,
	move_text: String,
	message: String,
	detail_code: String,
	transcript: Array,
	engine_id: String,
	started_at: int,
) -> Dictionary:
	_finish_process(io, pid, transcript)
	_set_running_pid(0)
	return make_search_result(status, move_text, message, detail_code, _transcript_text(transcript), engine_id, Time.get_ticks_msec() - started_at)


func _result(status: int, move_text: String, message: String, detail_code: String, transcript: Array, engine_id: String, started_at: int) -> Dictionary:
	return make_search_result(status, move_text, message, detail_code, _transcript_text(transcript), engine_id, Time.get_ticks_msec() - started_at)


func _finish_process(io: FileAccess, pid: int, transcript: Array) -> void:
	if io != null and not io.eof_reached():
		_send(io, "quit", transcript)
		OS.delay_msec(5)
	_safe_kill(pid)


func _transcript_text(transcript: Array) -> String:
	var lines := PackedStringArray()
	for line in transcript:
		lines.append(str(line))
	return "\n".join(lines)


func _set_running_pid(pid: int) -> void:
	_pid_mutex.lock()
	_running_pid = pid
	_pid_mutex.unlock()


func _safe_kill(pid: int) -> void:
	if pid != 0:
		OS.kill(pid)
