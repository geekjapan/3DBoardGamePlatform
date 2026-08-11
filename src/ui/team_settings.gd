class_name TeamSettings
extends RefCounted

## 陣営ごとのチーム選択。user://settings.cfg に保存し次回起動でも保持する。
## AI 設定と同じファイルの別セクションを使う(他設定を壊さない)。

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "teams"
const DEFAULT_TEAM_ID := "default"

var white_team_id: String = DEFAULT_TEAM_ID
var black_team_id: String = DEFAULT_TEAM_ID

## テスト差し替え用。空なら CONFIG_PATH を使う。
var config_path: String = ""


static func load_or_default(path: String = "") -> TeamSettings:
	var s := TeamSettings.new()
	if path != "":
		s.config_path = path
	s.load_from_disk()
	return s


func resolved_path() -> String:
	if config_path != "":
		return config_path
	return CONFIG_PATH


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(resolved_path())
	if err != OK:
		white_team_id = DEFAULT_TEAM_ID
		black_team_id = DEFAULT_TEAM_ID
		return
	white_team_id = str(cfg.get_value(SECTION, "white_team_id", DEFAULT_TEAM_ID)).strip_edges()
	black_team_id = str(cfg.get_value(SECTION, "black_team_id", DEFAULT_TEAM_ID)).strip_edges()
	if white_team_id == "":
		white_team_id = DEFAULT_TEAM_ID
	if black_team_id == "":
		black_team_id = DEFAULT_TEAM_ID


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	# 他セクションを壊さないよう既存を読んでから書く。
	cfg.load(resolved_path())
	cfg.set_value(SECTION, "white_team_id", white_team_id)
	cfg.set_value(SECTION, "black_team_id", black_team_id)
	cfg.save(resolved_path())


func apply_to_catalog(catalog: SpeechCatalog) -> void:
	if catalog == null:
		return
	var w := white_team_id
	var b := black_team_id
	# 未知 ID はカタログ既定へ寄せる(起動時に定義が消えても落ちない)。
	if catalog.team_by_id(w) == null:
		w = catalog.white_team_id if catalog.white_team_id != "" else DEFAULT_TEAM_ID
		if catalog.team_by_id(w) == null and not catalog.teams.is_empty():
			w = catalog.team_ids()[0]
	if catalog.team_by_id(b) == null:
		b = catalog.black_team_id if catalog.black_team_id != "" else DEFAULT_TEAM_ID
		if catalog.team_by_id(b) == null and not catalog.teams.is_empty():
			b = catalog.team_ids()[0]
	white_team_id = w
	black_team_id = b
	catalog.set_side_teams(w, b)


func clamp_to_catalog(catalog: SpeechCatalog) -> void:
	## 保存前に存在するチーム ID だけに丸める。
	if catalog == null:
		return
	if catalog.team_by_id(white_team_id) == null:
		white_team_id = DEFAULT_TEAM_ID if catalog.team_by_id(DEFAULT_TEAM_ID) != null else (
			catalog.team_ids()[0] if not catalog.teams.is_empty() else DEFAULT_TEAM_ID
		)
	if catalog.team_by_id(black_team_id) == null:
		black_team_id = DEFAULT_TEAM_ID if catalog.team_by_id(DEFAULT_TEAM_ID) != null else (
			catalog.team_ids()[0] if not catalog.teams.is_empty() else DEFAULT_TEAM_ID
		)
