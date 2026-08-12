class_name TeamStore
extends RefCounted

## ユーザーが編成画面で作った Team の永続化。
## res://data/teams は同梱定義、user://teams は編集可能コピー。
## 同一 id はユーザー定義がカタログ上で上書きする(同梱ファイルは触らない)。

const USER_TEAMS_DIR := "user://teams"


static func ensure_dir(dir_path: String = USER_TEAMS_DIR) -> void:
	var global := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(global)


static func load_into_catalog(catalog: SpeechCatalog, dir_path: String = USER_TEAMS_DIR) -> int:
	## user チームをカタログに取り込む。読み込んだ件数を返す。
	if catalog == null:
		return 0
	var loaded := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full := dir_path.path_join(file_name)
			var team := load_team_file(full)
			if team != null and team.id != "" and team.id != "empty":
				catalog.teams[team.id] = team
				loaded += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	# 既定選択が消えていた場合の保険。
	if catalog.team_by_id(catalog.white_team_id) == null or catalog.team_by_id(catalog.black_team_id) == null:
		catalog.set_side_teams(catalog.white_team_id, catalog.black_team_id)
	return loaded


static func load_team_file(path: String) -> TeamDef:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("TeamStore: JSON がオブジェクトではない: %s" % path.get_file())
		return null
	return team_from_dict(data as Dictionary)


static func save_team(team: TeamDef, dir_path: String = USER_TEAMS_DIR) -> Error:
	## 割当が欠けていても保存できる。空 id / 空名は拒否。
	if team == null:
		return ERR_INVALID_PARAMETER
	var id := team.id.strip_edges()
	var name := team.display_name.strip_edges()
	if id == "" or id == "empty":
		return ERR_INVALID_PARAMETER
	if name == "":
		return ERR_INVALID_PARAMETER
	ensure_dir(dir_path)
	var path := dir_path.path_join("%s.json" % _safe_file_stem(id))
	var json := JSON.stringify(team_to_dict(team), "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(json)
	f.store_string("\n")
	return OK


static func delete_team_file(team_id: String, dir_path: String = USER_TEAMS_DIR) -> void:
	var path := dir_path.path_join("%s.json" % _safe_file_stem(team_id))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func team_to_dict(team: TeamDef) -> Dictionary:
	var assigns: Dictionary = {}
	for kind in SpeechCatalog.ALL_KINDS:
		# 解決時フォールバックは暗黙 assignment として保存しない。
		if not team.assignments.has(kind):
			continue
		var cid := str(team.assignments[kind]).strip_edges()
		if cid == "":
			continue
		var kn := SpeechCatalog.kind_name(kind)
		if kn != "":
			assigns[kn] = cid
	return {
		"id": team.id,
		"display_name": team.display_name,
		"assignments": assigns,
	}


static func team_from_dict(dict: Dictionary) -> TeamDef:
	var team := TeamDef.new()
	team.id = str(dict.get("id", "")).strip_edges()
	team.display_name = str(dict.get("display_name", team.id)).strip_edges()
	var assigns: Variant = dict.get("assignments", {})
	if typeof(assigns) != TYPE_DICTIONARY:
		return team
	for key in assigns as Dictionary:
		var kind := SpeechCatalog.kind_from_name(str(key))
		if kind < 0:
			continue
		var char_id := str((assigns as Dictionary)[key]).strip_edges()
		if char_id == "":
			continue
		team.assign(kind, char_id)
	return team


static func make_team_id(display_name: String, existing_ids: PackedStringArray = PackedStringArray()) -> String:
	## 表示名からファイル安全な id を作る。衝突時は連番。
	var base := _slugify(display_name)
	if base == "" or base == "empty":
		base = "team"
	var candidate := base
	var n := 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base, n]
		n += 1
	return candidate


static func clone_team(source: TeamDef) -> TeamDef:
	## 編集用のディープコピー。
	var t := TeamDef.new()
	if source == null:
		return t
	t.id = source.id
	t.display_name = source.display_name
	for kind in source.assignments.keys():
		var cid := str(source.assignments[kind]).strip_edges()
		if cid != "":
			t.assign(int(kind), cid)
	return t


static func clear_assignment(team: TeamDef, kind: int) -> void:
	if team == null:
		return
	if team.assignments.has(kind):
		team.assignments.erase(kind)


static func _safe_file_stem(team_id: String) -> String:
	var s := team_id.strip_edges()
	# パス区切りや空白を落としてファイル名に使う。
	s = s.replace("/", "_").replace("\\", "_").replace("..", "_")
	s = s.replace(" ", "_")
	if s == "":
		return "team"
	return s


static func _slugify(text: String) -> String:
	var s := text.strip_edges().to_lower()
	# 英数字と日本語はそのまま、空白は _。その他記号は落とす。
	var out := ""
	for i in s.length():
		var ch := s[i]
		var code := ch.unicode_at(0)
		var ok := (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 122)
			or code == 95
			or code > 127
		)
		if ch == " " or ch == "-" or ch == "　":
			out += "_"
		elif ok:
			out += ch
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out
