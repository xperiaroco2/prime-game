class_name PinballDisplay
extends Node3D
## The pinball machine's display (#1400; ARCHITECTURE §4.7.63; GDD §3 "The pinball"): this lobby's
## best score and whose it is, and while a game is on its score and balls left, from the own
## ClientModel's ClientPinball alone (PinballState, which everyone gets). PinballViews places it on
## the level's display marker and calls show_state() each step; the text changes only when what it
## shows does (or the language).
##
## - The owner's name is drawn in the owner's body colour (the roster's), found by name:
##   PinballState carries the owner's name, not a peer (kept after the owner left, §7.1.22). Only a
##   name exactly one roster member has gets a colour; an owner gone or a name two members share is
##   drawn in the neutral colour, so no colour is ever a guess.
## - Captions are copy deck keys (`pinball.best`, `pinball.score`, `pinball.balls`; the raw key
##   shows until the deck has them) with the number after them, never inside a `{placeholder}` a
##   raw key would lose.
## - The lines fit the art cabinet's screen (SCREEN_M, #1721) and wear the game's UI font and
##   colours (the UI pack's, through the shared theme: BEST_LOOK, LINE_LOOK; the engineer's (a) on
##   #1721), light on the dark screen with no outline. Their sizes' ratio is provisional.

## The art cabinet's screen, width and height in metres, centred on the Display marker
## (prime-game-art pinball v6 HANDOFF: 66 x 38 cm; its `pinball_screen` surface spans it, #1721).
const SCREEN_M := Vector2(0.66, 0.38)
## The clear border inside the screen's edge, metres: no line reaches the trim.
const SCREEN_MARGIN_M := 0.02
## The lines' largest height in metres per pixel of font, and their font sizes (provisional). The
## three share one pixel size (`shared_pixel`, at most this), so their sizes keep their ratio (only
## a long owner name shrinks alone, _layout).
const PIXEL_M := 0.002
const BEST_SIZE := 64
const NAME_SIZE := 56
const GAME_SIZE := 40
## The lines' looks in the shared theme (GameUi.THEME, the UI pack's; the engineer's (a) on
## #1721): the best in the pack's display style, the owner and the game in its line style.
const BEST_LOOK := &"ToyDisplayOnLight"
const LINE_LOOK := &"ToyChipLineOnDarkText"

var best := Label3D.new()
var owner_name := Label3D.new()
var game := Label3D.new()
## The three lines' shared pixel size: PIXEL_M, or less so the three rows fit the screen's height.
var shared_pixel := PIXEL_M

## Each line's row on the screen (metres, the display's plane, y up, centred on the marker),
## best, owner, game, top to bottom: as tall as its line at `shared_pixel`, inside the margin.
var _rows: Array[Rect2] = []

var _model: ClientModel
## What the text shows now: [best, best_name, colour, score, balls_left, in_play, locale].
var _shown: Array = []


func _init() -> void:
	name = "PinballDisplay"
	var lines: Array[Label3D] = [best, owner_name, game]
	var names: Array[String] = ["Best", "Owner", "Game"]
	var sizes: Array[int] = [BEST_SIZE, NAME_SIZE, GAME_SIZE]
	for i in lines.size():
		var line := lines[i]
		line.name = names[i]
		line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		line.pixel_size = PIXEL_M
		line.font_size = sizes[i]
		var look := BEST_LOOK if line == best else LINE_LOOK
		line.font = ui_font(look)
		line.modulate = GameUi.THEME.get_color(&"font_color", look)
		line.outline_size = 0
		add_child(line)
	_layout()


## Shows `model`'s pinball (null shows nothing), re-texting only on a change.
func show_state(model: ClientModel) -> void:
	_model = model
	visible = model != null
	if model == null:
		_shown = []
		return
	var pinball := model.pinball
	var colour := owner_colour(model, pinball.best_name)
	var now: Array = [
		pinball.best,
		pinball.best_name,
		colour,
		pinball.score,
		pinball.balls_left,
		pinball.in_play or pinball.player >= 0,
		TranslationServer.get_locale(),
	]
	if now == _shown:
		return
	_shown = now
	best.text = "%s %d" % [tr(&"pinball.best"), pinball.best]
	owner_name.text = pinball.best_name
	owner_name.modulate = colour
	game.visible = now[5] as bool
	game.text = (
		"%s %d   %s %d"
		% [tr(&"pinball.score"), pinball.score, tr(&"pinball.balls"), pinball.balls_left]
	)
	_layout()


