class_name GameResult
extends RefCounted

## GameSession が所有する終局結果。
##
## 終局理由だけでなく、勝敗の向きもここに保持する。ステイルメイトや
## 通常の千日手のような引き分けでは両方の side を NO_SIDE とする。

enum Reason { CHECKMATE, STALEMATE, RESIGN, SENNICHITE }

const NO_SIDE := -1

var reason: int
var winner_side: int
var loser_side: int


func _init(
	p_reason: int,
	p_winner_side: int = NO_SIDE,
	p_loser_side: int = NO_SIDE,
) -> void:
	reason = p_reason
	winner_side = p_winner_side
	loser_side = p_loser_side
