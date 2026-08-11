class_name TeamEditorPanel
extends CanvasLayer

## チーム編成画面。駒種一覧にキャラクターを割り当て、名前を付けて保存する。
## 割当が欠けていても保存でき、対局は成立する(未割当駒は黙るだけ)。

signal saved(team: TeamDef)
signal closed

const UNASSIGNED_LABEL := "(未割当)"
const KIND_ORDER: Array = [
	Piece.Kind.PAWN, Piece.Kind.KNIGHT, Piece.Kind.BISHOP,
	Piece.Kind.ROOK, Piece.Kind.QUEEN, Piece.Kind.KING,
]
const KIND_LABELS: Dictionary = {
	Piece.Kind.PAWN: "ポーン",
	Piece.Kind.KNIGHT: "ナイト",
	Piece.Kind.BISHOP: "ビショップ",
	Piece.Kind.ROOK: "ルーク",
	Piece.Kind.QUEEN: "クイーン",
	Piece.Kind.KING: "キング",
}

var _catalog: SpeechCatalog
var _store_dir: String = TeamStore.USER_TEAMS_DIR
var _draft: TeamDef = TeamDef.new()
var _selected_kind: int = Piece.Kind.PAWN
## kind → OptionButton
var _kind_options: Dictionary = {}
## kind → Button (行選択)
var _kind_buttons: Dictionary = {}

var _root: Control
var _panel: PanelContainer
var _load_option: OptionButton
var _name_edit: LineEdit
var _id_label: Label
var _status_label: Label
var _preview: CharacterPreview3D
var _preview_caption: Label
var _is_new: bool = true


func _init() -> void:
	layer = 26
	name = "TeamEditorPanel"
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
	_panel.custom_minimum_size = Vector2(720, 520)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -360
	_panel.offset_top = -260
	_panel.offset_right = 360
	_panel.offset_bottom = 260
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	outer.add_child(left)

	var title := Label.new()
	title.text = "チーム編成"
	title.add_theme_font_size_override("font_size", 24)
	left.add_child(title)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "駒種ごとにキャラクターを割り当てます。未割当の駒種があっても保存・対局できます。"
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	left.add_child(hint)

	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	left.add_child(load_row)
	var load_label := Label.new()
	load_label.text = "読み込み"
	load_row.add_child(load_label)
	_load_option = OptionButton.new()
	_load_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_option.item_selected.connect(_on_load_selected)
	load_row.add_child(_load_option)
	var new_btn := Button.new()
	new_btn.text = "新規"
	new_btn.pressed.connect(_on_new_pressed)
	load_row.add_child(new_btn)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	left.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "編成名"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "例: 私のチーム"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)

	_id_label = Label.new()
	_id_label.add_theme_font_size_override("font_size", 13)
	_id_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	left.add_child(_id_label)

	var kinds_title := Label.new()
	kinds_title.text = "駒種一覧"
	kinds_title.add_theme_font_size_override("font_size", 18)
	left.add_child(kinds_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	left.add_child(scroll)

	var kinds_box := VBoxContainer.new()
	kinds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kinds_box.add_theme_constant_override("separation", 6)
	scroll.add_child(kinds_box)

	for kind in KIND_ORDER:
		kinds_box.add_child(_build_kind_row(int(kind)))

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
	left.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	left.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "閉じる"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_on_close)
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(120, 40)
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 0)
	right.add_theme_constant_override("separation", 8)
	outer.add_child(right)

	var preview_title := Label.new()
	preview_title.text = "3D プレビュー"
	preview_title.add_theme_font_size_override("font_size", 18)
	right.add_child(preview_title)

	_preview = CharacterPreview3D.new()
	_preview.custom_minimum_size = Vector2(220, 260)
	right.add_child(_preview)

	_preview_caption = Label.new()
	_preview_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_caption.add_theme_font_size_override("font_size", 14)
	_preview_caption.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	right.add_child(_preview_caption)


func _build_kind_row(kind: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var select_btn := Button.new()
	select_btn.toggle_mode = true
	select_btn.text = str(KIND_LABELS.get(kind, SpeechCatalog.kind_name(kind)))
	select_btn.custom_minimum_size = Vector2(110, 0)
	select_btn.pressed.connect(func() -> void: _select_kind(kind))
	row.add_child(select_btn)
	_kind_buttons[kind] = select_btn

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(_i: int) -> void: _on_kind_character_changed(kind))
	row.add_child(option)
	_kind_options[kind] = option
	return row


func open_with(catalog: SpeechCatalog, store_dir: String = TeamStore.USER_TEAMS_DIR, prefer_team_id: String = "") -> void:
	_catalog = catalog
	_store_dir = store_dir if store_dir != "" else TeamStore.USER_TEAMS_DIR
	_status_label.text = ""
	_populate_load_options(prefer_team_id)
	if prefer_team_id != "" and catalog != null and catalog.team_by_id(prefer_team_id) != null:
		_load_team_id(prefer_team_id)
	else:
		_start_new_draft()
	_select_kind(Piece.Kind.PAWN)
	visible = true


func draft() -> TeamDef:
	return _draft


func selected_kind() -> int:
	return _selected_kind


func set_assignment_for_test(kind: int, character_id: String) -> void:
	## ヘッドレステスト用: Option を操作して割当を変える。
	var option: OptionButton = _kind_options.get(kind) as OptionButton
	if option == null:
		return
	var target := character_id.strip_edges()
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == target:
			option.select(i)
			_on_kind_character_changed(kind)
			return


