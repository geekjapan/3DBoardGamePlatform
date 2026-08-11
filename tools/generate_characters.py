"""assets/models/ の VRM から、キャラクター定義の雛形を作る。

    python3 tools/generate_characters.py [--force]

`data/characters/<id>.json` を無ければ作る。既にあるものは触らない(セリフを
書き換えてしまうため)。`--force` を付けたときだけモデルのパスを貼り直す。

セリフは駒種を問わない汎用のものを入れておく。キャラの性格に合わせて書き換える
のが本来の使い方で、ここで作るのはあくまで出発点。CONTEXT.md の Character は
「モデル・性格・セリフ表を持つ実体」なので、モデルだけの定義は半端な状態になる。
"""

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(REPO, "assets", "models")
CHARACTERS_DIR = os.path.join(REPO, "data", "characters")

# 出発点のセリフ。どのキャラでも成立する言い回しにしてある。
DEFAULT_LINES = {
    "moved": ["行くよ。", "ここだね。", "次はどうする?"],
    "captured": ["もらった!", "そこだ!", "決まりだね。"],
    "captured_by": ["やられた…!", "くっ…!", "まだ終わらない。"],
    "check": ["王手!", "逃げ場はある?", "詰めるよ。"],
    "promoted": ["力が湧いてくる!", "ここからが本番。"],
    "game_over": ["いい勝負だった。", "また指そう。"],
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="既存の model を貼り直す")
    args = parser.parse_args()

    if not os.path.isdir(MODELS_DIR):
        sys.exit("モデルディレクトリが無い: %s" % MODELS_DIR)
    os.makedirs(CHARACTERS_DIR, exist_ok=True)

    created, updated, kept = [], [], []
    for entry in sorted(os.listdir(MODELS_DIR)):
        if not entry.lower().endswith(".vrm"):
            continue
        name = os.path.splitext(entry)[0]
        path = os.path.join(CHARACTERS_DIR, name + ".json")
        model = "res://assets/models/%s" % entry

        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
            if args.force and data.get("model") != model:
                data["model"] = model
                with open(path, "w", encoding="utf-8") as handle:
                    json.dump(data, handle, ensure_ascii=False, indent=2)
                updated.append(name)
            else:
                kept.append(name)
            continue

        data = {
            "id": name,
            "display_name": name,
            "personality": "",
            "model": model,
            "lines": DEFAULT_LINES,
        }
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
        created.append(name)

    print("作成 %d / 更新 %d / 既存のまま %d" % (len(created), len(updated), len(kept)))
    if created:
        print("作成:", ", ".join(created[:12]) + (" ..." if len(created) > 12 else ""))
    print("\nセリフと性格は雛形のまま。data/characters/*.json を編集して味付けする。")


main()
