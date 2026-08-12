extends "res://tests/case.gd"

const MainScript := preload("res://main.gd")


func test_game_settings_persist_and_invalid_values_fall_back_to_chess() -> void:
	var path := "user://test_game_settings_%d.cfg" % Time.get_ticks_usec()
	var settings := GameSettings.new()
	settings.config_path = path
	settings.game_id = SpeechCatalog.GAME_SHOGI
	check_eq(settings.save_to_disk(), OK, "将棋を専用設定へ保存")
	check_eq(GameSettings.load_or_default(path).game_id, SpeechCatalog.GAME_SHOGI, "保存値を復元")

	var cfg := ConfigFile.new()
	check_eq(cfg.load(path), OK, "設定を再読込")
	cfg.set_value(GameSettings.SECTION, GameSettings.KEY_GAME_ID, "go")
	check_eq(cfg.save(path), OK, "不正な旧値を作る")
	check_eq(GameSettings.load_or_default(path).game_id, SpeechCatalog.GAME_CHESS, "不正値は chess")
	check_eq(GameSettings.load_or_default(path + ".missing").game_id, SpeechCatalog.GAME_CHESS, "欠損は chess")
	check(GameSettings.DEFAULT_CONFIG_PATH != TeamSettings.CONFIG_PATH, "TeamSettings と別ファイル")
	check(GameSettings.DEFAULT_CONFIG_PATH != AiSettings.CONFIG_PATH, "AI 設定と別ファイル")
	_cleanup_file(path)


func test_game_select_restores_selection_and_saves_only_on_confirm() -> void:
	var path := "user://test_game_select_%d.cfg" % Time.get_ticks_usec()
	var settings := GameSettings.new()
	settings.config_path = path
	settings.game_id = SpeechCatalog.GAME_SHOGI
	var panel := GameSelectPanel.new()
	panel.open_with(settings)
	check(panel.visible, "起動時に表示")
	check_eq(panel.selected_game_id(), SpeechCatalog.GAME_SHOGI, "保存値を初期反映")
	check(not FileAccess.file_exists(path), "表示だけでは保存しない")

	panel.select_game_for_test(SpeechCatalog.GAME_CHESS)
	var got := {"game_id": ""}
	panel.confirmed.connect(func(game_id: String) -> void: got["game_id"] = game_id)
	panel._on_confirm()
	check_eq(got["game_id"], SpeechCatalog.GAME_CHESS, "confirmed(game_id)")
	check(FileAccess.file_exists(path), "ユーザー確定時に保存")
	check_eq(GameSettings.load_or_default(path).game_id, SpeechCatalog.GAME_CHESS, "確定値を復元")
	check(not panel.visible, "確定で閉じる")
	panel.free()
	_cleanup_file(path)


func test_team_panel_filters_lineup_and_editor_receives_same_game() -> void:
	var catalog := SpeechCatalog.load_default()
	var mixed := TeamDef.new()
	mixed.id = "mixed"
	mixed.display_name = "混成"
	mixed.assign(Piece.Kind.QUEEN, "tsundere")
	mixed.assign(Piece.Kind.SHOGI_GOLD, "hotblood")
	catalog.teams[mixed.id] = mixed
	var settings := TeamSettings.new()
	settings.white_team_id = mixed.id
	settings.black_team_id = mixed.id

	var panel := TeamSelectPanel.new()
	panel.open_with(catalog, settings, SpeechCatalog.GAME_CHESS)
	var chess_lineup := panel._lineup_text(mixed.id)
	check(chess_lineup.contains("queen="), "chess Kind を表示")
	check(not chess_lineup.contains("shogi_gold="), "shogi Kind を隠す")
	panel.open_with(catalog, settings, SpeechCatalog.GAME_SHOGI)
	var shogi_lineup := panel._lineup_text(mixed.id)
	check(shogi_lineup.contains("shogi_gold="), "shogi Kind を表示")
	check(not shogi_lineup.contains("queen="), "chess Kind を隠す")
	check_eq(panel.game_id(), SpeechCatalog.GAME_SHOGI, "TeamSelect が game_id を保持")

	var editor := TeamEditorPanel.new()
	editor.open_with(catalog, "user://test_unused", mixed.id, panel.game_id())
	check_eq(editor.game_id(), SpeechCatalog.GAME_SHOGI, "TeamEditor へ同じ game_id")
	check(editor._kind_rows[Piece.Kind.SHOGI_GOLD].visible, "将棋行を表示")
	check(not editor._kind_rows[Piece.Kind.QUEEN].visible, "チェス行を非表示")
	panel.free()
	editor.free()


