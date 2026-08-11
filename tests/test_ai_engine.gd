extends "res://tests/case.gd"

## Issue #7: Stockfish による AI 対戦。
##
## シーム:
## - EngineAdapter / UciEngine / UsiEngine / EngineFactory: プロトコル差し替え口
## - BoardFen / UciMoveParser: FEN・UCI 手の変換
## - AiSettings: 永続化とエンジン利用可否(例外にしない)
## - GameSession.apply_move: AI 着手入口
##
## エンジン実体がある環境でのみスモークを実行。無い環境ではスキップ。


func test_factory_exposes_uci_and_usi() -> void:
	var protocols := EngineFactory.supported_protocols()
	check(protocols.has("uci"), "uci がある")
	check(protocols.has("usi"), "usi がある(将棋用に並べる)")
	var uci := EngineFactory.create("uci")
	check(uci is UciEngine, "uci アダプタ")
	check_eq(uci.protocol_id(), "uci", "protocol_id")
	var usi := EngineFactory.create("usi")
	check(usi is UsiEngine, "usi アダプタ")
	check_eq(usi.protocol_id(), "usi", "usi id")


func test_missing_engine_is_unavailable_not_exception() -> void:
	var engine := UciEngine.new()
	var result := engine.probe("/this/path/definitely/does/not/exist/stockfish-xyz")
	check(
		int(result["availability"]) == EngineAdapter.Availability.MISSING
		or int(result["availability"]) == EngineAdapter.Availability.FAILED,
		"見つからないときは MISSING/FAILED"
	)
	check(str(result["message"]) != "", "メッセージがある")
	var move := engine.search_best_move_sync(
		"/this/path/definitely/does/not/exist/stockfish-xyz",
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		EngineAdapter.Strength.WEAK,
		100
	)
	check_eq(move, "", "探索も空文字で失敗(例外なし)")


func test_usi_stub_is_unavailable() -> void:
	var usi := UsiEngine.new()
	var result := usi.probe("/any/path")
	check_eq(
		int(result["availability"]),
		EngineAdapter.Availability.MISSING,
		"USI は未実装で MISSING"
	)
	check(str(result["message"]).contains("未対応") or str(result["message"]) != "", "説明あり")


func test_board_fen_roundtrip_startpos() -> void:
	var board := Board.chess_start()
	var fen := BoardFen.to_fen(board)
	check(
		fen.begins_with("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq"),
		"初期 FEN: %s" % fen
	)
	var again := Board.from_fen(fen)
	check_eq(again.side_to_move, Piece.Side.WHITE, "手番")
	check_eq(again.piece_at(Vector2i(4, 1)).kind, Piece.Kind.PAWN, "e2")


func test_board_fen_after_e2e4() -> void:
	var board := Board.chess_start()
	var e2e4 := Move.new(Vector2i(4, 1), Vector2i(4, 3))
	board = board.apply(e2e4)
	var fen := BoardFen.to_fen(board)
	check(fen.contains(" b "), "黒手番 FEN: %s" % fen)
	check(fen.contains("4P3") or fen.contains("/4P3/"), "e4 ポーンが FEN にある: %s" % fen)


func test_uci_move_parser_and_legal() -> void:
	var board := Board.chess_start()
	var move := UciMoveParser.parse("e2e4")
	check(move != null, "parse e2e4")
	check_eq(move.from, Vector2i(4, 1), "from")
	check_eq(move.to, Vector2i(4, 3), "to")
	check(UciMoveParser.is_legal_on(board, "e2e4"), "e2e4 合法")
	check(not UciMoveParser.is_legal_on(board, "e2e5"), "e2e5 非合法")
	var promo := UciMoveParser.parse("e7e8q")
	check_eq(promo.promotion, Piece.Kind.QUEEN, "昇格クイーン")


func test_settings_persist_and_disable_without_engine() -> void:
	var s := AiSettings.new()
	s.engine_path = "/no/such/stockfish-for-test"
	s.ai_enabled = true
	s.strength = EngineAdapter.Strength.STRONG
	s.protocol = "uci"
	s.refresh_engine_status()
	check(not s.engine_available, "利用不可")
	check(not s.ai_enabled, "利用不可なら AI オフに落とす")
	check(not s.can_play_ai(), "can_play_ai は false")
	check(s.engine_message != "", "メッセージ")

	# 実ファイルの user://settings.cfg は利用者の設定なので絶対に触らない。
	var path := "user://test_ai_settings_%d.cfg" % Time.get_ticks_usec()
	s.config_path = path
	s.engine_path = "/still/missing"
	s.strength = EngineAdapter.Strength.WEAK
	s.ai_enabled = false
	s.save_to_disk()
	var loaded := AiSettings.load_or_default(path)
	check_eq(loaded.engine_path, "/still/missing", "パスが保持される")
	check_eq(loaded.strength, EngineAdapter.Strength.WEAK, "強さが保持される")
	check(not loaded.ai_enabled, "オフが保持される")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_empty_saved_engine_path_falls_back_to_autodetect() -> void:
	# 空で保存された値が自動検出に勝つと、エンジンが入っていても見つからないままになる。
	var path := "user://test_ai_autodetect_%d.cfg" % Time.get_ticks_usec()
	var s := AiSettings.new()
	s.config_path = path
	s.engine_path = ""
	s.save_to_disk()
	var loaded := AiSettings.load_or_default(path)
	check(loaded.engine_path != "", "空保存なら自動検出にフォールバックする")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_strength_presets_map_to_different_skill_levels() -> void:
	var engine := UciEngine.new()
	var weak := engine.skill_level_for(EngineAdapter.Strength.WEAK)
	var mid := engine.skill_level_for(EngineAdapter.Strength.MEDIUM)
	var strong := engine.skill_level_for(EngineAdapter.Strength.STRONG)
	check(weak < mid and mid < strong, "弱 < 中 < 強 の Skill Level")
	check(engine.movetime_for(EngineAdapter.Strength.WEAK)
		<= engine.movetime_for(EngineAdapter.Strength.STRONG), "movetime も非減少")


