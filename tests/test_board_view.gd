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


func test_default_view_fits_whole_board_on_screen() -> void:
	# 初期状態で盤の手前側が画面下に見切れていた。四隅が視野に収まることを固定する。
	var orbit := OrbitCamera.new()
	var half_v := deg_to_rad(75.0) * 0.5           # Camera3D の既定 FOV(縦)
	var half_h := atan(tan(half_v) * (5.0 / 4.0))  # 想定しうる最も窮屈な横幅
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(orbit.pitch_degrees), deg_to_rad(orbit.yaw_degrees), 0.0)
	)
	var pivot: Vector3 = basis * Vector3(0.0, -orbit.focus_lift, 0.0)
	var cam_pos: Vector3 = pivot + basis * Vector3(0.0, 0.0, orbit.distance)
	var inv := basis.inverse()

	var worst := 0.0
	for sx in [-4.0, 4.0]:
		for sz in [-4.0, 4.0]:
			for sy in [0.0, 1.2]:  # 盤面と駒の高さ
				var local: Vector3 = inv * (Vector3(sx, sy, sz) - cam_pos)
				check(local.z < 0.0, "盤の四隅がカメラの前にある")
				worst = maxf(worst, absf(atan(local.y / -local.z)) / half_v)
				worst = maxf(worst, absf(atan(local.x / -local.z)) / half_h)
	check(worst < 1.0, "盤全体が視野に収まる(はみ出し率 %.2f)" % worst)
	orbit.free()


func test_orbit_camera_pan_follows_drag_and_clamps() -> void:
	var orbit := OrbitCamera.new()
	orbit.max_pan_distance = 5.0
	# ヨー/ピッチ 0 なら画面右 = +X、画面上 = +Y。
	orbit.set_orbit(0.0, 0.0)
	orbit.reset_pan()

	# 右へドラッグすると盤がカーソルに付いてくる = 注視点は左(-X)へ。
	orbit.pan_by_screen_delta(Vector2(100.0, 0.0))
	check(orbit.pan_offset.x < 0.0, "右ドラッグで注視点は -X へ")

	# 下へドラッグすると盤は下がる = 注視点は上(+Y)へ。
	orbit.reset_pan()
	orbit.pan_by_screen_delta(Vector2(0.0, 100.0))
	check(orbit.pan_offset.y > 0.0, "下ドラッグで注視点は +Y へ")

	# 盤を見失わないよう上限で頭打ちにする。
	orbit.reset_pan()
	for i in 200:
		orbit.pan_by_screen_delta(Vector2(500.0, 500.0))
	check(orbit.pan_offset.length() <= orbit.max_pan_distance + 0.001, "上限でクランプ")

	orbit.reset_pan()
	check_eq(orbit.pan_offset, Vector3.ZERO, "リセットで盤中心へ戻る")
	orbit.free()


func test_camera_settings_roundtrip_and_reset() -> void:
	# 実ファイルの user://settings.cfg は利用者の設定なので触らない。
	var path := "user://test_camera_%d.cfg" % Time.get_ticks_usec()
	var s := CameraSettings.load_or_default(path)
	check(not s.has_saved_view(), "未保存なら既定構図のまま")

	var orbit := OrbitCamera.new()
	var default_distance := orbit.distance
	orbit.set_orbit(80.0, -55.0)
	orbit.set_distance(6.0)
	orbit.pan_by_screen_delta(Vector2(120.0, 60.0))
	var moved_pan := orbit.pan_offset

	s.config_path = path
	s.capture_from(orbit)
	s.save_to_disk()

	# 別のカメラに読み戻すと同じ構図になる。
	var restored := CameraSettings.load_or_default(path)
	check(restored.has_saved_view(), "保存済みとして扱われる")
	var other := OrbitCamera.new()
	restored.apply_to(other)
	check_eq(other.distance, 6.0, "距離が復元される")
	check_eq(other.yaw_degrees, 80.0, "ヨーが復元される")
	check_eq(other.pitch_degrees, -55.0, "ピッチが復元される")
	check(other.pan_offset.distance_to(moved_pan) < 0.001, "平行移動が復元される")

	# 初期位置に戻すと保存が消え、既定構図に戻る。
	restored.clear_saved_view()
	check(not restored.has_saved_view(), "保存が消える")
	var after := CameraSettings.load_or_default(path)
	check(not after.has_saved_view(), "消えたことがディスクにも反映される")
	var fresh := OrbitCamera.new()
	check_eq(fresh.distance, default_distance, "既定の距離に戻る")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	orbit.free()
	other.free()
	fresh.free()


