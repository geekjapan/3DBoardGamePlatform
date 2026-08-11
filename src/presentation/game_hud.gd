class_name GameHud
extends CanvasLayer

## 手番・王手・終局結果・待ったボタンの 2D オーバーレイ。
## UI は _init で組み立てる(親の _ready 中に setup されても安全)。

signal undo_pressed

var _turn_label: Label
var _check_label: Label
var _result_label: Label
var _undo_button: Button


func _init() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.position = Vector2(16, 12)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_turn_label)

	_check_label = Label.new()
	_check_label.name = "CheckLabel"
	_check_label.position = Vector2(16, 44)
	_check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check_label.add_theme_font_size_override("font_size", 20)
	_check_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	_check_label.visible = false
	root.add_child(_check_label)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result_label.offset_top = 80
	_result_label.offset_left = -200
	_result_label.offset_right = 200
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.visible = false
	root.add_child(_result_label)

	_undo_button = Button.new()
	_undo_button.name = "UndoButton"
	_undo_button.text = "待った"
	_undo_button.position = Vector2(16, 80)
	_undo_button.custom_minimum_size = Vector2(100, 36)
	_undo_button.pressed.connect(func() -> void: undo_pressed.emit())
	root.add_child(_undo_button)

	refresh(Piece.Side.WHITE, false, "", false)


func refresh(side: int, in_check: bool, result: String, can_undo: bool) -> void:
	if result != "":
		_turn_label.text = "対局終了"
		_check_label.visible = false
		_result_label.text = result
		_result_label.visible = true
	else:
		var side_name := "白" if side == Piece.Side.WHITE else "黒"
		_turn_label.text = "手番: %s" % side_name
		_check_label.text = "王手!"
		_check_label.visible = in_check
		_result_label.visible = false
	_undo_button.disabled = not can_undo
