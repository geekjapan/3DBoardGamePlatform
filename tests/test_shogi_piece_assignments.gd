extends "res://tests/case.gd"

## Issue #24: 将棋の駒種、Team割当、placeholder形状の契約。

const AABB_TOLERANCE := 0.001
const STABLE_KIND_NAMES: PackedStringArray = [
	"pawn", "knight", "bishop", "rook", "queen", "king",
	"shogi_pawn", "shogi_lance", "shogi_knight", "shogi_silver",
	"shogi_gold", "shogi_bishop", "shogi_rook", "shogi_king",
	"shogi_promoted_pawn", "shogi_promoted_lance", "shogi_promoted_knight",
	"shogi_promoted_silver", "shogi_horse", "shogi_dragon",
]
const SHOGI_BASE_KINDS: Array[int] = [
	Piece.Kind.SHOGI_PAWN,
	Piece.Kind.SHOGI_LANCE,
	Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_SILVER,
	Piece.Kind.SHOGI_GOLD,
	Piece.Kind.SHOGI_BISHOP,
	Piece.Kind.SHOGI_ROOK,
	Piece.Kind.SHOGI_KING,
]
const SHOGI_PROMOTED_KINDS: Array[int] = [
	Piece.Kind.SHOGI_PROMOTED_PAWN,
	Piece.Kind.SHOGI_PROMOTED_LANCE,
	Piece.Kind.SHOGI_PROMOTED_KNIGHT,
	Piece.Kind.SHOGI_PROMOTED_SILVER,
	Piece.Kind.SHOGI_HORSE,
	Piece.Kind.SHOGI_DRAGON,
]


func test_all_piece_kind_ids_and_names_are_stable_and_reversible() -> void:
	var ids: Array[int] = [
		Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
		Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
		Piece.Kind.SHOGI_PAWN, Piece.Kind.SHOGI_LANCE, Piece.Kind.SHOGI_KNIGHT,
		Piece.Kind.SHOGI_SILVER, Piece.Kind.SHOGI_GOLD, Piece.Kind.SHOGI_BISHOP,
		Piece.Kind.SHOGI_ROOK, Piece.Kind.SHOGI_KING,
		Piece.Kind.SHOGI_PROMOTED_PAWN, Piece.Kind.SHOGI_PROMOTED_LANCE,
		Piece.Kind.SHOGI_PROMOTED_KNIGHT, Piece.Kind.SHOGI_PROMOTED_SILVER,
		Piece.Kind.SHOGI_HORSE, Piece.Kind.SHOGI_DRAGON,
	]
	check_eq(ids, range(20), "Piece.Kind は既存0〜5を保ち将棋6〜19を連続追加")
	for kind in range(20):
		var stable_name := STABLE_KIND_NAMES[kind]
		check_eq(SpeechCatalog.kind_name(kind), stable_name, "ID→安定名 kind=%d" % kind)
		check_eq(SpeechCatalog.kind_from_name(stable_name), kind, "安定名→ID kind=%d" % kind)
	check_eq(SpeechCatalog.kind_name(20), "", "未知IDは空名")
	check_eq(SpeechCatalog.kind_from_name("shogi_unknown"), -1, "未知名は拒否")


