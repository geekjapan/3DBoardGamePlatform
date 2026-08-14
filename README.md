# 3DBoardGamePlatform

Godot 4 プロジェクト。リポジトリ直下を Godot で開く。

## テスト

```sh
tests/run.sh
```

終了コードは失敗数（255 で頭打ち）で、すべて成功した場合は `0` になる。Godot の実行ファイルは `GODOT` 環境変数で上書きできる。テストは `tests/test_*.gd` に置き、`tests/case.gd` を継承して `test_` で始まるメソッドを書く。判定には `check` / `check_eq` を使う。失敗しても直ちに停止せず、失敗数を記録する。テストフレームワークは使わない。

## 継続的テスト

GitHub Actions は `main` への push と pull request ごとに、Ubuntu 24.04 上で **Godot 4.7.1** を明示的に導入し、ローカルと同じ `tests/run.sh` を実行する。テスト失敗または GDScript の実行エラーはジョブを失敗させる。失敗した場合は `godot-test.log` をワークフロー成果物として確認できる。

実機USIエンジンを必要とするスモークテストは、CIでは `USI_ENGINE_PATH` / `BOARDGAME_USI_ENGINE` を設定しないため正常なスキップとして扱う。ローカルで実機検証する場合だけ、これらの環境変数へUSIエンジンの実行ファイルを設定する。