func test_apply_move_path_for_ai_like_usage() -> void:
	## AI は apply_move 経由で指す。合法手ならイベントが返り、待ったも 1 往復できる。
	var session := GameSession.start()
	var white := UciMoveParser.parse("e2e4")
	check(session.apply_move(white) != null, "人: e2e4")
	var black := UciMoveParser.parse("e7e5")
	check(session.apply_move(black) != null, "AI 想定: e7e5")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "手番白")
	check(session.can_undo(), "1 往復後待った可")
	check(session.undo(), "待った")
	check_eq(session.side_to_move(), Piece.Side.WHITE, "待った後は白")
	check(session.board().piece_at(Vector2i(4, 3)) == null, "e4 クリア")


func test_smoke_stockfish_returns_legal_move_from_startpos() -> void:
	## エンジンがある環境でのみ走るスモーク。無ければスキップ(失敗にしない)。
	var path := _resolve_stockfish_path()
	if path.is_empty():
		print("SKIP test_smoke_stockfish_returns_legal_move_from_startpos — engine not found")
		return
	var engine := UciEngine.new()
	var probe := engine.probe(path)
	check_eq(
		int(probe["availability"]),
		EngineAdapter.Availability.AVAILABLE,
		"probe AVAILABLE: %s" % probe.get("message", "")
	)
	var fen := BoardFen.to_fen(Board.chess_start())
	var uci := engine.search_best_move_sync(path, fen, EngineAdapter.Strength.WEAK, 200)
	check(uci != "", "初期局面で手が返る: '%s'" % uci)
	check(UciMoveParser.is_legal_on(Board.chess_start(), uci), "返った手は合法: %s" % uci)
	# apply_move でも通る
	var session := GameSession.start()
	var move := UciMoveParser.parse(uci)
	check(session.apply_move(move) != null, "apply_move で受理: %s" % uci)


func test_smoke_strength_settings_change_search_params() -> void:
	## 手の質そのものの差は確率的なので、プリセットが探索パラメータを変えることを固定する。
	var engine := UciEngine.new()
	check(
		engine.skill_level_for(EngineAdapter.Strength.WEAK)
		!= engine.skill_level_for(EngineAdapter.Strength.STRONG),
		"強さで Skill Level が変わる"
	)
	var path := _resolve_stockfish_path()
	if path.is_empty():
		print("SKIP live strength search — engine not found")
		return
	# 両方とも合法手を返すことだけ確認(質の差は Skill Level 委譲)。
	var fen := BoardFen.to_fen(Board.chess_start())
	var w := engine.search_best_move_sync(path, fen, EngineAdapter.Strength.WEAK, 150)
	var s := engine.search_best_move_sync(path, fen, EngineAdapter.Strength.STRONG, 150)
	check(w != "" and UciMoveParser.is_legal_on(Board.chess_start(), w), "弱の手: %s" % w)
	check(s != "" and UciMoveParser.is_legal_on(Board.chess_start(), s), "強の手: %s" % s)


func _resolve_stockfish_path() -> String:
	var env := OS.get_environment("STOCKFISH")
	if env != "" and FileAccess.file_exists(env):
		return env
	for p in AiSettings.DEFAULT_PATH_CANDIDATES:
		if p != "stockfish" and FileAccess.file_exists(p):
			return p
	return ""


func test_settings_panel_fits_on_screen() -> void:
	# 項目を足してパネルが画面より高くなり、下のボタンが押せなくなっていた。
	# 中身はスクロールさせ、パネル自体は画面内に収める。
	var viewport_height := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var panel_height := SettingsPanel.PANEL_HALF_HEIGHT * 2.0
	check(
		panel_height < viewport_height,
		"設定パネル(%.0f)が画面の高さ(%.0f)に収まる" % [panel_height, viewport_height]
	)
