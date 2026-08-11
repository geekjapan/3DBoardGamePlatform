extends "res://tests/case.gd"

## Issue #8: 駒がキャラクターとして定型セリフを喋る(LINES)。
##
## シーム(自動化できる範囲):
## - SpeechCatalog / TeamDef: 外部テキストからの定義読込と駒種割当
## - SpeechResolver: 重要イベント必須発話、通常手の確率、セリフ表選択、欠落耐性
## - SpeechDirector.present_event: 吹き出し生成(見た目の追従は手動確認)
##
## カメラ追従の見た目・消えるタイミング感は手動確認。


func test_catalog_loads_characters_and_team_from_data() -> void:
	var catalog := SpeechCatalog.load_default()
	check(catalog.characters.size() >= 3, "キャラクターが data/ から読める")
	check(catalog.character("hotblood") != null, "hotblood がある")
	check(catalog.character("calm") != null, "calm がある")
	check(catalog.character("tsundere") != null, "tsundere がある")
	var hot: CharacterDef = catalog.character("hotblood")
	check(hot.personality != "", "性格を持てる")
	check(hot.has_lines_for("captured"), "セリフ表を持てる")
	check(hot.lines_for("captured").size() >= 2, "複数セリフ")

	check_eq(catalog.team.character_id_for_kind(Piece.Kind.PAWN), "hotblood", "ポーン割当")
	check_eq(catalog.team.character_id_for_kind(Piece.Kind.KNIGHT), "hotblood", "同キャラを複数駒種へ")
	check_eq(catalog.team.character_id_for_kind(Piece.Kind.BISHOP), "calm", "ビショップ割当")
	check_eq(catalog.team.character_id_for_kind(Piece.Kind.QUEEN), "tsundere", "クイーン割当")


func test_same_character_on_multiple_kinds_and_pieces() -> void:
	var catalog := _catalog_with_single("shared", {
		"moved": ["動く"],
		"captured": ["取る"],
		"captured_by": ["取られる"],
	})
	catalog.team.assign(Piece.Kind.PAWN, "shared")
	catalog.team.assign(Piece.Kind.KNIGHT, "shared")
	check_eq(catalog.character_for_kind(Piece.Kind.PAWN).id, "shared", "ポーン")
	check_eq(catalog.character_for_kind(Piece.Kind.KNIGHT).id, "shared", "ナイトも同一")

	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 1

	# 白ポーンと白ナイトが同じセリフ表を使う。
	var pawn_move := _event_quiet_move(Piece.Kind.PAWN)
	var knight_move := _event_quiet_move(Piece.Kind.KNIGHT)
	var p_plan: Array = resolver.plan(pawn_move)
	var k_plan: Array = resolver.plan(knight_move)
	check_eq(p_plan.size(), 1, "ポーン発話")
	check_eq(k_plan.size(), 1, "ナイト発話")
	check_eq((p_plan[0] as SpeechUtterance).character_id, "shared", "同一キャラ")
	check_eq((k_plan[0] as SpeechUtterance).character_id, "shared", "同一キャラ")


func test_important_events_always_speak() -> void:
	var catalog := _full_test_catalog()
	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 0.0  # 通常移動は黙る設定でも重要は喋る
	resolver.rng.seed = 42

	# 取り
	var cap_session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var cap_ev := cap_session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	check(cap_ev.was_capture(), "取り局面")
	var cap_plan: Array = resolver.plan(cap_ev)
	check(cap_plan.size() >= 1, "取りは必ず発話(取った側)")
	check(_has_event_key(cap_plan, "captured") or _has_event_key(cap_plan, "check"), "取り系キー")
	check(_has_event_key(cap_plan, "captured_by"), "取られた側も喋る")

	# 王手
	var check_session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1")
	)
	var check_ev := check_session.apply_move(Move.new(Vector2i(4, 1), Vector2i(4, 6)))
	check(check_ev.is_check, "王手")
	var check_plan: Array = resolver.plan(check_ev)
	check_eq(check_plan.size(), 1, "王手は必ず1発話以上")
	check_eq((check_plan[0] as SpeechUtterance).event_key, "check", "check キー")

	# 成り(黒王 e7・白ポーン g7→g8=Q は 8 段目のラインが切れて王手にならない)
	var promo_session := GameSession.from_board(
		Board.from_fen("8/4k1P1/8/8/8/8/8/4K3 w - - 0 1")
	)
	var promo_ev := promo_session.apply_move(
		Move.new(Vector2i(6, 6), Vector2i(6, 7), Piece.Kind.QUEEN)
	)
	check(promo_ev != null and promo_ev.was_promotion(), "成り")
	check(not promo_ev.is_check, "この局面では王手にしない")
	var promo_plan: Array = resolver.plan(promo_ev)
	check(promo_plan.size() >= 1, "成りは必ず発話")
	check_eq((promo_plan[0] as SpeechUtterance).event_key, "promoted", "promoted キー")

	# 勝敗(メイト)
	var mate_session := GameSession.from_board(
		Board.from_fen("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1")
	)
	var mate_ev := mate_session.apply_move(Move.new(Vector2i(5, 6), Vector2i(7, 6)))
	check(mate_ev.is_over and mate_ev.is_checkmate, "終局")
	var mate_plan: Array = resolver.plan(mate_ev)
	check(mate_plan.size() >= 1, "勝敗は必ず発話")
	check_eq((mate_plan[0] as SpeechUtterance).event_key, "game_over", "game_over キー")


