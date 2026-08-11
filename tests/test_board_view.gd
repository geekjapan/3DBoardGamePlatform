extends "res://tests/case.gd"

## Issue #4: 3D 盤とプレースホルダ駒、オービットカメラ。
##
## シーム(自動化できる範囲):
## - BoardLayout: 論理マス ↔ ワールド座標
## - BoardView.build_from(Board): 配置はルールエンジンの Board が唯一のソース
## - PieceNode モデルスロット: 見た目の差し替え
## - OrbitCamera: ズーム距離のクランプ
##
## 見た目の質・ドラッグ操作の感触は手動確認(親スペックの Testing Decisions)。


func test_layout_maps_corners_and_center() -> void:
	var a1 := BoardLayout.square_to_world(Vector2i(0, 0))
	var h1 := BoardLayout.square_to_world(Vector2i(7, 0))
	var a8 := BoardLayout.square_to_world(Vector2i(0, 7))
	var h8 := BoardLayout.square_to_world(Vector2i(7, 7))
	var e4 := BoardLayout.square_to_world(Vector2i(4, 3))

	check(a1.x < 0.0 and a1.z > 0.0, "a1 は -X / +Z 側")
	check(h1.x > 0.0 and h1.z > 0.0, "h1 は +X / +Z 側")
	check(a8.x < 0.0 and a8.z < 0.0, "a8 は -X / -Z 側")
	check(h8.x > 0.0 and h8.z < 0.0, "h8 は +X / -Z 側")
	check(absf(e4.x) < 0.6 and absf(e4.z) < 0.6, "e4 付近は原点近く")

	check_eq(BoardLayout.world_to_square(a1), Vector2i(0, 0), "a1 往復")
	check_eq(BoardLayout.world_to_square(h8), Vector2i(7, 7), "h8 往復")
	check_eq(BoardLayout.world_to_square(e4), Vector2i(4, 3), "e4 往復")


func test_light_dark_alternates_with_a1_dark() -> void:
	check(not BoardLayout.is_light_square(Vector2i(0, 0)), "a1 は暗色")
	check(BoardLayout.is_light_square(Vector2i(1, 0)), "b1 は明色")
	check(BoardLayout.is_light_square(Vector2i(0, 1)), "a2 は明色")
	check(not BoardLayout.is_light_square(Vector2i(1, 1)), "b2 は暗色")


func test_board_view_matches_engine_starting_position() -> void:
	var board := Board.chess_start()
	var view := BoardView.new()
	view.build_from(board)

	check_eq(view.piece_count(), 32, "初期配置は 32 駒")
	check(view.board() == board, "BoardView が保持する Board は渡したもの")

	for y in range(8):
		for x in range(8):
			var pos := Vector2i(x, y)
			var piece := board.piece_at(pos)
			var node := view.piece_node_at(pos)
			if piece == null:
				check(node == null, "空マス %s に駒ノードが無い" % str(pos))
			else:
				check(node != null, "駒のあるマス %s にノードがある" % str(pos))
				check_eq(node.piece_side, piece.side, "%s の side" % str(pos))
				check_eq(node.piece_kind, piece.kind, "%s の kind" % str(pos))
				check_eq(node.board_pos, pos, "%s の board_pos" % str(pos))
				var expected_pos := BoardLayout.square_to_world(pos)
				check(
					node.position.is_equal_approx(expected_pos),
					"%s のワールド位置 (got %s expected %s)" % [str(pos), node.position, expected_pos]
				)

	# 代表点: 白キング e1、黒クイーン d8
	check_eq(view.piece_node_at(Vector2i(4, 0)).piece_kind, Piece.Kind.KING, "e1 キング")
	check_eq(view.piece_node_at(Vector2i(4, 0)).piece_side, Piece.Side.WHITE, "e1 白")
	check_eq(view.piece_node_at(Vector2i(3, 7)).piece_kind, Piece.Kind.QUEEN, "d8 クイーン")
	check_eq(view.piece_node_at(Vector2i(3, 7)).piece_side, Piece.Side.BLACK, "d8 黒")

	view.free()


func test_board_view_does_not_invent_pieces_beyond_board() -> void:
	## 配置の二重管理がない: 空の Board からは駒が出ない。
	var empty := Board.empty()
	var view := BoardView.new()
	view.build_from(empty)
	check_eq(view.piece_count(), 0, "空盤には駒が無い")
	view.free()


func test_piece_node_model_slot_is_swappable() -> void:
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.ROOK, Vector2i(0, 0))
	check(not node.has_model(), "初期はモデル無し")

	var first := PlaceholderVisual.create(Piece.Side.WHITE, Piece.Kind.ROOK)
	node.set_model(first)
	check(node.has_model(), "セット後はモデルあり")
	check_eq(node.model_slot().get_child_count(), 1, "スロットに 1 子")
	check(node.model_slot().get_child(0) == first, "最初の見た目が入っている")

	var second := Node3D.new()
	second.name = "ReplacementModel"
	node.set_model(second)
	check_eq(node.model_slot().get_child_count(), 1, "差し替え後も 1 子")
	check(node.model_slot().get_child(0) == second, "新しい見た目に差し替わっている")
	check(not is_instance_valid(first), "旧モデルは解放される")

	node.clear_model()
	check(not node.has_model(), "クリア後はモデル無し")
	node.free()


func test_placeholder_visuals_encode_side_and_kind() -> void:
	var kinds := [
		Piece.Kind.PAWN,
		Piece.Kind.KNIGHT,
		Piece.Kind.BISHOP,
		Piece.Kind.ROOK,
		Piece.Kind.QUEEN,
		Piece.Kind.KING,
	]
	for kind in kinds:
		for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
			var visual := PlaceholderVisual.create(side, kind)
			check_eq(visual.get_meta(PlaceholderVisual.META_SIDE), side, "side meta")
			check_eq(visual.get_meta(PlaceholderVisual.META_KIND), kind, "kind meta")
			check(visual.get_child_count() >= 1, "メッシュ子がある kind=%d" % kind)
			var mesh_inst := visual.get_child(0) as MeshInstance3D
			check(mesh_inst != null and mesh_inst.mesh != null, "MeshInstance3D を持つ")
			visual.free()


func test_orbit_camera_clamps_zoom() -> void:
	var orbit := OrbitCamera.new()
	orbit.min_distance = 5.0
	orbit.max_distance = 20.0
	orbit.set_distance(3.0)
	check_eq(orbit.distance, 5.0, "下限でクランプ")
	orbit.set_distance(100.0)
	check_eq(orbit.distance, 20.0, "上限でクランプ")
	orbit.set_distance(12.0)
	check_eq(orbit.distance, 12.0, "範囲内はそのまま")

	orbit.set_orbit(10.0, -5.0)
	check_eq(orbit.pitch_degrees, orbit.max_pitch_degrees, "ピッチ上限")
	orbit.set_orbit(10.0, -90.0)
	check_eq(orbit.pitch_degrees, orbit.min_pitch_degrees, "ピッチ下限")
	orbit.free()
