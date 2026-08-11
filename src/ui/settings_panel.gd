class_name SettingsPanel
extends CanvasLayer

## 設定画面。AI 対戦のオン/オフ・強さ・エンジンパスを編集し AiSettings に保存する。
## エンジンが無いときは AI を選べず、その旨を表示する。

signal closed
signal settings_applied(settings: AiSettings)

var _settings: AiSettings
var _root: Control
var _panel: PanelContainer
var _ai_check: CheckBox
var _strength_option: OptionButton
var _path_edit: LineEdit
var _status_label: Label
var _protocol_label: Label


func _init() -> void:
	layer = 20
	name = "SettingsPanel"
	visible = false

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 320)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -220
	_panel.offset_top = -160
	_panel.offset_right = 220
	_panel.offset_bottom = 160
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "設定"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
	vbox.add_child(_status_label)

	_ai_check = CheckBox.new()
	_ai_check.text = "AI 対戦する (人が白・AI が黒)"
	vbox.add_child(_ai_check)

	var strength_row := HBoxContainer.new()
	strength_row.add_theme_constant_override("separation", 8)
	vbox.add_child(strength_row)
	var strength_label := Label.new()
	strength_label.text = "強さ"
	strength_row.add_child(strength_label)
	_strength_option = OptionButton.new()
	_strength_option.add_item("弱", EngineAdapter.Strength.WEAK)
	_strength_option.add_item("中", EngineAdapter.Strength.MEDIUM)
	_strength_option.add_item("強", EngineAdapter.Strength.STRONG)
	strength_row.add_child(_strength_option)

	var path_label := Label.new()
	path_label.text = "エンジン実行ファイル"
	vbox.add_child(path_label)

	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "/opt/homebrew/bin/stockfish"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_path_edit)

	_protocol_label = Label.new()
	_protocol_label.add_theme_font_size_override("font_size", 14)
	_protocol_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(_protocol_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var probe_btn := Button.new()
	probe_btn.text = "接続確認"
	probe_btn.pressed.connect(_on_probe)
	btn_row.add_child(probe_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "閉じる"
	cancel_btn.pressed.connect(_on_close)
	btn_row.add_child(cancel_btn)

	var apply_btn := Button.new()
	apply_btn.text = "保存"
	apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(apply_btn)


func open_with(settings: AiSettings) -> void:
	_settings = settings
	_path_edit.text = settings.engine_path
	_select_strength(settings.strength)
	_settings.refresh_engine_status()
	_ai_check.button_pressed = settings.ai_enabled and settings.engine_available
	_refresh_enabled_state()
	_protocol_label.text = "プロトコル: %s (将棋 USI は後から追加予定)" % settings.protocol
	visible = true


func _select_strength(value: int) -> void:
	for i in range(_strength_option.item_count):
		if _strength_option.get_item_id(i) == value:
			_strength_option.select(i)
			return
	_strength_option.select(1)


func _refresh_enabled_state() -> void:
	var avail := _settings != null and _settings.engine_available
	_ai_check.disabled = not avail
	if not avail:
		_ai_check.button_pressed = false
		_status_label.text = _settings.engine_message if _settings else "エンジン未設定"
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
	else:
		_status_label.text = _settings.engine_message
		_status_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5))
	_strength_option.disabled = false
	_path_edit.editable = true


func _on_probe() -> void:
	if _settings == null:
		return
	_settings.engine_path = _path_edit.text.strip_edges()
	_settings.refresh_engine_status()
	_ai_check.button_pressed = _ai_check.button_pressed and _settings.engine_available
	_refresh_enabled_state()


func _on_apply() -> void:
	if _settings == null:
		return
	_settings.engine_path = _path_edit.text.strip_edges()
	_settings.strength = _strength_option.get_selected_id()
	_settings.refresh_engine_status()
	_settings.ai_enabled = _ai_check.button_pressed and _settings.engine_available
	_settings.save_to_disk()
	_refresh_enabled_state()
	settings_applied.emit(_settings)
	visible = false
	closed.emit()


func _on_close() -> void:
	visible = false
	closed.emit()