func test_promoted_piece_resolution_uses_the_exact_fixed_map() -> void:
	var expected: Dictionary = {
		14: 6,
		15: 7,
		16: 8,
		17: 9,
		18: 11,
		19: 12,
	}
	check_eq(Piece.PROMOTED_TO_BASE, expected, "成駒→元駒の唯一の固定表")
	for promoted in expected:
		check_eq(Piece.base_kind_for_promoted(int(promoted)), expected[promoted], "成駒の元駒")
	for basic in range(14):
		check_eq(Piece.base_kind_for_promoted(basic), -1, "基本駒は変換しない kind=%d" % basic)

	var team := TeamDef.new()
	team.assign(Piece.Kind.PAWN, "chess_pawn")
	team.assign(Piece.Kind.SHOGI_PAWN, "shogi_pawn")
	team.assign(Piece.Kind.SHOGI_BISHOP, "shogi_bishop")
	check_eq(team.character_id_for_kind(Piece.Kind.SHOGI_PROMOTED_PAWN), "shogi_pawn", "と金は将棋歩へ")
	check_eq(team.character_id_for_kind(Piece.Kind.SHOGI_HORSE), "shogi_bishop", "馬は将棋角へ")
	check_eq(team.character_id_for_kind(Piece.Kind.SHOGI_DRAGON), "", "元の将棋飛車も無ければ安全に空")
	check_eq(team.character_id_for_kind(Piece.Kind.SHOGI_LANCE), "", "将棋基本駒はチェスへ落ちない")
	team.assign(Piece.Kind.SHOGI_PROMOTED_PAWN, "tokin_explicit")
	check_eq(team.character_id_for_kind(Piece.Kind.SHOGI_PROMOTED_PAWN), "tokin_explicit", "成駒明示割当を優先")


func test_flat_team_json_preserves_only_explicit_chess_and_shogi_assignments() -> void:
	var source := TeamDef.new()
	source.id = "mixed"
	source.display_name = "混在チーム"
	source.assign(Piece.Kind.ROOK, "chess_rook")
	source.assign(Piece.Kind.SHOGI_LANCE, "shogi_lance")
	source.assign(Piece.Kind.SHOGI_DRAGON, "shogi_dragon")
	var cloned := TeamStore.clone_team(source)
	check_eq(cloned.id, source.id, "clone id")
	check_eq(cloned.display_name, source.display_name, "clone display_name")
	check_eq(cloned.assignments, source.assignments, "clone は全明示割当を保持")

	var encoded := TeamStore.team_to_dict(cloned)
	check_eq(encoded["assignments"], {
		"rook": "chess_rook",
		"shogi_lance": "shogi_lance",
		"shogi_dragon": "shogi_dragon",
	}, "平坦assignmentsを維持")
	var decoded := TeamStore.team_from_dict(encoded)
	check_eq(decoded.assignments, source.assignments, "全明示割当を往復")

	var dir_path := "user://test_shogi_team_%d" % Time.get_ticks_usec()
	check_eq(TeamStore.save_team(cloned, dir_path), OK, "混在Teamを保存")
	var disk_team := TeamStore.load_team_file(dir_path.path_join("mixed.json"))
	check(disk_team != null, "混在Teamを再読込")
	if disk_team != null:
		check_eq(disk_team.assignments, source.assignments, "ディスク往復も明示割当を保持")
	_cleanup_dir(dir_path)

	var chess_only := TeamStore.team_from_dict({
		"id": "legacy",
		"display_name": "既存チェス",
		"assignments": {"pawn": "hotblood", "king": "calm"},
	})
	check_eq(chess_only.character_id_for_kind(Piece.Kind.PAWN), "hotblood", "既存pawnを読む")
	check_eq(chess_only.character_id_for_kind(Piece.Kind.KING), "calm", "既存kingを読む")
	check_eq(chess_only.character_id_for_kind(Piece.Kind.SHOGI_PAWN), "", "将棋割当を合成しない")

	var base_only := TeamDef.new()
	base_only.id = "base_only"
	base_only.display_name = "元駒のみ"
	base_only.assign(Piece.Kind.SHOGI_SILVER, "silver")
	check_eq(base_only.character_id_for_kind(Piece.Kind.SHOGI_PROMOTED_SILVER), "silver", "解決時だけ元駒へ")
	var base_encoded := TeamStore.team_to_dict(base_only)
	check(not base_encoded["assignments"].has("shogi_promoted_silver"), "暗黙成駒を永続化しない")


