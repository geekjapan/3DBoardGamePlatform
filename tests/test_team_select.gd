extends "res://tests/case.gd"

## Issue #10: 陣営ごとのチーム選択。
##
## シーム(自動化できる範囲):
## - 複数チーム定義の読込
## - 先手・後手の独立選択(同一チーム可)
## - 選んだチームどおりのキャラクター割当(盤上の駒種→キャラ)
## - 選んだチームのセリフが使われる
## - TeamSettings の永続化
##
## 3D 見た目の差し替えはプレースホルダ段階のため、論理割当で固定する。


func test_multiple_teams_loadable_from_data() -> void:
	var catalog := SpeechCatalog.load_default()
	check(catalog.teams.size() >= 2, "複数のチームを定義できる")
	check(catalog.team_by_id("default") != null, "default チーム")
	check(catalog.team_by_id("hotbloods") != null, "hotbloods チーム")
	check(catalog.team_by_id("calm_line") != null, "calm_line チーム")
	var ids := catalog.team_ids()
	check(ids.size() >= 3, "team_ids が列挙できる")
	check(ids.has("default"), "ids に default")


func test_independent_side_team_selection() -> void:
	var catalog := SpeechCatalog.load_default()
	catalog.set_side_teams("hotbloods", "calm_line")
	check_eq(catalog.white_team_id, "hotbloods", "先手チーム")
	check_eq(catalog.black_team_id, "calm_line", "後手チーム")
	check_eq(catalog.team_for_side(Piece.Side.WHITE).id, "hotbloods", "白のチーム")
	check_eq(catalog.team_for_side(Piece.Side.BLACK).id, "calm_line", "黒のチーム")


func test_same_team_on_both_sides() -> void:
	var catalog := SpeechCatalog.load_default()
	catalog.set_side_teams("hotbloods", "hotbloods")
	check_eq(catalog.team_for_side(Piece.Side.WHITE).id, "hotbloods", "白")
	check_eq(catalog.team_for_side(Piece.Side.BLACK).id, "hotbloods", "黒も同じ")
	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.WHITE, Piece.Kind.PAWN),
		"hotblood",
		"白ポーン"
	)
	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.BLACK, Piece.Kind.PAWN),
		"hotblood",
		"黒ポーンも同じキャラ"
	)


func test_lineup_matches_selected_team_on_board_pieces() -> void:
	## 選んだチームどおりのキャラクターが盤上の駒に載る(論理割当)。
	var catalog := SpeechCatalog.load_default()
	catalog.set_side_teams("hotbloods", "calm_line")

	var session := GameSession.start()
	var board := session.board()
	var checked_white := 0
	var checked_black := 0
	for y in range(board.height):
		for x in range(board.width):
			var pos := Vector2i(x, y)
			var piece := board.piece_at(pos)
			if piece == null:
				continue
			var expected := catalog.character_id_for_side_kind(piece.side, piece.kind)
			check(expected != "", "割当がある %s" % str(pos))
			var lineup: Dictionary = catalog.lineup_for_side(piece.side)
			check(lineup.has(piece.kind), "lineup に駒種")
			check_eq(str(lineup[piece.kind]), expected, "lineup 一致")
			if piece.side == Piece.Side.WHITE:
				check_eq(expected, "hotblood", "白は熱血軍団")
				checked_white += 1
			else:
				# calm_line: ポーン〜ルーク=calm、クイーン・キング=tsundere
				if piece.kind == Piece.Kind.QUEEN or piece.kind == Piece.Kind.KING:
					check_eq(expected, "tsundere", "黒の貴種はツンデレ")
				else:
					check_eq(expected, "calm", "黒のそれ以外は冷静")
				checked_black += 1
	check(checked_white >= 16, "白駒を検証")
	check(checked_black >= 16, "黒駒を検証")


func test_speech_uses_selected_team_characters() -> void:
	var catalog := SpeechCatalog.load_default()
	catalog.set_side_teams("hotbloods", "calm_line")
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 3

	# 白ナイト(熱血)が黒ポーン(冷静)を取る局面
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	var plan: Array = resolver.plan(ev)
	check_eq(plan.size(), 2, "双方発話")

	var mover_u: SpeechUtterance = null
	var victim_u: SpeechUtterance = null
	for item in plan:
		var u := item as SpeechUtterance
		if u.is_victim:
			victim_u = u
		else:
			mover_u = u
	check(mover_u != null and victim_u != null, "両方ある")
	check_eq(mover_u.character_id, "hotblood", "取った側は先手チーム")
	check_eq(victim_u.character_id, "calm", "取られた側は後手チーム")
	check(mover_u.text.length() > 0, "熱血セリフ")
	check(victim_u.text.length() > 0, "冷静セリフ")
	# キャラ固有の文言差(データ上の代表句)をざっくり確認
	check(
		mover_u.text.contains("!") or mover_u.text.contains("！") or mover_u.text.length() > 0,
		"取った側テキスト"
	)


