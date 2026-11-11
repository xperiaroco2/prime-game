class_name HowtoCardView
extends PanelContainer
## A how-to card as drawn (#254; prime-game-ui's P8, at ui-2.5.4 the same tree in s3's loading
## card, s8's map card and s5's Guide, #1570): the face, ToyPanelHowto, holding V with Head (a tile
## head: `howto.label` in small capitals over the title, the card's deck key), Scroll (sideways,
## no bar drawn, as wide as the place gives; with no width it takes its frames' width) > Frames
## (one per frame, each a ToyHowtoFrame, the finish frame ToyHowtoFrameDone, holding its Art), and
## on the map Bar with Close. raised() puts it on its toy base. Wordless: a frame holds only its
## picture; a frame with no picture yet shows its deck key's words (the Guide's basics), and a
## picture whose PNG is missing shows a placeholder naming the file (the UI pack's cards, #520).

## Close was pressed (the map's card; Esc and the map key close it there too).
signal close_requested

## The art's size per place, 4:3 (px at the 1920x1080 base; the handoff's numbers).
const MAP_ART := Vector2(352, 264)
const LOADING_ART := Vector2(352, 264)
const GUIDE_ART := Vector2(160, 120)

var card: HowtoCard
var title_label := Label.new()
## The frames' sideways scroll and the frames in it.
var scroll := ScrollContainer.new()
var frames_box := HBoxContainer.new()
## Close, on the map's card only; null elsewhere.
var close_button: Button
## Each frame's words (a frame without a picture) by frame index, set again on a language change.
var _words: Dictionary[int, Label] = {}


## `shown` with `art_size` art per frame; `with_close` adds Bar > Close (the map's card); a
## `scroll_width` above 0 is the Scroll's width (the frames past it scroll sideways), else the
## Scroll takes the frames' width.
func _init(shown: HowtoCard, art_size: Vector2, with_close := false, scroll_width := 0.0) -> void:
	card = shown
	name = "Card"
	theme_type_variation = &"ToyPanelHowto"
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnTwentyFour"
	add_child(column)
	var head := VBoxContainer.new()
	head.name = "Head"
	head.theme_type_variation = &"ToyColumnEight"
	column.add_child(head)
	var note := UiParts.styled_label("howto.label", &"ToyKicker")
	note.name = "Note"
	note.uppercase = true
	head.add_child(note)
	title_label.name = "Title"
	title_label.theme_type_variation = &"ToyTitleOnLight"
	title_label.text = String(shown.title)
	head.add_child(title_label)
	scroll.name = "Scroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	if scroll_width > 0.0:
		# No bar drawn until the pack has a sideways one; the frame cut at the edge shows more.
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.custom_minimum_size = Vector2(scroll_width, 0)
	else:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	frames_box.name = "Frames"
	frames_box.theme_type_variation = &"ToyRowSixteen"
	scroll.add_child(frames_box)
	for i in shown.frames.size():
		frames_box.add_child(_frame(i, shown.frames[i], art_size))
	if with_close:
		var bar := HBoxContainer.new()
		bar.name = "Bar"
		bar.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(bar)
		var close_raised := UiParts.button(
			"common.close", close_requested.emit, &"ToyButtonSecondary", ToyHints.LIGHT
		)
		close_button = close_raised.face as Button
		close_button.name = "Close"
		close_raised.name = "CloseRaised"
		bar.add_child(close_raised)
	_retext()


## `shown` drawn with `art_size` art on its toy base for a `context` screen (ToyHints.DARK on the
## loading screen, LIGHT over the map and in the Esc menu).
static func raised(
	shown: HowtoCard, art_size: Vector2, context: StringName, with_close := false
) -> ToyRaised:
	return UiParts.raised(HowtoCardView.new(shown, art_size, with_close), context)


## The face of a card: the card itself, or the face inside one made by raised(); null for
## anything else.
static func face_of(made: Control) -> HowtoCardView:
	if made is HowtoCardView:
		return made as HowtoCardView
	return (made as ToyRaised).face as HowtoCardView if made is ToyRaised else null


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
