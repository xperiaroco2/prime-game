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
## - The look (three Label3D lines, sizes, colours, the default font) is a placeholder in the Toy
##   style (provisional, not a decision).

## The lines' height in metres per pixel of font, and their font sizes (provisional).
const PIXEL_M := 0.002
const BEST_SIZE := 64
const NAME_SIZE := 56
const GAME_SIZE := 48
## The gap between two lines, metres.
const LINE_M := 0.15
## The neutral text colour and the outline (provisional).
const NEUTRAL := Color(1.0, 0.93, 0.7)
const OUTLINE := Color(0.08, 0.06, 0.12)

var best := Label3D.new()
var owner_name := Label3D.new()
var game := Label3D.new()

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
		line.outline_size = sizes[i] / 6
		line.modulate = NEUTRAL
		line.outline_modulate = OUTLINE
		line.position = Vector3(0.0, -LINE_M * i, 0.0)
		add_child(line)


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


## The colour `best_name` is drawn in: the body colour of the one roster member of that name, else
## NEUTRAL (nobody, an owner gone, or a name two members share).
static func owner_colour(model: ClientModel, best_name: String) -> Color:
	if best_name.is_empty():
		return NEUTRAL
	var found := -1
	for peer: int in model.roster:
		if model.roster[peer].name != best_name:
			continue
		if found >= 0:
			return NEUTRAL
		found = peer
	return BodyColours.of(model.colour_of(found)) if found >= 0 else NEUTRAL


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _model != null:
		_shown = []
		show_state(_model)
