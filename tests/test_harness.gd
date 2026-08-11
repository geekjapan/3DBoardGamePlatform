extends "res://tests/case.gd"

## ランナー自身の自己検証。失敗が記録され、成功が記録されないことを確かめる。

const Case := preload("res://tests/case.gd")


func test_failing_check_is_recorded() -> void:
	var other: Case = Case.new()
	other.check(false, "boom")
	check_eq(other.failures.size(), 1, "失敗した check は記録される")
	check_eq(other.failures[0], "boom", "メッセージが保持される")


func test_passing_check_is_silent() -> void:
	var other: Case = Case.new()
	other.check(true, "should not appear")
	check_eq(other.failures.size(), 0, "成功した check は何も記録しない")


func test_check_eq_reports_both_values() -> void:
	var other: Case = Case.new()
	other.check_eq(1, 2, "mismatch")
	check_eq(other.failures.size(), 1, "不一致は失敗として記録される")
	check(
		other.failures[0].contains("expected 2") and other.failures[0].contains("got 1"),
		"期待値と実際値の両方がメッセージに出る (got: %s)" % other.failures[0]
	)
