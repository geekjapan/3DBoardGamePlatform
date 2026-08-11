extends "res://tests/case.gd"

## Issue #12: チーム編成画面。
##
## シーム(自動化できる範囲):
## - 駒種一覧とキャラクター割当
## - 編成名付き保存 / 読み込み編集
## - 割当欠けでも保存でき、対局(発話)が落ちない
## - user:// 永続化とチーム選択への出現
## - 3D プレビューの論理状態(駒種・キャラ ID)
##
## 実画面の見た目はヘッドレス外。


func test_team_store_saves_and_reloads_partial_lineup() -> void:
	var dir := "user://test_team_store_%d" % Time.get_ticks_usec()
	TeamStore.ensure_dir(dir)

	var team := TeamDef.new()
	team.id = "partial_squad"
	team.display_name = "欠けあり部隊"
	# ポーンとキングだけ。他は未割当。
	team.assign(Piece.Kind.PAWN, "hotblood")
	team.assign(Piece.Kind.KING, "tsundere")

	var err := TeamStore.save_team(team, dir)
	check_eq(err, OK, "部分割当でも保存できる")

	var loaded := TeamStore.load_team_file(dir.path_join("partial_squad.json"))
	check(loaded != null, "再読込できる")
	check_eq(loaded.id, "partial_squad", "id")
	check_eq(loaded.display_name, "欠けあり部隊", "表示名")
	check_eq(loaded.character_id_for_kind(Piece.Kind.PAWN), "hotblood", "ポーン")
	check_eq(loaded.character_id_for_kind(Piece.Kind.KING), "tsundere", "キング")
	check_eq(loaded.character_id_for_kind(Piece.Kind.QUEEN), "", "クイーン未割当")
	check_eq(loaded.character_id_for_kind(Piece.Kind.KNIGHT), "", "ナイト未割当")

	_cleanup_dir(dir)


func test_team_store_merges_into_catalog_for_team_select() -> void:
	var dir := "user://test_team_merge_%d" % Time.get_ticks_usec()
	TeamStore.ensure_dir(dir)

	var custom := TeamDef.new()
	custom.id = "my_custom"
	custom.display_name = "マイ編成"
	custom.assign(Piece.Kind.PAWN, "calm")
	check_eq(TeamStore.save_team(custom, dir), OK, "保存")

	var catalog := SpeechCatalog.load_default()
	var before := catalog.team_ids().size()
	check(catalog.team_by_id("my_custom") == null, "同梱には無い")
	var n := TeamStore.load_into_catalog(catalog, dir)
	check_eq(n, 1, "1 件取り込み")
	check(catalog.team_by_id("my_custom") != null, "カタログに出る")
	check(catalog.team_ids().size() >= before + 1, "チーム数が増える")
	check_eq(
		catalog.team_by_id("my_custom").character_id_for_kind(Piece.Kind.PAWN),
		"calm",
		"割当保持"
	)

	# チーム選択パネルの選択肢に載る
	var settings := TeamSettings.new()
	settings.config_path = "user://test_team_editor_settings_%d.cfg" % Time.get_ticks_usec()
	var panel := TeamSelectPanel.new()
	panel.open_with(catalog, settings)
	var found := false
	for i in range(panel._white_option.item_count):
		if str(panel._white_option.get_item_metadata(i)) == "my_custom":
			found = true
			break
	check(found, "対局開始時のチーム選択に現れる")
	panel.free()

	if FileAccess.file_exists(settings.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))
	_cleanup_dir(dir)


func test_team_store_survives_reload_simulating_restart() -> void:
	var dir := "user://test_team_persist_%d" % Time.get_ticks_usec()
	TeamStore.ensure_dir(dir)

	var team := TeamDef.new()
	team.id = "keep_me"
	team.display_name = "次回も残る"
	team.assign(Piece.Kind.ROOK, "hotblood")
	check_eq(TeamStore.save_team(team, dir), OK, "保存")

	# 起動し直し相当: 新しいカタログに user を載せ直す
	var catalog1 := SpeechCatalog.load_default()
	TeamStore.load_into_catalog(catalog1, dir)
	check(catalog1.team_by_id("keep_me") != null, "1 回目ロード")

	var catalog2 := SpeechCatalog.load_default()
	TeamStore.load_into_catalog(catalog2, dir)
	var again := catalog2.team_by_id("keep_me")
	check(again != null, "次回起動でも残る")
	check_eq(again.display_name, "次回も残る", "名前保持")
	check_eq(again.character_id_for_kind(Piece.Kind.ROOK), "hotblood", "割当保持")

	_cleanup_dir(dir)


func test_partial_team_match_still_works() -> void:
	## 割当欠けチームでも対局(着手・発話解決)が成立する。
	var catalog := SpeechCatalog.load_default()
	var partial := TeamDef.new()
	partial.id = "sparse"
	partial.display_name = "薄い編成"
	partial.assign(Piece.Kind.KNIGHT, "hotblood")
	# ポーンは未割当
	catalog.teams[partial.id] = partial
	catalog.set_side_teams("sparse", "sparse")

	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.WHITE, Piece.Kind.KNIGHT),
		"hotblood",
		"割当あり"
	)
	check_eq(
		catalog.character_id_for_side_kind(Piece.Side.WHITE, Piece.Kind.PAWN),
		"",
		"未割当は空"
	)

	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 1

	# 白ナイト着手 → 発話あり
	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/2N5/8/4K3 w - - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(3, 4)))
	check(ev != null, "着手できる")
	var plan: Array = resolver.plan(ev)
	check(plan.size() >= 1, "割当あり駒は発話できる")

	# 白ポーン着手 → 未割当なので発話は空でもクラッシュしない
	var session2 := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/8/P7/4K3 w - - 0 1")
	)
	var ev2 := session2.apply_move(Move.new(Vector2i(0, 1), Vector2i(0, 2)))
	check(ev2 != null, "未割当ポーンでも着手できる")
	var plan2: Array = resolver.plan(ev2)
	check_eq(plan2.size(), 0, "未割当は黙る(対局は成立)")