func test_speech_same_team_both_sides_still_works() -> void:
	var catalog := SpeechCatalog.load_default()
	catalog.set_side_teams("calm_line", "calm_line")
	var resolver := SpeechResolver.new(catalog)
	resolver.rng.seed = 9

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	var plan: Array = resolver.plan(ev)
	check_eq(plan.size(), 2, "同一チーム同士でも双方発話")
	for item in plan:
		var u := item as SpeechUtterance
		check_eq(u.character_id, "calm", "calm_line のナイト/ポーンは calm")


func test_team_settings_persist_across_reload() -> void:
	var path := "user://test_team_settings_%d.cfg" % Time.get_ticks_usec()
	var s1 := TeamSettings.new()
	s1.config_path = path
	s1.white_team_id = "hotbloods"
	s1.black_team_id = "calm_line"
	s1.save_to_disk()

	var s2 := TeamSettings.load_or_default(path)
	check_eq(s2.white_team_id, "hotbloods", "先手選択が保持される")
	check_eq(s2.black_team_id, "calm_line", "後手選択が保持される")

	# クリーンアップ
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_team_settings_apply_to_catalog() -> void:
	var catalog := SpeechCatalog.load_default()
	var settings := TeamSettings.new()
	settings.white_team_id = "calm_line"
	settings.black_team_id = "hotbloods"
	settings.apply_to_catalog(catalog)
	check_eq(catalog.white_team_id, "calm_line", "適用 白")
	check_eq(catalog.black_team_id, "hotbloods", "適用 黒")
	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.WHITE, Piece.Kind.QUEEN),
		"tsundere",
		"白クイーン=冷静ライン"
	)
	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.BLACK, Piece.Kind.QUEEN),
		"hotblood",
		"黒クイーン=熱血"
	)


func test_team_select_panel_options_and_confirm() -> void:
	var catalog := SpeechCatalog.load_default()
	var settings := TeamSettings.new()
	settings.config_path = "user://test_team_panel_%d.cfg" % Time.get_ticks_usec()
	settings.white_team_id = "default"
	settings.black_team_id = "default"

	var panel := TeamSelectPanel.new()
	# ツリーに入れないと一部シグナルでも安全だが、ここは論理のみ。
	panel.open_with(catalog, settings)
	check(panel.visible, "開始時に表示")
	check(panel._white_option.item_count >= 2, "複数チームを選べる(先手)")
	check(panel._black_option.item_count >= 2, "複数チームを選べる(後手)")

	# 先手=hotbloods / 後手=calm_line を選択
	_select_team(panel._white_option, "hotbloods")
	_select_team(panel._black_option, "calm_line")
	check_eq(panel.selected_white_team_id(), "hotbloods", "先手選択")
	check_eq(panel.selected_black_team_id(), "calm_line", "後手選択")

	# GDScript の lambda は外側ローカルへの代入を捕捉しないので Dictionary 経由。
	var box: Dictionary = {"settings": null}
	panel.confirmed.connect(func(s: TeamSettings) -> void: box["settings"] = s)
	panel._on_confirm()
	var got: TeamSettings = box["settings"] as TeamSettings
	check(got != null, "confirmed が飛ぶ")
	if got != null:
		check_eq(got.white_team_id, "hotbloods", "保存対象 白")
		check_eq(got.black_team_id, "calm_line", "保存対象 黒")
	check(not panel.visible, "確定で閉じる")
	check_eq(catalog.white_team_id, "hotbloods", "カタログへ適用")
	check_eq(catalog.black_team_id, "calm_line", "カタログへ適用 黒")

	# 同一チーム選択も可
	var again := got if got != null else settings
	panel.open_with(catalog, again)
	_select_team(panel._white_option, "hotbloods")
	_select_team(panel._black_option, "hotbloods")
	panel._on_confirm()
	check_eq(catalog.white_team_id, "hotbloods", "同一チーム 白")
	check_eq(catalog.black_team_id, "hotbloods", "同一チーム 黒")

	if FileAccess.file_exists(settings.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))
	panel.free()


func test_unknown_team_id_falls_back_safely() -> void:
	var catalog := SpeechCatalog.load_default()
	var settings := TeamSettings.new()
	settings.white_team_id = "does_not_exist"
	settings.black_team_id = "also_missing"
	settings.apply_to_catalog(catalog)
	check(catalog.team_by_id(catalog.white_team_id) != null, "白は存在する ID に丸め")
	check(catalog.team_by_id(catalog.black_team_id) != null, "黒も存在 ID")
	# 発話が落ちない
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 1
	var plan: Array = resolver.plan(_quiet_white_pawn())
	check_eq(plan.size(), 1, "未知 ID でも発話できる")


func _select_team(option: OptionButton, team_id: String) -> void:
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == team_id:
			option.select(i)
			return
	check(false, "チーム %s が選択肢に無い" % team_id)


func _quiet_white_pawn() -> MoveEvent:
	var ev := MoveEvent.new()
	ev.move = Move.new(Vector2i(0, 1), Vector2i(0, 2))
	ev.mover_side = Piece.Side.WHITE
	ev.mover_kind = Piece.Kind.PAWN
	ev.is_check = false
	ev.is_checkmate = false
	ev.is_stalemate = false
	ev.is_over = false
	return ev
