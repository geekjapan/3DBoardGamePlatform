class_name MoveEvent
extends RefCounted

## 1 着手の結果。アニメーション / AI / 発話が同じ内容を観測するための共有ペイロード。
## CONTEXT.md の GameEvent(moved / captured / check / promoted / game_over)に対応する事実を持つ。

const NO_SQUARE := Vector2i(-1, -1)


## 適用された合法手(エンジンが受理したもの)。
var move: Move = null
## 動かした側 (Piece.Side)。
var mover_side: int = Piece.Side.WHITE
## 動かす直前の駒種 (成り前)。Piece.Kind。
var mover_kind: int = Piece.Kind.PAWN
## 取られた駒。取らなければ null。
var captured: Piece = null
## 取られたマス。アンパッサンでは移動先ではなく取られたポーンのマス。無ければ NO_SQUARE。
var captured_square: Vector2i = NO_SQUARE
## 着手後、相手側が王手か。
var is_check: bool = false
## チェックメイトで終局したか。
var is_checkmate: bool = false
## ステイルメイトで終局したか。
var is_stalemate: bool = false
## 対局終了か (メイト or ステイル)。
var is_over: bool = false
## 終局メッセージ。進行中は空文字。
var result_text: String = ""


func from_square() -> Vector2i:
	return move.from if move != null else NO_SQUARE


func to_square() -> Vector2i:
	return move.to if move != null else NO_SQUARE


func promotion() -> int:
	## 成らなければ -1。
	return move.promotion if move != null else -1


func was_capture() -> bool:
	return captured != null


func was_promotion() -> bool:
	return promotion() >= 0


func was_castling() -> bool:
	return move != null and move.is_castling


func was_en_passant() -> bool:
	return move != null and move.is_en_passant
