class_name FindPage
extends HBoxContainer
## The suit menu's Find a lobby (prime-game-ui's s05 `ship-find`, `ship-empty`, `ship-code` and
## `ship-direct` at ui-2.5.4, #1285; ARCHITECTURE §4.7.66): the page beside the panel in the ship
## with no session, holding the jobs of the removed main menu (s2).
## - `Nearby` (at the left): the lobbies nearby (#1316, LobbyFinder's list, show_lobbies): `List`,
##   one ToyPresetCard toggle row per lobby in one ButtonGroup (its name, players of the most and
##   the round trip; a full one disabled, dim, `connect.fail.full`), the first lobby with room
##   chosen, and `Join` under it (a double click on a row too): the lobby's code when it has one,
##   else its address and port. None found: the one quiet line, `find.none` (s05 `ship-empty`).
## - `Code` (420 px): the code entry (the code alphabet only, six characters, MainMenu.code_text),
##   Join (enabled with six), then the quiet Join by address, which swaps in `Address`.
## - `Address` (420 px, in Code's place): the host address (host or host:port, JoinTarget), the
##   default port, Join (enabled with an address), Host (hosts directly on the typed port, else
##   the default) and Back (the code entry again; Esc too, EscMenu.close_page's first step).
## What was typed stays after a failure. Styled only through the shared theme's variations.

## Join by the code `code` (Join, or Enter in the full field).
signal code_join_requested(code: String)
## Join directly at `address` on `port` unless the address names one (JoinTarget).
signal direct_join_requested(address: String, port: int)
## Host directly on `port`.
signal direct_host_requested(port: int)

## The code and address columns' width (the handoff's: it holds "Join by address").
const COLUMN_WIDTH := 420
## A lobby row's height and its content's inset (the handoff's: the target's 40 x 1.5, the
## ToyPresetCard `normal` StyleBox's content margins).
const ROW_HEIGHT := 60.0
const ROW_INSET := 16.0
## The rows shown before the list scrolls (s05: "A long list scrolls").
const ROWS_SHOWN := 5

var nearby := VBoxContainer.new()
var lobby_list := VBoxContainer.new()
var lobby_scroll := UiParts.scroll()
var none_label := UiParts.styled_label("find.none", &"ToyTextMutedOnLight")
var nearby_join := Button.new()
## Each lobby's row by its host's number (LobbyBeacon.Answer.host).
var rows: Dictionary[int, Button] = {}
var code_column := VBoxContainer.new()
var code_edit := LineEdit.new()
var code_join := Button.new()
var direct_button := Button.new()
var address_column := VBoxContainer.new()
var address_edit := LineEdit.new()
var port_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
var address_join := Button.new()
var address_host := Button.new()
var back_button := Button.new()
## The port a direct join or host uses when the address names none.
var default_port := LaunchOptions.DEFAULT_PORT

## The lobbies shown, by host number, and the chosen one's (-1: none).
var _lobbies: Dictionary[int, LobbyFinder.Found] = {}
var _chosen := -1
var _group := ButtonGroup.new()


func _init() -> void:
	name = "Find"
	theme_type_variation = &"ToyRowTwentyFour"
	_build_nearby()
	_build_code()
	_build_address()
	show_direct(false)
	_refresh()


## Join by address's entry in the code entry's place (true), or the code entry back (false).
func show_direct(on: bool) -> void:
	code_column.visible = not on
	address_column.visible = on
	# The hidden button had the focus: the address field takes it, or Join by address again.
	if is_visible_in_tree():
		var focus: Control = address_edit if on else direct_button
		focus.grab_focus.call_deferred()


func direct_open() -> bool:
	return address_column.visible


## The default port shown under the address and used without one.
func set_default_port(port: int) -> void:
	default_port = port
	_write_port()


## The code typed so far (the game fills it from --join=CODE).
func set_code(code: String) -> void:
	code_edit.text = MainMenu.code_text(code)
	_refresh()


## The address typed so far (the game fills it from --join=HOST).
func set_address(address: String) -> void:
	address_edit.text = address
	_refresh()


