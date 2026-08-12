class_name EngineAdapter
extends RefCounted

## 外部思考エンジンの共通インターフェース。
## UCI(チェス / Stockfish)と USI(将棋)を同じ入口で並べられるようにする。
## 具体プロトコルはサブクラスが実装する。バイナリはリポジトリに含めない。

## エンジンの利用可否。見つからない・起動失敗は例外にせずこの値で表す。
enum Availability {
	AVAILABLE,
	MISSING,
	FAILED,
}

## Structured result classifications shared by UCI and USI adapters.
enum SearchStatus {
	OK,
	CANCELLED,
	STALE,
	UNAVAILABLE,
	PROTOCOL_ERROR,
	SEARCH_TIMEOUT,
	PROCESS_EXITED,
	INVALID_MOVE,
	RESIGNED,
}

## 強さプリセット(弱 / 中 / 強)。UCI の Skill Level 等に写像する。
enum Strength {
	WEAK = 0,
	MEDIUM = 1,
	STRONG = 2,
}


## プロトコル識別子。"uci" / "usi" など。ファクトリが参照する。
func protocol_id() -> String:
	return ""


## 表示名(設定 UI 用)。
func display_name() -> String:
	return protocol_id()


## 実行ファイルの有無と起動可否を調べる。例外は投げない。
## 戻り値: { "availability": Availability, "message": String }
func probe(engine_path: String) -> Dictionary:
	return {
		"availability": Availability.MISSING,
		"message": "未実装のプロトコルです",
		"engine_id": "",
		"transcript": "",
	}


## 初期局面などで最善手 UCI/USI を構造化して同期取得する。
## 失敗時も例外を投げず、必ず SearchStatus と診断情報を返す。
func search_best_move_result_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = -1,
) -> Dictionary:
	return make_search_result(
		SearchStatus.UNAVAILABLE,
		"",
		"未実装のプロトコルです",
		"UNSUPPORTED_PROTOCOL",
		"",
		"",
		0,
	)


## Existing callers keep the string API; all non-OK outcomes become empty.
func search_best_move_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = -1,
) -> String:
	var result := search_best_move_result_sync(engine_path, position, strength, movetime_ms)
	if int(result.get("status", SearchStatus.PROTOCOL_ERROR)) != SearchStatus.OK:
		return ""
	return str(result.get("move_text", ""))


func make_search_result(
	status: int,
	move_text: String = "",
	message: String = "",
	detail_code: String = "",
	transcript: String = "",
	engine_id: String = "",
	elapsed_ms: int = 0,
) -> Dictionary:
	var elapsed := maxi(0, elapsed_ms)
	return {
		"status": status,
		"status_name": search_status_name(status),
		"move_text": move_text,
		"message": message,
		"detail_code": detail_code,
		"transcript": transcript,
		"engine_id": engine_id,
		"elapsed_ms": elapsed,
		"elapsed": elapsed,
	}


static func search_status_name(status: int) -> String:
	match status:
		SearchStatus.OK: return "OK"
		SearchStatus.CANCELLED: return "CANCELLED"
		SearchStatus.STALE: return "STALE"
		SearchStatus.UNAVAILABLE: return "UNAVAILABLE"
		SearchStatus.PROTOCOL_ERROR: return "PROTOCOL_ERROR"
		SearchStatus.SEARCH_TIMEOUT: return "SEARCH_TIMEOUT"
		SearchStatus.PROCESS_EXITED: return "PROCESS_EXITED"
		SearchStatus.INVALID_MOVE: return "INVALID_MOVE"
		SearchStatus.RESIGNED: return "RESIGNED"
		_: return "UNKNOWN"


func _path_looks_executable(path: String) -> bool:
	if path.is_empty():
		return false
	if FileAccess.file_exists(path):
		return true
	# PATH-resolved command names are accepted by execute_with_pipe. A failed
	# launch is classified as FAILED/UNAVAILABLE by the concrete adapter.
	return not path.contains("/")


func _reset_cancel_request() -> void:
	_cancel_mutex.lock()
	_cancel_requested = false
	_cancel_mutex.unlock()


func _request_cancel() -> void:
	_cancel_mutex.lock()
	_cancel_requested = true
	_cancel_mutex.unlock()


func _is_cancel_requested() -> bool:
	_cancel_mutex.lock()
	var requested := _cancel_requested
	_cancel_mutex.unlock()
	return requested


var _cancel_mutex := Mutex.new()
var _cancel_requested: bool = false


## 非同期探索のキャンセル用に保持しているプロセスがあれば落とす。
func cancel_running() -> void:
	pass