func test_team_store_and_filter_preserve_all_explicit_assignments() -> void:
	var dir := "user://test_mixed_team_%d" % Time.get_ticks_usec()
	TeamStore.ensure_dir(dir)
	var mixed := TeamDef.new()
	mixed.id = "mixed_sparse"
	mixed.display_name = "疎な混成"
	mixed.assign(Piece.Kind.KING, "tsundere")
	mixed.assign(Piece.Kind.SHOGI_PAWN, "hotblood")
	mixed.assign(Piece.Kind.SHOGI_DRAGON, "calm")
	var cloned := TeamStore.clone_team(mixed)
	check_eq(cloned.assignments.size(), 3, "clone は全明示 assignment")
	check_eq(TeamStore.save_team(cloned, dir), OK, "mixed Team を保存")
	var loaded := TeamStore.load_team_file(dir.path_join("mixed_sparse.json"))
	check_eq(loaded.assignments.size(), 3, "load は非表示側も保持")
	check_eq(loaded.assignments[Piece.Kind.KING], "tsundere", "chess assignment")
	check_eq(loaded.assignments[Piece.Kind.SHOGI_PAWN], "hotblood", "shogi assignment")
	check_eq(loaded.assignments[Piece.Kind.SHOGI_DRAGON], "calm", "成駒の明示 assignment")

	var catalog := SpeechCatalog.load_default()
	catalog.teams[loaded.id] = loaded
	var editor := TeamEditorPanel.new()
	editor.open_with(catalog, dir, loaded.id, SpeechCatalog.GAME_CHESS)
	editor.set_game_filter(SpeechCatalog.GAME_SHOGI)
	editor.set_game_filter(SpeechCatalog.GAME_CHESS)
	check_eq(editor.draft().assignments.size(), 3, "フィルター切替で刈り込まない")
	editor._on_save()
	var reloaded := TeamStore.load_team_file(dir.path_join("mixed_sparse.json"))
	check_eq(reloaded.assignments.size(), 3, "再保存でも全 assignment を保持")
	editor.free()
	_cleanup_dir(dir)


func test_main_two_stage_flow_back_switch_and_team_ids_are_preserved() -> void:
	var game_path := "user://test_main_game_%d.cfg" % Time.get_ticks_usec()
	var team_path := "user://test_main_team_%d.cfg" % Time.get_ticks_usec()
	var main: Node3D = MainScript.new()
	main._catalog = SpeechCatalog.load_default()
	main._team_settings = TeamSettings.new()
	main._team_settings.config_path = team_path
	main._game_settings = GameSettings.new()
	main._game_settings.config_path = game_path
	main._setup_selection_panels()
	main._game_panel.open_with(main._game_settings)
	check(main._game_panel.visible and not main._team_panel.visible, "最初は GameSelect だけ")

	main._game_panel.select_game_for_test(SpeechCatalog.GAME_SHOGI)
	main._game_panel._on_confirm()
	check(main._team_panel.visible and not main._game_panel.visible, "game 確定後だけ TeamSelect")
	check_eq(main._team_panel.game_id(), SpeechCatalog.GAME_SHOGI, "将棋で TeamSelect")
	_select_team(main._team_panel._white_option, "hotbloods")
	_select_team(main._team_panel._black_option, "calm_line")
	main._team_panel._on_game_selection_requested()
	check(main._game_panel.visible and not main._team_panel.visible, "ゲーム選択へ戻る")
	main._game_panel.select_game_for_test(SpeechCatalog.GAME_CHESS)
	main._game_panel._on_confirm()
	check_eq(main._team_panel.game_id(), SpeechCatalog.GAME_CHESS, "別ゲームへ進む")
	check_eq(main._team_panel.selected_white_team_id(), "hotbloods", "先手 Team ID 保持")
	check_eq(main._team_panel.selected_black_team_id(), "calm_line", "後手 Team ID 保持")
	main._on_open_team_editor()
	check_eq(main._team_editor.game_id(), SpeechCatalog.GAME_CHESS, "編集も同じ game_id")
	main.free()
	_cleanup_file(game_path)
	_cleanup_file(team_path)