## The lobbies found nearby now (LobbyFinder.lobbies()): a row per lobby, kept across calls by its
## host, the gone ones removed; the chosen one stays while it has room, else the first with room.
func show_lobbies(found: Array[LobbyFinder.Found]) -> void:
	var now: Dictionary[int, LobbyFinder.Found] = {}
	for each: LobbyFinder.Found in found:
		now[each.answer.host] = each
	for host: int in rows.keys():
		if not now.has(host):
			# Freed at once: show_lobbies runs from the game's frame, never from a row's own signal.
			lobby_list.remove_child(rows[host])
			rows[host].free()
			rows.erase(host)
	_lobbies = now
	for host: int in now:
		if not rows.has(host):
			rows[host] = _row(host)
			lobby_list.add_child(rows[host])
		_write_row(host)
	if not _lobbies.has(_chosen) or rows[_chosen].disabled:
		_chosen = -1
		for host: int in now:
			if not rows[host].disabled:
				_chosen = host
				break
	for host: int in rows:
		SettingRows.set_pressed(rows[host], host == _chosen)
	lobby_scroll.visible = not now.is_empty()
	var shown := mini(now.size(), ROWS_SHOWN)
	var gap := lobby_list.get_theme_constant(&"separation")
	lobby_scroll.custom_minimum_size.y = shown * ROW_HEIGHT + maxi(shown - 1, 0) * gap
	none_label.visible = now.is_empty()
	nearby_join.visible = not now.is_empty()
	nearby_join.disabled = _chosen < 0


## The chosen lobby's host number, -1 for none.
func chosen() -> int:
	return _chosen


## Join on the chosen lobby: by its code when it has one, else at its address and port.
func join_chosen() -> void:
	var lobby: LobbyFinder.Found = _lobbies.get(_chosen)
	if lobby == null or rows[_chosen].disabled:
		return
	if not lobby.answer.code.is_empty():
		code_join_requested.emit(lobby.answer.code)
	elif lobby.answer.port > 0:
		direct_join_requested.emit(lobby.address, lobby.answer.port)


