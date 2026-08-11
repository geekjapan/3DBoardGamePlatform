class_name SpeechCatalog
extends RefCounted

## data/ 以下のテキスト(JSON)から Character と Team を読み込む。
## 読み込み境界で検証し、壊れた定義はスキップして続行する。

const DEFAULT_CHARACTERS_DIR := "res://data/characters"
const DEFAULT_TEAM_PATH := "res://data/teams/default.json"

const KIND_NAMES: PackedStringArray = [
	"pawn", "knight", "bishop", "rook", "queen", "king"
]

## id → CharacterDef
var characters: Dictionary = {}
var team: TeamDef = TeamDef.new()


static func load_default() -> SpeechCatalog:
	return load_from(DEFAULT_CHARACTERS_DIR, DEFAULT_TEAM_PATH)


static func load_from(characters_dir: String, team_path: String) -> SpeechCatalog:
	var catalog := SpeechCatalog.new()
	catalog._load_characters_dir(characters_dir)
	catalog.team = catalog._load_team(team_path)
	return catalog


static func kind_from_name(name: String) -> int:
	## 未知の駒種名は -1。
	var key := name.strip_edges().to_lower()
	for i in KIND_NAMES.size():
		if KIND_NAMES[i] == key:
			return i
	return -1


static func kind_name(kind: int) -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return ""
	return KIND_NAMES[kind]


func character(character_id: String) -> CharacterDef:
	if character_id == "" or not characters.has(character_id):
		return null
	return characters[character_id] as CharacterDef


func character_for_kind(kind: int) -> CharacterDef:
	return character(team.character_id_for_kind(kind))


func _load_characters_dir(dir_path: String) -> void:
	characters.clear()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("SpeechCatalog: キャラクターディレクトリを開けない: %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full := dir_path.path_join(file_name)
			var def := _parse_character_file(full)
			if def != null and def.id != "":
				characters[def.id] = def
		file_name = dir.get_next()
	dir.list_dir_end()


func _parse_character_file(path: String) -> CharacterDef:
	var text := _read_text(path)
	if text == "":
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SpeechCatalog: キャラクター JSON がオブジェクトではない: %s" % path.get_file())
		return null
	var dict: Dictionary = data
	var def := CharacterDef.new()
	def.id = str(dict.get("id", "")).strip_edges()
	if def.id == "":
		push_warning("SpeechCatalog: id が空: %s" % path.get_file())
		return null
	def.display_name = str(dict.get("display_name", def.id)).strip_edges()
	def.personality = str(dict.get("personality", "")).strip_edges()
	var lines_raw: Variant = dict.get("lines", {})
	if typeof(lines_raw) == TYPE_DICTIONARY:
		def.lines = _normalize_lines(lines_raw as Dictionary)
	return def


func _load_team(path: String) -> TeamDef:
	var team_def := TeamDef.new()
	team_def.id = "empty"
	team_def.display_name = "empty"
	var text := _read_text(path)
	if text == "":
		push_warning("SpeechCatalog: チーム定義を読めない: %s" % path)
		return team_def
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("SpeechCatalog: チーム JSON がオブジェクトではない")
		return team_def
	var dict: Dictionary = data
	team_def.id = str(dict.get("id", "default")).strip_edges()
	team_def.display_name = str(dict.get("display_name", team_def.id)).strip_edges()
	var assigns: Variant = dict.get("assignments", {})
	if typeof(assigns) != TYPE_DICTIONARY:
		return team_def
	for key in assigns as Dictionary:
		var kind := kind_from_name(str(key))
		if kind < 0:
			push_warning("SpeechCatalog: 未知の駒種名 '%s' をスキップ" % str(key))
			continue
		var char_id := str((assigns as Dictionary)[key]).strip_edges()
		if char_id == "":
			continue
		# 未登録キャラでも割当は保持する(後から足す・テスト差し替え用)。
		team_def.assign(kind, char_id)
	return team_def


func _normalize_lines(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw:
		var event_key := str(key).strip_edges()
		if event_key == "":
			continue
		var arr := PackedStringArray()
		var value: Variant = raw[key]
		if value is Array:
			for item in value as Array:
				var s := str(item).strip_edges()
				if s != "":
					arr.append(s)
		elif typeof(value) == TYPE_STRING:
			var one := str(value).strip_edges()
			if one != "":
				arr.append(one)
		out[event_key] = arr
	return out


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()
