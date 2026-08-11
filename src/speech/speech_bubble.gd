class_name SpeechBubble
extends Node3D

## 駒の近くに出すセリフ吹き出し。Label3D のビルボードでカメラ追従する。
## 親を駒ノードにすれば移動・オービットでも相対位置を保てる。

const DISPLAY_SEC := 2.8
const OFFSET_Y := 1.15
const FONT_SIZE := 36
const OUTLINE_SIZE := 10

var _label: Label3D
var _age: float = 0.0
var _lifetime: float = DISPLAY_SEC


func _init(text: String = "", lifetime_sec: float = DISPLAY_SEC) -> void:
	name = "SpeechBubble"
	_lifetime = maxf(0.2, lifetime_sec)
	_label = Label3D.new()
	_label.name = "Label"
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = FONT_SIZE
	_label.outline_size = OUTLINE_SIZE
	_label.modulate = Color(1.0, 1.0, 0.95)
	_label.outline_modulate = Color(0.12, 0.1, 0.18, 0.95)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector3(0.0, OFFSET_Y, 0.0)
	_label.pixel_size = 0.012
	_label.no_depth_test = true
	_label.render_priority = 10
	add_child(_label)
	set_process(true)


func set_text(text: String) -> void:
	if _label != null:
		_label.text = text


func text() -> String:
	return _label.text if _label != null else ""


func _process(delta: float) -> void:
	_age += delta
	# 終盤で少しフェード。
	if _age > _lifetime * 0.7 and _label != null:
		var t := clampf((_age - _lifetime * 0.7) / maxf(_lifetime * 0.3, 0.001), 0.0, 1.0)
		var c := _label.modulate
		c.a = 1.0 - t
		_label.modulate = c
	if _age >= _lifetime:
		queue_free()
