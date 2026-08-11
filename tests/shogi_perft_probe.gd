extends SceneTree

## Issue #25 / D-006: 初期将棋盤 perft の隔離 depth4 probe。

const EXPECTED := {
	1: 30,
	2: 900,
	3: 25470,
	4: 719731,
}


func _initialize() -> void:
	var board := ShogiBoard.start()
	for depth in range(1, 5):
		var actual := board.perft(depth)
		if actual != EXPECTED[depth]:
			assert(false, "shogi perft(%d): expected %d, got %d" % [depth, EXPECTED[depth], actual])
			quit(1)
			return
		print("shogi perft(%d) = %d" % [depth, actual])
	quit(0)
