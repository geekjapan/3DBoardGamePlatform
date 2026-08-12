extends "res://tests/case.gd"

## T28 / D-015: UCI と USI の設定プロファイルを独立して永続化する。


func test_legacy_uci_migration_defaults_other_profile() -> void:
	var path := _path("legacy_uci")
	var cfg := ConfigFile.new()
	cfg.set_value(AiSettings.SECTION, "enabled", true)
	cfg.set_value(AiSettings.SECTION, "strength", EngineAdapter.Strength.STRONG)
	cfg.set_value(AiSettings.SECTION, "engine_path", "/engines/stockfish")
	cfg.set_value(AiSettings.SECTION, "protocol", "uci")
	cfg.set_value(AiSettings.SECTION, "human_side", Piece.Side.BLACK)
	check_eq(cfg.save(path), OK, "旧 UCI 設定を作成")

	var settings := AiSettings.load_or_default(path)
	check(settings.uci.enabled, "旧 enabled を UCI へ移行")
	check_eq(settings.uci.strength, EngineAdapter.Strength.STRONG, "旧 strength を UCI へ移行")
	check_eq(settings.uci.engine_path, "/engines/stockfish", "旧 path を UCI へ移行")
	check_eq(settings.uci.human_side, Piece.Side.BLACK, "旧 human_side を UCI へ移行")
	check(not settings.usi.enabled, "反対側 enabled は既定 false")
	check_eq(settings.usi.strength, EngineAdapter.Strength.MEDIUM, "反対側 strength は中")
	check_eq(settings.usi.human_side, Piece.Side.WHITE, "反対側 human_side は白")
	check_eq(settings.usi.engine_path, "", "USI の既定 path は空")
	check_eq(settings.profile("uci"), settings.uci, "protocol profile alias")
	var migrated := ConfigFile.new()
	check_eq(migrated.load(path), OK, "移行後設定を再読込")
	check(migrated.has_section(AiSettings.UCI_SECTION), "loadだけで新UCIを正本化")
	check(migrated.has_section(AiSettings.USI_SECTION), "loadだけで新USIも確定")
	check(migrated.has_section(AiSettings.SECTION), "旧sectionは非破壊で保持")
	_cleanup(path)


func test_legacy_usi_migration_moves_only_to_usi() -> void:
	var path := _path("legacy_usi")
	var cfg := ConfigFile.new()
	cfg.set_value(AiSettings.SECTION, "enabled", true)
	cfg.set_value(AiSettings.SECTION, "strength", EngineAdapter.Strength.WEAK)
	cfg.set_value(AiSettings.SECTION, "engine_path", "")
	cfg.set_value(AiSettings.SECTION, "protocol", "usi")
	cfg.set_value(AiSettings.SECTION, "human_side", Piece.Side.BLACK)
	check_eq(cfg.save(path), OK, "旧 USI 設定を作成")

	var settings := AiSettings.load_or_default(path)
	check(settings.usi.enabled, "旧 enabled を USI へ移行")
	check_eq(settings.usi.strength, EngineAdapter.Strength.WEAK, "旧 strength を USI へ移行")
	check_eq(settings.usi.engine_path, "", "USI の空 path を保持")
	check_eq(settings.usi.human_side, Piece.Side.BLACK, "旧 human_side を USI へ移行")
	check(not settings.uci.enabled, "UCI は既定 false")
	check_eq(settings.uci.engine_path, _default_uci_path(), "UCI だけ空 path を探索")
	check_eq(settings.profile_for_game("shogi"), settings.usi, "将棋は USI profile")
	check_eq(settings.profile_for_game("chess"), settings.uci, "チェスは UCI profile")
	_cleanup(path)


func test_unknown_legacy_protocol_migrates_to_uci() -> void:
	var path := _path("legacy_unknown")
	var cfg := ConfigFile.new()
	cfg.set_value(AiSettings.SECTION, "protocol", "future-protocol")
	cfg.set_value(AiSettings.SECTION, "engine_path", "/engine/future")
	check_eq(cfg.save(path), OK, "不明 protocol の旧設定を作成")
	var settings := AiSettings.load_or_default(path)
	check_eq(settings.uci.engine_path, "/engine/future", "不明 protocol は UCI")
	check(not settings.usi.enabled, "USI は既定 false")
	_cleanup(path)


func test_new_profiles_roundtrip_and_runtime_status_not_persisted() -> void:
	var path := _path("roundtrip")
	var settings := AiSettings.new()
	settings.config_path = path
	settings.uci.enabled = true
	settings.uci.strength = EngineAdapter.Strength.STRONG
	settings.uci.engine_path = "/engines/chess"
	settings.uci.human_side = Piece.Side.BLACK
	settings.usi.enabled = true
	settings.usi.strength = EngineAdapter.Strength.WEAK
	settings.usi.engine_path = "/engines/shogi"
	settings.usi.human_side = Piece.Side.WHITE
	settings.usi.engine_available = true
	settings.usi.engine_message = "runtime only"
	check_eq(settings.save_to_disk(), OK, "新形式を保存")

	var loaded := AiSettings.load_or_default(path)
	check(loaded.uci.enabled and loaded.usi.enabled, "両 profile enabled を復元")
	check_eq(loaded.uci.engine_path, "/engines/chess", "UCI path 往復")
	check_eq(loaded.usi.engine_path, "/engines/shogi", "USI path 往復")
	check_eq(loaded.uci.strength, EngineAdapter.Strength.STRONG, "UCI strength 往復")
	check_eq(loaded.usi.strength, EngineAdapter.Strength.WEAK, "USI strength 往復")
	check_eq(loaded.uci.human_side, Piece.Side.BLACK, "UCI side 往復")
	check_eq(loaded.usi.human_side, Piece.Side.WHITE, "USI side 往復")
	check(not loaded.usi.engine_available, "runtime availability は保存しない")
	check_eq(loaded.usi.engine_message, "", "runtime message は保存しない")
	_cleanup(path)


