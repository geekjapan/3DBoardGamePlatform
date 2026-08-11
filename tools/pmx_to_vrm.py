"""PMX を VRM へ変換する Blender スクリプト。

使い方:

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/pmx_to_vrm.py -- <入力.pmx> <出力.vrm> [身長メートル]

手順書は docs/model-import.md。GUI で同じことをしてもよいが、humanoid の
割り当ては VRM アドオンの自動割り当てに任せられるので、MMD 標準のボーン名
(上半身 / 頭 / 腕.L など)を持つモデルならこのスクリプトで完結する。

自動割り当てが必須ボーンを埋められない場合は、その時点で失敗を報告して止まる。
壊れた VRM を書き出して後から気づくより、ここで落とすほうが安い。
"""

import os
import sys

import addon_utils
import bpy

# mmd_tools の既定スケール。1 単位 = 8cm 前後で読み込まれる。
MMD_IMPORT_SCALE = 0.08
DEFAULT_TARGET_HEIGHT = 1.6

MMD_TOOLS = "bl_ext.blender_org.mmd_tools"
VRM_ADDON = "bl_ext.blender_org.vrm"


def argv():
    if "--" not in sys.argv:
        sys.exit("引数がない。-- のあとに <入力.pmx> <出力.vrm> [身長] を渡す")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) < 2:
        sys.exit("入力と出力の 2 つが要る")
    height = float(args[2]) if len(args) > 2 else DEFAULT_TARGET_HEIGHT
    return os.path.abspath(args[0]), os.path.abspath(args[1]), height


def enable_addons():
    # read_factory_settings はアドオンごと落とすので、必ずそのあとで有効化する。
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name in (MMD_TOOLS, VRM_ADDON):
        addon_utils.enable(name, default_set=True, persistent=True)


def mesh_height():
    zs = [
        (obj.matrix_world @ v.co).z
        for obj in bpy.data.objects
        if obj.type == "MESH"
        for v in obj.data.vertices
    ]
    return (max(zs) - min(zs)) if zs else 0.0


def normalize_height(armature, target):
    """VRM は 1 単位 = 1m。身長がおよそ target になるよう合わせて確定する。"""
    current = mesh_height()
    if current <= 0.0:
        return 0.0
    factor = target / current
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.parent is None:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.transform.resize(value=(factor, factor, factor))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return mesh_height()


def missing_required_bones(armature):
    """必須 humanoid ボーンのうち、割り当てが空のもの。"""
    human_bones = armature.data.vrm_addon_extension.vrm0.humanoid.human_bones
    missing = []
    for entry in human_bones:
        required = getattr(entry, "requirement", None)
        if required is None:
            # 版によっては requirement を持たない。名前で必須を判定する。
            required = entry.bone in {
                "hips", "spine", "chest", "neck", "head",
                "leftUpperArm", "leftLowerArm", "leftHand",
                "rightUpperArm", "rightLowerArm", "rightHand",
                "leftUpperLeg", "leftLowerLeg", "leftFoot",
                "rightUpperLeg", "rightLowerLeg", "rightFoot",
            }
        if required and not entry.node.bone_name:
            missing.append(entry.bone)
    return missing


def main():
    src, dst, target_height = argv()
    if not os.path.exists(src):
        sys.exit("入力が無い: %s" % src)

    enable_addons()
    bpy.ops.mmd_tools.import_model(
        filepath=src, scale=MMD_IMPORT_SCALE, types={"MESH", "ARMATURE"}
    )
    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if armature is None:
        sys.exit("アーマチュアが見つからない。PMX の読み込みに失敗している")

    height = normalize_height(armature, target_height)
    print("HEIGHT %.3f" % height)

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.vrm.assign_vrm0_humanoid_human_bones_automatically(
        armature_object_name=armature.name
    )

    missing = missing_required_bones(armature)
    if missing:
        sys.exit("必須ボーンを割り当てられなかった: %s" % ", ".join(missing))
    print("HUMANOID_OK")

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.vrm(filepath=dst)
    if not os.path.exists(dst):
        sys.exit("書き出しに失敗した")
    print("EXPORT_OK %s %d bytes" % (dst, os.path.getsize(dst)))


main()
