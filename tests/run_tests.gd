extends SceneTree

## ヘッドレステストランナー。呼び出しは `tests/run.sh` 経由。
##
## `tests/test_*.gd` を集め、`test_` で始まるメソッドをすべて実行する。
## 終了コードは失敗数(255 で頭打ち)。
##
## ソースから実行する前提(書き出し済みビルドでは .gd が .gdc になり探索できない)。
##
## GDScript のランタイムエラーは GDScript 側から捕捉できず、エラーの起きた関数だけが
## 中断して呼び出し元は素通りする。そのため実行境界(`tests/run.sh`)で出力を見て
## 失敗にしている。ここで検知できるのは読み込み失敗と `check` の失敗のみ。

const TESTS_DIR := "res://tests"


func _initialize() -> void:
	var ran := 0
	var failed := 0

	for path in _test_files():
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s — スクリプトを読み込めませんでした" % path.get_file())
			continue
		for method_name in _test_methods(script):
			ran += 1
			var test_case: Variant = script.new()
			test_case.call(method_name)
			for message: String in test_case.failures:
				failed += 1
				print("FAIL %s::%s — %s" % [path.get_file(), method_name, message])

	print("%d tests, %d failures" % [ran, failed])
	quit(mini(failed, 255))


func _test_files() -> PackedStringArray:
	var paths := PackedStringArray()
	for file_name in DirAccess.get_files_at(TESTS_DIR):
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			paths.append(TESTS_DIR.path_join(file_name))
	paths.sort()
	return paths


func _test_methods(script: GDScript) -> PackedStringArray:
	var names := PackedStringArray()
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names
