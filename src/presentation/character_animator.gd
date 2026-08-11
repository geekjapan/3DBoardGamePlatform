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

## 素立ちの補正。VRM は T ポーズが基準なので、そのまま置くと腕が真横に
## 広がったカカシになる。常に適用してから、下のクリップを重ねる。
##
## 軸は実測で決めた。上腕は X の正回転で下がり(左右とも同符号)、Y は捻り、
## Z は前後振り。肘は X の正回転で前へ曲がる。試験用モデルと安比の両方で
## 同じ挙動だったので、humanoid の役割で書けば他のモデルにもそのまま効く。
const BASE_POSE := {
	"LeftUpperArm": Vector3(70.0, 0.0, 6.0),
	"RightUpperArm": Vector3(70.0, 0.0, -6.0),
	"LeftLowerArm": Vector3(12.0, 0.0, 0.0),
	"RightLowerArm": Vector3(12.0, 0.0, 0.0),
}

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
## 駒本体の Tween より長いと、倒れ切る前にノードが消えて動きが途中で切れる。
## PieceNode の MOVE_DURATION_SEC / CAPTURE_DURATION_SEC に合わせる。
const MOVE_DURATION := PieceNode.MOVE_DURATION_SEC
const CAPTURE_DURATION := PieceNode.CAPTURE_DURATION_SEC
## 取られたときに body ごと倒れる角度。骨の傾きだけでは「倒れた」と読めない。
## 足元が原点なので、X 回転がそのまま踵を軸にした転倒になる。
const TOPPLE_DEGREES := 82.0

## 転倒はモデル全体を傾ける。向き(Y 回転)は BoardView が陣営で決めるので触らない。
var _model: Node3D
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
	animator._model = model
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
	for role in BASE_POSE:
		roles[role] = true
	for pose in POSES.values():
		for role in (pose as Dictionary):
			roles[role] = true
	for role in roles:
		var idx := _find_bone_for_role(skeleton, bone_map, role)
		if idx < 0:
			continue
		_bones[role] = idx
		_rest[idx] = skeleton.get_bone_pose_rotation(idx)


static func faces_plus_z(model: Node3D) -> bool:
	## モデルが +Z を向いているか。VRM 規約は -Z だが、MMD から変換したモデルは
	## +Z のまま書き出されることがある。規約を信じると盤の外を向いてしまうので、
	## 骨の左右で実測する。
	##
	## Godot は前方 -Z / 上 +Y / 右 +X。-Z を向くキャラの左手は -X 側に来る。
	## 左手が +X 側にあるなら +Z を向いている。
	if model == null:
		return false
	var skeleton := _find_skeleton(model)
	var bone_map := _find_bone_map(model)
	if skeleton == null:
		return false
	var left := _find_bone_for_role(skeleton, bone_map, "LeftHand")
	var right := _find_bone_for_role(skeleton, bone_map, "RightHand")
	if left < 0 or right < 0:
		# 手が引けなければ足で見る。
		left = _find_bone_for_role(skeleton, bone_map, "LeftFoot")
		right = _find_bone_for_role(skeleton, bone_map, "RightFoot")
	if left < 0 or right < 0:
		return false
	skeleton.force_update_all_bone_transforms()
	return skeleton.get_bone_global_pose(left).origin.x > skeleton.get_bone_global_pose(right).origin.x


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
	_apply_topple(amount if _clip == Clip.CAPTURE else 0.0)


func _apply_topple(amount: float) -> void:
	if _model == null:
		return
	# 倒れ始めはゆっくり、途中から加速させる(棒が倒れる感じ)。
	# 消えるまでに倒れ切るよう、終盤で 1.0 に届く曲線にする。
	var eased := amount * amount * (3.0 - 2.0 * amount)
	_model.rotation.x = deg_to_rad(TOPPLE_DEGREES) * eased


func _apply(pose: Dictionary, amount: float) -> void:
	for role in _bones:
		var idx: int = _bones[role]
		var rest: Quaternion = _rest[idx]
		# 素立ちの補正は常に効かせ、クリップの動きをその上に重ねる。
		var degrees: Vector3 = BASE_POSE.get(role, Vector3.ZERO)
		degrees += (pose.get(role, Vector3.ZERO) as Vector3) * amount
		if degrees == Vector3.ZERO:
			_skeleton.set_bone_pose_rotation(idx, rest)
			continue
		var offset := Quaternion.from_euler(Vector3(
			deg_to_rad(degrees.x),
			deg_to_rad(degrees.y),
			deg_to_rad(degrees.z)
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
