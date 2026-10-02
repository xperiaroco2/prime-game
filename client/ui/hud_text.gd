class_name HudText
extends RefCounted
## What the round's HUD says (ARCHITECTURE §4.7, the HUD; M4-8), as words: pure, from the own
## ClientModel, the client's own copy of the mode, the estimated host tick and what the game knows
## locally (the predicted stamina, the crosshair's hint). Greybox wording, placeholders until the
## UI milestone (#150).
##
## Only the own player's facts: its health and stamina, its hand and belt by their kinds' display
## names, its package's destination (the swatch of its circle's colour; the world marks the
## circle, D10 (b)), the shared progress, the match clock, its own role by its display name and,
## for a role whose players know each other, its teammates (Teammates, its own knowledge; the M4
## ADR's §3 item 6). No own invulnerability read-out (the engineer's answer 2 on PR #167). No
## item's or player's position, no other role.
##
## While the own player is dead it spectates (#168): "Spectating <name>" and the watched target's
## hand and belt items by their kinds' display names (public: everyone sees them in 3D), with the
## match's lines and its own role and teammates; none of the target's health, stamina, role,
## teammates or private events (the M4 ADR's §3 item 2), and none of its own health, stamina,
## slots, destination or crosshair hint.


## What the HUD knows besides the model and the mode.
class Local:
	extends RefCounted
	## The predicted stamina in points (PredictedStamina); negative when unknown.
	var stamina := -1.0
	## What the crosshair would do (ItemInteractions); empty for nothing.
	var hint := ""
	## The peer a dead player watches (LifeView.target()); 0 for none.
	var watching := 0


## The HUD's lines; an empty one hides its label.
class Shown:
	extends RefCounted
	var health := ""
	var stamina := ""
	var hand := ""
	var belt := ""
	## The destination of the package the player carries, and its circle's colour.
	var destination := ""
	var destination_colour: Color
	var progress := ""
	var clock := ""
	var role := ""
	var teammates := ""
	var hint := ""
	## Whom a dead player watches: "Spectating <name>".
	var spectating := ""


static func of(model: ClientModel, mode: GameMode, host_tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	if model.tasks_total > 0:
		shown.progress = "Tasks %d / %d" % [model.tasks_done, model.tasks_total]
	var left := GameFlow.seconds_left(model.end_tick, floori(host_tick))
	if left >= 0:
		shown.clock = "%d:%02d" % [floori(left / 60.0), left % 60]
	shown.role = role_text(model, mode)
	shown.teammates = teammates_text(model)
	if spectates(model):
		_spectated(shown, model, mode, local.watching)
		return shown
	shown.health = "Health %s" % _points(model.health)
	shown.stamina = ("Stamina %d" % ceili(local.stamina) if local.stamina >= 0.0 else "Stamina -")
	shown.hand = "Hand: %s" % slot_text(model, mode, model.hand_item(model.own_peer))
	shown.belt = "Belt: %s" % slot_text(model, mode, model.belt_item(model.own_peer))
	var package := ItemViews.destination_item(model)
	if package >= 0:
		shown.destination = "Deliver to the circle of this colour"
		shown.destination_colour = model.items[package].colour
	shown.hint = local.hint
	return shown


## Whether the own player spectates: dead (or gone), with no body of its own to show.
static func spectates(model: ClientModel) -> bool:
	var life := model.life_of(model.own_peer)
	return life == ClientModel.Life.DEAD or life == ClientModel.Life.LEFT


## The spectator's lines: whom it watches and that player's public slots; nothing for nobody.
static func _spectated(shown: Shown, model: ClientModel, mode: GameMode, target: int) -> void:
	if target == 0:
		return
	shown.spectating = "Spectating %s" % LifeHud.name_of(model, target)
	shown.hand = "Hand: %s" % slot_text(model, mode, model.hand_item(target))
	shown.belt = "Belt: %s" % slot_text(model, mode, model.belt_item(target))


## An item in a slot by its kind's display name; "empty" for -1. A two-handed item says so.
static func slot_text(model: ClientModel, mode: GameMode, item_id: int) -> String:
	var item: ClientModel.Item = model.items.get(item_id)
	if item == null:
		return "empty"
	var kind := mode.find_item_kind(item.kind)
	if kind == null:
		return String(item.kind)
	return kind.display_name + (" (both hands)" if kind.is_two_handed() else "")


## "Role: <the role's display name>", or empty before RoleAssigned.
static func role_text(model: ClientModel, mode: GameMode) -> String:
	if model.role.is_empty():
		return ""
	var role := mode.find_role(model.role)
	return "Role: %s" % (role.display_name if role != null else String(model.role))


## The other players of the own role, by name, when the own role's players know each other
## (Teammates reaches only them); empty otherwise.
static func teammates_text(model: ClientModel) -> String:
	if not model.teammates.has(model.role):
		return ""
	var names := PackedStringArray()
	for peer: int in model.teammates[model.role]:
		if peer == model.own_peer:
			continue
		var member: ClientModel.Member = model.roster.get(peer)
		names.append(member.name if member != null else "player %d" % peer)
	return "Teammates: %s" % (", ".join(names) if not names.is_empty() else "none")


## Thousandths of a point (§3.3) as whole points, rounded up; "-" before the first SelfStatus.
static func _points(thousandths: int) -> String:
	if thousandths < 0:
		return "-"
	return str(ceili(thousandths / float(Ticks.THOUSANDTHS)))
