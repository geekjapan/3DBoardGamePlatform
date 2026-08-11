class_name GameController
extends Node

## GameSession と BoardView / GameHud / カメラ入力を結線する。
## 左クリック(ドラッグでない)でマスを指定。待ったは HUD ボタン。
## ドラッグ閾値は OrbitCamera.DRAG_THRESHOLD_PX と共有する。
## AI 対戦時は AiMatch が思考・着手し、人手番以外の入力を止める。

var session: GameSession
var board_view: BoardView
var hud: GameHud
var orbit: OrbitCamera
var ai_match: AiMatch

var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragged: bool = false


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
	if not hud.undo_pressed.is_connected(_on_undo):
		hud.undo_pressed.connect(_on_undo)
	if ai_match != null:
		if not ai_match.board_updated.is_connected(_on_ai_board_updated):
			ai_match.board_updated.connect(_on_ai_board_updated)
	_refresh_view()
	if ai_match != null:
		ai_match.on_position_changed()


func _unhandled_input(event: InputEvent) -> void:
	if session == null:
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
		origin, direction, occupied, board_view.square_size, board.width, board.height
	)
	if sq == BoardLayout.INVALID_SQUARE:
		# 盤外クリックは選択解除(盤内の空きと同様の UX)。
		if session.is_selected():
			session.deselect()
			_refresh_view()
		return
	session.click(sq)
	_refresh_view()
	if ai_match != null:
		ai_match.on_position_changed()
	# 左クリックを handled にしない: OrbitCamera が release を受け取る必要がある。


func _on_undo() -> void:
	if ai_match != null:
		ai_match.cancel_search()
	if session != null and session.undo():
		_refresh_view()
		if ai_match != null:
			ai_match.on_position_changed()


func _on_ai_board_updated() -> void:
	_refresh_view()


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
			session.can_undo()
		)
