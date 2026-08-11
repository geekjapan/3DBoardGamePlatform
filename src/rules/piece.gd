class_name Piece
extends RefCounted

## ルール上の駒。種類と所有者だけを持つ(CONTEXT.md の Piece)。

enum Side { WHITE = 0, BLACK = 1 }

## チェスの駒種。将棋を載せるときはここに足す(桂・銀・金・香など)。
enum Kind { PAWN = 0, KNIGHT = 1, BISHOP = 2, ROOK = 3, QUEEN = 4, KING = 5 }


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
