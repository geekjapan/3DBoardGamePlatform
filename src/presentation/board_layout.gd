class_name BoardLayout
extends RefCounted

## 盤の論理座標(Vector2i: file=x, rank=y, a1=(0,0))と 3D ワールド座標の変換。
## 盤は原点中心。白側(rank 0)が +Z、黒側が -Z。マス一辺は square_size。

const DEFAULT_SQUARE_SIZE := 1.0


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


static func is_light_square(pos: Vector2i) -> bool:
	## a1 が暗色になる標準チェス配色 (file+rank が偶数なら暗)。
	return (pos.x + pos.y) % 2 != 0
