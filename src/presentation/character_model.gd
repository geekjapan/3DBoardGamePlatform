class_name CharacterModel
extends RefCounted

## キャラクターの 3D モデル(VRM / glTF)を読み込み、盤のマスに収まる大きさに整える。
##
## 読めない・指定が無い場合は null を返す。呼び出し側は仮の見た目に落とす。
## モデルの欠品でクラッシュさせないのが方針(ADR 0002)。
##
## 同じキャラクターを複数の駒に割り当てても、PackedScene は 1 回だけ読み込んで
## instantiate を繰り返す。31MB 級のモデルを駒の数だけ読み直さないため。

## 駒として置いたときの高さ(ワールド単位)。マス一辺 1.0 に対する見た目の基準。
const TARGET_HEIGHT := 1.15
## 足元がマスに埋まらないよう、AABB の下端を Y=0 に合わせる。
const GROUND_EPSILON := 0.001
## 実寸合わせが必要な見た目に付ける印。仮の見た目と区別する。
const META_NEEDS_FIT := "character_model_needs_fit"

## パス → PackedScene。読み込み失敗も null で記憶し、毎回試さない。
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func is_available(path: String) -> bool:
	return _load_scene(path) != null


static func create(path: String) -> Node3D:
	## 指定モデルのインスタンスを返す。読めなければ null。
	var scene := _load_scene(path)
	if scene == null:
		return null
	var node := scene.instantiate()
	if not (node is Node3D):
		# 3D でないものが入っていたら見た目として使えない。
		node.free()
		return null
	var model := node as Node3D
	model.set_meta(META_NEEDS_FIT, true)
	return model


static func fit_to_square(model: Node3D, square_size: float) -> void:
	## モデルの実寸を測り、駒として妥当な高さに揃えて足元を接地させる。
	##
	## 実寸はモデル内部の相対座標で測る。ワールド座標だとツリーに入るまで
	## 確定せず、build_from の途中では測れない。何度呼んでも同じ結果になる。
	if model == null:
		return
	var box := _local_aabb(model)
	if box.size.y <= 0.0:
		return
	var factor := (TARGET_HEIGHT * square_size) / box.size.y
	model.scale = Vector3.ONE * factor
	# 原点が足元とは限らない。拡大後の下端を盤面(親の原点)へ合わせる。
	model.position.y = -box.position.y * factor + GROUND_EPSILON


static func _load_scene(path: String) -> PackedScene:
	var key := path.strip_edges()
	if key == "":
		return null
	if _cache.has(key):
		return _cache[key] as PackedScene
	var scene: PackedScene = null
	if ResourceLoader.exists(key):
		scene = ResourceLoader.load(key) as PackedScene
	_cache[key] = scene
	return scene


static func _local_aabb(root: Node3D) -> AABB:
	## root を原点とした実寸。root 自身の scale / position は含めない。
	var out := AABB()
	var first := true
	# (ノード, root からの相対 Transform)
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		if node is VisualInstance3D:
			var box: AABB = xform * (node as VisualInstance3D).get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xform * (c as Node3D).transform])
			else:
				stack.append([c, xform])
	return out
