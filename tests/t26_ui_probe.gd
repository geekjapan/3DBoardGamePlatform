extends SceneTree

## Issue #26 の実Viewport校正probe。独立フレームを待ち、実Nodeのlayout/投影/inputを測る。

const VIEWPORT_SIZE := Vector2i(1280, 720)
const TOLERANCE_PX := 2.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.gui_disable_input = false
	viewport.handle_input_locally = true
	var scene_root := Node3D.new()
	viewport.add_child(scene_root)
	root.add_child(viewport)

	var board := ShogiBoard.start()
	board.hands[Piece.Side.WHITE][Piece.Kind.SHOGI_SILVER] = 1
	var session := GameSession.from_board(board)
	var view := BoardView.new()
	var orbit := OrbitCamera.new()
	var hud := GameHud.new()
	var controller := GameController.new()
	scene_root.add_child(view)
	scene_root.add_child(orbit)
	scene_root.add_child(hud)
	scene_root.add_child(controller)
	view.build_from(board)
	controller.setup(session, view, hud, orbit)

	# Canvas anchor、Camera global transform、SubViewport worldを確定する。
	await process_frame
	orbit.camera().force_update_transform()
	view.force_update_transform()

	var board_rect := _projected_board_rect(orbit.camera(), Vector2i(9, 9))
	var left_rect := hud.hand_panel(Piece.Side.WHITE).get_global_rect()
	var right_rect := hud.hand_panel(Piece.Side.BLACK).get_global_rect()
	var layout_pass := _panels_fit_without_board_overlap(board_rect, left_rect, right_rect)
	var fail_left := Rect2(board_rect.position + Vector2(8.0, 8.0), left_rect.size)
	var layout_fail_control := _panels_fit_without_board_overlap(board_rect, fail_left, right_rect)

	var actual_button := hud.hand_button(Piece.Side.WHITE, Piece.Kind.SHOGI_SILVER)
	var input_pass := _consumes_pointer(actual_button)
	var fail_button := Button.new()
	fail_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var input_fail_control := _consumes_pointer(fail_button)
	fail_button.free()

	var from_screen := orbit.camera().unproject_position(
		BoardLayout.square_to_world(Vector2i(4, 2), Vector2i(9, 9)) + Vector3(0.0, 0.25, 0.0)
	)
	var to_screen := orbit.camera().unproject_position(
		BoardLayout.square_to_world(Vector2i(4, 3), Vector2i(9, 9))
	)
	controller._handle_click(from_screen)
	controller._handle_click(to_screen)
	var moved: Piece = session.board().piece_at(Vector2i(4, 3)) as Piece
	var board_input_pass := moved != null and moved.kind == Piece.Kind.SHOGI_PAWN
	var view_sync_pass := view.piece_node_at(Vector2i(4, 3)) != null

	print(
		"T26 UI calibration: viewport=1280x720; target=actual BoardLayout/BoardView/GameHud; "
		+ "boardAABB=%s leftPanel=%s rightPanel=%s tolerance=%.1fpx; " % [board_rect, left_rect, right_rect, TOLERANCE_PX]
		+ "PASS control actualLayout=%s actualInputStop=%s; " % [layout_pass, input_pass]
		+ "FAIL control overlappedLayout=%s ignoreInputStop=%s; " % [layout_fail_control, input_fail_control]
		+ "inputCoords from=%s to=%s boardInput=%s viewSync=%s" % [
			from_screen, to_screen, board_input_pass, view_sync_pass
		]
	)

	var passed := (
		layout_pass
		and not layout_fail_control
		and input_pass
		and not input_fail_control
		and board_input_pass
		and view_sync_pass
	)
	viewport.queue_free()
	quit(0 if passed else 1)


func _projected_board_rect(camera: Camera3D, board_size: Vector2i) -> Rect2:
	var points: Array[Vector2] = []
	var half_x := float(board_size.x) * 0.5
	var half_z := float(board_size.y) * 0.5
	for x in [-half_x, half_x]:
		for z in [-half_z, half_z]:
			points.append(camera.unproject_position(Vector3(x, 0.0, z)))
	var min_pos := points[0]
	var max_pos := points[0]
	for point in points:
		min_pos.x = minf(min_pos.x, point.x)
		min_pos.y = minf(min_pos.y, point.y)
		max_pos.x = maxf(max_pos.x, point.x)
		max_pos.y = maxf(max_pos.y, point.y)
	return Rect2(min_pos, max_pos - min_pos)


func _panels_fit_without_board_overlap(board_rect: Rect2, left_rect: Rect2, right_rect: Rect2) -> bool:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	var measured_board := board_rect.grow(-TOLERANCE_PX)
	return (
		viewport_rect.encloses(board_rect)
		and viewport_rect.encloses(left_rect)
		and viewport_rect.encloses(right_rect)
		and not measured_board.intersects(left_rect)
		and not measured_board.intersects(right_rect)
	)


func _consumes_pointer(control: Control) -> bool:
	return control.mouse_filter == Control.MOUSE_FILTER_STOP
