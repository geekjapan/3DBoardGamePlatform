class_name SpeechSettings
extends RefCounted

## 発話モードと通常手の発話確率。user://settings.cfg に保存し次回起動でも保持する。
## API キーはここに持たない(環境変数からのみ読む。永続化禁止)。

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "speech"

## 定型文 / 音声読み上げ / LLM 動的生成。
enum Mode {
	LINES = 0,
	TTS = 1,
	LLM = 2,
}

const DEFAULT_MOVE_PROBABILITY := 0.3
## LLM 応答の既定待ち時間(ミリ秒)。超過したら定型へフォールバック。
const DEFAULT_LLM_TIMEOUT_MS := 2500

var mode: int = Mode.LINES
var move_probability: float = DEFAULT_MOVE_PROBABILITY
## LLM 待ち時間。設定 UI には出さず定数既定を使うが、テスト差し替え用に公開。
var llm_timeout_ms: int = DEFAULT_LLM_TIMEOUT_MS

## テスト差し替え用。空なら CONFIG_PATH を使う。
var config_path: String = ""


static func load_or_default(path: String = "") -> SpeechSettings:
	var s := SpeechSettings.new()
	if path != "":
		s.config_path = path
	s.load_from_disk()
	return s


static func mode_label(value: int) -> String:
	match value:
		Mode.LINES:
			return "定型"
		Mode.TTS:
			return "音声"
		Mode.LLM:
			return "生成"
		_:
			return "定型"


func resolved_path() -> String:
	if config_path != "":
		return config_path
	return CONFIG_PATH


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(resolved_path())
	if err != OK:
		mode = Mode.LINES
		move_probability = DEFAULT_MOVE_PROBABILITY
		return
	mode = int(cfg.get_value(SECTION, "mode", Mode.LINES))
	mode = clampi(mode, Mode.LINES, Mode.LLM)
	move_probability = float(cfg.get_value(SECTION, "move_probability", DEFAULT_MOVE_PROBABILITY))
	move_probability = clampf(move_probability, 0.0, 1.0)
	# API キーを設定ファイルから読まない(あっても無視)。


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	# 他セクションを壊さないよう既存を読んでから書く。
	cfg.load(resolved_path())
	cfg.set_value(SECTION, "mode", clampi(mode, Mode.LINES, Mode.LLM))
	cfg.set_value(SECTION, "move_probability", clampf(move_probability, 0.0, 1.0))
	# API キーは絶対に書かない。
	cfg.save(resolved_path())


func apply_to_resolver(resolver: SpeechResolver) -> void:
	if resolver == null:
		return
	resolver.move_probability = clampf(move_probability, 0.0, 1.0)
