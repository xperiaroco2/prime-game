class_name LifeHud
extends RefCounted
## What the life panel shows (ARCHITECTURE §4.7, the own player by life), as words: pure, from the
## own ClientModel, the own LifeCountdowns at the estimated host tick and the life view's own state
## (whom a dead player watches, how long G has been held, whether the crosshair is on a downed
## player within reach). Greybox wording, placeholders until the UI milestone (#150).
##
## - Living: the raise it runs and its progress; "Hold E to raise" over a downed player in reach.
##   No own invulnerability read-out (the engineer's answer 2 on PR #167: a later buffs UI may
##   show it); other players' invulnerable shell (D8) stays.
## - Downed: the knockdown countdown (paused while raised), who raises them and the raise's
##   progress, and the give-up hold (G).
## - Dead: the respawn countdown and whom they watch: nothing of the target's (no health, stamina,
##   role or private event).


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
	## Seconds G has been held, and how long it must be.
	var give_up_held_s := 0.0
	var give_up_hold_s := 1.0
	## The crosshair is on a downed player the host would let this player raise.
	var can_raise := false


static func of(model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	var own := model.own_peer
	match model.life_of(own):
		ClientModel.Life.ALIVE:
			_living(shown, model, countdowns, tick, local)
		ClientModel.Life.DOWNED:
			_downed(shown, model, countdowns, tick, local)
		ClientModel.Life.DEAD:
			_dead(shown, model, countdowns, tick, local)
	return shown


static func _living(
	shown: Shown, model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local
) -> void:
	var raising := countdowns.raising()
	var progress := countdowns.raise_progress(tick)
	if raising != 0 and progress >= 0.0:
		shown.title = "Raising %s" % name_of(model, raising)
		shown.progress = progress
		shown.progress_label = "Keep holding E"
		return
	if local.can_raise:
		shown.title = "Downed player"
		shown.lines.append("Hold E to raise")


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
	shown.lines.append("Hold G to give up")


static func _dead(
	shown: Shown, model: ClientModel, countdowns: LifeCountdowns, tick: float, local: Local
) -> void:
	shown.title = "Dead"
	var left := countdowns.respawn_left_s(tick)
	if left >= 0.0:
		shown.lines.append("Respawn in %d s" % ceili(left))
	if local.watching != 0:
		shown.lines.append("Watching %s" % name_of(model, local.watching))
		shown.lines.append("Left and right click: next and previous")
	else:
		shown.lines.append("Nobody to watch")


## A player's roster name, or "Player <id>" once it left the roster.
static func name_of(model: ClientModel, peer: int) -> String:
	var member: ClientModel.Member = model.roster.get(peer)
	return member.name if member != null else "Player %d" % peer
