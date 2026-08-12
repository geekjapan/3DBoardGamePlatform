#!/usr/bin/env bash
# ヘッドレステスト実行。終了コードは失敗数(255 で頭打ち)、成功なら 0。
#
# GDScript のランタイムエラーはエラーの起きた関数だけを中断し、呼び出し元は
# 素通りするため、ランナー内からは検知できない。出力に現れた時点でここで失敗にする。
#
# Godot の実行ファイルは $GODOT で上書きできる。
set -u
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT:-godot}"

# class_name はグローバルクラスキャッシュが古いとヘッドレスで解決できない。
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

log=$(mktemp "${TMPDIR:-/tmp}/godot-tests.XXXXXX")
trap 'rm -f "$log"' EXIT

"$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if grep -q 'SCRIPT ERROR' "$log"; then
	echo "FAIL: テスト実行中にスクリプトエラーが発生しました" >&2
	if [ "$status" -eq 0 ]; then status=1; fi
fi

exit "$status"