func test_save_preserves_legacy_and_other_sections() -> void:
	var path := _path("preserve")
	var cfg := ConfigFile.new()
	cfg.set_value(AiSettings.SECTION, "protocol", "usi")
	cfg.set_value(AiSettings.SECTION, "engine_path", "/legacy")
	cfg.set_value("speech", "mode", 2)
	cfg.set_value("unrelated", "keep", "yes")
	check_eq(cfg.save(path), OK, "既存設定を作成")

	var settings := AiSettings.load_or_default(path)
	settings.uci.engine_path = "/new-uci"
	settings.usi.engine_path = "/new-usi"
	check_eq(settings.save_to_disk(), OK, "新セクションを追記")

	var after := ConfigFile.new()
	check_eq(after.load(path), OK, "保存結果を再読込")
	check_eq(after.get_value(AiSettings.SECTION, "protocol"), "usi", "legacy protocol を保持")
	check_eq(after.get_value(AiSettings.SECTION, "engine_path"), "/legacy", "legacy path を保持")
	check_eq(after.get_value("speech", "mode"), 2, "別セクションを保持")
	check_eq(after.get_value("unrelated", "keep"), "yes", "未知セクションを保持")
	check_eq(after.get_value(AiSettings.UCI_SECTION, "engine_path"), "/new-uci", "UCI 新セクション")
	check_eq(after.get_value(AiSettings.USI_SECTION, "engine_path"), "/new-usi", "USI 新セクション")
	_cleanup(path)


func test_new_format_ignores_legacy_and_missing_profile_defaults() -> void:
	var path := _path("new_precedence")
	var cfg := ConfigFile.new()
	cfg.set_value(AiSettings.SECTION, "enabled", true)
	cfg.set_value(AiSettings.SECTION, "engine_path", "/legacy")
	cfg.set_value(AiSettings.UCI_SECTION, "enabled", false)
	cfg.set_value(AiSettings.UCI_SECTION, "engine_path", "/new")
	check_eq(cfg.save(path), OK, "新形式と旧形式を作成")

	var settings := AiSettings.load_or_default(path)
	check(not settings.uci.enabled, "新 UCI を正本にする")
	check_eq(settings.uci.engine_path, "/new", "legacy より新 UCI を優先")
	check(not settings.usi.enabled, "欠落 USI は既定 false")
	check_eq(settings.usi.engine_path, "", "欠落 USI は空")
	_cleanup(path)


func test_usi_empty_path_is_unavailable_without_changing_enabled() -> void:
	var settings := AiSettings.new()
	settings.usi.enabled = true
	settings.usi.engine_path = ""
	settings.refresh_engine_status("usi")
	check(not settings.usi.engine_available, "空 USI は利用不可")
	check(settings.usi.engine_message != "", "空 USI はメッセージあり")
	check(settings.usi.enabled, "runtime unavailable は enabled を変更しない")
	check(not settings.can_play_ai("usi"), "利用不可なら AI をプレイできない")


func test_settings_panel_edits_only_active_game_profile() -> void:
	var path := _path("panel_profile")
	var settings := AiSettings.new()
	settings.config_path = path
	settings.uci.engine_path = "/keep-uci"
	settings.uci.enabled = true
	settings.uci.strength = EngineAdapter.Strength.STRONG
	settings.uci.human_side = Piece.Side.BLACK
	settings.usi.engine_path = ""
	settings.usi.enabled = true
	settings.usi.human_side = Piece.Side.BLACK
	var panel := SettingsPanel.new()
	panel.open_for_game(settings, "shogi", SpeechSettings.new())
	check_eq(panel.active_game(), "shogi", "panel は game 文脈を保持")
	check_eq(panel.active_profile(), settings.usi, "panel は USI profile だけを表示")
	check_eq(panel._human_side_option.get_item_text(0), "先手", "将棋の人側表示")
	check_eq(panel._human_side_option.get_item_text(1), "後手", "将棋の相手側表示")
	check_eq(panel._human_side_option.get_selected_id(), Piece.Side.BLACK, "将棋の human_side を表示")
	panel._path_edit.text = " /edited-usi "
	panel._strength_option.select(0)
	panel._human_side_option.select(0)
	panel._on_apply()
	check_eq(settings.usi.engine_path, "/edited-usi", "表示中の USI を編集")
	check_eq(settings.usi.strength, EngineAdapter.Strength.WEAK, "表示中の USI strength を編集")
	check_eq(settings.usi.human_side, Piece.Side.WHITE, "表示中の USI human_side を編集")
	check_eq(settings.uci.engine_path, "/keep-uci", "非表示 UCI path を保持")
	check_eq(settings.uci.strength, EngineAdapter.Strength.STRONG, "非表示 UCI strength を保持")
	check(settings.uci.enabled, "非表示 UCI enabled を保持")
	panel.free()
	_cleanup(path)


func _path(prefix: String) -> String:
	return "user://test_ai_settings_%s_%d.cfg" % [prefix, Time.get_ticks_usec()]


func _default_uci_path() -> String:
	for candidate in AiSettings.DEFAULT_PATH_CANDIDATES:
		if candidate != "stockfish" and FileAccess.file_exists(candidate):
			return candidate
	return "/opt/homebrew/bin/stockfish"


func _cleanup(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
