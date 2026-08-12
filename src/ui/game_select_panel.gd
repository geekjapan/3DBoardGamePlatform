class_name GameSelectPanel
extends CanvasLayer

## 起動直後のゲーム選択だけを担当する。チームや対局は扱わない。

signal confirmed(game_id: String)

var _settings: GameSettings
var _game_option: OptionButton


func _init() -> void:
	layer = 24
	name = "GameSelectPanel"
	visible = false

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 300)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_top = -150
	panel.offset_right = 240
	panel.offset_bottom = 150
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ゲーム選択"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "遊ぶゲームを選んでください。選択は次回起動時にも使われます。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	vbox.add_child(hint)

	_game_option = OptionButton.new()
	_game_option.custom_minimum_size = Vector2(0, 48)
	_game_option.add_item("チェス（8×8）")
	_game_option.set_item_metadata(0, SpeechCatalog.GAME_CHESS)
	_game_option.add_item("将棋（9×9・持ち駒あり）")
	_game_option.set_item_metadata(1, SpeechCatalog.GAME_SHOGI)
	vbox.add_child(_game_option)

	var confirm_button := Button.new()
	confirm_button.text = "このゲームでチーム選択へ"
	confirm_button.custom_minimum_size = Vector2(220, 44)
	confirm_button.pressed.connect(_on_confirm)
	vbox.add_child(confirm_button)


func open_with(settings: GameSettings) -> void:
	_settings = settings if settings != null else GameSettings.new()
	select_game_for_test(_settings.game_id)
	visible = true


func selected_game_id() -> String:
	if _game_option == null or _game_option.item_count == 0:
		return SpeechCatalog.GAME_CHESS
	var index := _game_option.selected
	if index < 0 or index >= _game_option.item_count:
		return SpeechCatalog.GAME_CHESS
	return GameSettings.normalize_game_id(str(_game_option.get_item_metadata(index)))


func select_game_for_test(game_id: String) -> void:
	var normalized := GameSettings.normalize_game_id(game_id)
	for i in range(_game_option.item_count):
		if str(_game_option.get_item_metadata(i)) == normalized:
			_game_option.select(i)
			return
	_game_option.select(0)


func _on_confirm() -> void:
	if _settings == null:
		_settings = GameSettings.new()
	_settings.game_id = selected_game_id()
	_settings.save_to_disk()
	visible = false
	confirmed.emit(_settings.game_id)
