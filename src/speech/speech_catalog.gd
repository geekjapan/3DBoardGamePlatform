class_name SpeechCatalog
extends RefCounted

## data/ 以下のテキスト(JSON)から Character と Team を読み込む。
## 複数チームをディレクトリから読み、対局時は陣営ごとに1つ選ぶ。
## 読み込み境界で検証し、壊れた定義はスキップして続行する。

const DEFAULT_CHARACTERS_DIR := "res://data/characters"
const DEFAULT_TEAMS_DIR := "res://data/teams"
const DEFAULT_TEAM_PATH := "res://data/teams/default.json"

const GAME_CHESS := "chess"
const GAME_SHOGI := "shogi"

const KIND_NAMES: PackedStringArray = [
	"pawn", "knight", "bishop", "rook", "queen", "king",
	"shogi_pawn", "shogi_lance", "shogi_knight", "shogi_silver",
	"shogi_gold", "shogi_bishop", "shogi_rook", "shogi_king",
	"shogi_promoted_pawn", "shogi_promoted_lance", "shogi_promoted_knight",
	"shogi_promoted_silver", "shogi_horse", "shogi_dragon",
]

const CHESS_KINDS: Array = [
	Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
	Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
]
const SHOGI_KINDS: Array = [
	Piece.Kind.SHOGI_PAWN, Piece.Kind.SHOGI_LANCE, Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_SILVER, Piece.Kind.SHOGI_GOLD, Piece.Kind.SHOGI_BISHOP,
	Piece.Kind.SHOGI_ROOK, Piece.Kind.SHOGI_KING,
	Piece.Kind.SHOGI_PROMOTED_PAWN, Piece.Kind.SHOGI_PROMOTED_LANCE,
	Piece.Kind.SHOGI_PROMOTED_KNIGHT, Piece.Kind.SHOGI_PROMOTED_SILVER,
	Piece.Kind.SHOGI_HORSE, Piece.Kind.SHOGI_DRAGON,
]
const ALL_KINDS: Array = CHESS_KINDS + SHOGI_KINDS

## id → CharacterDef
var characters: Dictionary = {}
## id → TeamDef
var teams: Dictionary = {}
## 後方互換用の単一チーム参照(既定チーム、または明示的に差し替えたもの)。
var team: TeamDef = TeamDef.new()

## 対局で使う陣営ごとのチーム ID。未設定や未知 ID は team にフォールバック。
var white_team_id: String = ""
var black_team_id: String = ""


static func load_default() -> SpeechCatalog:
	return load_from(DEFAULT_CHARACTERS_DIR, DEFAULT_TEAMS_DIR)


static func load_from(characters_dir: String, teams_path: String) -> SpeechCatalog:
	## teams_path はディレクトリ(全チーム)でも単一 JSON ファイルでも可。
	var catalog := SpeechCatalog.new()
	catalog._load_characters_dir(characters_dir)
	if _is_directory(teams_path):
		catalog._load_teams_dir(teams_path)
	else:
		var one := catalog._load_team(teams_path)
		if one.id != "" and one.id != "empty":
			catalog.teams[one.id] = one
	catalog._ensure_default_team_selection()
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


static func kinds_for_game(game_id: String) -> Array:
	## 未知値は既存チェス表示へ安全に丸める。
	return SHOGI_KINDS if game_id == GAME_SHOGI else CHESS_KINDS


static func _is_directory(path: String) -> bool:
	var dir := DirAccess.open(path)
	return dir != null


func character(character_id: String) -> CharacterDef:
	if character_id == "" or not characters.has(character_id):
		return null
	return characters[character_id] as CharacterDef


func team_by_id(team_id: String) -> TeamDef:
	if team_id == "" or not teams.has(team_id):
		return null
	return teams[team_id] as TeamDef


func team_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in teams.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func team_for_side(side: int) -> TeamDef:
	## 陣営に選ばれたチーム。未知 ID や未設定は後方互換の team を返す。
	var id := white_team_id if side == Piece.Side.WHITE else black_team_id
	var found := team_by_id(id)
	if found != null:
		return found
	return team


func set_side_teams(p_white_team_id: String, p_black_team_id: String) -> void:
	## 両陣営に同じチーム ID を渡しても成立する。
	white_team_id = p_white_team_id.strip_edges()
	black_team_id = p_black_team_id.strip_edges()
	if teams.has(white_team_id):
		team = teams[white_team_id] as TeamDef
	elif not teams.is_empty():
		team = teams[team_ids()[0]] as TeamDef


func character_for_kind(kind: int, side: int = -1) -> CharacterDef:
	## side 省略時は後方互換の単一 team。指定時は陣営チームを使う。
	if side < 0:
		return character(team.character_id_for_kind(kind))
	return character(team_for_side(side).character_id_for_kind(kind))


func character_id_for_side_kind(side: int, kind: int) -> String:
	## 盤上の駒(陣営+駒種)に乗るキャラクター ID。未割当は空文字。
	return team_for_side(side).character_id_for_kind(kind)


func lineup_for_side(side: int, game_id: String = GAME_CHESS) -> Dictionary:
	## 駒種整数 → キャラクター ID。選んだチームどおりの並び(論理)。
	var out: Dictionary = {}
	var t := team_for_side(side)
	for kind in kinds_for_game(game_id):
		var cid := t.character_id_for_kind(kind)
		if cid != "":
			out[kind] = cid
	return out


func _ensure_default_team_selection() -> void:
	if teams.is_empty():
		team = TeamDef.new()
		team.id = "empty"
		team.display_name = "empty"
		white_team_id = ""
		black_team_id = ""
		return
	var preferred := "default"
	if not teams.has(preferred):
		preferred = team_ids()[0]
	team = teams[preferred] as TeamDef
	if white_team_id == "" or not teams.has(white_team_id):
		white_team_id = preferred
	if black_team_id == "" or not teams.has(black_team_id):
		black_team_id = preferred


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


func _load_teams_dir(dir_path: String) -> void:
	teams.clear()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("SpeechCatalog: チームディレクトリを開けない: %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full := dir_path.path_join(file_name)
			var def := _load_team(full)
			if def != null and def.id != "" and def.id != "empty":
				teams[def.id] = def
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
	def.model_path = str(dict.get("model", "")).strip_edges()
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
