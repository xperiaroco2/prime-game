class_name LifeHud
extends RefCounted
## What the downed, dead and respawn screen shows (LifeScreen, #497; ARCHITECTURE §4.7.44, the UI
## handoff s09), as data: pure, from the own ClientModel, the own LifeCountdowns at the estimated
## host tick and the life view's own state (whom a dead player watches, how long the give-up key
## has been held, and the give-up key bound now, KeyLabel's, so the line follows a rebind, #211).
## The screen turns it into the deck's words (#208).
##
## - Downed (`down`, `down-holding`): the bleed-out time left, as a fraction of the mode's knockdown
##   and as m:ss, and the give-up hold's progress with its key.
## - Raised (`raise`): the raiser's name and the raise's progress (the knockdown is paused).
## - Dead: the time to respawn as m:ss and the watched player's name; nothing of the target's (no
##   health, stamina, role or private event), and no key (the tutorial teaches them).
## - Living after a respawn (`back`): the protection's whole seconds left, 3, 2, 1; nothing after a
##   raise, as drawn.
## Never who knocked the player down: the model does not say, and nothing here asks.

## What the screen shows: nothing, the downed plates, the raise or the spectator's plate.
enum State { NONE, DOWN, RAISE, DEAD }


## One state of the screen; a default one shows nothing.
class Shown:
	extends RefCounted
	var state := State.NONE
	## DOWN: the bleed-out time left as a fraction of the mode's knockdown (1 to 0) and as m:ss.
	var bleed := 0.0
	var time_left := ""
	## DOWN: the give-up hold's progress (0 at rest, 1 gives up) and the give-up key's label.
	var give_up := 0.0
	var give_up_key := "F"
	## DOWN: whether the give-up keycap takes the wide size (KeyLabel.is_wide_action: Space, Shift,
	## Tab or Esc bound; ARCHITECTURE §4.7.30 rule 7).
	var give_up_wide := false
	## RAISE: the raiser's name and the raise's progress, 0 to 1.
	var raiser := ""
	var raise := 0.0
	## DEAD: the time to respawn as m:ss ("" when none runs) and whom the player watches ("" for
	## nobody).
	var respawn := ""
	var watching := ""
	## Living after a respawn: the protection's whole seconds left; 0 hides the chip.
	var protected := 0


## The life view's own state the screen shows besides the model and the countdowns.
class Local:
	extends RefCounted
	## The peer a dead player watches; 0 for none.
	var watching := 0
	## Seconds the give-up key has been held, and how long it must be.
	var give_up_held_s := 0.0
	var give_up_hold_s := 1.0
	## The label of the give_up key bound now (KeyLabel.of_action); the project's default F.
	var give_up_key := "F"
	## Whether that key's keycap takes the wide size (KeyLabel.is_wide_action).
	var give_up_wide := false

	## The label of the give-up key bound now, from the InputMap and the keyboard layout, and
	## whether its keycap is wide.
	func read_keys() -> void:
		give_up_key = KeyLabel.of_action(&"give_up")
		give_up_wide = KeyLabel.is_wide_action(&"give_up")


static func of(model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	match model.life_of(model.own_peer):
		ClientModel.Life.ALIVE:
			var protection := countdowns.protection_left_s(tick)
			shown.protected = ceili(protection) if protection > 0.0 else 0
		ClientModel.Life.DOWNED:
			_downed(shown, model, countdowns, tick, local)
		ClientModel.Life.DEAD, ClientModel.Life.LEFT:
			shown.state = State.DEAD
			var left := countdowns.respawn_left_s(tick)
			shown.respawn = clock_text(ceili(left)) if left >= 0.0 else ""
			shown.watching = name_of(model, local.watching) if local.watching != 0 else ""
	return shown


static func _downed(
	shown: Shown, model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local
) -> void:
	var raiser := model.raiser_of(model.own_peer)
	if raiser != 0:
		shown.state = State.RAISE
		shown.raiser = name_of(model, raiser)
		shown.raise = maxf(0.0, countdowns.raise_progress(tick))
		return
	shown.state = State.DOWN
	var left := countdowns.knockdown_left_s(tick)
	shown.bleed = maxf(0.0, countdowns.knockdown_fraction(tick))
	shown.time_left = clock_text(ceili(left)) if left >= 0.0 else ""
	if local.give_up_hold_s > 0.0:
		shown.give_up = clampf(local.give_up_held_s / local.give_up_hold_s, 0.0, 1.0)
	shown.give_up_key = local.give_up_key
	shown.give_up_wide = local.give_up_wide


## Seconds as m:ss ("0:10", "1:05"), the downed and dead plates' times.
static func clock_text(seconds: int) -> String:
	var whole := maxi(seconds, 0)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


## The deck's `downed.give_up_hold` sentence (translated) split at its `{key}`: the words before
## and after the keycap, each through strip_edges() (the row's gap and the keycap's padding stand
## in for the spaces); an empty piece is hidden. A sentence without `{key}` is all before it.
static func give_up_pieces(sentence: String) -> PackedStringArray:
	var at := sentence.find("{key}")
	if at < 0:
		return PackedStringArray([sentence.strip_edges(), ""])
	var before := sentence.substr(0, at).strip_edges()
	var after := sentence.substr(at + "{key}".length()).strip_edges()
	return PackedStringArray([before, after])


## A player's roster name, or "Player <id>" once it left the roster.
static func name_of(model: ClientModel, peer: int) -> String:
	var member: ClientModel.Member = model.roster.get(peer)
	return member.name if member != null else "Player %d" % peer
