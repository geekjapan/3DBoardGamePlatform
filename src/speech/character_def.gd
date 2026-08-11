class_name CharacterDef
extends RefCounted

## キャラクター定義。3D モデル・性格・セリフ表を持つ実体(CONTEXT.md の Character)。
## 駒種からは独立し、チーム割当経由でどの駒にも載せられる。

## データ上の一意 ID。
var id: String = ""
## 表示名(日本語可)。
var display_name: String = ""
## 性格の説明文。LLM 発話などの後続モード向けにも使う。
var personality: String = ""
## GameEvent キー → セリフ配列。キー例: moved / captured / captured_by / check / promoted / game_over。
var lines: Dictionary = {}


func lines_for(event_key: String) -> PackedStringArray:
	## 未定義キーや空配列は空を返す(呼び出し側で発話スキップ。クラッシュしない)。
	if event_key == "" or not lines.has(event_key):
		return PackedStringArray()
	var raw: Variant = lines[event_key]
	if raw is PackedStringArray:
		return raw as PackedStringArray
	if raw is Array:
		var out := PackedStringArray()
		for item in raw as Array:
			var s := str(item).strip_edges()
			if s != "":
				out.append(s)
		return out
	return PackedStringArray()


func has_lines_for(event_key: String) -> bool:
	return not lines_for(event_key).is_empty()
