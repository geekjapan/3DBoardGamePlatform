class_name GameHud
extends CanvasLayer

## 手番・王手・終局結果・待ったボタンの 2D オーバーレイ。
## UI は _init で組み立てる(親の _ready 中に setup されても安全)。

signal undo_pressed
signal drop_pressed(side: int, kind: int)

const HAND_PANEL_WIDTH := 170.0
const HAND_PANEL_HEIGHT := 316.0
const HAND_PANEL_MARGIN := 12.0
const HAND_KINDS := [
	Piece.Kind.SHOGI_PAWN,
	Piece.Kind.SHOGI_LANCE,
	Piece.Kind.SHOGI_KNIGHT,
	Piece.Kind.SHOGI_SILVER,
	Piece.Kind.SHOGI_GOLD,
	Piece.Kind.SHOGI_BISHOP,
	Piece.Kind.SHOGI_ROOK,
]
const HAND_NAMES := {
	Piece.Kind.SHOGI_PAWN: "歩",
	Piece.Kind.SHOGI_LANCE: "香",
	Piece.Kind.SHOGI_KNIGHT: "桂",
	Piece.Kind.SHOGI_SILVER: "銀",
	Piece.Kind.SHOGI_GOLD: "金",
	Piece.Kind.SHOGI_BISHOP: "角",
	Piece.Kind.SHOGI_ROOK: "飛",
}

var _turn_label: Label
var _check_label: Label
var _result_label: Label
var _undo_button: Button
var _hands_root: Control
var _hand_panels: Dictionary = {}
var _hand_buttons: Dictionary = {}


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

	_build_hand_panels(root)

	refresh(Piece.Side.WHITE, false, "", false)


func refresh(
	side: int,
	in_check: bool,
	result: String,
	can_undo: bool,
	board: Object = null,
	selected_drop_kind: int = -1,
	legal_drop_kinds: Array = [],
) -> void:
	var is_shogi := board != null and board is ShogiBoard
	if result != "":
		_turn_label.text = "対局終了"
		_check_label.visible = false
		_result_label.text = result
		_result_label.visible = true
	else:
		var side_name := "先手" if side == Piece.Side.WHITE else "後手"
		if not is_shogi:
			side_name = "白" if side == Piece.Side.WHITE else "黒"
		_turn_label.text = "手番: %s" % side_name
		_check_label.text = "王手!"
		_check_label.visible = in_check
		_result_label.visible = false
	_undo_button.disabled = not can_undo
	_refresh_hands(board, side, selected_drop_kind, legal_drop_kinds)


func hands_visible() -> bool:
	return _hands_root.visible


func hand_panel(side: int) -> Control:
	return _hand_panels.get(side) as Control


func hand_button(side: int, kind: int) -> Button:
	var by_kind: Dictionary = _hand_buttons.get(side, {})
	return by_kind.get(kind) as Button


func _build_hand_panels(root: Control) -> void:
	_hands_root = Control.new()
	_hands_root.name = "Hands"
	_hands_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hands_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hands_root)
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var panel := PanelContainer.new()
		panel.name = "WhiteHand" if side == Piece.Side.WHITE else "BlackHand"
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_top = -HAND_PANEL_HEIGHT * 0.5
		panel.offset_bottom = HAND_PANEL_HEIGHT * 0.5
		if side == Piece.Side.WHITE:
			panel.anchor_left = 0.0
			panel.anchor_right = 0.0
			panel.offset_left = HAND_PANEL_MARGIN
			panel.offset_right = HAND_PANEL_MARGIN + HAND_PANEL_WIDTH
		else:
			panel.anchor_left = 1.0
			panel.anchor_right = 1.0
			panel.offset_left = -HAND_PANEL_MARGIN - HAND_PANEL_WIDTH
			panel.offset_right = -HAND_PANEL_MARGIN
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_hands_root.add_child(panel)
		_hand_panels[side] = panel

		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_STOP
		column.add_theme_constant_override("separation", 3)
		panel.add_child(column)
		var title := Label.new()
		title.text = "先手 持ち駒" if side == Piece.Side.WHITE else "後手 持ち駒"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_STOP
		column.add_child(title)

		var by_kind := {}
		for kind in HAND_KINDS:
			var button := Button.new()
			button.name = "Hand_%d_%d" % [side, kind]
			button.custom_minimum_size = Vector2(HAND_PANEL_WIDTH - 16.0, 34.0)
			button.toggle_mode = true
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.pressed.connect(_on_hand_button.bind(side, kind))
			column.add_child(button)
			by_kind[kind] = button
		_hand_buttons[side] = by_kind
	_hands_root.visible = false


func _refresh_hands(
	board: Object,
	turn_side: int,
	selected_drop_kind: int,
	legal_drop_kinds: Array,
) -> void:
	var is_shogi := board != null and board is ShogiBoard
	_hands_root.visible = is_shogi
	if not is_shogi:
		return
	for side in [Piece.Side.WHITE, Piece.Side.BLACK]:
		var hand: Dictionary = board.hands[side]
		for kind in HAND_KINDS:
			var button := hand_button(side, kind)
			var count := int(hand.get(kind, 0))
			button.text = "%s  x%d" % [HAND_NAMES[kind], count]
			button.disabled = side != turn_side or count <= 0 or not legal_drop_kinds.has(kind)
			button.button_pressed = side == turn_side and selected_drop_kind == kind


func _on_hand_button(side: int, kind: int) -> void:
	## Button/Panel の STOP が盤クリックと camera の unhandled input への伝播を防ぐ。
	drop_pressed.emit(side, kind)