func test_main_chess_manual_start_is_8x8_fixed_and_rejects_double_start() -> void:
	var main := _prepared_main(SpeechCatalog.GAME_CHESS)
	check(main._start_match(), "chess start 成功")
	var session: GameSession = main.current_session()
	var board := session.board()
	check(board is Board, "chess Board")
	check_eq(Vector2i(board.width, board.height), Vector2i(8, 8), "8x8")
	for y in range(board.height):
		for x in range(board.width):
			var piece: Piece = board.piece_at(Vector2i(x, y))
			if piece != null:
				check(piece.kind >= Piece.Kind.PAWN and piece.kind <= Piece.Kind.KING, "Piece.Kind 0〜5")
	check(main._ai_match != null, "既存 chess UCI 結線を保持")
	_assert_shared_session(main, session)
	var board_view: BoardView = main._board_view
	check(not main._start_match(), "二重 start 拒否")
	check(main.current_session() == session and main._board_view == board_view, "既存対局を再構築しない")
	check(main.game_lock_message().contains("対局中はゲームを変更できません"), "変更不可を明示")
	main._on_game_confirmed(SpeechCatalog.GAME_SHOGI)
	check_eq(main.active_game, SpeechCatalog.GAME_CHESS, "開始後の game 変更を拒否")
	main.free()


func test_main_shogi_start_is_9x9_with_hands_and_usi_fallback() -> void:
	var main := _prepared_main(SpeechCatalog.GAME_SHOGI)
	check(main._start_match(), "shogi start 成功")
	var session: GameSession = main.current_session()
	var board := session.board()
	check(board is ShogiBoard, "ShogiBoard initial")
	check_eq(Vector2i(board.width, board.height), Vector2i(9, 9), "9x9")
	check(board.hands.has(Piece.Side.WHITE) and board.hands.has(Piece.Side.BLACK), "両陣営の持ち駒")
	check(main._hud.hands_visible(), "HUD 持ち駒表示")
	check(main._ai_match != null, "T28 shogi は USI AiMatch を結線")
	check_eq(main._ai_match.protocol, "usi", "将棋は USI profile 固定")
	check(not main._ai_match.is_ai_enabled(), "USI 未検出時は AI 選択不能")
	check(not main._ai_match.blocks_human_input(), "USI 未検出でも2人対戦の入力可")
	_assert_shared_session(main, session)
	var history_board := session.board()
	check(not main._start_match(), "shogi 二重 start 拒否")
	check(session.board() == history_board, "盤と履歴の所有 Session を維持")
	check(not main._game_panel.visible and not main._team_panel.visible, "開始後は選択操作を非表示")
	main.free()


func test_main_reset_view_refits_the_active_chess_and_shogi_board() -> void:
	for case in [
		{"game_id": SpeechCatalog.GAME_CHESS, "expected_distance": 7.5},
		{"game_id": SpeechCatalog.GAME_SHOGI, "expected_distance": 9.5},
	]:
		var main := _prepared_main(str(case["game_id"]))
		check(main._start_match(), "%s start 成功" % case["game_id"])
		var settings_path := "user://test_reset_view_%s_%d.cfg" % [
			case["game_id"], Time.get_ticks_usec(),
		]
		main._camera_settings = CameraSettings.new()
		main._camera_settings.config_path = settings_path
		main._orbit.set_orbit(80.0, -70.0)
		main._orbit.set_pan(Vector3(2.0, 1.0, -1.0))
		main._orbit.set_distance(3.0)

		main._on_reset_view()

		var fresh := OrbitCamera.new()
		check_eq(main._orbit.yaw_degrees, fresh.yaw_degrees, "%s reset yaw" % case["game_id"])
		check_eq(main._orbit.pitch_degrees, fresh.pitch_degrees, "%s reset pitch" % case["game_id"])
		check_eq(main._orbit.pan_offset, Vector3.ZERO, "%s reset pan" % case["game_id"])
		check_eq(
			main._orbit.distance,
			float(case["expected_distance"]),
			"%s active board 寸法を reset 後に再適用" % case["game_id"],
		)
		fresh.free()
		main.free()
		_cleanup_file(settings_path)


func _prepared_main(game_id: String) -> Node3D:
	var main: Node3D = MainScript.new()
	main._settings = AiSettings.new()
	main._speech_settings = SpeechSettings.new()
	main._catalog = SpeechCatalog.load_default()
	main._team_settings = TeamSettings.new()
	main._game_settings = GameSettings.new()
	main._pending_game = game_id
	main.active_game = game_id
	main._setup_selection_panels()
	return main


func _assert_shared_session(main: Node3D, session: GameSession) -> void:
	check(main._board_view.board() == session.board(), "BoardView は同じ盤")
	check(main._controller.session == session, "Controller は同じ Session")
	check(main._speech_director.session == session, "Speech は同じ Session")


func _select_team(option: OptionButton, team_id: String) -> void:
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == team_id:
			option.select(i)
			return
	check(false, "Team ID が選択肢にある: %s" % team_id)


func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in DirAccess.get_files_at(dir_path):
		dir.remove(name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
