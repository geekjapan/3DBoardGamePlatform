# 3DBoardGamePlatform

Godot 4 プロジェクト。リポジトリ直下を Godot で開く。

## テスト

```sh
tests/run.sh
```

終了コードは失敗数(255 で頭打ち)。すべて成功なら 0。
Godot の実行ファイルは `GODOT` 環境変数で上書きできる。

テストは `tests/test_*.gd` に置き、`tests/case.gd` を継承して `test_` で始まる
メソッドを書く。判定は `check` / `check_eq` を使う(失敗しても止まらず記録され、
失敗数が終了コードになる)。テストフレームワークは使わない。
