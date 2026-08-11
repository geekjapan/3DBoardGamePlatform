class_name AiSettings
extends RefCounted

## AI 対戦の永続設定。user://settings.cfg に保存し次回起動でも保持する。

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "ai"

## よくある Stockfish の場所(初回デフォルト候補)。
const DEFAULT_PATH_CANDIDATES := [
	"/opt/homebrew/bin/stockfish",
	"/usr/local/bin/stockfish",
	"/usr/bin/stockfish",
	"stockfish",
]

var ai_enabled: bool = false
## EngineAdapter.Strength
var strength: int = EngineAdapter.Strength.MEDIUM
var engine_path: String = ""
## "uci" / "usi"
var protocol: String = "uci"
## プレイヤー側。AI は opposite。デフォルトは人が白。
var human_side: int = Piece.Side.WHITE

## 実行時のみ(永続化しない)
var engine_available: bool = false
var engine_message: String = ""


static func load_or_default() -> AiSettings:
	var s := AiSettings.new()
	s.load_from_disk()
	return s


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		engine_path = _guess_default_path()
		return
	ai_enabled = bool(cfg.get_value(SECTION, "enabled", false))
	strength = int(cfg.get_value(SECTION, "strength", EngineAdapter.Strength.MEDIUM))
	engine_path = str(cfg.get_value(SECTION, "engine_path", "")).strip_edges()
	if engine_path == "":
		# 空で保存された設定が自動検出に勝たないようにする。
		engine_path = _guess_default_path()
	protocol = str(cfg.get_value(SECTION, "protocol", "uci"))
	human_side = int(cfg.get_value(SECTION, "human_side", Piece.Side.WHITE))
	strength = clampi(strength, EngineAdapter.Strength.WEAK, EngineAdapter.Strength.STRONG)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	# 他セクションを壊さないよう既存を読んでから書く。
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, "enabled", ai_enabled)
	cfg.set_value(SECTION, "strength", strength)
	cfg.set_value(SECTION, "engine_path", engine_path)
	cfg.set_value(SECTION, "protocol", protocol)
	cfg.set_value(SECTION, "human_side", human_side)
	cfg.save(CONFIG_PATH)


func strength_label() -> String:
	match strength:
		EngineAdapter.Strength.WEAK:
			return "弱"
		EngineAdapter.Strength.MEDIUM:
			return "中"
		EngineAdapter.Strength.STRONG:
			return "強"
		_:
			return "?"


## エンジンを probe して engine_available / message を更新する。
## 利用不可なら ai_enabled を落とす(例外は投げない)。
func refresh_engine_status() -> void:
	var adapter := EngineFactory.create(protocol)
	var result := adapter.probe(engine_path)
	var availability: int = int(result.get("availability", EngineAdapter.Availability.MISSING))
	engine_message = str(result.get("message", ""))
	engine_available = availability == EngineAdapter.Availability.AVAILABLE
	if not engine_available:
		ai_enabled = false


func can_play_ai() -> bool:
	return engine_available and ai_enabled


func create_adapter() -> EngineAdapter:
	return EngineFactory.create(protocol)


func _guess_default_path() -> String:
	for p in DEFAULT_PATH_CANDIDATES:
		if p == "stockfish":
			continue
		if FileAccess.file_exists(p):
			return p
	return "/opt/homebrew/bin/stockfish"