func _populate_load_options(prefer_team_id: String) -> void:
	_load_option.clear()
	_load_option.add_item("— 新規編成 —", 0)
	_load_option.set_item_metadata(0, "")
	if _catalog == null:
		return
	var select_idx := 0
	var ids := _catalog.team_ids()
	for i in ids.size():
		var id := ids[i]
		var t := _catalog.team_by_id(id)
		var label := t.display_name if t != null else id
		var idx := i + 1
		_load_option.add_item("%s (%s)" % [label, id], idx)
		_load_option.set_item_metadata(idx, id)
		if prefer_team_id != "" and id == prefer_team_id:
			select_idx = idx
	_load_option.select(select_idx)


func _start_new_draft() -> void:
	_is_new = true
	_draft = TeamDef.new()
	_draft.id = ""
	_draft.display_name = ""
	_name_edit.text = ""
	_refresh_id_label()
	_fill_kind_options()
	_refresh_preview()


func _load_team_id(team_id: String) -> void:
	if _catalog == null:
		_start_new_draft()
		return
	var source := _catalog.team_by_id(team_id)
	if source == null:
		_start_new_draft()
		return
	_is_new = false
	_draft = TeamStore.clone_team(source)
	_name_edit.text = _draft.display_name
	_refresh_id_label()
	_fill_kind_options()
	_refresh_preview()


func _fill_kind_options() -> void:
	for kind in KIND_ORDER:
		var option: OptionButton = _kind_options[kind]
		option.clear()
		option.add_item(UNASSIGNED_LABEL, 0)
		option.set_item_metadata(0, "")
		var select_idx := 0
		if _catalog != null:
			var char_ids := _character_ids()
			for i in char_ids.size():
				var cid := char_ids[i]
				var ch := _catalog.character(cid)
				var label := ch.display_name if ch != null and ch.display_name != "" else cid
				var idx := i + 1
				option.add_item("%s (%s)" % [label, cid], idx)
				option.set_item_metadata(idx, cid)
				if _draft != null and _draft.character_id_for_kind(kind) == cid:
					select_idx = idx
		option.select(select_idx)


func _character_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if _catalog == null:
		return ids
	for key in _catalog.characters.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func _select_kind(kind: int) -> void:
	_selected_kind = kind
	for k in _kind_buttons.keys():
		var btn: Button = _kind_buttons[k]
		btn.button_pressed = int(k) == kind
	_refresh_preview()


func _on_kind_character_changed(kind: int) -> void:
	var option: OptionButton = _kind_options.get(kind) as OptionButton
	if option == null or _draft == null:
		return
	var cid := ""
	if option.item_count > 0 and option.selected >= 0:
		cid = str(option.get_item_metadata(option.selected)).strip_edges()
	if cid == "":
		TeamStore.clear_assignment(_draft, kind)
	else:
		_draft.assign(kind, cid)
	if kind == _selected_kind:
		_refresh_preview()


func _on_name_changed(new_text: String) -> void:
	if _draft == null:
		return
	_draft.display_name = new_text.strip_edges()
	if _is_new or _draft.id == "":
		var existing := _catalog.team_ids() if _catalog != null else PackedStringArray()
		_draft.id = TeamStore.make_team_id(_draft.display_name, existing)
	_refresh_id_label()


func _refresh_id_label() -> void:
	var id := _draft.id if _draft != null else ""
	if id == "":
		_id_label.text = "ID: (名前を入れると自動生成)"
	else:
		_id_label.text = "ID: %s%s" % [id, " (新規)" if _is_new else ""]


func _refresh_preview() -> void:
	if _preview == null or _draft == null:
		return
	var cid := _draft.character_id_for_kind(_selected_kind)
	_preview.set_preview(_selected_kind, cid)
	var kind_label := str(KIND_LABELS.get(_selected_kind, SpeechCatalog.kind_name(_selected_kind)))
	if cid == "":
		_preview_caption.text = "%s: 未割当" % kind_label
		return
	var cname := cid
	if _catalog != null:
		var ch := _catalog.character(cid)
		if ch != null and ch.display_name != "":
			cname = ch.display_name
	_preview_caption.text = "%s → %s" % [kind_label, cname]


func _on_load_selected(index: int) -> void:
	var id := str(_load_option.get_item_metadata(index))
	if id == "":
		_start_new_draft()
	else:
		_load_team_id(id)
	_select_kind(_selected_kind)


func _on_new_pressed() -> void:
	_load_option.select(0)
	_start_new_draft()
	_select_kind(Piece.Kind.PAWN)


func _on_save() -> void:
	if _draft == null:
		return
	var name := _name_edit.text.strip_edges()
	if name == "":
		_status_label.text = "編成名を入力してください。"
		return
	_draft.display_name = name
	if _draft.id.strip_edges() == "":
		var existing := _catalog.team_ids() if _catalog != null else PackedStringArray()
		_draft.id = TeamStore.make_team_id(name, existing)
	# 割当欠けても保存する。
	var err := TeamStore.save_team(_draft, _store_dir)
	if err != OK:
		_status_label.text = "保存に失敗しました (err=%d)" % err
		return
	if _catalog != null:
		_catalog.teams[_draft.id] = TeamStore.clone_team(_draft)
	_is_new = false
	_status_label.text = "保存しました: %s" % _draft.display_name
	_populate_load_options(_draft.id)
	_refresh_id_label()
	saved.emit(TeamStore.clone_team(_draft))


func _on_close() -> void:
	visible = false
	closed.emit()
