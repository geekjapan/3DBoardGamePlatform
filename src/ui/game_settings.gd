class_name GameSettings
extends RefCounted

## 起動時に選ぶゲーム種別だけを保持する専用設定。
## AI 設定や TeamSettings とは別ファイルにし、不正値は chess へ閉じる。

const DEFAULT_CONFIG_PATH := "user://game_settings.cfg"
const SECTION := "game"
const KEY_GAME_ID := "game_id"

var config_path: String = DEFAULT_CONFIG_PATH
var game_id: String = SpeechCatalog.GAME_CHESS


static func load_or_default(path: String = DEFAULT_CONFIG_PATH) -> GameSettings:
	var settings := GameSettings.new()
	settings.config_path = path
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return settings
	settings.game_id = normalize_game_id(str(
		cfg.get_value(SECTION, KEY_GAME_ID, SpeechCatalog.GAME_CHESS)
	))
	return settings


func save_to_disk() -> Error:
	game_id = normalize_game_id(game_id)
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(config_path):
		cfg.load(config_path)
	cfg.set_value(SECTION, KEY_GAME_ID, game_id)
	return cfg.save(config_path)


static func normalize_game_id(value: String) -> String:
	return SpeechCatalog.GAME_SHOGI if value == SpeechCatalog.GAME_SHOGI else SpeechCatalog.GAME_CHESS
