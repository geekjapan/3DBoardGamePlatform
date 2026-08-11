# ADR 0001: ゲームエンジンに Godot 4 を採用

## Status

Accepted (2026-08-11)

## Context

3Dボードゲームプラットフォーム(チェス・将棋、キャラ駒、発話機能)のエンジン選定。候補は Unity / Godot / Unreal。開発は AI コーディングエージェント(Claude Code)主体で行うため、エージェントがテキストとCLIだけで開発を完結できることが最重要の選定軸だった。

## Decision

Godot 4.x + GDScript を採用する。

## Consequences

- シーン(.tscn)・リソース(.tres)がテキスト形式のため、エージェントが直接読み書き・diff確認できる
- `godot --headless --script` によりルールエンジンのテストを CLI で完結できる
- Mac / Windows へのデスクトップ書き出しが標準機能で足りる
- Unreal 級のグラフィックス表現は得られない(個人用途では許容)
- アセットエコシステムは Unity より小さい。VRM は godot-vrm アドオンで補う(ADR 0002)