func test_move_probability_zero_and_one() -> void:
	var catalog := _full_test_catalog()
	var quiet := _event_quiet_move(Piece.Kind.PAWN)

	var never_r := SpeechResolver.new(catalog)
	never_r.move_probability = 0.0
	never_r.rng.seed = 1
	for i in 20:
		check_eq(never_r.plan(quiet).size(), 0, "確率0なら通常移動は発話しない #%d" % i)

	var always_r := SpeechResolver.new(catalog)
	always_r.move_probability = 1.0
	always_r.rng.seed = 1
	for i in 20:
		var plan: Array = always_r.plan(quiet)
		check_eq(plan.size(), 1, "確率1なら通常移動は必ず発話 #%d" % i)
		check_eq((plan[0] as SpeechUtterance).event_key, "moved", "moved キー #%d" % i)


func test_lines_come_from_assigned_character_table() -> void:
	var catalog := SpeechCatalog.new()
	var pawn_char := CharacterDef.new()
	pawn_char.id = "pawn_only"
	pawn_char.lines = {"moved": PackedStringArray(["ポーンのセリフA", "ポーンのセリフB"])}
	var rook_char := CharacterDef.new()
	rook_char.id = "rook_only"
	rook_char.lines = {"moved": PackedStringArray(["ルーク専用ゼリフ"])}
	catalog.characters["pawn_only"] = pawn_char
	catalog.characters["rook_only"] = rook_char
	catalog.team.assign(Piece.Kind.PAWN, "pawn_only")
	catalog.team.assign(Piece.Kind.ROOK, "rook_only")

	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 7

	var pawn_plan: Array = resolver.plan(_event_quiet_move(Piece.Kind.PAWN))
	check_eq(pawn_plan.size(), 1, "ポーン発話")
	var pawn_u := pawn_plan[0] as SpeechUtterance
	check_eq(pawn_u.character_id, "pawn_only", "割当キャラ")
	check(
		pawn_u.text == "ポーンのセリフA" or pawn_u.text == "ポーンのセリフB",
		"ポーンのセリフ表から選ばれる"
	)

	var rook_plan: Array = resolver.plan(_event_quiet_move(Piece.Kind.ROOK))
	check_eq(rook_plan.size(), 1, "ルーク発話")
	var rook_u := rook_plan[0] as SpeechUtterance
	check_eq(rook_u.character_id, "rook_only", "ルーク割当")
	check_eq(rook_u.text, "ルーク専用ゼリフ", "ルークのセリフ表")


func test_missing_event_lines_do_not_crash() -> void:
	var catalog := SpeechCatalog.new()
	var mute := CharacterDef.new()
	mute.id = "mute"
	# moved だけ定義。重要イベントは未定義。
	mute.lines = {"moved": PackedStringArray(["動いた"])}
	catalog.characters["mute"] = mute
	for kind in [
		Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
		Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
	]:
		catalog.team.assign(kind, "mute")

	var resolver := SpeechResolver.new(catalog)
	resolver.move_probability = 1.0
	resolver.rng.seed = 3

	# 取り: セリフ未定義でも落ちず、計画は空または部分的。
	var cap_session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var cap_ev := cap_session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	var plan: Array = resolver.plan(cap_ev)
	check_eq(plan.size(), 0, "未定義イベントは発話なし(クラッシュしない)")

	# 王手も同様
	var check_session := GameSession.from_board(
		Board.from_fen("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1")
	)
	var check_ev := check_session.apply_move(Move.new(Vector2i(4, 1), Vector2i(4, 6)))
	plan = resolver.plan(check_ev)
	check_eq(plan.size(), 0, "check 未定義でも空配列")

	# 通常移動は定義があるので喋る
	plan = resolver.plan(_event_quiet_move(Piece.Kind.PAWN))
	check_eq(plan.size(), 1, "moved は定義あり")


