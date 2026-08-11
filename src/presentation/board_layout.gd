class_name BoardLayout
extends RefCounted

## 盤の論理座標(Vector2i: file=x, rank=y, a1=(0,0))と 3D ワールド座標の変換。
## 盤は原点中心。白側(rank 0)が +Z、黒側が -Z。マス一辺は square_size。

const DEFAULT_SQUARE_SIZE := 1.0
const INVALID_SQUARE := Vector2i(-1, -1)


static func square_to_world(pos: Vector2i, square_size: float = DEFAULT_SQUARE_SIZE) -> Vector3:
	var half := (8.0 * square_size) * 0.5
	var x := (float(pos.x) + 0.5) * square_size - half
	var z := half - (float(pos.y) + 0.5) * square_size
	return Vector3(x, 0.0, z)


static func world_to_square(world: Vector3, square_size: float = DEFAULT_SQUARE_SIZE) -> Vector2i:
	var half := (8.0 * square_size) * 0.5
	var file := int(floor((world.x + half) / square_size))
	var rank := int(floor((half - world.z) / square_size))
	return Vector2i(file, rank)


static func is_in_board(pos: Vector2i, width: int = 8, height: int = 8) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


static func ray_to_square(
	origin: Vector3,
	direction: Vector3,
	square_size: float = DEFAULT_SQUARE_SIZE,
	width: int = 8,
	height: int = 8,
) -> Vector2i:
	## y=0 平面との交点をマスに変換。盤外・平行・背面は INVALID_SQUARE。
	if absf(direction.y) < 0.000001:
		return INVALID_SQUARE
	var t := -origin.y / direction.y
	if t < 0.0:
		return INVALID_SQUARE
	var hit := origin + direction * t
	var pos := world_to_square(hit, square_size)
	if not is_in_board(pos, width, height):
		return INVALID_SQUARE
	return pos


static func pick_square(
	origin: Vector3,
	direction: Vector3,
	occupied: Array,
	square_size: float = DEFAULT_SQUARE_SIZE,
	width: int = 8,
	height: int = 8,
) -> Vector2i:
	## 駒の簡易球ヒットを優先し、外れたら盤面平面へフォールバック。
	## occupied: 駒のある Vector2i の配列。
	var dir := direction.normalized()
	var best_t := INF
	var best := INVALID_SQUARE
	var radius := 0.42 * square_size
	var piece_y := 0.35 * square_size
	for item in occupied:
		var pos: Vector2i = item
		var center := square_to_world(pos, square_size) + Vector3(0.0, piece_y, 0.0)
		var t := _ray_sphere_t(origin, dir, center, radius)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = pos
	if best != INVALID_SQUARE:
		return best
	return ray_to_square(origin, dir, square_size, width, height)


static func _ray_sphere_t(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	## dir は正規化済み。ヒットしなければ -1。
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	var t0 := -b - s
	if t0 >= 0.0:
		return t0
	var t1 := -b + s
	if t1 >= 0.0:
		return t1
	return -1.0


static func is_light_square(pos: Vector2i) -> bool:
	## a1 が暗色になる標準チェス配色 (file+rank が偶数なら暗)。
	return (pos.x + pos.y) % 2 != 0
