class_name PieceNode
extends Node3D

## 盤上の 1 駒の見た目ノード。
## ModelSlot にプリミティブ / glTF / VRM のいずれかを装着でき、差し替えはスロットの入れ替えのみ。
## 移動・待機・取られの演出を持つ。モデルに対応クリップがあれば再生し、無ければ代替モーション。

const MODEL_SLOT_NAME := "ModelSlot"

## クリップ名の候補(先頭から優先)。モデル側の命名ゆれを吸収する。
const IDLE_CLIP_CANDIDATES: PackedStringArray = ["idle", "Idle", "IDLE", "wait", "Wait"]
const MOVE_CLIP_CANDIDATES: PackedStringArray = ["move", "Move", "MOVE", "walk", "Walk", "run", "Run"]
const CAPTURE_CLIP_CANDIDATES: PackedStringArray = [
	"capture", "Capture", "death", "Death", "die", "Die", "hit", "Hit"
]

const MOVE_DURATION_SEC := 0.28
const CAPTURE_DURATION_SEC := 0.35
const IDLE_BOB_AMPLITUDE := 0.028
const IDLE_BOB_SPEED := 2.4

enum AnimState {
	IDLE,
	MOVING,
	CAPTURING,
}

## 論理座標 (file, rank)。Board と同じ。
var board_pos: Vector2i = Vector2i(-1, -1)
## Piece.Side
var piece_side: int = Piece.Side.WHITE
## Piece.Kind
var piece_kind: int = Piece.Kind.PAWN

var _model_slot: Node3D
var _anim_state: int = AnimState.IDLE
## 待機の上下動を除いた着地位置。
var _rest_position: Vector3 = Vector3.ZERO
var _idle_phase: float = 0.0
var _active_tween: Tween = null
## 取られ演出の完了を BoardView が待つ。
signal capture_finished
signal move_finished


func _init(
	p_side: int = Piece.Side.WHITE,
	p_kind: int = Piece.Kind.PAWN,
	p_pos: Vector2i = Vector2i(-1, -1),
) -> void:
	piece_side = p_side
	piece_kind = p_kind
	board_pos = p_pos
	_model_slot = Node3D.new()
	_model_slot.name = MODEL_SLOT_NAME
	add_child(_model_slot)
	# 駒ごとに位相をずらし、待機が同期しないようにする。
	_idle_phase = float(abs(p_side) * 7 + abs(p_kind) * 3 + abs(p_pos.x) + abs(p_pos.y) * 5) * 0.37
	set_process(true)


func _process(delta: float) -> void:
	if _anim_state != AnimState.IDLE:
		return
	_idle_phase += delta * IDLE_BOB_SPEED
	var bob := sin(_idle_phase) * IDLE_BOB_AMPLITUDE
	position = Vector3(_rest_position.x, _rest_position.y + bob, _rest_position.z)


func model_slot() -> Node3D:
	return _model_slot


func has_model() -> bool:
	return _model_slot.get_child_count() > 0


func set_model(visual: Node3D) -> void:
	## スロット内を置き換える。visual はまだ親を持っていないこと。
	clear_model()
	if visual != null:
		_model_slot.add_child(visual)


func clear_model() -> void:
	while _model_slot.get_child_count() > 0:
		var child: Node = _model_slot.get_child(0)
		_model_slot.remove_child(child)
		child.free()


func anim_state() -> int:
	return _anim_state


func is_animating() -> bool:
	return _anim_state == AnimState.MOVING or _anim_state == AnimState.CAPTURING


func rest_position() -> Vector3:
	return _rest_position


func has_model_animation(candidates: PackedStringArray) -> bool:
	## モデル側に候補いずれかのクリップがあるか(テスト・分岐用)。
	return _find_clip_name(candidates) != ""


func snap_to(world_pos: Vector3) -> void:
	## 瞬間移動。初期配置・中断時・ツリー外。
	_kill_tween()
	_anim_state = AnimState.IDLE
	_rest_position = world_pos
	position = world_pos
	_reset_model_visual()
	_try_play_model_clip(IDLE_CLIP_CANDIDATES, true)


