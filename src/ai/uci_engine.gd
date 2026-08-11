class_name UciEngine
extends EngineAdapter

## Stockfish など UCI エンジンとの標準入出力アダプタ。
## プロセスは OS.execute_with_pipe で起動し、探索中はワーカースレッドから待つ。
## エンジンが見つからない・起動できない場合は Availability で返し、例外にはしない。

## 弱 / 中 / 強 → Skill Level (0-20) と movetime 目安。
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

## キャンセル用。探索中プロセスの PID。0 なら無し。
var _running_pid: int = 0
var _pid_mutex := Mutex.new()


func protocol_id() -> String:
	return "uci"


func display_name() -> String:
	return "UCI (Stockfish など)"


func probe(engine_path: String) -> Dictionary:
	var path := engine_path.strip_edges()
	if path.is_empty():
		return {
			"availability": Availability.MISSING,
			"message": "エンジンのパスが未設定です",
		}
	if not _path_looks_executable(path):
		return {
			"availability": Availability.MISSING,
			"message": "エンジンが見つかりません: %s" % path,
		}
	var info := OS.execute_with_pipe(path, PackedStringArray(), false)
	if info.is_empty() or not info.has("stdio") or not info.has("pid"):
		return {
			"availability": Availability.FAILED,
			"message": "エンジンを起動できませんでした: %s" % path,
		}
	var io: FileAccess = info["stdio"]
	var pid: int = int(info["pid"])
	_send(io, "uci")
	var ok := _wait_for_token(io, "uciok", 3000)
	_send(io, "quit")
	_safe_kill(pid)
	if not ok:
		return {
			"availability": Availability.FAILED,
			"message": "UCI 応答がありません: %s" % path,
		}
	return {
		"availability": Availability.AVAILABLE,
		"message": "エンジン利用可: %s" % path,
	}


func search_best_move_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = -1,
) -> String:
	var path := engine_path.strip_edges()
	if path.is_empty() or not _path_looks_executable(path):
		return ""
	var skill: int = int(SKILL_BY_STRENGTH.get(strength, 10))
	var mt: int = movetime_ms
	if mt < 0:
		mt = int(MOVETIME_BY_STRENGTH.get(strength, 500))
	var info := OS.execute_with_pipe(path, PackedStringArray(), false)
	if info.is_empty() or not info.has("stdio") or not info.has("pid"):
		return ""
	var io: FileAccess = info["stdio"]
	var pid: int = int(info["pid"])
	_set_running_pid(pid)
	var best := ""
	if _wait_handshake_and_go(io, position, skill, mt):
		best = _wait_bestmove(io, mt + 8000)
	_send(io, "quit")
	_safe_kill(pid)
	_set_running_pid(0)
	if best == "(none)" or best == "0000":
		return ""
	return best


func cancel_running() -> void:
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


func _wait_handshake_and_go(io: FileAccess, position: String, skill: int, movetime_ms: int) -> bool:
	_send(io, "uci")
	if not _wait_for_token(io, "uciok", 5000):
		return false
	_send(io, "setoption name Skill Level value %d" % skill)
	# 弱・中は Elo 上限も掛けて手の質の差をはっきりさせる。
	if skill < 20:
		_send(io, "setoption name UCI_LimitStrength value true")
		var elo := 1320
		if skill >= 10:
			elo = 1800
		elif skill >= 5:
			elo = 1500
		_send(io, "setoption name UCI_Elo value %d" % elo)
	else:
		_send(io, "setoption name UCI_LimitStrength value false")
	_send(io, "isready")
	if not _wait_for_token(io, "readyok", 5000):
		return false
	_send(io, "ucinewgame")
	_send(io, "isready")
	if not _wait_for_token(io, "readyok", 5000):
		return false
	# position は FEN 全文、または "startpos" / "startpos moves ..."
	if position.begins_with("startpos") or position.begins_with("fen "):
		_send(io, "position %s" % position)
	else:
		_send(io, "position fen %s" % position)
	_send(io, "go movetime %d" % movetime_ms)
	return true


func _path_looks_executable(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	# シンボリックリンクや実行ビットのみのケース向けに絶対パス存在も見る。
	return FileAccess.open(path, FileAccess.READ) != null


func _set_running_pid(pid: int) -> void:
	_pid_mutex.lock()
	_running_pid = pid
	_pid_mutex.unlock()


func _send(io: FileAccess, line: String) -> void:
	if io == null:
		return
	io.store_string(line + "\n")
	io.flush()


func _wait_for_token(io: FileAccess, token: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var line := io.get_line()
		if line.find(token) >= 0:
			return true
		if line.is_empty():
			OS.delay_msec(5)
	return false


func _wait_bestmove(io: FileAccess, timeout_ms: int) -> String:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var line := io.get_line()
		if line.begins_with("bestmove"):
			var parts := line.strip_edges().split(" ")
			if parts.size() >= 2:
				return parts[1]
			return ""
		if line.is_empty():
			OS.delay_msec(5)
	return ""


func _safe_kill(pid: int) -> void:
	if pid == 0:
		return
	# 既に終了していても OS.kill は失敗するだけなので握りつぶす。
	OS.kill(pid)
