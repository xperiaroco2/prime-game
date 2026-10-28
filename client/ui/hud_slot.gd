class_name HudSlot
extends PanelContainer
## One of the round HUD's three places (#489, #1218; ARCHITECTURE §4.7.37; GDD §6 "Drawing from
## the belt": three numbered icons, the one in the hand lit), after the UI handoff's (prime-game-ui
## `ui-0.4.0` `docs/handoff/s07-hud.md`) `Hud/Slots/Hand` and `Belt`: `Place<n>` > `Center`
## CenterContainer > `Row` ToyRowEight > `Icon`, `Name` and `ItemName`, and `Number` over the top
## left, always showing the place's number. The place in the hand is lit (the handoff's Hand:
## ToySlotActive, empty showing "Hand"), the others not (its Belt: ToySlot, empty showing "Belt").
## One pattern for all:
## empty shows the slot's name; a one-handed item only its icon (48 px); a two-handed item (the
## package) widens the slot to its variation's `wide_width` and shows its icon and its name,
## wrapped at 106 px onto at most two lines (word boundaries; the ellipsis only after the second
## line, #1017): the slot keeps its width and its height takes the second line. A kind with no pack
## icon shows its name instead. The slot never repeats the package's room sign (#255).

## The icon's size and the item name's width, px at the 1920x1080 base (the handoff: 106 = 180, the
## wide width, - 2 x 9, the content margins, - 48, the icon, - 8, the gap). Layout, not style.
const ICON_SIZE := Vector2(48, 48)
const ITEM_NAME_SIZE := Vector2(106, 0)
## A two-handed item's name wraps at word boundaries onto at most this many lines (#1017).
const ITEM_NAME_LINES := 2

var center := CenterContainer.new()
var row := HBoxContainer.new()
var icon := TextureRect.new()
## The place's number (GDD §6: places 1, 2 and 3), always shown.
var number_label := UiParts.styled_label("", &"ToySlotTextEmpty")
## The slot's name (a deck key), shown while it is empty.
var name_label := UiParts.styled_label("", &"ToySlotTextEmpty")
## A two-handed item's name (a deck key or a display name).
var item_label := UiParts.styled_label("", &"ToySlotText")
## The item's icon tint: the `font_color` of this variation (the handoff: ToySlotText for the hand,
## ToyTextOnDark for the belt; the same cream today).
var tint_from: StringName
## Whether the slot has its wide width now.
var wide := false
## Whether the slot is the place in the hand now (lit).
var lit := false


## Place `number` (1 to 3), named `Place<number>`, not lit.
func _init(number: int) -> void:
	name = "Place%d" % number
	number_label.name = "Number"
	number_label.text = str(number)
	# In the slot's top left corner over the centred row, so it never widens the slot (the
	# handoff's widths stay).
	number_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	number_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_light(false)
	item_label.resized.connect(_fit_item_height)
	center.name = "Center"
	row.name = "Row"
	row.theme_type_variation = &"ToyRowEight"
	icon.name = "Icon"
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	name_label.name = "Name"
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_label.name = "ItemName"
	item_label.custom_minimum_size = ITEM_NAME_SIZE
	item_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_label.custom_maximum_size = Vector2(ITEM_NAME_SIZE.x, -1)
	item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_label.max_lines_visible = ITEM_NAME_LINES
	item_label.clip_text = true
	item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item_label.visible = false
	for node: Control in [self, center, row, number_label, icon, name_label, item_label]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	row.add_child(name_label)
	row.add_child(item_label)
	center.add_child(row)
	add_child(center)
	add_child(number_label)
	# Deferred, as in UiParts.sized: the theme cache is still the old one while it is emitted.
	theme_changed.connect(_restyle, CONNECT_DEFERRED)


## Shows `slot`: its name while empty, else the item's icon, and its name when two-handed (or when
## its kind has no icon).
func show_slot(slot: HudText.Slot) -> void:
	var texture := ToyIcons.texture(slot.icon) if not slot.icon.is_empty() else null
	name_label.visible = slot.is_empty()
	icon.texture = texture
	icon.visible = not slot.is_empty() and texture != null
	item_label.text = slot.item
	_fit_item_height()
	item_label.visible = not slot.is_empty() and (slot.two_handed or texture == null)
	if wide != slot.two_handed:
		wide = slot.two_handed
		_restyle()


## Lights the slot as the place in the hand (`on`), or not; nothing when it already is.
func light(on: bool) -> void:
	if lit != on:
		_light(on)
		_restyle()


## The item's name shown now ("" while empty): a deck key or a display name.
func shown_item() -> String:
	return "" if name_label.visible else item_label.text


## The handoff's Hand look when `on`, its Belt look otherwise.
func _light(on: bool) -> void:
	lit = on
	theme_type_variation = &"ToySlotActive" if on else &"ToySlot"
	tint_from = &"ToySlotText" if on else &"ToyTextOnDark"
	name_label.text = "hud.slot.hand" if on else "hud.slot.belt"


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_restyle()


## The slot's size from its variation (wide or not) and the icon's tint, read again after every
## theme change (the large-text swap).
func _restyle() -> void:
	if not is_inside_tree():
		return
	custom_minimum_size = UiParts.size_of(self, wide)
	icon.self_modulate = icon.get_theme_color(&"font_color", tint_from)
	_fit_item_height()


## The item name's height: a Label that wraps and trims has a minimum height of 1 px (it takes the
## height its container gives), so the label is given the lines its name wraps to at its width, one
## or two (#1017). Run again when the width settles (resized), since the lines depend on it.
func _fit_item_height() -> void:
	var lines := clampi(item_label.get_line_count(), 1, ITEM_NAME_LINES)
	var spacing := item_label.get_theme_constant(&"line_spacing")
	var height := item_label.get_line_height() * lines + spacing * (lines - 1)
	if not is_equal_approx(item_label.custom_minimum_size.y, height):
		item_label.custom_minimum_size.y = height
