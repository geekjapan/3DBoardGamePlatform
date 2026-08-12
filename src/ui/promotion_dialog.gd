class_name PromotionDialog
extends CanvasLayer

## 任意成りの完全 Move 候補を選ぶモーダル。候補自体は変更せず参照を返す。

signal move_chosen(move: Move)
signal cancelled

var _root: Control
var _panel: PanelContainer
var _candidates: Array = []


func _init() -> void:
	layer = 30
	_root = Control.new()
	_root.name = "ModalBlocker"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "PromotionPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -150.0
	_panel.offset_top = -86.0
	_panel.offset_right = 150.0
	_panel.offset_bottom = 86.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "成りますか？"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var promote := Button.new()
	promote.name = "PromoteButton"
	promote.text = "成る"
	promote.pressed.connect(func() -> void: choose_promotion(true))
	column.add_child(promote)

	var stay := Button.new()
	stay.name = "StayButton"
	stay.text = "成らない"
	stay.pressed.connect(func() -> void: choose_promotion(false))
	column.add_child(stay)

	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "取消"
	cancel.pressed.connect(cancel_selection)
	column.add_child(cancel)

	visible = false


func open_with(candidates: Array) -> bool:
	if candidates.size() < 2:
		return false
	_candidates = candidates.duplicate()
	visible = true
	return true


func candidates() -> Array:
	## 呼び出し側が配列を変更しても保持中候補へ影響しない。
	return _candidates.duplicate()


func choose_promotion(promote: bool) -> bool:
	if not visible:
		return false
	for candidate in _candidates:
		var move := candidate as Move
		if (move.promotion >= 0) == promote:
			visible = false
			_candidates.clear()
			move_chosen.emit(move)
			return true
	return false


func cancel_selection() -> void:
	if not visible:
		return
	visible = false
	_candidates.clear()
	cancelled.emit()