func test_camera_ignores_input_while_dialog_is_open() -> void:
	# 設定ダイアログのスクロール端でホイールが消費されず、盤までズームが効いていた。
	var orbit := OrbitCamera.new()
	var start := orbit.distance

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true

	orbit.input_enabled = false
	orbit._unhandled_input(wheel)
	check_eq(orbit.distance, start, "ダイアログ表示中はズームしない")

	# 右ドラッグの平行移動も止まる。
	orbit.reset_pan()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	orbit._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 100.0)
	orbit._unhandled_input(motion)
	check_eq(orbit.pan_offset, Vector3.ZERO, "ダイアログ表示中は平行移動しない")

	orbit.free()


func test_character_model_falls_back_when_missing() -> void:
	# モデル欠品でクラッシュさせない。呼び出し側が仮の見た目に落とせるよう null を返す。
	check(CharacterModel.create("") == null, "指定なしは null")
	check(CharacterModel.create("res://assets/models/does_not_exist.vrm") == null, "実体が無ければ null")
	check(not CharacterModel.is_available("res://assets/models/does_not_exist.vrm"), "利用不可と分かる")


func test_board_view_falls_back_to_placeholder_when_factory_returns_null() -> void:
	# キャラクターにモデルが無い駒は、仮の見た目のまま盤に並ぶ。
	var view := BoardView.new()
	view.visual_factory = func(_side: int, _kind: int) -> Node3D:
		return null
	view.build_from(Board.chess_start())
	check_eq(view.piece_count(), 32, "全駒が並ぶ")
	var node := view.piece_node_at(Vector2i(4, 0))
	check(node.has_model(), "見た目が付いている")
	var visual := node.model_slot().get_child(0) as Node3D
	check(not visual.has_meta(CharacterModel.META_NEEDS_FIT), "仮の見た目(実寸合わせ不要)")
	view.free()


func test_character_model_fit_is_idempotent() -> void:
	# 2 回目で等倍に戻る実装だと、盤更新のたびにモデルが原寸へ跳ね上がる。
	var model := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 2.0, 0.5)   # 高さ 2.0 の箱
	mesh.mesh = box
	mesh.position = Vector3(0.0, 1.0, 0.0)  # 足元が原点に来るよう持ち上げる
	model.add_child(mesh)

	CharacterModel.fit_to_square(model, 1.0)
	var first_scale := model.scale.x
	var expected := CharacterModel.TARGET_HEIGHT / 2.0
	check(absf(first_scale - expected) < 0.001, "目標高さに合わせる (got %.3f)" % first_scale)

	CharacterModel.fit_to_square(model, 1.0)
	check(absf(model.scale.x - first_scale) < 0.001, "2 回目も同じ倍率")
	CharacterModel.fit_to_square(model, 1.0)
	check(absf(model.scale.x - first_scale) < 0.001, "3 回目も同じ倍率")
	check(absf(model.position.y) < 0.01, "足元が盤面に接地する")
	model.free()


func test_animator_needs_humanoid_mapping() -> void:
	# 仮の見た目や humanoid でないモデルには付かない(静止のまま動作する)。
	var plain := Node3D.new()
	check(CharacterAnimator.attach_to(plain) == null, "骨格が無ければ付かない")
	plain.free()
	check(CharacterAnimator.attach_to(null) == null, "null でも落ちない")


