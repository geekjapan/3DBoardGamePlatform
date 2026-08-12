extends SceneTree

## GameSession の fail-fast assertion を親テストプロセスから観測する隔離 probe。

func _initialize() -> void:
	call_deferred("_finish_after_assertion")
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "probe mode required")
	var mode: String = args[0]
	if mode == "null_board":
		var invalid_session := GameSession.from_board(null)
		if invalid_session != null:
			print("UNEXPECTED_CONTRACT_SUCCESS: %s" % mode)
	elif mode == "invalid_apply":
		var original := _make_board("", true)
		var invalid_session := GameSession.from_board(original)
		var event := invalid_session.apply_move(Move.new(Vector2i(0, 0), Vector2i(0, 1)))
		if (
			event != null
			or invalid_session.board() != original
			or invalid_session.last_move_event() != null
			or invalid_session.can_undo()
		):
			print("UNEXPECTED_CONTRACT_SUCCESS: %s" % mode)
	else:
		var invalid_session := GameSession.from_board(_make_board(mode, false))
		if invalid_session != null:
			print("UNEXPECTED_CONTRACT_SUCCESS: %s" % mode)


func _finish_after_assertion() -> void:
	quit(0)


func _make_board(missing: String, invalid_apply: bool) -> Object:
	var lines := PackedStringArray(["extends RefCounted"])
	if missing != "side_to_move":
		lines.append("var side_to_move: int = Piece.Side.WHITE")
	if missing != "legal_moves":
		lines.append("func legal_moves() -> Array:")
		lines.append("\treturn [Move.new(Vector2i(0, 0), Vector2i(0, 1))]")
	if missing != "apply":
		lines.append("func apply(_move: Move):")
		lines.append("\treturn null" if invalid_apply else "\treturn self")
	if missing != "piece_at":
		lines.append("func piece_at(_pos: Vector2i) -> Piece:")
		lines.append("\treturn Piece.new(Piece.Side.WHITE, Piece.Kind.SHOGI_PAWN)")
	if missing != "in_check":
		lines.append("func in_check(_side: int = -1) -> bool:")
		lines.append("\treturn false")
	if missing != "is_checkmate":
		lines.append("func is_checkmate() -> bool:")
		lines.append("\treturn false")
	if missing != "is_stalemate":
		lines.append("func is_stalemate() -> bool:")
		lines.append("\treturn false")
	var script := GDScript.new()
	script.source_code = "\n".join(lines)
	assert(script.reload() == OK, "probe board script must compile")
	return script.new()
