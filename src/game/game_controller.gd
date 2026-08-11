class_name GameController
extends Node

const PromotionDialogScript := preload("res://src/ui/promotion_dialog.gd")

## GameSession と BoardView / GameHud / カメラ入力を結線する。
## 左クリック(ドラッグでない)でマスを指定。待ったは HUD ボタン。
## ドラッグ閾値は OrbitCamera.DRAG_THRESHOLD_PX と共有する。
## AI 対戦時は AiMatch が思考・着手し、人手番以外の入力を止める。

var session: GameSession
var board_view: BoardView
var hud: GameHud
var orbit: OrbitCamera
var ai_match: AiMatch

## ダイアログ表示中は false にして、盤のクリックを止める。
var input_enabled: bool = true

var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragged: bool = false
var _promotion_dialog: Variant = null
var _orbit_input_before_promotion: bool = true


func setup(
	p_session: GameSession,
	p_view: BoardView,
	p_hud: GameHud,
	p_orbit: OrbitCamera,
	p_ai_match: AiMatch = null,
) -> void:
	session = p_session
	board_view = p_view
	hud = p_hud
	orbit = p_orbit
	ai_match = p_ai_match
	if orbit != null:
		var board := session.board()
		orbit.ensure_board_fits(Vector2i(board.width, board.height))
	if not hud.undo_pressed.is_connected(_on_undo):
		hud.undo_pressed.connect(_on_undo)
	if not hud.drop_pressed.is_connected(_on_drop_pressed):
		hud.drop_pressed.connect(_on_drop_pressed)
	if _promotion_dialog == null:
		_promotion_dialog = PromotionDialogScript.new()
		_promotion_dialog.name = "PromotionDialog"
		add_child(_promotion_dialog)
		_promotion_dialog.move_chosen.connect(_on_promotion_chosen)
		_promotion_dialog.cancelled.connect(_on_promotion_cancelled)
	if ai_match != null:
		if not ai_match.board_updated.is_connected(_on_ai_board_updated):
			ai_match.board_updated.connect(_on_ai_board_updated)
	_refresh_view()
	if ai_match != null:
		ai_match.on_position_changed()


func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if not input_enabled or has_pending_promotion():
		# ダイアログ表示中。押しっぱなしの状態を残さない。
		_pressing = false
		_dragged = false
		return
	if ai_match != null and ai_match.blocks_human_input():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pressing = true
			_dragged = false
			_press_pos = mb.position
		else:
			if _pressing and not _dragged:
				_handle_click(mb.position)
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if _press_pos.distance_to(mm.position) > OrbitCamera.DRAG_THRESHOLD_PX:
			_dragged = true


func _handle_click(screen_pos: Vector2) -> void:
	var camera := orbit.camera() if orbit != null else get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var board := session.board()
	var occupied: Array = []
	for y in range(board.height):
		for x in range(board.width):
			var pos := Vector2i(x, y)
			if board.piece_at(pos) != null:
				occupied.append(pos)
	var sq := BoardLayout.pick_square(
		origin, direction, occupied, Vector2i(board.width, board.height), board_view.square_size
	)
	if sq == BoardLayout.INVALID_SQUARE:
		# 盤外クリックは選択解除(盤内の空きと同様の UX)。
		if session.is_selected():
			session.deselect()
			_refresh_view()
		return
	_handle_board_square(sq)
	# 左クリックを handled にしない: OrbitCamera が release を受け取る必要がある。


func _handle_board_square(sq: Vector2i) -> void:
	## raycast と分離した決定的な盤入力境界。任意成りだけ Controller が保留する。
	if session == null or has_pending_promotion():
		return
	var before := session.last_move_event()
	if session.is_selected():
		var candidates := session.legal_moves_to(sq)
		if candidates.size() > 1:
			_open_promotion(candidates)
			_refresh_view()
			return
		if candidates.size() == 1:
			session.try_move_to(sq)
			_after_board_interaction(before)
			return
	session.click(sq)
	_after_board_interaction(before)


func select_drop(kind: int) -> bool:
	## HUD の同じ持ち駒ボタンは取消、別Kindは排他的な選択切替。
	if session == null or has_pending_promotion():
		return false
	if session.selected_drop_kind() == kind:
		session.deselect()
		_refresh_view()
		return true
	var selected := session.select_drop(kind)
	_refresh_view()
	return selected


func promotion_dialog() -> Object:
	return _promotion_dialog


func has_pending_promotion() -> bool:
	return _promotion_dialog != null and _promotion_dialog.visible


func _on_undo() -> void:
	if ai_match != null:
		ai_match.cancel_search()
	if session != null and session.undo():
		_refresh_view()
		if ai_match != null:
			ai_match.on_position_changed()


func _on_ai_board_updated() -> void:
	_refresh_view()


func _on_drop_pressed(side: int, kind: int) -> void:
	if session == null or side != session.side_to_move():
		return
	select_drop(kind)


func _open_promotion(candidates: Array) -> void:
	if _promotion_dialog == null or not _promotion_dialog.open_with(candidates):
		return
	if orbit != null:
		_orbit_input_before_promotion = orbit.input_enabled
		orbit.input_enabled = false
	if ai_match != null:
		ai_match.cancel_search()


func _on_promotion_chosen(move: Move) -> void:
	_restore_after_promotion()
	var before := session.last_move_event()
	session.apply_move(move)
	_after_board_interaction(before)


func _on_promotion_cancelled() -> void:
	## 盤・履歴・last_move_event・選択は変更しない。
	_restore_after_promotion()
	_refresh_view()


func _restore_after_promotion() -> void:
	if orbit != null:
		orbit.input_enabled = _orbit_input_before_promotion


func _after_board_interaction(before: MoveEvent) -> void:
	_refresh_view()
	if ai_match != null and session.last_move_event() != before:
		ai_match.on_position_changed()


func _refresh_view() -> void:
	if session == null or board_view == null:
		return
	board_view.apply_board(session.board())
	var check_sq := BoardLayout.INVALID_SQUARE
	if session.in_check():
		check_sq = session.board().king_square()
	board_view.set_highlights(
		session.selected_square() if session.is_selected() else BoardLayout.INVALID_SQUARE,
		session.legal_targets(),
		check_sq
	)
	if hud != null:
		hud.refresh(
			session.side_to_move(),
			session.in_check() and not session.is_over(),
			session.result_text(),
			session.can_undo(),
			session.board(),
			session.selected_drop_kind(),
			session.legal_drop_kinds()
		)
