"""フォルダ配下の PMX をまとめて VRM へ変換する Blender スクリプト。

使い方:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/batch_pmx_to_vrm.py -- <入力ルート> <出力ディレクトリ> [身長]

武器や小物も同じフォルダに入っているので、**humanoid ボーンを割り当てられたものだけ**
を書き出す。ファイル名で判定しない(`本` `武器` のような名前は当てにならないし、
キャラの名前は多言語で網羅できない)。

同名のキャラが複数フォルダにある場合は、いちばん大きいファイルだけを採る。
作りの新しい・情報量の多いものが残る想定。

1 体ごとに Blender の状態を初期化する。前のモデルが残っていると身長の測定が狂う。
途中で失敗しても他の体には影響させず、最後に一覧を出す。
"""

import os
import sys
import glob

import addon_utils
import bpy

MMD_IMPORT_SCALE = 0.08
DEFAULT_TARGET_HEIGHT = 1.6
MMD_TOOLS = "bl_ext.blender_org.mmd_tools"
VRM_ADDON = "bl_ext.blender_org.vrm"

REQUIRED_BONES = {
    "hips", "spine", "chest", "neck", "head",
    "leftUpperArm", "leftLowerArm", "leftHand",
    "rightUpperArm", "rightLowerArm", "rightHand",
    "leftUpperLeg", "leftLowerLeg", "leftFoot",
    "rightUpperLeg", "rightLowerLeg", "rightFoot",
}


def argv():
    if "--" not in sys.argv:
        sys.exit("引数がない。-- のあとに <入力ルート> <出力先> [身長] を渡す")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) < 2:
        sys.exit("入力ルートと出力先の 2 つが要る")
    height = float(args[2]) if len(args) > 2 else DEFAULT_TARGET_HEIGHT
    return os.path.expanduser(args[0]), os.path.expanduser(args[1]), height


def pick_sources(root):
    """同名は最大サイズのものだけ残す。小物は humanoid 判定で後段が落とす。"""
    best = {}
    for path in glob.glob(os.path.join(root, "**", "*.pmx"), recursive=True):
        name = os.path.splitext(os.path.basename(path))[0]
        size = os.path.getsize(path)
        if name not in best or size > best[name][0]:
            best[name] = (size, path)
    # 小さすぎるものは小物。読み込む価値がない。
    return sorted(
        (path, name) for name, (size, path) in best.items() if size > 1_000_000
    )


def slugify(name, used):
    """元の名前を残す。Godot は UTF-8 のパスを扱えるし、ASCII へ落とすと
    中国語名がすべて消えて character_1, character_2 と区別が付かなくなる。
    パス区切りなど扱いに困る文字だけを外す。"""
    out = "".join("_" if c in '/\\:*?"<>|' else c for c in name).strip().strip(".")
    out = out or "character"
    base = out
    i = 2
    while out in used:
        out = "%s_%d" % (base, i)
        i += 1
    used.add(out)
    return out


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon_utils.enable(MMD_TOOLS, default_set=True, persistent=True)
    addon_utils.enable(VRM_ADDON, default_set=True, persistent=True)


def mesh_height():
    zs = [
        (obj.matrix_world @ v.co).z
        for obj in bpy.data.objects
        if obj.type == "MESH"
        for v in obj.data.vertices
    ]
    return (max(zs) - min(zs)) if zs else 0.0


def convert(src, dst, target_height):
    reset_scene()
    bpy.ops.mmd_tools.import_model(
        filepath=src, scale=MMD_IMPORT_SCALE, types={"MESH", "ARMATURE"}
    )
    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if armature is None:
        return "アーマチュアが無い(小物)"

    current = mesh_height()
    if current <= 0.0:
        return "メッシュが無い"
    factor = target_height / current
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.parent is None:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.transform.resize(value=(factor, factor, factor))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    armature.select_set(True)
    bpy.ops.vrm.assign_vrm0_humanoid_human_bones_automatically(
        armature_object_name=armature.name
    )
    human_bones = armature.data.vrm_addon_extension.vrm0.humanoid.human_bones
    missing = [
        e.bone
        for e in human_bones
        if e.bone in REQUIRED_BONES and not e.node.bone_name
    ]
    if missing:
        return "humanoid 不成立(小物か非人型): %s" % ", ".join(sorted(missing)[:3])

    bpy.ops.export_scene.vrm(filepath=dst)
    if not os.path.exists(dst):
        return "書き出し失敗"
    return None


def main():
    root, out_dir, target_height = argv()
    os.makedirs(out_dir, exist_ok=True)
    sources = pick_sources(root)
    print("SCAN %d 件を候補として検査する" % len(sources))

    used = set()
    ok, skipped, failed = [], [], []
    for index, (src, name) in enumerate(sources, 1):
        slug = slugify(name, used)
        dst = os.path.join(out_dir, slug + ".vrm")
        print("PROGRESS %d/%d %s -> %s" % (index, len(sources), name, slug))
        try:
            error = convert(src, dst, target_height)
        except Exception as exc:  # noqa: BLE001 - 1 体の失敗で全体を止めない
            error = "%s: %s" % (type(exc).__name__, exc)
        if error is None:
            ok.append((name, slug, os.path.getsize(dst)))
            print("OK %s %s %d" % (name, slug, os.path.getsize(dst)))
        elif "humanoid 不成立" in error or "アーマチュア" in error:
            skipped.append((name, error))
            print("SKIP %s (%s)" % (name, error))
        else:
            failed.append((name, error))
            print("FAIL %s (%s)" % (name, error))

    print("\nSUMMARY 変換 %d / 小物として除外 %d / 失敗 %d" % (len(ok), len(skipped), len(failed)))
    for name, slug, size in ok:
        print("  RESULT %s\t%s\t%.1fMB" % (slug, name, size / 1048576))
    for name, error in failed:
        print("  FAILED %s\t%s" % (name, error))


main()
