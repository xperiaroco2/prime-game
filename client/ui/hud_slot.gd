class_name HudSlot
extends PanelContainer
## One of the round HUD's two slots (#489; ARCHITECTURE §4.7.37): the UI handoff's (prime-game-ui
## `ui-0.4.0` `docs/handoff/s07-hud.md`) `Hud/Slots/Hand` and `Belt`, `<slot>` > `Center`
## CenterContainer > `Row` ToyRowEight > `Icon`, `Name` and `ItemName`. One pattern for both: empty
## shows the slot's name; a one-handed item only its icon (48 px); a two-handed item (the package)
## widens the slot to its variation's `wide_width` and shows its icon and its name, cut at 106 px
## with an ellipsis. A kind with no pack icon shows its name instead. The slot never repeats the
## package's room sign (#255).

## The icon's size and the item name's width, px at the 1920x1080 base (the handoff: 106 = 180, the
## wide width, - 2 x 9, the content margins, - 48, the icon, - 8, the gap). Layout, not style.
const ICON_SIZE := Vector2(48, 48)
const ITEM_NAME_SIZE := Vector2(106, 0)

var center := CenterContainer.new()
var row := HBoxContainer.new()
var icon := TextureRect.new()
## The slot's name (a deck key), shown while it is empty.
var name_label := UiParts.styled_label("", &"ToySlotTextEmpty")
## A two-handed item's name (a deck key or a display name).
var item_label := UiParts.styled_label("", &"ToySlotText")
## The item's icon tint: the `font_color` of this variation (the handoff: ToySlotText for the hand,
## ToyTextOnDark for the belt; the same cream today).
var tint_from: StringName
## Whether the slot has its wide width now.
var wide := false


## A slot named `node_name` of `variation` (ToySlotActive, ToySlot), empty showing `slot_key`.
func _init(
	node_name: String, variation: StringName, slot_key: String, icon_tint: StringName
) -> void:
	name = node_name
	theme_type_variation = variation
	tint_from = icon_tint
	center.name = "Center"
	row.name = "Row"
	row.theme_type_variation = &"ToyRowEight"
	icon.name = "Icon"
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	name_label.name = "Name"
	name_label.text = slot_key
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_label.name = "ItemName"
	item_label.custom_minimum_size = ITEM_NAME_SIZE
	item_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_label.clip_text = true
	item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item_label.visible = false
	for node: Control in [self, center, row, icon, name_label, item_label]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	row.add_child(name_label)
	row.add_child(item_label)
	center.add_child(row)
	add_child(center)
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
	item_label.visible = not slot.is_empty() and (slot.two_handed or texture == null)
	if wide != slot.two_handed:
		wide = slot.two_handed
		_restyle()


## The item's name shown now ("" while empty): a deck key or a display name.
func shown_item() -> String:
	return "" if name_label.visible else item_label.text


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