func test_team_editor_lists_kinds_and_assigns_characters() -> void:
	var catalog := SpeechCatalog.load_default()
	var dir := "user://test_team_editor_ui_%d" % Time.get_ticks_usec()
	TeamStore.ensure_dir(dir)

	var panel := TeamEditorPanel.new()
	panel.open_with(catalog, dir)
	check(panel.visible, "編成画面が開く")

	# 駒種一覧(6 種)が表示用 Option を持つ
	for kind in [
		Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
		Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
	]:
		check(panel._kind_options.has(kind), "駒種 %s の行がある" % SpeechCatalog.kind_name(kind))
		var opt: OptionButton = panel._kind_options[kind]
		check(opt.item_count >= 2, "未割当 + キャラクター選択肢")

	panel._name_edit.text = "テスト編成A"
	panel._on_name_changed(panel._name_edit.text)
	panel.set_assignment_for_test(Piece.Kind.PAWN, "hotblood")
	panel.set_assignment_for_test(Piece.Kind.QUEEN, "tsundere")
	# ナイトは未割当のまま

	check_eq(panel.draft().character_id_for_kind(Piece.Kind.PAWN), "hotblood", "ポーン割当")
	check_eq(panel.draft().character_id_for_kind(Piece.Kind.QUEEN), "tsundere", "クイーン割当")
	check_eq(panel.draft().character_id_for_kind(Piece.Kind.KNIGHT), "", "ナイト未割当可")

	panel._select_kind(Piece.Kind.PAWN)
	check_eq(panel.selected_kind(), Piece.Kind.PAWN, "選択駒種")
	check_eq(panel._preview.current_character_id(), "hotblood", "3D プレビューが選択キャラ")
	check_eq(panel._preview.current_kind(), Piece.Kind.PAWN, "3D プレビューが駒種")

	panel._select_kind(Piece.Kind.QUEEN)
	check_eq(panel._preview.current_character_id(), "tsundere", "クイーン選択でプレビュー更新")
	check_eq(panel._preview.current_kind(), Piece.Kind.QUEEN, "クイーン形状")

	var box: Dictionary = {"team": null}
	panel.saved.connect(func(t: TeamDef) -> void: box["team"] = t)
	panel._on_save()
	var saved: TeamDef = box["team"] as TeamDef
	check(saved != null, "saved が飛ぶ")
	check_eq(saved.display_name, "テスト編成A", "名前付き保存")
	check(catalog.team_by_id(saved.id) != null, "カタログに載る")
	check(FileAccess.file_exists(dir.path_join("%s.json" % saved.id)), "ディスクに残る")

	# 既存編成の読み込み編集
	var panel2 := TeamEditorPanel.new()
	panel2.open_with(catalog, dir, saved.id)
	check_eq(panel2.draft().id, saved.id, "既存を読み込む")
	check_eq(panel2.draft().display_name, "テスト編成A", "名前復元")
	check_eq(panel2.draft().character_id_for_kind(Piece.Kind.PAWN), "hotblood", "割当復元")
	panel2.set_assignment_for_test(Piece.Kind.BISHOP, "calm")
	panel2._on_save()
	var reloaded := TeamStore.load_team_file(dir.path_join("%s.json" % saved.id))
	check_eq(reloaded.character_id_for_kind(Piece.Kind.BISHOP), "calm", "編集して再保存")

	panel.free()
	panel2.free()
	_cleanup_dir(dir)


func test_team_editor_rejects_empty_name_but_allows_sparse() -> void:
	var catalog := SpeechCatalog.load_default()
	var dir := "user://test_team_editor_name_%d" % Time.get_ticks_usec()
	var panel := TeamEditorPanel.new()
	panel.open_with(catalog, dir)
	panel._name_edit.text = ""
	panel._on_save()
	check(panel.draft().id == "" or not FileAccess.file_exists(dir.path_join("%s.json" % panel.draft().id)),
		"空名ではファイルを作らない")
	# 名前だけ入れて割当ゼロでも保存可
	panel._name_edit.text = "空割当OK"
	panel._on_name_changed("空割当OK")
	var box: Dictionary = {"ok": false}
	panel.saved.connect(func(_t: TeamDef) -> void: box["ok"] = true)
	panel._on_save()
	check(box["ok"], "割当ゼロでも保存できる")
	panel.free()
	_cleanup_dir(dir)


func test_make_team_id_unique() -> void:
	var existing := PackedStringArray(["team", "team_2"])
	check_eq(TeamStore.make_team_id("Team", existing), "team_3", "連番で衝突回避")
	check(TeamStore.make_team_id("熱血カスタム", PackedStringArray()).length() > 0, "日本語名でも id 生成")


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
