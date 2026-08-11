class_name CharacterAnimator
extends Node

## VRM キャラクターの体を動かす。1 つの動きの定義を、リグの違う複数のモデルで使い回す。
##
## 要点はボーン名を直接書かないこと。VRM の humanoid_bone_mapping は「役割」から
## そのモデル固有のボーン名へ変換する。例えばこのプロジェクトの試験用モデルでは
## LeftUpperArm の実体は "Left arm" で、標準名では引けない。役割で引けば、
## 命名の違うモデルにも同じ動きがそのまま載る。
##
## 位置と拡縮の演出(移動・取られ)は PieceNode の Tween が持つ。ここは体の姿勢だけ。

enum Clip { IDLE, MOVE, CAPTURE }

## 動きの定義。役割 → [X 軸, Y 軸, Z 軸] の振れ幅(度)。
## IDLE は sin で往復、MOVE と CAPTURE は一度だけ傾けて戻す。
const POSES := {
	Clip.IDLE: {
		"Spine": Vector3(1.6, 0.0, 0.0),
		"Chest": Vector3(1.2, 0.0, 0.0),
		"Head": Vector3(-1.0, 1.5, 0.0),
		"LeftUpperArm": Vector3(0.0, 0.0, 2.0),
		"RightUpperArm": Vector3(0.0, 0.0, -2.0),
	},
	Clip.MOVE: {
		"Spine": Vector3(-9.0, 0.0, 0.0),
		"Chest": Vector3(-5.0, 0.0, 0.0),
		"Head": Vector3(4.0, 0.0, 0.0),
	},
	Clip.CAPTURE: {
		"Spine": Vector3(22.0, 0.0, 0.0),
		"Chest": Vector3(12.0, 0.0, 0.0),
		"Head": Vector3(18.0, 0.0, 0.0),
		"LeftUpperArm": Vector3(0.0, 0.0, 24.0),
		"RightUpperArm": Vector3(0.0, 0.0, -24.0),
	},
}

const IDLE_PERIOD := 3.4
const MOVE_DURATION := 0.45
const CAPTURE_DURATION := 0.5

var _skeleton: Skeleton3D
## 役割 → ボーン番号。解決できた役割だけ入る。
var _bones: Dictionary = {}
## ボーン番号 → 元の姿勢。毎フレームここからの差分で上書きする。
var _rest: Dictionary = {}
var _clip: int = Clip.IDLE
var _elapsed: float = 0.0
var _phase: float = 0.0


static func attach_to(model: Node3D) -> CharacterAnimator:
	## humanoid の対応が取れるモデルにだけ付く。取れなければ null(仮の見た目や
	## 素の glTF は対象外)。
	if model == null:
		return null
	var skeleton := _find_skeleton(model)
	var bone_map := _find_bone_map(model)
	if skeleton == null or bone_map == null:
		return null
	var animator := CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	animator._bind(skeleton, bone_map)
	if animator._bones.is_empty():
		animator.free()
		return null
	model.add_child(animator)
	return animator


func resolved_roles() -> PackedStringArray:
	var out := PackedStringArray()
	for role in _bones:
		out.append(role)
	out.sort()
	return out


func play(clip: int) -> void:
	if clip == _clip:
		return
	_clip = clip
	_elapsed = 0.0


func _bind(skeleton: Skeleton3D, bone_map: BoneMap) -> void:
	_skeleton = skeleton
	# 同じ見た目が並んでも呼吸が揃わないよう、個体ごとに位相をずらす。
	_phase = float(skeleton.get_instance_id() % 1000) / 1000.0 * TAU
	var roles := {}
	for pose in POSES.values():
		for role in (pose as Dictionary):
			roles[role] = true
	for role in roles:
		var idx := _find_bone_for_role(skeleton, bone_map, role)
		if idx < 0:
			continue
		_bones[role] = idx
		_rest[idx] = skeleton.get_bone_pose_rotation(idx)


static func _find_bone_for_role(skeleton: Skeleton3D, bone_map: BoneMap, role: String) -> int:
	## VRM の骨格には 2 通りある。godot-vrm がボーンを標準名へ改名したものと、
	## 変換元の名前のままのもの。試験用モデルでは BoneMap が変換元の "Left arm" を
	## 指す一方、骨格側は標準名 "LeftUpperArm" に改名されていた。両方試す。
	var idx := skeleton.find_bone(role)
	if idx >= 0:
		return idx
	if bone_map == null:
		return -1
	var mapped := bone_map.get_skeleton_bone_name(role)
	if mapped == "":
		return -1
	return skeleton.find_bone(mapped)


func _process(delta: float) -> void:
	if _skeleton == null or _bones.is_empty():
		return
	_elapsed += delta
	var amount := 0.0
	var pose: Dictionary = POSES.get(_clip, {})
	match _clip:
		Clip.IDLE:
			amount = sin(_elapsed * TAU / IDLE_PERIOD + _phase)
		Clip.MOVE:
			amount = _pulse(_elapsed / MOVE_DURATION)
			if _elapsed >= MOVE_DURATION:
				play(Clip.IDLE)
		Clip.CAPTURE:
			# 取られる演出は戻さない。倒れたまま消える。
			amount = minf(_elapsed / CAPTURE_DURATION, 1.0)
	_apply(pose, amount)


func _apply(pose: Dictionary, amount: float) -> void:
	for role in _bones:
		var idx: int = _bones[role]
		var rest: Quaternion = _rest[idx]
		var degrees: Vector3 = pose.get(role, Vector3.ZERO)
		if degrees == Vector3.ZERO:
			_skeleton.set_bone_pose_rotation(idx, rest)
			continue
		var offset := Quaternion.from_euler(Vector3(
			deg_to_rad(degrees.x * amount),
			deg_to_rad(degrees.y * amount),
			deg_to_rad(degrees.z * amount)
		))
		_skeleton.set_bone_pose_rotation(idx, rest * offset)


static func _pulse(t: float) -> float:
	## 0 → 1 → 0。行って戻る一度きりの動き。
	return sin(clampf(t, 0.0, 1.0) * PI)


static func _find_skeleton(root: Node) -> Skeleton3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n as Skeleton3D
		for c in n.get_children():
			stack.append(c)
	return null


static func _find_bone_map(model: Node3D) -> BoneMap:
	## VRM は vrm_meta.humanoid_bone_mapping に役割 → ボーン名を持つ。
	var meta: Variant = model.get("vrm_meta")
	if meta == null:
		return null
	var mapping: Variant = (meta as Object).get("humanoid_bone_mapping")
	return mapping as BoneMap