## Line `index`'s row (0 best, 1 owner, 2 game): see _rows.
func row_of(index: int) -> Rect2:
	return _rows[index]


## The screen inside its margin, metres, centred on the marker (y up).
static func inner_screen() -> Rect2:
	var size := SCREEN_M - Vector2.ONE * 2.0 * SCREEN_MARGIN_M
	return Rect2(-size * 0.5, size)


## One row per line, stacked top to bottom and centred, each its line's height (the font's, outline
## included) at `shared_pixel`: the largest pixel size, PIXEL_M at most, at which the stack fits
## the inner screen's height and the best's and the game's texts fit its width, so the three
## shrink together and keep their ratio. Only an owner's name wider than its row shrinks alone.
func _layout() -> void:
	var inner := inner_screen()
	var lines: Array[Label3D] = [best, owner_name, game]
	var heights: Array[float] = []
	var total := 0.0
	for line: Label3D in lines:
		var height := font_of(line).get_height(line.font_size) + 2.0 * line.outline_size
		heights.append(height)
		total += height
	shared_pixel = minf(PIXEL_M, inner.size.y / total)
	for line: Label3D in [best, game]:
		var width := text_width(line)
		if width > 0.0:
			shared_pixel = minf(shared_pixel, inner.size.x / width)
	_rows.clear()
	var top := total * shared_pixel * 0.5
	for i in lines.size():
		var height := heights[i] * shared_pixel
		_rows.append(Rect2(inner.position.x, top - height, inner.size.x, height))
		lines[i].position = Vector3(0.0, top - height * 0.5, 0.0)
		lines[i].pixel_size = shared_pixel
		top -= height
	var name_width := text_width(owner_name)
	if name_width > 0.0:
		owner_name.pixel_size = minf(shared_pixel, inner.size.x / name_width)


## `line`'s text width in font pixels, outline included, as the font Label3D draws with measures it.
static func text_width(line: Label3D) -> float:
	var font := font_of(line)
	var width := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.font_size).x
	return width + 2.0 * line.outline_size if not line.text.is_empty() else 0.0


## The font `line` draws with, as Label3D picks it: its own, else the project theme's (a Label3D
## font or the theme's default), else the engine's fallback.
static func font_of(line: Label3D) -> Font:
	if line.font != null:
		return line.font
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.has_font(&"font", &"Label3D"):
		return theme.get_font(&"font", &"Label3D")
	return ThemeDB.fallback_font


## The colour `best_name` is drawn in: the body colour of the one roster member of that name, else
## neutral() (nobody, an owner gone, or a name two members share).
static func owner_colour(model: ClientModel, best_name: String) -> Color:
	if best_name.is_empty():
		return neutral()
	var found := -1
	for peer: int in model.roster:
		if model.roster[peer].name != best_name:
			continue
		if found >= 0:
			return neutral()
		found = peer
	return BodyColours.of(model.colour_of(found)) if found >= 0 else neutral()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _model != null:
		_shown = []
		show_state(_model)


## The colour of a name nobody's colour belongs to (and of the game line): the line style's text
## colour in the shared theme.
static func neutral() -> Color:
	return GameUi.THEME.get_color(&"font_color", LINE_LOOK)


## The theme's font for `look`, or the engine's fallback when the UI pack's font is CI's Git LFS
## stand-in (a font that maps no character): Label3D then draws the fallback's glyphs, and the
## layout must measure the font it draws with.
static func ui_font(look: StringName) -> Font:
	return GameUi.THEME.get_font(&"font", look) if has_ui_fonts() else ThemeDB.fallback_font


## Whether the UI pack's fonts are here (not CI's Git LFS stand-ins).
static func has_ui_fonts() -> bool:
	return GameUi.THEME.get_font(&"font", BEST_LOOK).has_char("0".unicode_at(0))
