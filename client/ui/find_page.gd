class_name FindPage
extends HBoxContainer
## The suit menu's Find a lobby (prime-game-ui's s05 `ship-find`, `ship-empty`, `ship-code` and
## `ship-direct` at ui-2.5.4, #1285; ARCHITECTURE §4.7.66): the page beside the panel in the ship
## with no session, holding the jobs of the removed main menu (s2).
## - `Nearby` (at the left): the lobbies nearby, the game's discovery (#1316); none yet, so the
##   list's one quiet line, `find.none` (s05 `ship-empty`).
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

var nearby := VBoxContainer.new()
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_write_port()


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
	var none := UiParts.styled_label("find.none", &"ToyTextMutedOnLight")
	none.name = "None"
	nearby.add_child(none)


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
