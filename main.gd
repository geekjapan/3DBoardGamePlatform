extends Node3D

## 起動シーン。ルールエンジンの初期配置を 3D 盤に載せ、クリックで対局する。
## LINES モードの定型セリフを SpeechDirector 経由で吹き出し表示する。
## AI 対戦(Stockfish / UCI)と設定画面を結線する。


var _settings: AiSettings
var _ai_match: AiMatch
var _ai_overlay: AiOverlay
var _settings_panel: SettingsPanel
var _controller: GameController


func _ready() -> void:
	_setup_environment()
	_setup_light()

	_settings = AiSettings.load_or_default()
	_settings.refresh_engine_status()
	# 起動時にエンジン無しなら AI はオフのまま 2 人対戦。

	var session := GameSession.start()

	var board_view := BoardView.new()
	add_child(board_view)
	board_view.build_from(session.board())

	var orbit := OrbitCamera.new()
	orbit.name = "OrbitCamera"
	add_child(orbit)

	var hud := GameHud.new()
	hud.name = "GameHud"
	add_child(hud)

	_ai_match = AiMatch.new()
	_ai_match.name = "AiMatch"
	add_child(_ai_match)
	_ai_match.setup(session, _settings)

	_controller = GameController.new()
	_controller.name = "GameController"
	add_child(_controller)
	_controller.setup(session, board_view, hud, orbit, _ai_match)

	_ai_overlay = AiOverlay.new()
	add_child(_ai_overlay)
	_ai_overlay.settings_pressed.connect(_on_open_settings)
	_ai_match.thinking_changed.connect(_ai_overlay.set_thinking)
	_ai_match.status_message.connect(_ai_overlay.set_status)
	_refresh_ai_badge()

	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.settings_applied.connect(_on_settings_applied)

	var catalog := SpeechCatalog.load_default()
	var resolver := SpeechResolver.new(catalog)
	var director := SpeechDirector.new()
	director.name = "SpeechDirector"
	add_child(director)
	director.setup(session, board_view, resolver, board_view.square_size)


func _on_open_settings() -> void:
	_settings_panel.open_with(_settings)


func _on_settings_applied(settings: AiSettings) -> void:
	_settings = settings
	_ai_match.rebind_settings(_settings)
	_refresh_ai_badge()


func _refresh_ai_badge() -> void:
	if _ai_overlay == null or _settings == null:
		return
	_ai_overlay.set_ai_mode(
		_settings.ai_enabled,
		_settings.strength_label(),
		_settings.engine_available
	)
	if not _settings.engine_available:
		_ai_overlay.set_status(_settings.engine_message)


func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.55
	world_env.environment = env
	add_child(world_env)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
