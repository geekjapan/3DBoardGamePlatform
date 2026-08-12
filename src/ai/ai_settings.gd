class_name AiSettings
extends RefCounted

## UCI/USI 対戦の永続設定。
##
## プロトコルごとに独立したプロファイルを持つ。engine_available と
## engine_message は probe の結果だけを保持する実行時値であり、設定には保存しない。

const CONFIG_PATH := "user://settings.cfg"
## 旧形式の読み取り専用セクション。保存では削除・変更しない。
const SECTION := "ai"
const UCI_SECTION := "ai_uci"
const USI_SECTION := "ai_usi"
const UCI := "uci"
const USI := "usi"
const PROFILE_UCI := UCI
const PROFILE_USI := USI

## よくある Stockfish の場所(初回デフォルト候補)。
const DEFAULT_PATH_CANDIDATES := [
	"/opt/homebrew/bin/stockfish",
	"/usr/local/bin/stockfish",
	"/usr/bin/stockfish",
	"stockfish",
]


class Profile extends RefCounted:
	## プロファイルキーでプロトコルが決まり、ここは可変設定ではない。
	var protocol: String
	var engine_path: String = ""
	var enabled: bool = false
	## EngineAdapter.Strength
	var strength: int = EngineAdapter.Strength.MEDIUM
	## プレイヤー側。AI は opposite。デフォルトは人が白(先手)。
	var human_side: int = Piece.Side.WHITE

	## 実行時のみ(永続化しない)。
	var engine_available: bool = false
	var engine_message: String = ""
	## 旧 API の ai_enabled が実効値を返すための状態。設定値とは別物。
	var status_checked: bool = false

	func _init(p_protocol: String = "uci") -> void:
		protocol = p_protocol

	func can_play_ai() -> bool:
		return enabled and engine_available

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


var uci: Profile = Profile.new(UCI)
var usi: Profile = Profile.new(USI)

## テスト差し替え用。空なら CONFIG_PATH を使う。
## テストが実ファイルへ書くと、利用者の保存済み設定を壊す。
var config_path: String = ""

## 旧 API 互換。既定プロファイルは UCI、protocol の変更で対象を切り替える。
## 新規コードは profile_for() / profile_for_game() を使う。
var _active_protocol: String = UCI

var protocol: String:
	get:
		return _active_protocol
	set(value):
		_active_protocol = _normalize_protocol(value)


## 旧 API の設定値は active profile の保存値へ転送する。
var ai_enabled: bool:
	get:
		var profile := active_profile()
		# 旧呼び出し元には、probe 後だけ従来どおり実効値を返す。
		# profile.enabled 自体は runtime probe で変更しない。
		return profile.enabled and (not profile.status_checked or profile.engine_available)
	set(value):
		active_profile().enabled = value

var strength: int:
	get:
		return active_profile().strength
	set(value):
		active_profile().strength = _normalize_strength(value)

var engine_path: String:
	get:
		return active_profile().engine_path
	set(value):
		active_profile().engine_path = str(value).strip_edges()

var human_side: int:
	get:
		return active_profile().human_side
	set(value):
		active_profile().human_side = int(value)

## 実行時状態の旧 API 互換 alias。永続化はしない。
var engine_available: bool:
	get:
		return active_profile().engine_available
	set(value):
		active_profile().engine_available = value

var engine_message: String:
	get:
		return active_profile().engine_message
	set(value):
		active_profile().engine_message = str(value)


static func load_or_default(path: String = "") -> AiSettings:
	var settings := AiSettings.new()
	if path != "":
		settings.config_path = path
	settings.load_from_disk()
	return settings


func resolved_path() -> String:
	if config_path != "":
		return config_path
	return CONFIG_PATH


## protocol または "chess"/"shogi" からプロファイルを得る。
func profile_for(protocol_id: String) -> Profile:
	return usi if _normalize_protocol(protocol_id) == USI else uci


## 短い互換 alias。AiMatch など protocol を持つ caller から使う。
func profile(protocol_id: String) -> Profile:
	return profile_for(protocol_id)


## ゲーム選択の境界でプロトコルを一度だけ変換する。
func profile_for_game(game_id: String) -> Profile:
	return usi if str(game_id).to_lower() == "shogi" else uci


## active profile の selector。引数なしは旧 API の active protocol、
## "chess"/"shogi" を渡した場合はゲーム ID として扱う。
func active_profile(selector: String = "") -> Profile:
	if selector.to_lower() == "chess" or selector.to_lower() == "shogi":
		return profile_for_game(selector)
	return profile_for(_active_protocol if selector == "" else selector)


func set_active_protocol(protocol_id: String) -> void:
	_active_protocol = _normalize_protocol(protocol_id)


