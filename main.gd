extends Node3D

## 起動シーン。ルールエンジンの初期配置を 3D 盤に載せ、クリックで対局する。
## 対局開始前に陣営ごとのチームを選び、選んだ割当でセリフを解決する。
## LINES モードの定型セリフを SpeechDirector 経由で吹き出し表示する。
## AI 対戦(Stockfish / UCI)と設定画面を結線する。


var _settings: AiSettings
var _team_settings: TeamSettings
var _catalog: SpeechCatalog
var _ai_match: AiMatch
var _ai_overlay: AiOverlay
var _settings_panel: SettingsPanel
var _team_panel: TeamSelectPanel
var _controller: GameController
var _board_view: BoardView
var _hud: GameHud
var _orbit: OrbitCamera
var _speech_director: SpeechDirector
var _speech_resolver: SpeechResolver
var _match_started: bool = false


func _ready() -> void:
	_setup_environment()
	_setup_light()

	_settings = AiSettings.load_or_default()
	_settings.refresh_engine_status()
	# 起動時にエンジン無しなら AI はオフのまま 2 人対戦。

	_catalog = SpeechCatalog.load_default()
	_team_settings = TeamSettings.load_or_default()
	_team_settings.apply_to_catalog(_catalog)

	_team_panel = TeamSelectPanel.new()
	add_child(_team_panel)
	_team_panel.confirmed.connect(_on_teams_confirmed)
	# 対局開始時に先手・後手を独立選択(同一チームも可)。保持済み選択を初期値に。
	_team_panel.open_with(_catalog, _team_settings)


func _on_teams_confirmed(settings: TeamSettings) -> void:
	_team_settings = settings
	_team_settings.apply_to_catalog(_catalog)
	if _match_started:
		# 再選択時はセリフ解決だけ更新(盤の再構築はしない)。
		if _speech_resolver != null:
			_speech_resolver.catalog = _catalog
		_refresh_team_badge()
		return
	_start_match()


func _start_match() -> void:
	_match_started = true

	var session := GameSession.start()

	_board_view = BoardView.new()
	add_child(_board_view)
	_board_view.build_from(session.board())

	_orbit = OrbitCamera.new()
	_orbit.name = "OrbitCamera"
	add_child(_orbit)

	_hud = GameHud.new()
	_hud.name = "GameHud"
	add_child(_hud)

	_ai_match = AiMatch.new()
	_ai_match.name = "AiMatch"
	add_child(_ai_match)
	_ai_match.setup(session, _settings)

	_controller = GameController.new()
	_controller.name = "GameController"
	add_child(_controller)
	_controller.setup(session, _board_view, _hud, _orbit, _ai_match)

	_ai_overlay = AiOverlay.new()
	add_child(_ai_overlay)
	_ai_overlay.settings_pressed.connect(_on_open_settings)
	_ai_match.thinking_changed.connect(_ai_overlay.set_thinking)
	_ai_match.status_message.connect(_ai_overlay.set_status)
	_refresh_ai_badge()
	_refresh_team_badge()

	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.settings_applied.connect(_on_settings_applied)

	_speech_resolver = SpeechResolver.new(_catalog)
	_speech_director = SpeechDirector.new()
	_speech_director.name = "SpeechDirector"
	add_child(_speech_director)
	_speech_director.setup(session, _board_view, _speech_resolver, _board_view.square_size)


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


func _refresh_team_badge() -> void:
	if _ai_overlay == null or _catalog == null:
		return
	var w := _catalog.team_for_side(Piece.Side.WHITE)
	var b := _catalog.team_for_side(Piece.Side.BLACK)
	var w_name := w.display_name if w != null else "?"
	var b_name := b.display_name if b != null else "?"
	# チーム表示は status 行に載せる(AI 無し時のメッセージを上書きしすぎないよう併記)。
	var base := ""
	if _settings != null and not _settings.engine_available:
		base = _settings.engine_message + " / "
	_ai_overlay.set_status("%sチーム 白:%s 黒:%s" % [base, w_name, b_name])


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
