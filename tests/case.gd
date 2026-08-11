extends RefCounted

## テストケースの基底クラス。
##
## テストファイルは `tests/test_*.gd` に置き、このスクリプトを継承して
## `test_` で始まるメソッドを定義する。ランナーがメソッドごとに
## 新しいインスタンスを作って呼び出し、`failures` を回収する。
##
## 失敗しても即座に停止せず記録するため、Godot 組み込みの `assert()` ではなく
## 以下のヘルパーを使う(ランナーが失敗数を終了コードで返すため)。

var failures: PackedStringArray = PackedStringArray()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])
