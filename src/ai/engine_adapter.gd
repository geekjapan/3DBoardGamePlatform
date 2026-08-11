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
	}


## 初期局面などで最善手 UCI/USI 文字列を同期取得する(テスト・スモーク用)。
## 失敗時は空文字。例外は投げない。
func search_best_move_sync(
	engine_path: String,
	position: String,
	strength: int,
	movetime_ms: int = 200,
) -> String:
	return ""


## 非同期探索のキャンセル用に保持しているプロセスがあれば落とす。
func cancel_running() -> void:
	pass
