extends Node3D

## 起動シーン。ルールエンジンの初期配置を 3D 盤に載せ、クリックで対局する。
## 起動時にゲームを選び、そのゲーム用の陣営チームを選んでセリフを解決する。
## 編成画面で駒種→キャラクターを編集し、user://teams に保存して次回起動でも使う。
## 発話モード(定型 / 音声 / 生成)を SpeechDirector 経由で吹き出し・読み上げに反映する。
## AI 対戦(Stockfish / UCI)と設定画面を結線する。


var _settings: AiSettings
var _speech_settings: SpeechSettings
var _team_settings: TeamSettings
var _game_settings: GameSettings
var _catalog: SpeechCatalog
var _ai_match: AiMatch
var _ai_overlay: AiOverlay
var _settings_panel: SettingsPanel
var _game_panel: GameSelectPanel
var _team_panel: TeamSelectPanel
var _team_editor: TeamEditorPanel
var _controller: GameController
var _board_view: BoardView
var _hud: GameHud
var _orbit: OrbitCamera
var _camera_settings: CameraSettings
var _speech_director: SpeechDirector
var _speech_resolver: SpeechResolver
var _llm_client: LlmSpeechClient
var _tts_speaker: TtsSpeaker
var _session: GameSession
var _pending_game: String = SpeechCatalog.GAME_CHESS
var active_game: String = ""
var _match_started: bool = false
var _game_lock_notice: Label


func _ready() -> void:
	_setup_environment()
	_setup_light()

	_settings = AiSettings.load_or_default()
	_settings.refresh_engine_status()
	# 起動時にエンジン無しなら AI はオフのまま 2 人対戦。

	_speech_settings = SpeechSettings.load_or_default()

	_catalog = SpeechCatalog.load_default()
	# ユーザーが保存した編成を取り込み、チーム選択に出す。
	TeamStore.load_into_catalog(_catalog)
	_team_settings = TeamSettings.load_or_default()
	_team_settings.apply_to_catalog(_catalog)
	_game_settings = GameSettings.load_or_default()
	_pending_game = _game_settings.game_id

	_setup_selection_panels()
	# 起動時はチーム選択より先に、必ずゲーム選択を表示する。
	_game_panel.open_with(_game_settings)


func _setup_selection_panels() -> void:
	if _game_panel != null:
		return

	_team_editor = TeamEditorPanel.new()
	add_child(_team_editor)
	_team_editor.saved.connect(_on_team_edited)
	_team_editor.closed.connect(_on_team_editor_closed)

	_team_panel = TeamSelectPanel.new()
	add_child(_team_panel)
	_team_panel.confirmed.connect(_on_teams_confirmed)
	_team_panel.edit_requested.connect(_on_open_team_editor)
	_team_panel.game_selection_requested.connect(_on_game_selection_requested)

	_game_panel = GameSelectPanel.new()
	add_child(_game_panel)
	_game_panel.confirmed.connect(_on_game_confirmed)


func _on_game_confirmed(game_id: String) -> void:
	if _match_started:
		return
	_pending_game = GameSettings.normalize_game_id(game_id)
	_game_panel.visible = false
	_team_panel.open_with(_catalog, _team_settings, _pending_game)


func _on_game_selection_requested() -> void:
	if _match_started:
		return
	# 未確定の UI 選択も in-memory で引き継ぎ、ゲームを変えても可能な限り保持する。
	_team_settings.white_team_id = _team_panel.selected_white_team_id()
	_team_settings.black_team_id = _team_panel.selected_black_team_id()
	_team_panel.visible = false
	_team_editor.visible = false
	_game_panel.open_with(_game_settings)


func _on_teams_confirmed(settings: TeamSettings) -> void:
	if _match_started:
		return
	_team_settings = settings
	_team_settings.apply_to_catalog(_catalog)
	active_game = _pending_game
	_start_match()


func _on_open_team_editor() -> void:
	_team_panel.visible = false
	var prefer := ""
	if _team_settings != null:
		prefer = _team_settings.white_team_id
	_team_editor.open_with(_catalog, TeamStore.USER_TEAMS_DIR, prefer, _pending_game)


func _on_team_edited(team: TeamDef) -> void:
	if team == null or _catalog == null:
		return
	_catalog.teams[team.id] = team
	if _team_panel != null:
		_team_panel.refresh_options()


func _on_team_editor_closed() -> void:
	if _match_started:
		return
	# 対局前ならチーム選択に戻す。
	if _team_panel != null and _team_settings != null:
		_team_panel.open_with(_catalog, _team_settings, _pending_game)


