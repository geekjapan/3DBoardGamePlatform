# 3DBoardGamePlatform

Godot 4 で作る、キャラクター駒でチェスと将棋を遊ぶ 3D ボードゲームです。ゲーム、
先手・後手のチーム、駒の見た目、発話方法を選んで対局します。3D モデルがなくても、
プレースホルダの駒でそのまま遊べます。

## できること

- **チェスと将棋** — 起動時に 8×8 のチェスまたは 9×9 の将棋を選びます。将棋では
  成り、持ち駒、打つ手を扱います。
- **チーム編成** — 先手・後手それぞれにチームを選び、駒種ごとの Character 割当を
  編集・保存できます。
- **3D の盤と駒** — 盤をクリックして着手し、ドラッグで視点を動かせます。VRM モデルを
  ローカルに置けばキャラクター駒として表示し、ない場合はプリミティブで代替します。
- **発話** — 定型セリフ、OS のテキスト読み上げ、生成 API による短いセリフの 3 モードを
  選べます。キーや通信が使えないときは定型セリフへ戻ります。
- **AI 対戦** — チェスは UCI、将棋は USI の外部エンジンを使えます。エンジンなしでも
  二人対戦は通常どおり遊べます。

## 起動する

必要なのは [Godot 4.7.1](https://godotengine.org/download/) です。AI 対戦、生成発話、
キャラクターモデルはいずれも任意です。

```sh
git clone https://github.com/geekjapan/3DBoardGamePlatform.git
cd 3DBoardGamePlatform
godot --editor --path .
```

Godot の Project Manager から、このリポジトリの `project.godot` を開いても起動できます。
エディタで実行すると、まずゲーム、次に先手・後手のチームを選択します。

対局中は、盤上の自分の駒と移動先を順にクリックして指します。将棋の持ち駒は HUD から
選び、成りの選択肢がある手ではダイアログで決めます。ドラッグで盤を見やすい向きにして、
設定画面からその視点を保存できます。

## AI 対戦を使う

対局開始後に左側の「設定」を開き、AI を有効にしてエンジン実行ファイルを指定します。
エンジンのパスと強さは、チェス用（UCI）と将棋用（USI）で別々に保存されます。

- チェスには UCI 対応エンジンが必要です。macOS では Stockfish を
  `brew install stockfish` で入れ、通常は `/opt/homebrew/bin/stockfish` を指定します。
- 将棋には USI 対応エンジンが必要です。エンジンは同梱しないため、入手元の手順に従って
  インストールし、その実行ファイルを指定してください。

外部エンジンが見つからない場合、AI は有効にできず、対局は二人対戦として続きます。
設計上の詳細は [ADR 0003](docs/adr/0003-external-uci-engine-for-ai.md) を参照してください。

## 発話モード

設定画面で、次のいずれかを選べます。

- **定型** — キャラクター定義のセリフを表示します。追加設定は不要です。
- **音声** — OS のテキスト読み上げ機能でセリフを読み上げます。
- **生成** — OpenAI Chat Completions API に短いセリフを要求します。API キーは
  `BOARDGAME_LLM_API_KEY` または `OPENAI_API_KEY` 環境変数に設定し、ゲームの設定には保存しません。

生成に失敗した場合、時間切れの場合、またはキーがない場合は、定型セリフで続行します。

## キャラクターモデル

このリポジトリとリリースには、3D キャラクターモデルおよびその付随アセットを含めません。
`assets/models/` はローカル専用の Git 非追跡ディレクトリです。モデルがない状態でも、
すべてのルールと対局操作を試せます。

ローカルでモデルを使う場合は、利用・変換・表示が許可されたアセットだけを用いてください。
VRM の取り込みと PMX からの変換は [モデル取り込み手順](docs/model-import.md) にまとめています。
キャラクター名や設定は、関連する権利者との提携・承認を示すものではありません。

## 開発とテスト

リポジトリ直下で次を実行します。

```sh
tests/run.sh
```

終了コード `0` は全テスト成功です。`GODOT` 環境変数で Godot の実行ファイルを上書きできます。
GitHub Actions は Godot 4.7.1 に加えて、GPL-3.0の[Apery Rust版](https://github.com/HiraokaTakuya/apery_rust)を固定コミット `8e64bc427bff033a38f1b60b9013ad2d62f88db7` から、評価関数不要の`material`構成でビルドする。CIではこの実機USIエンジンを必須として同じテスト入口を実行するため、エンジン未設定によるスモークテストのスキップは失敗になる。エンジンのバイナリや評価関数はリポジトリへ同梱しない。

ローカルの通常テストは、`USI_ENGINE_PATH`または`BOARDGAME_USI_ENGINE`が未設定なら実機スモークテストをスキップする。実機連携も再現したい場合は、Aperyを`cargo build --release --locked --no-default-features --features material`でビルドし、次のように実行する。

実機USIの有限対局で失敗した場合は、`USI_DIAGNOSTICS_DIR`で指定したディレクトリへ`usi-failure-diagnostics.json`が出力される。JSONには局面名、手数、USI position、結果分類、エンジンID、経過時間、返答手、最大2000文字のトランスクリプト要約のみを記録する。CIではテスト失敗時にこのJSONとテストログを成果物として取得できる。

通常のpush・PRでは実機USI耐性テストを8手で実行する。より長い検証はGitHub Actionsの手動実行から`usi_soak_plies`を指定して実行でき、上限は80手である。ローカルでも`USI_SOAK_PLIES=40`のように指定できる。

```sh
USI_ENGINE_REQUIRED=1 \
USI_ENGINE_PATH=/path/to/apery \
./tests/run.sh
```

用語の定義は [CONTEXT.md](CONTEXT.md)、設計判断は [docs/adr/](docs/adr/) を参照してください。

## ライセンスと第三者コード

本プロジェクトの独自素材は [MIT License](LICENSE) です。VRM と MToon の同梱アドオンには
それぞれのライセンスが適用されます。詳細は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を
参照してください。キャラクターモデルは配布しません。
