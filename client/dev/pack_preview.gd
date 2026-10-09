extends Control
## A preview of the UI pack's assets in the game for `tools\run.cmd shot` (#520): English on the
## left and Ukrainian on the right, each with a title, the eight room pictograms (white SVGs tinted
## with the map room text's ink, as the s08 handoff tints them) and their names, every icon of
## `icons/` at its import scale, the base slider and dropdown with the pack's grabber and arrow,
## and a name plate with the teammate mark; under them the four Delivery cards (the s08 how-to
## frames, 320x240, untinted). Both columns read the copy deck at once (each label's text from its
## language's Translation, not the game's locale). Until the Comfortaa TTF lands (#520) the text is
## Godot's default font. Dev only: nothing here reaches the game.

const ART := "res://assets/ui/toy_pack/"
const ROOMS: Array[String] = [
	"storage", "kitchen", "lab", "office", "hall", "lounge", "server", "workshop"
]
const ICONS: Array[String] = [
	"check",
	"chevron-down",
	"chevron-left",
	"chevron-right",
	"item",
	"knife",
	"lock",
	"mic",
	"mic-off",
	"pointer",
	"swatch-disc",
	"teammate-mark",
	"radio-checked",
	"radio-checked-disabled",
	"radio-unchecked",
	"slider-knob",
	"slider-knob-disabled",
]
## The icons the pack draws in their own colours (`tint: none`); the others are white and tinted.
const UNTINTED: Array[String] = [
	"radio-checked",
	"radio-checked-disabled",
	"radio-unchecked",
	"slider-knob",
	"slider-knob-disabled"
]
const CARD := Vector2(320.0, 240.0)
const PLATE_NAMES := {Languages.ENGLISH: "Olena", Languages.UKRAINIAN: "Євген"}


func _ready() -> void:
	theme = GameUi.THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiParts.backdrop(self, &"ToyBackdrop")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 24)
	margin.add_child(page)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	page.add_child(columns)
	for language: String in Languages.ALL:
		columns.add_child(_column(language))
	page.add_child(_cards())


## One language's panel: the title, the rooms, the icons, the controls and a name plate.
func _column(language: String) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToyPanelMenu"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label(_text(language, "menu.settings"), &"ToyTitleOnLight"))
	var rooms := GridContainer.new()
	rooms.columns = 4
	rooms.add_theme_constant_override("h_separation", 18)
	rooms.add_theme_constant_override("v_separation", 8)
	var ink := get_theme_color(&"font_color", &"ToyMapRoomText")
	for room in ROOMS:
		var cell := HBoxContainer.new()
		cell.add_child(_icon("icons/room/%s.svg" % room, ink))
		var name_text := _text(language, "room." + room)
		cell.add_child(_label(room if name_text.is_empty() else name_text, &"ToyMapRoomText"))
		rooms.add_child(cell)
	box.add_child(rooms)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 10)
	var text_ink := get_theme_color(&"font_color", &"ToyTextOnLight")
	for icon in ICONS:
		var tint := Color.WHITE if UNTINTED.has(icon) else text_ink
		icons.add_child(_icon("icons/%s.svg" % icon, tint))
	box.add_child(icons)
	var slider := HSlider.new()
	slider.value = 60.0
	slider.custom_minimum_size = Vector2(320.0, 0.0)
	box.add_child(_row(_text(language, "settings.voice_volume"), slider))
	var talk := OptionButton.new()
	talk.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	talk.add_item(_text(language, "settings.talk_mode.push"))
	talk.add_item(_text(language, "settings.talk_mode.open"))
	box.add_child(_row(_text(language, "settings.talk_mode"), talk))
	var plate := NamePlate.new()
	plate.show_player(str(PLATE_NAMES[language]), true)
	var plate_row := HBoxContainer.new()
	plate_row.add_child(plate)
	plate_row.add_child(
		_label(
			_text(language, "pregame.teammate").format({"names": PLATE_NAMES[language]}),
			&"ToyTextOnLight"
		)
	)
	box.add_child(plate_row)
	return panel


## The four Delivery cards as the s08 how-to frames draw them.
func _cards() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for frame in range(1, 5):
		var card := PanelContainer.new()
		card.theme_type_variation = &"ToyHowtoFrameDone" if frame == 4 else &"ToyHowtoFrame"
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = load(ART + "cards/delivery-%d.png" % frame) as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = CARD
		card.add_child(art)
		row.add_child(card)
	return row


## A control after its name, on the light panel (UiParts.labelled's text is for dark ones).
func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _label(text, &"ToyTextOnLight")
	label.custom_minimum_size = Vector2(260.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _icon(path: String, tint: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = load(ART + path) as Texture2D
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.self_modulate = tint
	return rect


func _label(text: String, variation: StringName) -> Label:
	var label := UiParts.styled_label(text, variation)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


## The copy deck's text of `key` in `language`, whatever the game's locale.
func _text(language: String, key: String) -> String:
	var translation := TranslationServer.get_translation_object(language)
	if translation == null:
		return key
	return str(translation.get_message(StringName(key)))
