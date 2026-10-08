class_name LifeHud
extends RefCounted
## What the life panel shows (ARCHITECTURE §4.7, the own player by life), as words: pure, from the
## own ClientModel, the own LifeCountdowns at the estimated host tick and the life view's own state
## (whom a dead player watches, how long the give-up key has been held, whether the crosshair is on
## a downed player within reach, and the keys bound now, KeyLabel's, so every prompt follows a
## rebind, #211). Greybox wording, placeholders until the UI milestone (#150).
##
## - Living: the raise it runs and its progress; "Hold <interact> to raise" over a downed player in
##   reach.
##   No own invulnerability read-out (the engineer's answer 2 on PR #167: a later buffs UI may
##   show it); other players' invulnerable shell (D8) stays.
## - Downed: the knockdown countdown (paused while raised), who raises them and the raise's
##   progress, and "Hold <give_up> to give up" with the hold's progress (F by default, #211).
## - Dead: the respawn countdown and the keys that cycle the target (the HUD names whom they
##   watch, #168): nothing of the target's (no health, stamina, role or private event).


## One panel's content; an empty title shows no panel.
class Shown:
	extends RefCounted
	var title := ""
	var lines := PackedStringArray()
	## From 0 to 1, or a negative number for no bar.
	var progress := -1.0
	var progress_label := ""


## The life view's own state the panel shows besides the model and the countdowns.
class Local:
	extends RefCounted
	## The peer a dead player watches; 0 for none.
	var watching := 0
	## Seconds the give-up key has been held, and how long it must be.
	var give_up_held_s := 0.0
	var give_up_hold_s := 1.0
	## The crosshair is on a downed player the host would let this player raise.
	var can_raise := false
	## The labels of the keys bound now (KeyLabel.of_action): give_up, interact (the raise),
	## spectate_next and spectate_previous. The defaults are the project's.
	var give_up_key := "F"
	var raise_key := "E"
	var next_key := "LMB"
	var previous_key := "RMB"

	## The labels of the keys bound now, from the InputMap and the keyboard layout.
	func read_keys() -> void:
		give_up_key = KeyLabel.of_action(&"give_up")
		raise_key = KeyLabel.of_action(&"interact")
		next_key = KeyLabel.of_action(&"spectate_next")
		previous_key = KeyLabel.of_action(&"spectate_previous")


static func of(model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	var own := model.own_peer
	match model.life_of(own):
		ClientModel.Life.ALIVE:
			_living(shown, model, countdowns, tick, local)
		ClientModel.Life.DOWNED:
			_downed(shown, model, countdowns, tick, local)
		ClientModel.Life.DEAD:
			_dead(shown, countdowns, tick, local)
	return shown


static func _living(
	shown: Shown, model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local
) -> void:
	var raising := countdowns.raising()
	var progress := countdowns.raise_progress(tick)
	if raising != 0 and progress >= 0.0:
		shown.title = "Raising %s" % name_of(model, raising)
		shown.progress = progress
		shown.progress_label = "Keep holding %s" % local.raise_key
		return
	if local.can_raise:
		shown.title = "Downed player"
		shown.lines.append("Hold %s to raise" % local.raise_key)


static func _downed(
	shown: Shown, model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local
) -> void:
	shown.title = "Knocked down"
	var left := countdowns.knockdown_left_s(tick)
	if left >= 0.0:
		var paused := " (paused)" if countdowns.knockdown_paused() else ""
		shown.lines.append("Dying in %d s%s" % [ceili(left), paused])
	var raiser := model.raiser_of(model.own_peer)
	var progress := countdowns.raise_progress(tick)
	if raiser != 0:
		shown.lines.append("Being raised by %s" % name_of(model, raiser))
		if progress >= 0.0:
			shown.progress = progress
			shown.progress_label = ""
		return
	if local.give_up_held_s > 0.0:
		shown.progress = clampf(local.give_up_held_s / local.give_up_hold_s, 0.0, 1.0)
		shown.progress_label = "Giving up"
	shown.lines.append(give_up_line(local.give_up_key))


static func _dead(shown: Shown, countdowns: LifeCountdowns, tick: float, local: Local) -> void:
	shown.title = "Dead"
	var left := countdowns.respawn_left_s(tick)
	if left >= 0.0:
		shown.lines.append("Respawn in %d s" % ceili(left))
	# Whom it watches is the HUD's "Spectating <name>" (HudText, #168).
	if local.watching != 0:
		shown.lines.append("%s and %s: next and previous" % [local.next_key, local.previous_key])
	else:
		shown.lines.append("Nobody to watch")


## The downed player's prompt with the bound key: the deck's `downed.give_up_hold` in English
## ("Hold {key} to give up"), as the rest of this greybox panel; the Toy downed screen (#497)
## shows that key through tr().
static func give_up_line(key: String) -> String:
	return "Hold {key} to give up".format({"key": key})


## A player's roster name, or "Player <id>" once it left the roster.
static func name_of(model: ClientModel, peer: int) -> String:
	var member: ClientModel.Member = model.roster.get(peer)
	return member.name if member != null else "Player %d" % peer