func _start_match() -> bool:
	if _match_started:
		return false
	active_game = GameSettings.normalize_game_id(active_game)
	_session = _create_session_for_game(active_game)
	if _session == null:
		return false
	_match_started = true
	_game_panel.visible = false
	_team_panel.visible = false
	_team_editor.visible = false
	_show_game_lock_notice()

	_board_view = BoardView.new()
	# チームのキャラクターにモデルがあれば駒として立てる。無ければ仮の見た目。
	_board_view.visual_factory = _character_visual
	add_child(_board_view)
	_board_view.build_from(_session.board())

	_orbit = OrbitCamera.new()
	_orbit.name = "OrbitCamera"
	add_child(_orbit)
	# 保存された視点があれば復元する。無ければ OrbitCamera の既定構図のまま。
	_camera_settings = CameraSettings.load_or_default()
	_camera_settings.apply_to(_orbit)

	_hud = GameHud.new()
	_hud.name = "GameHud"
	add_child(_hud)

	# T27 の将棋は human-vs-human。既存 UCI は chess のときだけ非回帰で結線する。
	if active_game == SpeechCatalog.GAME_CHESS:
		_ai_match = AiMatch.new()
		_ai_match.name = "AiMatch"
		add_child(_ai_match)
		_ai_match.setup(_session, _settings)
	else:
		_ai_match = null

	_controller = GameController.new()
	_controller.name = "GameController"
	add_child(_controller)
	_controller.setup(_session, _board_view, _hud, _orbit, _ai_match)

	_ai_overlay = AiOverlay.new()
	add_child(_ai_overlay)
	_ai_overlay.settings_pressed.connect(_on_open_settings)
	if _ai_match != null:
		_ai_match.thinking_changed.connect(_ai_overlay.set_thinking)
		_ai_match.status_message.connect(_ai_overlay.set_status)
	_refresh_ai_badge()
	_refresh_team_badge()

	_settings_panel = SettingsPanel.new()
	add_child(_settings_panel)
	_settings_panel.settings_applied.connect(_on_settings_applied)
	_settings_panel.speech_settings_applied.connect(_on_speech_settings_applied)
	_settings_panel.view_save_requested.connect(_on_save_view)
	_settings_panel.view_reset_requested.connect(_on_reset_view)

	_speech_resolver = SpeechResolver.new(_catalog)
	_speech_settings.apply_to_resolver(_speech_resolver)
	_llm_client = LlmSpeechClient.new()
	_llm_client.timeout_ms = _speech_settings.llm_timeout_ms
	_tts_speaker = TtsSpeaker.new()
	_speech_director = SpeechDirector.new()
	_speech_director.name = "SpeechDirector"
	add_child(_speech_director)
	_speech_director.setup(
		_session,
		_board_view,
		_speech_resolver,
		_board_view.square_size,
		_speech_settings,
		_llm_client,
		_tts_speaker
	)
	return true


func _create_session_for_game(game_id: String) -> GameSession:
	if game_id == SpeechCatalog.GAME_SHOGI:
		return GameSession.from_board(ShogiBoard.start())
	return GameSession.start()


func current_session() -> GameSession:
	return _session


func match_started() -> bool:
	return _match_started


func game_lock_message() -> String:
	return _game_lock_notice.text if _game_lock_notice != null else ""


func _show_game_lock_notice() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_game_lock_notice = Label.new()
	_game_lock_notice.text = "対局中はゲームを変更できません。次回起動時に選択してください"
	_game_lock_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_game_lock_notice.offset_left = -310
	_game_lock_notice.offset_right = 310
	_game_lock_notice.offset_top = 16
	_game_lock_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_lock_notice.add_theme_font_size_override("font_size", 16)
	layer.add_child(_game_lock_notice)


func _on_open_settings() -> void:
	_settings_panel.open_with(_settings, _speech_settings)


func _character_visual(side: int, kind: int) -> Node3D:
	## チーム割当のキャラクターに 3D モデルがあれば使う。
	## 指定なし・読み込み失敗はここで null を返し、BoardView が仮の見た目に落とす。
	if _catalog == null:
		return null
	var character := _catalog.character_for_kind(kind, side)
	if character == null or character.model_path == "":
		return null
	return CharacterModel.create(character.model_path)


func _process(_delta: float) -> void:
	# ダイアログの開閉は複数箇所で起きる(自分で閉じるパネルもある)ため、
	# 開閉ごとに結線せず毎フレーム見る。真偽値 3 つの比較で十分に軽い。
	var modal := (_settings_panel != null and _settings_panel.visible) \
		or (_game_panel != null and _game_panel.visible) \
		or (_team_panel != null and _team_panel.visible) \
		or (_team_editor != null and _team_editor.visible) \
		or (_controller != null and _controller.has_pending_promotion())
	if _orbit != null:
		_orbit.input_enabled = not modal
	if _controller != null:
		_controller.input_enabled = not modal


func _on_save_view() -> void:
	if _camera_settings == null:
		_camera_settings = CameraSettings.new()
	_camera_settings.capture_from(_orbit)
	_camera_settings.save_to_disk()


func _on_reset_view() -> void:
	if _camera_settings != null:
		_camera_settings.clear_saved_view()
	# OrbitCamera の既定構図へ戻す。
	var fresh := OrbitCamera.new()
	_orbit.set_orbit(fresh.yaw_degrees, fresh.pitch_degrees)
	_orbit.reset_pan()
	_orbit.set_distance(fresh.distance)
	fresh.free()


func _on_settings_applied(settings: AiSettings) -> void:
	_settings = settings
	if _ai_match != null:
		_ai_match.rebind_settings(_settings)
	_refresh_ai_badge()


func _on_speech_settings_applied(settings: SpeechSettings) -> void:
	_speech_settings = settings
	if _speech_director != null:
		_speech_director.apply_speech_settings(_speech_settings)
	elif _speech_resolver != null:
		_speech_settings.apply_to_resolver(_speech_resolver)


func _refresh_ai_badge() -> void:
	if _ai_overlay == null or _settings == null:
		return
	if active_game == SpeechCatalog.GAME_SHOGI:
		_ai_overlay.set_ai_mode(false, "", false)
		_ai_overlay.set_status("将棋は人間対人間で対局します")
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
	var white_label := "白"
	var black_label := "黒"
	if active_game == SpeechCatalog.GAME_SHOGI:
		base = "将棋は人間対人間 / "
		white_label = "先手"
		black_label = "後手"
	elif _settings != null and not _settings.engine_available:
		base = _settings.engine_message + " / "
	_ai_overlay.set_status("%sチーム %s:%s %s:%s" % [
		base, white_label, w_name, black_label, b_name,
	])


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
