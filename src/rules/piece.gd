class_name Piece
extends RefCounted

## ルール上の駒。種類と所有者だけを持つ(CONTEXT.md の Piece)。

enum Side { WHITE = 0, BLACK = 1 }

## チェスと将棋で共有する安定駒種 ID。既存チェス値は永続化互換のため不変。
enum Kind {
	PAWN = 0,
	KNIGHT = 1,
	BISHOP = 2,
	ROOK = 3,
	QUEEN = 4,
	KING = 5,
	SHOGI_PAWN = 6,
	SHOGI_LANCE = 7,
	SHOGI_KNIGHT = 8,
	SHOGI_SILVER = 9,
	SHOGI_GOLD = 10,
	SHOGI_BISHOP = 11,
	SHOGI_ROOK = 12,
	SHOGI_KING = 13,
	SHOGI_PROMOTED_PAWN = 14,
	SHOGI_PROMOTED_LANCE = 15,
	SHOGI_PROMOTED_KNIGHT = 16,
	SHOGI_PROMOTED_SILVER = 17,
	SHOGI_HORSE = 18,
	SHOGI_DRAGON = 19,
}

## 成駒から対応する将棋基本駒への唯一の変換表。
const PROMOTED_TO_BASE: Dictionary = {
	Kind.SHOGI_PROMOTED_PAWN: Kind.SHOGI_PAWN,
	Kind.SHOGI_PROMOTED_LANCE: Kind.SHOGI_LANCE,
	Kind.SHOGI_PROMOTED_KNIGHT: Kind.SHOGI_KNIGHT,
	Kind.SHOGI_PROMOTED_SILVER: Kind.SHOGI_SILVER,
	Kind.SHOGI_HORSE: Kind.SHOGI_BISHOP,
	Kind.SHOGI_DRAGON: Kind.SHOGI_ROOK,
}


## Side の値
var side: int
## Kind の値
var kind: int


func _init(p_side: int = Side.WHITE, p_kind: int = Kind.PAWN) -> void:
	side = p_side
	kind = p_kind


func duplicate_piece() -> Piece:
	return Piece.new(side, kind)


static func opposite(p_side: int) -> int:
	return Side.BLACK if p_side == Side.WHITE else Side.WHITE


static func base_kind_for_promoted(promoted_kind: int) -> int:
	## 基本駒や未知値は -1。数値差分による推測はしない。
	return int(PROMOTED_TO_BASE.get(promoted_kind, -1))