func animate_move_to(world_pos: Vector3) -> void:
	## 移動先へ滑らかに動く。ツリー外や距離ゼロは即着地。
	_kill_tween()
	_rest_position = world_pos
	if not is_inside_tree() or position.distance_to(world_pos) < 0.0001:
		position = world_pos
		_anim_state = AnimState.IDLE
		_try_play_model_clip(IDLE_CLIP_CANDIDATES, true)
		move_finished.emit()
		return

	_anim_state = AnimState.MOVING
	# 移動中は待機の上下動を止め、XZ+Y を rest へ。
	position = Vector3(position.x, _rest_position.y, position.z)
	var used_model_clip := _try_play_model_clip(MOVE_CLIP_CANDIDATES, false)
	if not used_model_clip:
		# 代替: わずかに浮きながら進む。
		pass

	var start := position
	var mid := (start + world_pos) * 0.5 + Vector3(0.0, 0.18, 0.0)
	var tween := create_tween()
	_active_tween = tween
	tween.set_parallel(false)
	tween.tween_property(self, "position", mid, MOVE_DURATION_SEC * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", world_pos, MOVE_DURATION_SEC * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_move_tween_finished, CONNECT_ONE_SHOT)


func play_capture() -> void:
	## 取られ演出のあと capture_finished を出す。ツリー外は即完了。
	_kill_tween()
	if not is_inside_tree():
		_anim_state = AnimState.IDLE
		capture_finished.emit()
		return

	_anim_state = AnimState.CAPTURING
	var used_model_clip := _try_play_model_clip(CAPTURE_CLIP_CANDIDATES, false)
	var start_pos := position
	var end_pos := start_pos + Vector3(0.0, -0.15, 0.0)
	var tween := create_tween()
	_active_tween = tween
	tween.set_parallel(true)
	if not used_model_clip:
		# 代替: 沈みつつ透明化(メッシュ material を触る)。
		_fade_meshes(0.0, CAPTURE_DURATION_SEC)
	tween.tween_property(self, "position", end_pos, CAPTURE_DURATION_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3(0.15, 0.15, 0.15), CAPTURE_DURATION_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_capture_tween_finished, CONNECT_ONE_SHOT)


func finish_animations_now() -> void:
	## 進行中の演出を打ち切り、rest 位置へスナップする(中断・テスト用)。
	var was_capturing := _anim_state == AnimState.CAPTURING
	_kill_tween()
	if was_capturing:
		_anim_state = AnimState.IDLE
		capture_finished.emit()
		return
	position = _rest_position
	scale = Vector3.ONE
	_reset_model_visual()
	_anim_state = AnimState.IDLE
	_try_play_model_clip(IDLE_CLIP_CANDIDATES, true)


func _on_move_tween_finished() -> void:
	_active_tween = null
	if _anim_state != AnimState.MOVING:
		return
	position = _rest_position
	_anim_state = AnimState.IDLE
	_try_play_model_clip(IDLE_CLIP_CANDIDATES, true)
	move_finished.emit()


func _on_capture_tween_finished() -> void:
	_active_tween = null
	if _anim_state != AnimState.CAPTURING:
		return
	_anim_state = AnimState.IDLE
	capture_finished.emit()


func _kill_tween() -> void:
	if _active_tween != null and is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = null


func _reset_model_visual() -> void:
	scale = Vector3.ONE
	_fade_meshes(1.0, 0.0)


func _fade_meshes(target_alpha: float, duration: float) -> void:
	## プレースホルダ等の StandardMaterial3D を半透明にする。duration=0 は即時。
	for mesh_inst in _collect_mesh_instances(self):
		var mi := mesh_inst as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		# 共有 material を壊さないよう複製。
		if duration > 0.0 or target_alpha < 0.999:
			mat = mat.duplicate() as StandardMaterial3D
			mi.material_override = mat
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if duration <= 0.0 or not is_inside_tree():
			var c := mat.albedo_color
			c.a = target_alpha
			mat.albedo_color = c
		else:
			var c2 := mat.albedo_color
			c2.a = target_alpha
			var tw := create_tween()
			tw.tween_property(mat, "albedo_color", c2, duration)


func _collect_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_mesh_instances(child))
	return out


func _drive_character_animator(candidates: PackedStringArray) -> void:
	var animator := _find_character_animator(_model_slot)
	if animator == null:
		return
	if candidates == CAPTURE_CLIP_CANDIDATES:
		animator.play(CharacterAnimator.Clip.CAPTURE)
	elif candidates == MOVE_CLIP_CANDIDATES:
		animator.play(CharacterAnimator.Clip.MOVE)
	else:
		animator.play(CharacterAnimator.Clip.IDLE)


static func _find_character_animator(root: Node) -> CharacterAnimator:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CharacterAnimator:
			return n as CharacterAnimator
		for c in n.get_children():
			stack.append(c)
	return null


func _try_play_model_clip(candidates: PackedStringArray, only_if_idle_loop: bool) -> bool:
	## 対応クリップがあれば再生。無ければ false(呼び出し側が代替へ)。
	## AnimationPlayer を持たない VRM には、humanoid の役割で動く共通アニメを載せる。
	## 位置の演出は呼び出し側の Tween が持つので、ここは体の姿勢だけを切り替える。
	_drive_character_animator(candidates)
	var player := _find_animation_player(_model_slot)
	if player == null:
		return false
	var clip := _find_clip_name(candidates)
	if clip == "":
		return false
	if only_if_idle_loop:
		# すでに同じ待機を再生中なら触らない。
		if player.current_animation == clip and player.is_playing():
			return true
	if player.has_animation(clip):
		player.play(clip)
		return true
	return false


func _find_clip_name(candidates: PackedStringArray) -> String:
	var player := _find_animation_player(_model_slot)
	if player == null:
		return ""
	for name in candidates:
		if player.has_animation(name):
			return name
	# AnimationLibrary 経由(Godot 4)も拾う。
	var list := player.get_animation_list()
	for name in candidates:
		if list.has(name):
			return name
	return ""


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
