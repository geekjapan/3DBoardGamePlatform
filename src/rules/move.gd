class_name Move
extends RefCounted

## 1 手。通常移動・キャスリング・アンパッサン・昇格・将棋の打ちを表現する。

const NO_SQUARE := Vector2i(-1, -1)


var from: Vector2i = NO_SQUARE
var to: Vector2i = NO_SQUARE
## 昇格先の Piece.Kind。昇格しない手は -1。
var promotion: int = -1
var is_castling: bool = false
var is_en_passant: bool = false
var is_drop: bool = false
## 打つ基本駒種。通常手は常に -1。
var drop_kind: int = -1


func _init(
	p_from: Vector2i = NO_SQUARE,
	p_to: Vector2i = NO_SQUARE,
	p_promotion: int = -1,
	p_is_castling: bool = false,
	p_is_en_passant: bool = false,
	p_is_drop: bool = false,
	p_drop_kind: int = -1,
) -> void:
	from = p_from
	to = p_to
	promotion = p_promotion
	is_castling = p_is_castling
	is_en_passant = p_is_en_passant
	is_drop = p_is_drop
	drop_kind = p_drop_kind


static func drop(kind: int, p_to: Vector2i) -> Move:
	## 将棋の打つ手を作る唯一の正規入口。合法性は盤が現在局面に対して検証する。
	return Move.new(NO_SQUARE, p_to, -1, false, false, true, kind)


func equals(other: Move) -> bool:
	return (
		from == other.from
		and to == other.to
		and promotion == other.promotion
		and is_castling == other.is_castling
		and is_en_passant == other.is_en_passant
		and is_drop == other.is_drop
		and drop_kind == other.drop_kind
	)


func to_uci() -> String:
	## テスト用の簡易 UCI 風表記 (e2e4, e7e8q, e1g1 など)。
	if is_drop:
		return "drop%s" % _sq(to)
	var s := "%s%s" % [_sq(from), _sq(to)]
	if promotion >= 0:
		s += _promo_char(promotion)
	return s


static func _sq(pos: Vector2i) -> String:
	return "%s%d" % [char(97 + pos.x), pos.y + 1]


static func _promo_char(kind: int) -> String:
	match kind:
		Piece.Kind.QUEEN:
			return "q"
		Piece.Kind.ROOK:
			return "r"
		Piece.Kind.BISHOP:
			return "b"
		Piece.Kind.KNIGHT:
			return "n"
		_:
			return "?"
