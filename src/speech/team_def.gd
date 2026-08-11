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
	## 明示割当を優先し、成駒だけ対応する将棋基本駒へ解決する。
	if assignments.has(kind):
		return str(assignments[kind])
	var base_kind := Piece.base_kind_for_promoted(kind)
	if base_kind >= 0 and assignments.has(base_kind):
		return str(assignments[base_kind])
	return ""


func assign(kind: int, character_id: String) -> void:
	assignments[kind] = character_id