func load_from_disk() -> void:
	_reset_runtime_status()
	var cfg := ConfigFile.new()
	var err := cfg.load(resolved_path())
	if err != OK:
		# 初回の UCI だけ既知の Stockfish 候補を解決する。USI は空のまま。
		uci.engine_path = _guess_default_path()
		return

	var has_new_format := cfg.has_section(UCI_SECTION) or cfg.has_section(USI_SECTION)
	if has_new_format:
		_read_profile(cfg, UCI_SECTION, uci, true)
		_read_profile(cfg, USI_SECTION, usi, false)
		# 新形式に旧 protocol の意味を持ち込まない。既存 caller 向けの既定値だけ UCI。
		_active_protocol = UCI
		return

	# 新形式が無いときだけ旧 [ai] を一度読み、対応する側へ移す。
	if cfg.has_section(SECTION):
		_migrate_legacy(cfg)
		# 旧 section は非破壊で残しつつ、新形式を直ちに正本化して再移行を防ぐ。
		_write_profile(cfg, UCI_SECTION, uci)
		_write_profile(cfg, USI_SECTION, usi)
		cfg.save(resolved_path())
	else:
		uci.engine_path = _guess_default_path()
		usi.engine_path = ""
		_active_protocol = UCI


func save_to_disk() -> int:
	var cfg := ConfigFile.new()
	# 他セクションと旧 [ai] はそのまま読み込んでから新セクションだけ更新する。
	cfg.load(resolved_path())
	_write_profile(cfg, UCI_SECTION, uci)
	_write_profile(cfg, USI_SECTION, usi)
	return cfg.save(resolved_path())


func strength_label(protocol_id: String = "") -> String:
	return active_profile(protocol_id).strength_label()


## 指定プロトコルのエンジンを probe して実行時 status を更新する。
## enabled / strength / human_side は probe の失敗でも変更しない。
func refresh_engine_status(protocol_id: String = "") -> void:
	var profile := active_profile(protocol_id)
	var adapter := EngineFactory.create(profile.protocol)
	var probe_path := profile.engine_path
	if profile.protocol == UCI and probe_path == "":
		probe_path = _guess_default_path()
		profile.engine_path = probe_path
	var result := adapter.probe(probe_path)
	var availability: int = int(result.get("availability", EngineAdapter.Availability.MISSING))
	profile.engine_message = str(result.get("message", ""))
	profile.engine_available = availability == EngineAdapter.Availability.AVAILABLE
	profile.status_checked = true


func can_play_ai(protocol_id: String = "") -> bool:
	return active_profile(protocol_id).can_play_ai()


func create_adapter(protocol_id: String = "") -> EngineAdapter:
	return EngineFactory.create(active_profile(protocol_id).protocol)


func _reset_runtime_status() -> void:
	for profile in [uci, usi]:
		profile.engine_available = false
		profile.engine_message = ""
		profile.status_checked = false


func _read_profile(cfg: ConfigFile, section: String, profile: Profile, discover_uci: bool) -> void:
	profile.enabled = bool(cfg.get_value(section, "enabled", false))
	profile.strength = _normalize_strength(int(cfg.get_value(
		section,
		"strength",
		EngineAdapter.Strength.MEDIUM,
	)))
	profile.engine_path = str(cfg.get_value(section, "engine_path", "")).strip_edges()
	profile.human_side = int(cfg.get_value(section, "human_side", Piece.Side.WHITE))
	if discover_uci and profile.engine_path == "":
		profile.engine_path = _guess_default_path()


func _write_profile(cfg: ConfigFile, section: String, profile: Profile) -> void:
	cfg.set_value(section, "enabled", profile.enabled)
	cfg.set_value(section, "strength", _normalize_strength(profile.strength))
	cfg.set_value(section, "engine_path", profile.engine_path)
	cfg.set_value(section, "human_side", profile.human_side)


func _migrate_legacy(cfg: ConfigFile) -> void:
	var legacy_protocol := str(cfg.get_value(SECTION, "protocol", UCI)).to_lower()
	var target := usi if legacy_protocol == USI else uci
	var other := uci if target == usi else usi
	_read_legacy_field_values(cfg, target, target == uci)
	other.engine_path = _guess_default_path() if other == uci else ""
	other.enabled = false
	other.strength = EngineAdapter.Strength.MEDIUM
	other.human_side = Piece.Side.WHITE
	_active_protocol = target.protocol


func _read_legacy_field_values(cfg: ConfigFile, target: Profile, discover_uci: bool) -> void:
	target.enabled = bool(cfg.get_value(SECTION, "enabled", false))
	target.strength = _normalize_strength(int(cfg.get_value(
		SECTION,
		"strength",
		EngineAdapter.Strength.MEDIUM,
	)))
	target.engine_path = str(cfg.get_value(SECTION, "engine_path", "")).strip_edges()
	target.human_side = int(cfg.get_value(SECTION, "human_side", Piece.Side.WHITE))
	if discover_uci and target.engine_path == "":
		target.engine_path = _guess_default_path()


static func _normalize_protocol(value: String) -> String:
	return USI if value.to_lower() == USI else UCI


static func _normalize_strength(value: int) -> int:
	return clampi(value, EngineAdapter.Strength.WEAK, EngineAdapter.Strength.STRONG)


func _guess_default_path() -> String:
	for p in DEFAULT_PATH_CANDIDATES:
		if p == "stockfish":
			continue
		if FileAccess.file_exists(p):
			return p
	return "/opt/homebrew/bin/stockfish"