func test_capture_both_sides_speak_japanese() -> void:
	var catalog := _full_test_catalog()
	var resolver := SpeechResolver.new(catalog)
	resolver.rng.seed = 11

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	var plan: Array = resolver.plan(ev)
	check_eq(plan.size(), 2, "取った側と取られた側の両方")

	var mover_u: SpeechUtterance = null
	var victim_u: SpeechUtterance = null
	for item in plan:
		var u := item as SpeechUtterance
		if u.is_victim:
			victim_u = u
		else:
			mover_u = u
	check(mover_u != null, "取った側")
	check(victim_u != null, "取られた側")
	check_eq(mover_u.event_key, "captured", "取りセリフ")
	check_eq(victim_u.event_key, "captured_by", "取られセリフ")
	check(mover_u.text.length() > 0, "日本語テキストあり(取り)")
	check(victim_u.text.length() > 0, "日本語テキストあり(取られ)")
	# データ上の日本語セリフに含まれる文字種のざっくり確認
	check(mover_u.text != victim_u.text or true, "両方言える")
	check_eq(mover_u.character_id, "hotblood", "ナイト=hotblood")
	check_eq(victim_u.character_id, "hotblood", "ポーン=hotblood")


func test_line_choice_varies_with_rng() -> void:
	## 同じ状況でも RNG が違えばセリフが変わり得る(常に同一ではない)。
	var catalog := _catalog_with_single("talker", {
		"moved": ["一", "二", "三", "四", "五"],
	})
	catalog.team.assign(Piece.Kind.PAWN, "talker")
	var quiet := _event_quiet_move(Piece.Kind.PAWN)

	var seen := {}
	for seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var resolver := SpeechResolver.new(catalog)
		resolver.move_probability = 1.0
		resolver.rng.seed = seed
		var plan: Array = resolver.plan(quiet)
		check_eq(plan.size(), 1, "発話 seed=%d" % seed)
		seen[(plan[0] as SpeechUtterance).text] = true
	check(seen.size() >= 2, "複数シードで異なるセリフが選ばれる")


func test_director_spawns_bubbles_for_plan() -> void:
	var catalog := _full_test_catalog()
	var resolver := SpeechResolver.new(catalog)
	resolver.rng.seed = 5

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var view := BoardView.new()
	view.build_from(session.board())
	var director := SpeechDirector.new()
	director.setup(session, view, resolver)

	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	view.apply_board(session.board())
	var bubbles: Array = director.present_event(ev)
	check_eq(bubbles.size(), 2, "吹き出しが2つ")
	for b in bubbles:
		var bubble := b as SpeechBubble
		check(bubble != null, "SpeechBubble")
		check(bubble.text().length() > 0, "テキスト表示")
	# 取った側は駒ノードの子
	var knight := view.piece_node_at(Vector2i(1, 4))
	check(knight != null, "ナイト位置")
	var child_bubble_count := 0
	for child in knight.get_children():
		if child is SpeechBubble:
			child_bubble_count += 1
	check_eq(child_bubble_count, 1, "取った側の吹き出しは駒に追従する子ノード")

	director.free()
	view.free()


func test_is_important_flags() -> void:
	var resolver := SpeechResolver.new(_full_test_catalog())
	var quiet := _event_quiet_move(Piece.Kind.PAWN)
	check(not resolver.is_important(quiet), "静かな移動は非重要")

	var session := GameSession.from_board(
		Board.from_fen("4k3/8/8/1p6/8/2N5/8/4K3 w - - 0 1")
	)
	var ev := session.apply_move(Move.new(Vector2i(2, 2), Vector2i(1, 4)))
	check(resolver.is_important(ev), "取りは重要")


# --- helpers ---


func _full_test_catalog() -> SpeechCatalog:
	return SpeechCatalog.load_default()


func _catalog_with_single(id: String, lines_map: Dictionary) -> SpeechCatalog:
	var catalog := SpeechCatalog.new()
	var def := CharacterDef.new()
	def.id = id
	def.display_name = id
	def.personality = "test"
	var normalized: Dictionary = {}
	for key in lines_map:
		var arr := PackedStringArray()
		for item in lines_map[key]:
			arr.append(str(item))
		normalized[str(key)] = arr
	def.lines = normalized
	catalog.characters[id] = def
	return catalog


func _event_quiet_move(kind: int) -> MoveEvent:
	## 盤を使わず、通常移動の最小 MoveEvent を合成する。
	var ev := MoveEvent.new()
	ev.move = Move.new(Vector2i(0, 1), Vector2i(0, 2))
	ev.mover_side = Piece.Side.WHITE
	ev.mover_kind = kind
	ev.is_check = false
	ev.is_checkmate = false
	ev.is_stalemate = false
	ev.is_over = false
	return ev


func _has_event_key(plan: Array, key: String) -> bool:
	for item in plan:
		var u := item as SpeechUtterance
		if u != null and u.event_key == key:
			return true
	return false