func test_game_filtered_team_ui_keeps_hidden_explicit_assignments() -> void:
	var catalog := SpeechCatalog.load_default()
	var mixed := TeamDef.new()
	mixed.id = "mixed_ui"
	mixed.display_name = "混在UI"
	mixed.assign(Piece.Kind.BISHOP, "calm")
	mixed.assign(Piece.Kind.SHOGI_GOLD, "hotblood")
	catalog.teams[mixed.id] = mixed

	var editor := TeamEditorPanel.new()
	editor.open_with(catalog, "user://unused", mixed.id, SpeechCatalog.GAME_CHESS)
	check(editor._kind_rows[Piece.Kind.BISHOP].visible, "チェス行を表示")
	check(not editor._kind_rows[Piece.Kind.SHOGI_GOLD].visible, "将棋行を隠す")
	editor.set_game_filter(SpeechCatalog.GAME_SHOGI)
	check(not editor._kind_rows[Piece.Kind.BISHOP].visible, "チェス行を隠す")
	check(editor._kind_rows[Piece.Kind.SHOGI_GOLD].visible, "将棋行を表示")
	check_eq(editor.draft().assignments, mixed.assignments, "非表示側の明示割当を保持")
	editor._on_new_pressed()
	editor.draft().assign(Piece.Kind.SHOGI_PAWN, "hotblood")
	check_eq(editor.draft().assignments.size(), 1, "片ゲームだけの疎な新規Team")
	editor.free()

	var settings := TeamSettings.new()
	settings.config_path = "user://test_shogi_select_%d.cfg" % Time.get_ticks_usec()
	var select := TeamSelectPanel.new()
	select.open_with(catalog, settings, SpeechCatalog.GAME_SHOGI)
	var lineup := select._lineup_text(mixed.id)
	check(lineup.contains("shogi_gold="), "選択画面は将棋割当を表示")
	check(not lineup.contains(", bishop=") and not lineup.begins_with("並び: bishop="),
		"選択画面はチェス割当を表示しない")
	check_eq(mixed.assignments[Piece.Kind.BISHOP], "calm", "表示フィルターは隠れた割当を破棄しない")
	select.free()
	if FileAccess.file_exists(settings.config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))


func test_aabb_probe_controls_calibrate_one_square_measurement() -> void:
	var known_box := _box_control(Vector3(1.0, 0.4, 1.0))
	var oversize_box := _box_control(Vector3(1.02, 0.4, 1.0))
	var pass_result := _fits_one_square(_recursive_aabb(known_box))
	var fail_result := _fits_one_square(_recursive_aabb(oversize_box))
	print(
		"AABB calibration: recursive transformed mesh corners; square_size=1; tolerance=%.3f; PASS control expected=true actual=%s; FAIL control expected=false actual=%s"
		% [AABB_TOLERANCE, pass_result, fail_result]
	)
	check(pass_result, "既知寸法1x1箱はPASS control")
	check(not fail_result, "故意の1.02幅箱はFAIL control")
	known_box.free()
	oversize_box.free()