## The lobby's name as its row shows it: the name its host gave, else `lobby.default_name`.
static func lobby_text(answer: LobbyBeacon.Answer) -> String:
	if not answer.lobby_name.is_empty():
		return answer.lobby_name
	return String(TranslationServer.translate("lobby.default_name")).format(
		{"name": answer.host_name}
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_write_port()
		for host: int in rows:
			_write_row(host)


func _write_port() -> void:
	port_label.text = tr("join.port").format({"port": str(default_port)})


## As the main menu's (MainMenu.refresh_buttons): Join a whole code or an address that parses,
## Host a port that parses or none.
func _refresh() -> void:
	code_join.disabled = not SignalCodec.is_code(code_edit.text)
	var target := JoinTarget.of_direct(address_edit.text, default_port)
	address_join.disabled = not target.problem.is_empty()
	address_host.disabled = target.port_problem


func _join_code() -> void:
	if not code_join.disabled:
		code_join_requested.emit(MainMenu.code_text(code_edit.text))


func _join_direct() -> void:
	if not address_join.disabled:
		direct_join_requested.emit(address_edit.text.strip_edges(), default_port)


func _host_direct() -> void:
	var port := MainMenu.typed_port(address_edit.text, default_port)
	if port > 0:
		direct_host_requested.emit(port)


func _on_code_changed(typed: String) -> void:
	var kept := MainMenu.code_text(typed)
	if kept != typed:
		var caret := MainMenu.code_text(typed.left(code_edit.caret_column)).length()
		code_edit.text = kept
		code_edit.caret_column = caret
	_refresh()


func _build_nearby() -> void:
	nearby.name = "Nearby"
	nearby.theme_type_variation = &"ToyColumnTwelve"
	nearby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nearby.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(nearby)
	nearby.add_child(_head("find.nearby"))
	# The list in a scroll as tall as ROWS_SHOWN rows: more scroll (s05's note on List).
	lobby_scroll.name = "Scroll"
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_scroll.visible = false
	nearby.add_child(lobby_scroll)
	lobby_list.name = "List"
	lobby_list.theme_type_variation = &"ToyColumnEight"
	lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(lobby_list)
	none_label.name = "None"
	nearby.add_child(none_label)
	_button(nearby_join, "Join", "join.connect", &"ToyButtonPrimary", join_chosen)
	nearby_join.size_flags_horizontal = Control.SIZE_SHRINK_END
	nearby_join.visible = false
	nearby.add_child(nearby_join)


## A lobby's row: a ToyPresetCard toggle whose content is H (Name, Count, Ping, Full); every part
## ignores the mouse, so the button takes the press.
func _row(host: int) -> Button:
	var row := UiParts.toggle("", func() -> void: _choose(host), &"ToyPresetCard")
	row.name = "Lobby%d" % host
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.button_group = _group
	row.gui_input.connect(_on_row_input.bind(host))
	var line := HBoxContainer.new()
	line.name = "H"
	line.theme_type_variation = &"ToyRowTwelve"
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = ROW_INSET
	line.offset_top = ROW_INSET
	line.offset_right = -ROW_INSET
	line.offset_bottom = -ROW_INSET
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var title := UiParts.styled_label("", &"ToyPresetCardName")
	title.name = "Name"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(title)
	var count := UiParts.styled_label("", &"ToyPresetCardName")
	count.name = "Count"
	line.add_child(count)
	var ping := UiParts.styled_label("", &"ToyPresetCardNote")
	ping.name = "Ping"
	line.add_child(ping)
	var full := UiParts.styled_label("connect.fail.full", &"ToyPresetCardNote")
	full.name = "Full"
	line.add_child(full)
	for label: Label in [title, count, ping, full]:
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if label != full:
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for inner: Node in row.get_children(true):
		if inner is ToyToggle:
			(inner as ToyToggle).companion(ping, &"ToyPresetCardNote", &"ToyPresetCardNoteSelected")
	return row


## Writes lobby `host`'s row from its latest answer, in the language now.
func _write_row(host: int) -> void:
	var lobby := _lobbies[host]
	var row := rows[host]
	var has_room := lobby.answer.has_room()
	row.disabled = not has_room
	var title := row.get_node(^"H/Name") as Label
	title.text = lobby_text(lobby.answer)
	title.theme_type_variation = &"ToyPresetCardName" if has_room else &"ToyPresetCardNote"
	var count := row.get_node(^"H/Count") as Label
	count.text = "%d / %d" % [lobby.answer.players, lobby.answer.most]
	count.visible = has_room
	var ping := row.get_node(^"H/Ping") as Label
	ping.text = tr("unit.ms").format({"count": lobby.ping_ms})
	ping.visible = has_room
	(row.get_node(^"H/Full") as Control).visible = not has_room


func _choose(host: int) -> void:
	if rows.has(host) and not rows[host].disabled:
		_chosen = host
	for each: int in rows:
		SettingRows.set_pressed(rows[each], each == _chosen)
	nearby_join.disabled = _chosen < 0


## A double click on a row is its Join (s05); a disabled row (a full lobby) still gets the
## input, and joins nothing, never the lobby chosen before.
func _on_row_input(event: InputEvent, host: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or not click.double_click:
		return
	if click.button_index != MOUSE_BUTTON_LEFT or not rows.has(host) or rows[host].disabled:
		return
	_choose(host)
	join_chosen()


func _build_code() -> void:
	_column(code_column, "Code")
	code_column.add_child(_head("common.code"))
	_edit(code_edit, SignalCodec.CODE_LENGTH)
	code_edit.text_changed.connect(_on_code_changed)
	code_edit.text_submitted.connect(func(_text: String) -> void: _join_code())
	code_column.add_child(code_edit)
	_button(code_join, "Join", "join.connect", &"ToyButtonSecondary", _join_code)
	code_column.add_child(code_join)
	_button(
		direct_button, "Direct", "menu.direct", &"ToyButtonGhostOnLight", show_direct.bind(true)
	)
	direct_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	code_column.add_child(direct_button)


func _build_address() -> void:
	_column(address_column, "Address")
	address_column.add_child(_head("join.address"))
	_edit(address_edit, 0)
	address_edit.text_changed.connect(func(_text: String) -> void: _refresh())
	address_edit.text_submitted.connect(func(_text: String) -> void: _join_direct())
	address_column.add_child(address_edit)
	port_label.name = "Port"
	port_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	address_column.add_child(port_label)
	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.theme_type_variation = &"ToyColumnTwelve"
	address_column.add_child(buttons)
	_button(address_join, "Join", "join.connect", &"ToyButtonSecondary", _join_direct)
	buttons.add_child(address_join)
	_button(address_host, "Host", "menu.host", &"ToyButtonSecondary", _host_direct)
	buttons.add_child(address_host)
	_button(back_button, "Back", "common.back", &"ToyButtonGhostOnLight", show_direct.bind(false))
	buttons.add_child(back_button)
	_write_port()


func _column(column: VBoxContainer, column_name: String) -> void:
	column.name = column_name
	column.theme_type_variation = &"ToyColumnTwelve"
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	add_child(column)


## A column's head in small capitals.
static func _head(key: String) -> Label:
	var head := UiParts.styled_label(key, &"ToyKicker")
	head.name = "Head"
	head.uppercase = true
	return head


## A ToyField named Field: no context menu (its words are Godot's own English), data typed.
static func _edit(edit: LineEdit, most: int) -> void:
	edit.name = "Field"
	edit.theme_type_variation = &"ToyField"
	edit.context_menu_enabled = false
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if most > 0:
		edit.max_length = most


static func _button(
	button: Button, button_name: String, key: String, variation: StringName, pressed: Callable
) -> void:
	button.name = button_name
	button.text = key
	button.theme_type_variation = variation
	button.pressed.connect(pressed)
	ToyPress.attach(button)