func test_animator_resolves_bones_by_role_not_by_name() -> void:
	# 1 つの動きの定義をリグの違うモデルで使い回す肝。ボーン名を直接引くと、
	# 命名の違うモデル(試験用モデルは LeftUpperArm の実体が "Left arm")で
	# 腕が動かないまま気づけない。
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Hips")
	skeleton.add_bone("背骨")          # 標準名と違う名前
	skeleton.add_bone("左腕")

	var profile := SkeletonProfileHumanoid.new()
	var bone_map := BoneMap.new()
	bone_map.profile = profile
	bone_map.set_skeleton_bone_name("Spine", "背骨")
	bone_map.set_skeleton_bone_name("LeftUpperArm", "左腕")

	check_eq(
		CharacterAnimator._find_bone_for_role(skeleton, bone_map, "Spine"),
		skeleton.find_bone("背骨"),
		"標準名で引けなければ BoneMap 経由で解決する"
	)
	check_eq(
		CharacterAnimator._find_bone_for_role(skeleton, bone_map, "LeftUpperArm"),
		skeleton.find_bone("左腕"),
		"腕も役割から解決できる"
	)
	check_eq(
		CharacterAnimator._find_bone_for_role(skeleton, bone_map, "Hips"),
		skeleton.find_bone("Hips"),
		"標準名のままの骨も引ける"
	)
	check_eq(
		CharacterAnimator._find_bone_for_role(skeleton, bone_map, "Head"),
		-1,
		"存在しない役割は -1(その役割を飛ばす)"
	)
	skeleton.free()


func test_capture_animation_finishes_before_piece_disappears() -> void:
	# アニメータ側が駒本体の Tween より長いと、倒れ切る前にノードが消えて
	# 「倒れた」と読めない。実際に 0.5 秒 対 0.35 秒でずれていた。
	check(
		CharacterAnimator.CAPTURE_DURATION <= PieceNode.CAPTURE_DURATION_SEC,
		"取られ演出が駒の寿命に収まる (%.2f <= %.2f)"
			% [CharacterAnimator.CAPTURE_DURATION, PieceNode.CAPTURE_DURATION_SEC]
	)
	check(
		CharacterAnimator.MOVE_DURATION <= PieceNode.MOVE_DURATION_SEC,
		"移動演出も移動時間に収まる"
	)


func test_pieces_face_the_opponent() -> void:
	# 全員が同じ方を向いていた。盤は白側が +Z、VRM は -Z を向く規約なので、
	# 白はそのままで相手を向き、黒だけ反転させる。
	var view := BoardView.new()
	view.visual_factory = func(_side: int, _kind: int) -> Node3D:
		var stand_in := Node3D.new()
		stand_in.set_meta(CharacterModel.META_NEEDS_FIT, true)
		return stand_in
	view.build_from(Board.chess_start())

	var white := view.piece_node_at(Vector2i(4, 0)).model_slot().get_child(0) as Node3D
	var black := view.piece_node_at(Vector2i(4, 7)).model_slot().get_child(0) as Node3D
	check(absf(white.rotation.y) < 0.001, "白はそのまま黒を向く")
	check(absf(black.rotation.y - PI) < 0.001, "黒は反転して白を向く")
	view.free()


func test_base_pose_lowers_arms_from_t_pose() -> void:
	# VRM は T ポーズが基準なので、素立ちのままだと腕が真横に広がった
	# カカシになる。素立ちの補正が抜けたら気づけるようにする。
	var base: Dictionary = CharacterAnimator.BASE_POSE
	for role in ["LeftUpperArm", "RightUpperArm"]:
		check(base.has(role), "%s に素立ちの補正がある" % role)
		var degrees: Vector3 = base[role]
		# 上腕は X の正回転で下がる(左右とも同符号)。実測で確認済み。
		check(degrees.x > 30.0, "%s を下ろしている (X=%.0f度)" % [role, degrees.x])
	# 左右で下ろす量が違うと片腕だけ上がって見える。
	check_eq(
		(base["LeftUpperArm"] as Vector3).x,
		(base["RightUpperArm"] as Vector3).x,
		"左右で下ろす量が同じ"
	)


func test_character_pieces_stay_grounded_while_idle() -> void:
	# 待機の上下動は駒ノードごと動かすので、立っているキャラクターだと
	# 足が地面から浮く。呼吸は骨格側が出すため、キャラのときは切る。
	var node := PieceNode.new(Piece.Side.WHITE, Piece.Kind.KING, Vector2i(4, 0))
	var stand_in := Node3D.new()
	node.set_model(stand_in)
	var rest := Vector3(1.0, 0.0, 2.0)
	node.snap_to(rest)

	# 仮の見た目(アニメータ無し)は従来どおり上下する。
	node._process(0.2)
	check(node.position.y != rest.y, "プリミティブは浮遊する")

	# CharacterAnimator が居るときは動かさない。
	var animator := CharacterAnimator.new()
	stand_in.add_child(animator)
	node.snap_to(rest)
	node._process(0.2)
	check_eq(node.position, rest, "キャラクターは接地したまま")
	node.free()
