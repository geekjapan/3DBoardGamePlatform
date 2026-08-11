class_name TeamDef
extends RefCounted

## 駒種 → Character の割当セット(CONTEXT.md の Team)。
## 同じキャラクター ID を複数の駒種に割り当ててよい。

## データ上の一意 ID。
var id: String = ""
## 表示名。
var display_name: String = ""
## Piece.Kind 整数 → キャラクター ID。
var assignments: Dictionary = {}


func character_id_for_kind(kind: int) -> String:
	## 未割当なら空文字。
	if not assignments.has(kind):
		return ""
	return str(assignments[kind])


func assign(kind: int, character_id: String) -> void:
	assignments[kind] = character_id
