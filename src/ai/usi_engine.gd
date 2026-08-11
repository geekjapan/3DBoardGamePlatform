class_name UsiEngine
extends EngineAdapter

## 将棋用 USI エンジンのプレースホルダ。
## Phase 7 で実装する。今はインターフェースを並べるだけ(常に利用不可)。


func protocol_id() -> String:
	return "usi"


func display_name() -> String:
	return "USI (将棋・未実装)"


func probe(engine_path: String) -> Dictionary:
	return {
		"availability": Availability.MISSING,
		"message": "USI エンジンはまだ未対応です",
	}


func search_best_move_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = 200,
) -> String:
	return ""
