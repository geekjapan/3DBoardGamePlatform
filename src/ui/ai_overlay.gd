class_name AiOverlay
extends CanvasLayer

## 思考中表示と設定ボタン。GameHud を触らずに重ねるオーバーレイ。

signal settings_pressed

var _thinking_label: Label
var _status_label: Label
var _settings_button: Button
var _ai_badge: Label


func _init() -> void:
	layer = 15
	name = "AiOverlay"

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "設定"
	_settings_button.position = Vector2(16, 130)
	_settings_button.custom_minimum_size = Vector2(100, 36)
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	root.add_child(_settings_button)

	_ai_badge = Label.new()
	_ai_badge.name = "AiBadge"
	_ai_badge.position = Vector2(16, 176)
	_ai_badge.add_theme_font_size_override("font_size", 16)
	_ai_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ai_badge)

	_thinking_label = Label.new()
	_thinking_label.name = "ThinkingLabel"
	_thinking_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_thinking_label.offset_top = 140
	_thinking_label.offset_left = -180
	_thinking_label.offset_right = 180
	_thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thinking_label.add_theme_font_size_override("font_size", 26)
	_thinking_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_thinking_label.text = "AI 思考中…"
	_thinking_label.visible = false
	_thinking_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_thinking_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(16, 204)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status_label)

	set_thinking(false)
	set_ai_mode(false, "", false)
	set_status("")


func set_thinking(active: bool) -> void:
	_thinking_label.visible = active


func set_ai_mode(enabled: bool, strength_label: String, engine_ok: bool) -> void:
	if not engine_ok:
		_ai_badge.text = "AI: エンジンなし (2人対戦)"
		_ai_badge.add_theme_color_override("font_color", Color(0.9, 0.55, 0.4))
	elif enabled:
		_ai_badge.text = "AI 対戦: オン (強さ %s)" % strength_label
		_ai_badge.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	else:
		_ai_badge.text = "AI 対戦: オフ (2人対戦)"
		_ai_badge.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))


func set_status(text: String) -> void:
	_status_label.text = text
