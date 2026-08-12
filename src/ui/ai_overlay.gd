class_name AiOverlay
extends CanvasLayer

## 思考中表示と設定ボタン。GameHud を触らずに重ねるオーバーレイ。

signal settings_pressed
signal retry_pressed
signal disable_for_match_pressed

var _thinking_label: Label
var _status_label: Label
var _settings_button: Button
var _ai_badge: Label
var _failure_panel: PanelContainer
var _failure_label: Label
var _retry_button: Button
var _disable_button: Button


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

	_failure_panel = PanelContainer.new()
	_failure_panel.name = "FailurePanel"
	_failure_panel.position = Vector2(16, 236)
	_failure_panel.custom_minimum_size = Vector2(480, 128)
	root.add_child(_failure_panel)
	var failure_box := VBoxContainer.new()
	failure_box.add_theme_constant_override("separation", 8)
	_failure_panel.add_child(failure_box)
	_failure_label = Label.new()
	_failure_label.name = "FailureLabel"
	_failure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_failure_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	failure_box.add_child(_failure_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	failure_box.add_child(actions)
	_retry_button = Button.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = "再試行"
	_retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	actions.add_child(_retry_button)
	_disable_button = Button.new()
	_disable_button.name = "DisableForMatchButton"
	_disable_button.text = "この対局だけAI解除"
	_disable_button.pressed.connect(func() -> void: disable_for_match_pressed.emit())
	actions.add_child(_disable_button)
	var failure_settings := Button.new()
	failure_settings.name = "FailureSettingsButton"
	failure_settings.text = "設定"
	failure_settings.pressed.connect(func() -> void: settings_pressed.emit())
	actions.add_child(failure_settings)

	set_thinking(false)
	set_ai_mode(false, "", false)
	set_status("")
	clear_failure()


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


func set_failed(classification: String, reason: String, retry_enabled: bool = true) -> void:
	_ai_badge.text = "AI対戦: 停止中"
	_ai_badge.add_theme_color_override("font_color", Color(1.0, 0.48, 0.35))
	_failure_label.text = "AI探索に失敗しました（分類: %s）。%s\n盤面は変更していません" % [
		classification, reason,
	]
	_retry_button.disabled = not retry_enabled
	_failure_panel.visible = true


func set_retrying(active: bool) -> void:
	_retry_button.disabled = active


func clear_failure() -> void:
	if _failure_panel != null:
		_failure_panel.visible = false


func set_status(text: String) -> void:
	_status_label.text = text
