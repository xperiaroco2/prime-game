class_name HowtoCardView
extends PanelContainer
## A how-to card as drawn (#254; prime-game-ui's P8 at ui-0.4.0, the same tree in s3's loading
## card, s8's map card and s5's Guide): the face, ToyPanelHowto, holding V with Head (the title,
## the card's deck key, and the corner label `howto.label`) and Frames (Frame1 to Frame4, each a
## ToyHowtoFrame, the finish frame ToyHowtoFrameDone, holding its Art), and on the map Bar with
## Close. raised() puts it on its toy base. Wordless: a frame holds only its picture; a frame with
## no picture yet shows its deck key's words (the Guide's basics), and a picture whose PNG is
## missing shows a placeholder naming the file (the UI pack's cards come with #520).

## Close was pressed (the map's card; Esc and the map key close it there too).
signal close_requested

## The art's size per place, 4:3 (px at the 1920x1080 base; the handoff's numbers).
const MAP_ART := Vector2(320, 240)
const LOADING_ART := Vector2(352, 264)
const GUIDE_ART := Vector2(160, 120)

var card: HowtoCard
var title_label := Label.new()
var frames_box := HBoxContainer.new()
## Close, on the map's card only; null elsewhere.
var close_button: Button
## Each frame's words (a frame without a picture) by frame index, set again on a language change.
var _words: Dictionary[int, Label] = {}


func _init(shown: HowtoCard, art_size: Vector2, with_close := false) -> void:
	card = shown
	name = "Card"
	theme_type_variation = &"ToyPanelHowto"
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnSixteen"
	add_child(column)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.theme_type_variation = &"ToyRowSixteen"
	column.add_child(head)
	title_label.name = "Title"
	title_label.theme_type_variation = &"ToyTitleOnLight"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text = String(shown.title)
	head.add_child(title_label)
	var note := UiParts.styled_label("howto.label", &"ToyHowtoNote")
	note.name = "Note"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(note)
	frames_box.name = "Frames"
	frames_box.theme_type_variation = &"ToyRowTwelve"
	column.add_child(frames_box)
	for i in shown.frames.size():
		frames_box.add_child(_frame(i, shown.frames[i], art_size))
	if with_close:
		var bar := HBoxContainer.new()
		bar.name = "Bar"
		bar.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(bar)
		var raised := UiParts.button(
			"common.close", close_requested.emit, &"ToyButtonSecondary", ToyHints.LIGHT
		)
		close_button = raised.face as Button
		close_button.name = "Close"
		raised.name = "CloseRaised"
		bar.add_child(raised)
	_retext()


## `shown` drawn with `art_size` art on its toy base for a `context` screen (ToyHints.DARK on the
## loading screen, LIGHT over the map and in the Esc menu).
static func raised(
	shown: HowtoCard, art_size: Vector2, context: StringName, with_close := false
) -> ToyRaised:
	return UiParts.raised(HowtoCardView.new(shown, art_size, with_close), context)


## The face inside a card made by raised(); null for anything else.
static func face_of(made: ToyRaised) -> HowtoCardView:
	return made.face as HowtoCardView if made != null else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retext()


## A frame's words in the language now, `{key}` filled with its action's bound key.
static func words_of(frame: HowtoFrame) -> String:
	var said := String(TranslationServer.translate(frame.text))
	if frame.key_action.is_empty():
		return said
	return said.format({"key": KeyLabel.of_action(frame.key_action)})


## The frame's picture, or null while its PNG is missing (not imported yet).
static func art_of(frame: HowtoFrame) -> Texture2D:
	if frame.art.is_empty() or not ResourceLoader.exists(frame.art):
		return null
	return load(frame.art) as Texture2D


func _frame(index: int, frame: HowtoFrame, art_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Frame%d" % (index + 1)
	panel.theme_type_variation = &"ToyHowtoFrameDone" if frame.done else &"ToyHowtoFrame"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var texture := art_of(frame)
	if texture != null:
		var art := TextureRect.new()
		art.name = "Art"
		art.custom_minimum_size = art_size
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(art)
		return panel
	# Words (a basic's frame), or a placeholder naming the PNG that is not in the game yet.
	var stand_in := Label.new()
	stand_in.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	stand_in.custom_minimum_size = art_size
	stand_in.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stand_in.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stand_in.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if frame.text.is_empty():
		stand_in.name = "Placeholder"
		stand_in.theme_type_variation = &"ToyTextMutedOnLight"
		stand_in.text = frame.art.get_file()
	else:
		stand_in.name = "Words"
		stand_in.theme_type_variation = &"ToyTextOnLight"
		_words[index] = stand_in
	panel.add_child(stand_in)
	return panel


func _retext() -> void:
	for index: int in _words:
		_words[index].text = words_of(card.frames[index])
