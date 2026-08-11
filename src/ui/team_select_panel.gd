class_name TeamSelectPanel
extends CanvasLayer

## 対局開始時のチーム選択。先手(白)・後手(黒)を独立に選び、同一チームも可。
## 確定で TeamSettings を保存し confirmed を出す。
## 編成画面へは edit_requested で遷移する。

signal confirmed(settings: TeamSettings)
signal edit_requested
signal closed

var _catalog: SpeechCatalog
var _settings: TeamSettings
var _root: Control
var _panel: PanelContainer
var _white_option: OptionButton
var _black_option: OptionButton
var _white_lineup: Label
var _black_lineup: Label
var _hint_label: Label


func _init() -> void:
	layer = 25
	name = "TeamSelectPanel"
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
	_panel.custom_minimum_size = Vector2(520, 420)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -260
	_panel.offset_top = -210
	_panel.offset_right = 260
	_panel.offset_bottom = 210
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
	title.text = "チーム選択"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.text = "先手・後手それぞれチームを選べます。同じチーム同士でも対局できます。編成の作成・編集もここから。"
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	vbox.add_child(_hint_label)

	vbox.add_child(_build_side_block("先手 (白)", true))
	vbox.add_child(_build_side_block("後手 (黒)", false))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	var edit_btn := Button.new()
	edit_btn.text = "編成を編集"
	edit_btn.custom_minimum_size = Vector2(140, 40)
	edit_btn.pressed.connect(_on_edit_pressed)
	btn_row.add_child(edit_btn)

	var start_btn := Button.new()
	start_btn.text = "このチームで対局開始"
	start_btn.custom_minimum_size = Vector2(200, 40)
	start_btn.pressed.connect(_on_confirm)
	btn_row.add_child(start_btn)


func _build_side_block(title_text: String, is_white: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var label := Label.new()
	label.text = title_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(_on_option_changed)
	row.add_child(option)

	var lineup := Label.new()
	lineup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lineup.add_theme_font_size_override("font_size", 14)
	lineup.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(lineup)

	if is_white:
		_white_option = option
		_white_lineup = lineup
	else:
		_black_option = option
		_black_lineup = lineup
	return box


func open_with(catalog: SpeechCatalog, settings: TeamSettings) -> void:
	_catalog = catalog
	_settings = settings
	refresh_options()
	visible = true


func refresh_options() -> void:
	## カタログにユーザー編成が追加されたあと選択肢を取り直す。
	if _settings == null:
		return
	var white_pref := selected_white_team_id() if _white_option.item_count > 0 else _settings.white_team_id
	var black_pref := selected_black_team_id() if _black_option.item_count > 0 else _settings.black_team_id
	if white_pref == "":
		white_pref = _settings.white_team_id
	if black_pref == "":
		black_pref = _settings.black_team_id
	_populate_options(_white_option, white_pref)
	_populate_options(_black_option, black_pref)
	_refresh_lineups()


func selected_white_team_id() -> String:
	return _id_at(_white_option)


func selected_black_team_id() -> String:
	return _id_at(_black_option)


func _populate_options(option: OptionButton, preferred_id: String) -> void:
	option.clear()
	if _catalog == null:
		return
	var ids := _catalog.team_ids()
	var select_idx := 0
	for i in ids.size():
		var id := ids[i]
		var t := _catalog.team_by_id(id)
		var label := t.display_name if t != null else id
		option.add_item("%s (%s)" % [label, id], i)
		option.set_item_metadata(i, id)
		if id == preferred_id:
			select_idx = i
	if option.item_count > 0:
		option.select(select_idx)


func _id_at(option: OptionButton) -> String:
	if option == null or option.item_count == 0:
		return TeamSettings.DEFAULT_TEAM_ID
	var idx := option.selected
	if idx < 0 or idx >= option.item_count:
		idx = 0
	return str(option.get_item_metadata(idx))


func _on_option_changed(_index: int) -> void:
	_refresh_lineups()


func _refresh_lineups() -> void:
	if _catalog == null:
		return
	_white_lineup.text = _lineup_text(selected_white_team_id())
	_black_lineup.text = _lineup_text(selected_black_team_id())


func _lineup_text(team_id: String) -> String:
	var t := _catalog.team_by_id(team_id)
	if t == null:
		return "割当なし"
	var parts: PackedStringArray = []
	for kind in [
		Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
		Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
	]:
		var cid := t.character_id_for_kind(kind)
		var cname := cid
		var ch := _catalog.character(cid)
		if ch != null and ch.display_name != "":
			cname = ch.display_name
		parts.append("%s=%s" % [SpeechCatalog.kind_name(kind), cname])
	return "並び: " + ", ".join(parts)


func _on_edit_pressed() -> void:
	edit_requested.emit()


func _on_confirm() -> void:
	if _settings == null:
		_settings = TeamSettings.new()
	_settings.white_team_id = selected_white_team_id()
	_settings.black_team_id = selected_black_team_id()
	if _catalog != null:
		_settings.clamp_to_catalog(_catalog)
		_settings.apply_to_catalog(_catalog)
	_settings.save_to_disk()
	visible = false
	confirmed.emit(_settings)
	closed.emit()
