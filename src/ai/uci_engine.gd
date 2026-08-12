class_name UciEngine
extends EngineAdapter

## Stockfish など UCI エンジンとの標準入出力アダプタ。
## 各探索は新しいプロセスで行い、外部応答を構造化して返す。

const SKILL_BY_STRENGTH := {
	Strength.WEAK: 3,
	Strength.MEDIUM: 10,
	Strength.STRONG: 20,
}
const MOVETIME_BY_STRENGTH := {
	Strength.WEAK: 200,
	Strength.MEDIUM: 500,
	Strength.STRONG: 1000,
}
const UCI_HANDSHAKE_TIMEOUT_MS := 5000
const READY_TIMEOUT_MS := 5000
const SEARCH_GRACE_MS := 1000

var _running_pid: int = 0
var _pid_mutex := Mutex.new()


func protocol_id() -> String:
	return "uci"


func display_name() -> String:
	return "UCI (Stockfish など)"


func probe(engine_path: String) -> Dictionary:
	var path := engine_path.strip_edges()
	if path.is_empty():
		return {"availability": Availability.MISSING, "message": "エンジンのパスが未設定です", "engine_id": "", "transcript": ""}
	if not _path_looks_executable(path):
		return {"availability": Availability.MISSING, "message": "エンジンが見つかりません: %s" % path, "engine_id": "", "transcript": ""}

	var started_at := Time.get_ticks_msec()
	_reset_cancel_request()
	var process := _start_process(path)
	if not bool(process.get("ok", false)):
		return {"availability": Availability.FAILED, "message": str(process.get("message", "エンジンを起動できませんでした")), "detail_code": "PROCESS_START_FAILED", "engine_id": "", "transcript": "", "elapsed_ms": Time.get_ticks_msec() - started_at}
	var io: FileAccess = process["io"]
	var pid := int(process["pid"])
	_set_running_pid(pid)
	var transcript: Array = []
	_send(io, "uci", transcript)
	var handshake := _wait_for_token(io, "uciok", UCI_HANDSHAKE_TIMEOUT_MS, transcript)
	var engine_id := _engine_id_from_transcript(transcript)
	var available := bool(handshake.get("ok", false))
	var message := "UCI エンジン利用可: %s" % path if available else str(handshake.get("message", "UCI 応答がありません"))
	_finish_process(io, pid, transcript)
	_set_running_pid(0)
	return {"availability": Availability.AVAILABLE if available else Availability.FAILED, "message": message, "detail_code": str(handshake.get("detail_code", "")), "engine_id": engine_id, "transcript": _transcript_text(transcript), "elapsed_ms": maxi(0, Time.get_ticks_msec() - started_at)}


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
		return make_search_result(SearchStatus.UNAVAILABLE, "", "エンジンが見つかりません: %s" % path if not path.is_empty() else "エンジンのパスが未設定です", "ENGINE_NOT_FOUND" if not path.is_empty() else "ENGINE_NOT_CONFIGURED", "", "", Time.get_ticks_msec() - started_at)
	var process := _start_process(path)
	if not bool(process.get("ok", false)):
		return make_search_result(SearchStatus.UNAVAILABLE, "", str(process.get("message", "エンジンを起動できませんでした")), "PROCESS_START_FAILED", "", "", Time.get_ticks_msec() - started_at)
	var io: FileAccess = process["io"]
	var pid := int(process["pid"])
	_set_running_pid(pid)
	var transcript: Array = []
	_send(io, "uci", transcript)
	var handshake := _wait_for_token(io, "uciok", UCI_HANDSHAKE_TIMEOUT_MS, transcript)
	var engine_id := _engine_id_from_transcript(transcript)
	if not bool(handshake.get("ok", false)):
		var hs_code := "CANCELLED" if _is_cancel_requested() else str(handshake.get("detail_code", "UCI_HANDSHAKE_FAILED"))
		var hs_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if hs_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, hs_status, "", str(handshake.get("message", "UCI handshake に失敗しました")), hs_code, transcript, engine_id, started_at)

	var skill := skill_level_for(strength)
	_send(io, "setoption name Skill Level value %d" % skill, transcript)
	if skill < 20:
		_send(io, "setoption name UCI_LimitStrength value true", transcript)
		var elo := 1320 if skill < 5 else 1800
		_send(io, "setoption name UCI_Elo value %d" % elo, transcript)
	else:
		_send(io, "setoption name UCI_LimitStrength value false", transcript)

	_send(io, "isready", transcript)
	var ready := _wait_for_token(io, "readyok", READY_TIMEOUT_MS, transcript)
	if not bool(ready.get("ok", false)):
		var ready_code := "CANCELLED" if _is_cancel_requested() else str(ready.get("detail_code", "READY_FAILED"))
		var ready_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if ready_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, ready_status, "", str(ready.get("message", "UCI readyok がありません")), ready_code, transcript, engine_id, started_at)
	_send(io, "ucinewgame", transcript)
	_send(io, "isready", transcript)
	var new_ready := _wait_for_token(io, "readyok", READY_TIMEOUT_MS, transcript)
	if not bool(new_ready.get("ok", false)):
		var new_code := "CANCELLED" if _is_cancel_requested() else str(new_ready.get("detail_code", "READY_FAILED"))
		var new_status := SearchStatus.CANCELLED if _is_cancel_requested() else SearchStatus.PROCESS_EXITED if new_code == "PROCESS_EXITED" else SearchStatus.UNAVAILABLE
		return _finish_result(io, pid, new_status, "", str(new_ready.get("message", "UCI readyok がありません")), new_code, transcript, engine_id, started_at)

	_send(io, _position_command(position), transcript)
	var budget := movetime_ms if movetime_ms > 0 else movetime_for(strength)
	_send(io, "go movetime %d" % budget, transcript)
	var best := _wait_for_bestmove(io, maxi(1000, budget + SEARCH_GRACE_MS), transcript)
	if not bool(best.get("ok", false)):
		return _finish_result(io, pid, int(best.get("status", SearchStatus.PROTOCOL_ERROR)), "", str(best.get("message", "UCI bestmove がありません")), str(best.get("detail_code", "UCI_SEARCH_FAILED")), transcript, engine_id, started_at)

	var move_text := str(best.get("move_text", ""))
	var lowered := move_text.to_lower()
	if lowered == "resign":
		return _finish_result(io, pid, SearchStatus.RESIGNED, "", "UCI エンジンが投了しました", "RESIGNED", transcript, engine_id, started_at)
	if lowered == "win":
		return _finish_result(io, pid, SearchStatus.PROTOCOL_ERROR, "", "UCI の win 通知は未対応です", "UNSUPPORTED_WIN_DECLARATION", transcript, engine_id, started_at)
	if not _looks_like_uci_move(move_text):
		return _finish_result(io, pid, SearchStatus.INVALID_MOVE, move_text, "UCI の手文字列が不正です: %s" % move_text, "INVALID_MOVE_TEXT", transcript, engine_id, started_at)
	return _finish_result(io, pid, SearchStatus.OK, move_text, "", "", transcript, engine_id, started_at)


