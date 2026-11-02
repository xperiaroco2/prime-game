class_name HudSlot
extends PanelContainer
## One of the round HUD's three places (#489, #1218, #1570; ARCHITECTURE §4.7.37; GDD §6 "Drawing
## from the belt": three numbered places, the one in the hand lit), drawn as the UI handoff's tiles
## (prime-game-ui `ui-2.5.4` `docs/handoff/s07-hud.md`) `Hud/Slots/Hand` and `Belt`: `Place<n>` >
## `V` ToyColumnFour > `Head` ToyKicker (uppercase), `Picture` and `Name` ToySlotTagText. The place
## in the hand is the handoff's Hand (ToySlotHand, "Hand", its picture tinted by ToySlotText), the
## others its Belt (ToySlotBelt, "Belt", tinted by ToyTextOnDark). Empty: the slot's empty picture
## (`slot-empty-hand`, `slot-empty-belt`) and no name; an item: its line icon and its name inside
## the tile at its bottom, wrapped at word boundaries onto at most two lines (the ellipsis only
## after the second, #1017). A kind with no pack icon shows its name alone. The tile's size is its
## variation's `width` and `height` (117 x 132), the same for a two-handed item (the handoff draws
## no wide hand). `Number` over the top left keeps the game's place number (the handoff draws two
## tiles; the game has three places, GDD §6: kept, listed for the engineer in #1570's PR).

## The picture's size, px at the 1920x1080 base (the handoff's 57 x 57). Layout, not style.
const PICTURE_SIZE := Vector2(57, 57)
## An item's name wraps at word boundaries onto at most this many lines (#1017).
const NAME_LINES := 2
const HAND := &"ToySlotHand"
const BELT := &"ToySlotBelt"

var v := VBoxContainer.new()
var head := UiParts.styled_label("", &"ToyKicker")
var picture := TextureRect.new()
var name_label := UiParts.styled_label("", &"ToySlotTagText")
var number_label := UiParts.styled_label("", &"ToySlotTextEmpty")
var tint_from: StringName
var lit := false
var _slot := HudText.Slot.new()


func _init(number: int) -> void:
	name = "Place%d" % number
	size_flags_vertical = Control.SIZE_SHRINK_END
	v.name = "V"
	v.theme_type_variation = &"ToyColumnFour"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	head.name = "Head"
	head.uppercase = true
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picture.name = "Picture"
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.custom_minimum_size = PICTURE_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = NAME_LINES
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.visible = false
	name_label.resized.connect(_fit_name_height)
	number_label.name = "Number"
	number_label.text = str(number)
	# In the tile's top left corner over the column, so it never widens the tile.
	number_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	number_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for node: Control in [self, v, head, picture, name_label, number_label]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	v.add_child(picture)
	v.add_child(name_label)
	add_child(v)
	add_child(number_label)
	_light(false)
	# Deferred, as in UiParts.sized: the theme cache is still the old one while it is emitted.
	theme_changed.connect(_restyle, CONNECT_DEFERRED)


func show_slot(slot: HudText.Slot) -> void:
	_slot = slot
	var texture := ToyIcons.texture(slot.icon) if not slot.icon.is_empty() else null
	if slot.is_empty():
		texture = ToyIcons.texture(&"slot-empty-hand" if lit else &"slot-empty-belt")
	picture.texture = texture
	picture.visible = texture != null
	name_label.text = slot.item
	name_label.visible = not slot.is_empty()
	_fit_name_height()


func light(on: bool) -> void:
	if lit != on:
		_light(on)
		show_slot(_slot)
		_restyle()


## The item's name shown, "" for an empty place.
func shown_item() -> String:
	return name_label.text if name_label.visible else ""


func _light(on: bool) -> void:
	lit = on
	theme_type_variation = HAND if on else BELT
	tint_from = &"ToySlotText" if on else &"ToyTextOnDark"
	head.text = "hud.slot.hand" if on else "hud.slot.belt"


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_restyle()


func _restyle() -> void:
	if not is_inside_tree():
		return
	custom_minimum_size = UiParts.size_of(self)
	picture.self_modulate = picture.get_theme_color(&"font_color", tint_from)
	# The name wraps inside the tile's content width (the variation's width less its margins).
	var inner := custom_minimum_size.x - get_theme_stylebox(&"panel").get_minimum_size().x
	name_label.custom_minimum_size.x = maxf(0.0, inner)
	name_label.custom_maximum_size = Vector2(maxf(0.0, inner), -1)
	_fit_name_height()


func _fit_name_height() -> void:
	var lines := clampi(name_label.get_line_count(), 1, NAME_LINES)
	var spacing := name_label.get_theme_constant(&"line_spacing")
	var height := name_label.get_line_height() * lines + spacing * (lines - 1)
	if not is_equal_approx(name_label.custom_minimum_size.y, height):
		name_label.custom_minimum_size.y = height