func test_shogi_placeholders_fit_and_have_deterministic_compositions() -> void:
	var basic_signatures: Dictionary = {}
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var min_z := INF
	var max_z := -INF
	for kind in SHOGI_BASE_KINDS:
		var visual := PlaceholderVisual.create(Piece.Side.WHITE, kind)
		var bounds := _recursive_aabb(visual)
		min_x = minf(min_x, bounds.position.x)
		max_x = maxf(max_x, bounds.end.x)
		min_y = minf(min_y, bounds.position.y)
		min_z = minf(min_z, bounds.position.z)
		max_z = maxf(max_z, bounds.end.z)
		check(_fits_one_square(bounds), "基本駒 kind=%d は1マス内で接地: %s" % [kind, bounds])
		var signature := _geometry_signature(visual, false)
		check(not basic_signatures.has(signature), "基本8種は異なる形状signature kind=%d" % kind)
		basic_signatures[signature] = kind
		visual.free()
	check_eq(basic_signatures.size(), 8, "基本8種のsignatureが相互に異なる")

	var shared_marker_signature := ""
	for promoted_kind in SHOGI_PROMOTED_KINDS:
		var promoted := PlaceholderVisual.create(Piece.Side.WHITE, promoted_kind)
		var base_kind := Piece.base_kind_for_promoted(promoted_kind)
		var base := PlaceholderVisual.create(Piece.Side.WHITE, base_kind)
		var bounds := _recursive_aabb(promoted)
		min_x = minf(min_x, bounds.position.x)
		max_x = maxf(max_x, bounds.end.x)
		min_y = minf(min_y, bounds.position.y)
		min_z = minf(min_z, bounds.position.z)
		max_z = maxf(max_z, bounds.end.z)
		check(_fits_one_square(bounds), "成駒 kind=%d は1マス内で接地: %s" % [promoted_kind, bounds])
		check_eq(_geometry_signature(promoted, true), _geometry_signature(base, false), "成駒は元形状を再利用")
		var marker := promoted.find_child(str(PlaceholderVisual.PROMOTION_MARKER_NAME), true, false) as MeshInstance3D
		check(marker != null, "成駒に共通3Dマーカー")
		if marker != null:
			var marker_signature := _mesh_signature(marker, marker.transform)
			if shared_marker_signature == "":
				shared_marker_signature = marker_signature
			else:
				check_eq(marker_signature, shared_marker_signature, "全成駒で同一マーカー")
			var marker_size := marker.mesh.get_aabb().size
			check(marker_size.x > 0.0 and marker_size.y > 0.0 and marker_size.z > 0.0, "マーカーは非平面3D")
		promoted.free()
		base.free()
	print(
		"Shogi AABB probe: 14/14 PASS; recursive composition; envelope x=[%.3f,%.3f] z=[%.3f,%.3f] min_y=%.3f; 8 distinct basics; promoted=base+shared marker"
		% [min_x, max_x, min_z, max_z, min_y]
	)


func _box_control(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position.y = size.y * 0.5
	root.add_child(instance)
	return root


func _fits_one_square(bounds: AABB) -> bool:
	return (
		bounds.position.x >= -0.5 - AABB_TOLERANCE
		and bounds.end.x <= 0.5 + AABB_TOLERANCE
		and bounds.position.z >= -0.5 - AABB_TOLERANCE
		and bounds.end.z <= 0.5 + AABB_TOLERANCE
		and absf(bounds.position.y) <= AABB_TOLERANCE
	)


func _recursive_aabb(root: Node3D) -> AABB:
	var points: Array[Vector3] = []
	_collect_mesh_corners(root, Transform3D.IDENTITY, points)
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		bounds = bounds.expand(points[i])
	return bounds


func _collect_mesh_corners(node: Node, parent_transform: Transform3D, points: Array[Vector3]) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			var mesh_bounds := instance.mesh.get_aabb()
			for x in [mesh_bounds.position.x, mesh_bounds.end.x]:
				for y in [mesh_bounds.position.y, mesh_bounds.end.y]:
					for z in [mesh_bounds.position.z, mesh_bounds.end.z]:
						points.append(current_transform * Vector3(x, y, z))
	for child in node.get_children():
		_collect_mesh_corners(child, current_transform, points)


func _geometry_signature(root: Node, exclude_marker: bool) -> String:
	var parts := PackedStringArray()
	_collect_geometry(root, Transform3D.IDENTITY, exclude_marker, parts)
	parts.sort()
	return "|".join(parts)


func _collect_geometry(node: Node, parent_transform: Transform3D, exclude_marker: bool, parts: PackedStringArray) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		if exclude_marker and node.name == PlaceholderVisual.PROMOTION_MARKER_NAME:
			return
		parts.append(_mesh_signature(node as MeshInstance3D, current_transform))
	for child in node.get_children():
		_collect_geometry(child, current_transform, exclude_marker, parts)


func _mesh_signature(instance: MeshInstance3D, transform: Transform3D) -> String:
	var bounds := instance.mesh.get_aabb()
	var euler := transform.basis.get_euler()
	return "%s:s(%.3f,%.3f,%.3f):p(%.3f,%.3f,%.3f):r(%.3f,%.3f,%.3f)" % [
		instance.mesh.get_class(),
		bounds.size.x, bounds.size.y, bounds.size.z,
		transform.origin.x, transform.origin.y, transform.origin.z,
		euler.x, euler.y, euler.z,
	]


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