func cancel_running() -> void:
	_request_cancel()
	_pid_mutex.lock()
	var pid := _running_pid
	_running_pid = 0
	_pid_mutex.unlock()
	if pid != 0:
		_safe_kill(pid)


func skill_level_for(strength: int) -> int:
	return int(SKILL_BY_STRENGTH.get(strength, 10))


func movetime_for(strength: int) -> int:
	return int(MOVETIME_BY_STRENGTH.get(strength, 500))


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
			return {"ok": false, "detail_code": "CANCELLED", "message": "UCI 探索をキャンセルしました"}
		elif kind == "exit":
			return {"ok": false, "detail_code": "PROCESS_EXITED", "message": "UCI エンジンが応答前に終了しました"}
		elif kind == "timeout":
			break
	return {"ok": false, "detail_code": "READY_TIMEOUT" if token == "readyok" else "UCI_HANDSHAKE_TIMEOUT", "message": "UCI の %s 応答がありません" % token}


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
				return {"ok": false, "status": SearchStatus.PROTOCOL_ERROR, "detail_code": "MALFORMED_BESTMOVE", "message": "UCI bestmove の形式が不正です"}
			return {"ok": true, "move_text": str(parts[1]).strip_edges()}
		elif kind == "cancelled":
			return {"ok": false, "status": SearchStatus.CANCELLED, "detail_code": "CANCELLED", "message": "UCI 探索をキャンセルしました"}
		elif kind == "exit":
			return {"ok": false, "status": SearchStatus.PROCESS_EXITED, "detail_code": "PROCESS_EXITED", "message": "UCI エンジンが bestmove 前に終了しました"}
		elif kind == "timeout":
			return {"ok": false, "status": SearchStatus.SEARCH_TIMEOUT, "detail_code": "SEARCH_TIMEOUT", "message": "UCI の探索がタイムアウトしました"}
	return {"ok": false, "status": SearchStatus.SEARCH_TIMEOUT, "detail_code": "SEARCH_TIMEOUT", "message": "UCI の探索がタイムアウトしました"}


func _looks_like_uci_move(move_text: String) -> bool:
	if move_text.is_empty() or move_text == "0000" or move_text == "(none)":
		return false
	var regex := RegEx.new()
	regex.compile("^[a-h][1-8][a-h][1-8][qrbn]?$")
	return regex.search(move_text) != null


func _position_command(position: String) -> String:
	var value := position.strip_edges()
	if value.begins_with("position "):
		return value
	if value.begins_with("startpos") or value.begins_with("fen "):
		return "position %s" % value
	return "position fen %s" % value


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
		return {"ok": false, "message": "UCI エンジンを起動できませんでした: %s" % path}
	var io: FileAccess = info["stdio"]
	if io == null:
		return {"ok": false, "message": "UCI 標準入出力を開けませんでした: %s" % path}
	return {"ok": true, "io": io, "pid": int(info["pid"])}


func _send(io: FileAccess, line: String, transcript: Array) -> void:
	transcript.append(line)
	if io == null:
		return
	io.store_string(line + "\n")
	io.flush()


func _finish_result(io: FileAccess, pid: int, status: int, move_text: String, message: String, detail_code: String, transcript: Array, engine_id: String, started_at: int) -> Dictionary:
	_finish_process(io, pid, transcript)
	_set_running_pid(0)
	return make_search_result(status, move_text, message, detail_code, _transcript_text(transcript), engine_id, Time.get_ticks_msec() - started_at)


func _finish_process(io: FileAccess, pid: int, transcript: Array) -> void:
	if io != null and not io.eof_reached():
		_send(io, "quit", transcript)
		OS.delay_msec(5)
	_safe_kill(pid)


func _engine_id_from_transcript(transcript: Array) -> String:
	for line in transcript:
		var value := str(line)
		if value.to_lower().begins_with("id name "):
			return value.substr(8).strip_edges()
	for line in transcript:
		var author := str(line)
		if author.to_lower().begins_with("id author "):
			return author.substr(10).strip_edges()
	return ""


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
