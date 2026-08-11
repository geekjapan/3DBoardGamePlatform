class_name SettingsPanel
extends CanvasLayer

## 設定画面。AI 対戦と発話(モード・通常手確率)を編集し永続化する。
## エンジンが無いときは AI を選べず、その旨を表示する。
## API キー入力欄は置かない(環境変数専用)。

## 画面の論理高さ 720(project.godot の viewport_height)に収まる高さの半分。
## これを超えると下のボタンが画面外へ出る。
const PANEL_HALF_HEIGHT := 320.0

signal closed
signal settings_applied(settings: AiSettings)
signal speech_settings_applied(settings: SpeechSettings)
## 現在の視点を初期位置として保存したい / 既定構図へ戻したい。
signal view_save_requested
signal view_reset_requested

var _settings: AiSettings
var _speech: SpeechSettings
var _root: Control
var _panel: PanelContainer
var _ai_check: CheckBox
var _strength_option: OptionButton
var _path_edit: LineEdit
var _status_label: Label
var _protocol_label: Label
var _speech_mode_option: OptionButton
var _move_prob_slider: HSlider
var _move_prob_value: Label
var _view_status: Label


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
	# 高さは画面内に固定する。項目が増えても下のボタンが画面外へ出ないよう、
	# 中身は ScrollContainer に入れてパネル自体は伸ばさない。
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -250
	_panel.offset_top = -PANEL_HALF_HEIGHT
	_panel.offset_right = 250
	_panel.offset_bottom = PANEL_HALF_HEIGHT
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	# 外側は「スクロールする本体」と「常に見えるボタン列」の 2 段。
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

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

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var speech_title := Label.new()
	speech_title.text = "発話"
	speech_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(speech_title)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	vbox.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "発話モード"
	mode_row.add_child(mode_label)
	_speech_mode_option = OptionButton.new()
	_speech_mode_option.add_item("定型", SpeechSettings.Mode.LINES)
	_speech_mode_option.add_item("音声", SpeechSettings.Mode.TTS)
	_speech_mode_option.add_item("生成", SpeechSettings.Mode.LLM)
	mode_row.add_child(_speech_mode_option)

	var prob_label := Label.new()
	prob_label.text = "通常手の発話確率"
	vbox.add_child(prob_label)

	var prob_row := HBoxContainer.new()
	prob_row.add_theme_constant_override("separation", 8)
	vbox.add_child(prob_row)
	_move_prob_slider = HSlider.new()
	_move_prob_slider.min_value = 0.0
	_move_prob_slider.max_value = 1.0
	_move_prob_slider.step = 0.05
	_move_prob_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_move_prob_slider.value_changed.connect(_on_prob_changed)
	prob_row.add_child(_move_prob_slider)
	_move_prob_value = Label.new()
	_move_prob_value.custom_minimum_size = Vector2(48, 0)
	prob_row.add_child(_move_prob_value)

	var key_hint := Label.new()
	key_hint.text = "生成モードの API キーは環境変数 BOARDGAME_LLM_API_KEY または OPENAI_API_KEY のみ(設定には保存しません)"
	key_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_hint.add_theme_font_size_override("font_size", 12)
	key_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	vbox.add_child(key_hint)

	var cam_sep := HSeparator.new()
	vbox.add_child(cam_sep)

	var cam_title := Label.new()
	cam_title.text = "視点"
	cam_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(cam_title)

	var cam_hint := Label.new()
	cam_hint.text = "盤を見やすい向きにしてから保存すると、次回起動時もその視点で始まります。"
	cam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cam_hint.add_theme_font_size_override("font_size", 12)
	cam_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	vbox.add_child(cam_hint)

	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 12)
	vbox.add_child(cam_row)

	var save_view_btn := Button.new()
	save_view_btn.text = "現在の視点を初期位置にする"
	save_view_btn.pressed.connect(_on_save_view)
	cam_row.add_child(save_view_btn)

	var reset_view_btn := Button.new()
	reset_view_btn.text = "初期位置に戻す"
	reset_view_btn.pressed.connect(_on_reset_view)
	cam_row.add_child(reset_view_btn)

	_view_status = Label.new()
	_view_status.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_view_status)

	# ボタン列はスクロールの外。項目が増えても「保存」が必ず見える。
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

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


func open_with(settings: AiSettings, speech: SpeechSettings = null) -> void:
	_settings = settings
	_speech = speech if speech != null else SpeechSettings.load_or_default()
	_path_edit.text = settings.engine_path
	_select_strength(settings.strength)
	_settings.refresh_engine_status()
	_ai_check.button_pressed = settings.ai_enabled and settings.engine_available
	_select_speech_mode(_speech.mode)
	_move_prob_slider.value = clampf(_speech.move_probability, 0.0, 1.0)
	_on_prob_changed(_move_prob_slider.value)
	_refresh_enabled_state()
	_protocol_label.text = "プロトコル: %s (将棋 USI は後から追加予定)" % settings.protocol
	visible = true


func _on_save_view() -> void:
	view_save_requested.emit()
	set_view_status("現在の視点を初期位置として保存しました。")


func _on_reset_view() -> void:
	view_reset_requested.emit()
	set_view_status("初期位置に戻しました。")


func set_view_status(text: String) -> void:
	if _view_status != null:
		_view_status.text = text


func _select_strength(value: int) -> void:
	for i in range(_strength_option.item_count):
		if _strength_option.get_item_id(i) == value:
			_strength_option.select(i)
			return
	_strength_option.select(1)


func _select_speech_mode(value: int) -> void:
	for i in range(_speech_mode_option.item_count):
		if _speech_mode_option.get_item_id(i) == value:
			_speech_mode_option.select(i)
			return
	_speech_mode_option.select(0)


func _on_prob_changed(value: float) -> void:
	if _move_prob_value != null:
		_move_prob_value.text = "%d%%" % int(round(value * 100.0))


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

	if _speech == null:
		_speech = SpeechSettings.new()
	_speech.mode = _speech_mode_option.get_selected_id()
	_speech.move_probability = clampf(float(_move_prob_slider.value), 0.0, 1.0)
	_speech.save_to_disk()
	speech_settings_applied.emit(_speech)

	visible = false
	closed.emit()


func _on_close() -> void:
	visible = false
	closed.emit()
