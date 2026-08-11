class_name SpeechUtterance
extends RefCounted

## 1 回の発話内容。表示層(吹き出し)がそのまま消費する。

## GameEvent キー(moved / captured / captured_by / check / promoted / game_over)。
var event_key: String = ""
## 表示するセリフ本文(日本語)。
var text: String = ""
## 発話キャラクター ID。
var character_id: String = ""
## 吹き出しを寄せるマス。
var square: Vector2i = Vector2i(-1, -1)
## Piece.Side
var side: int = Piece.Side.WHITE
## Piece.Kind(着手時点 / 取られた駒の kind)
var kind: int = Piece.Kind.PAWN
## 取られた側の発話か。true なら盤から消える駒向けの配置になる。
var is_victim: bool = false
