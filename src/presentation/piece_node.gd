class_name PieceNode
extends Node3D

## 盤上の 1 駒の見た目ノード。
## ModelSlot にプリミティブ / glTF / VRM のいずれかを装着でき、差し替えはスロットの入れ替えのみ。

const MODEL_SLOT_NAME := "ModelSlot"

## 論理座標 (file, rank)。Board と同じ。
var board_pos: Vector2i = Vector2i(-1, -1)
## Piece.Side
var piece_side: int = Piece.Side.WHITE
## Piece.Kind
var piece_kind: int = Piece.Kind.PAWN

var _model_slot: Node3D


func _init(
	p_side: int = Piece.Side.WHITE,
	p_kind: int = Piece.Kind.PAWN,
	p_pos: Vector2i = Vector2i(-1, -1),
) -> void:
	piece_side = p_side
	piece_kind = p_kind
	board_pos = p_pos
	_model_slot = Node3D.new()
	_model_slot.name = MODEL_SLOT_NAME
	add_child(_model_slot)


func model_slot() -> Node3D:
	return _model_slot


func has_model() -> bool:
	return _model_slot.get_child_count() > 0


func set_model(visual: Node3D) -> void:
	## スロット内を置き換える。visual はまだ親を持っていないこと。
	clear_model()
	if visual != null:
		_model_slot.add_child(visual)


func clear_model() -> void:
	while _model_slot.get_child_count() > 0:
		var child: Node = _model_slot.get_child(0)
		_model_slot.remove_child(child)
		child.free()
