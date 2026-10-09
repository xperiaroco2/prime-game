class_name HudText
extends RefCounted
## What the round's HUD shows (ARCHITECTURE §4.7.37, #489; M4-8 first), pure: from the own
## ClientModel, the client's own copy of the mode, the estimated host tick and what the game knows
## locally (the predicted stamina, the item under the crosshair, whether the own voice is heard, the
## own raise's progress, whom a dead player watches). The Toy HUD (prime-game-ui `ui-0.4.0`
## `docs/handoff/s07-hud.md`) draws it: texts are copy deck keys (#208) or data.
##
## Only the own player's facts: the time left, its own role, its health and stamina as fractions,
## its microphone, its hand and belt, the item its crosshair is on and the raise it runs. Never a
## key, walking or running, a player list, who knocked it down, a destination or task progress (the
## handoff), no other player's role, health or slots, no own invulnerability read-out (the
## engineer's answer 2 on PR #167).
##
## While the own player is dead it spectates (#168): the watched player's name and its hand and belt
## items (public: everyone sees them in 3D), nothing else of the HUD (the handoff s09's `dead`: no
## time, role, bars or mic); none of the target's health, stamina, role, teammates or private events
## (the M4 ADR's §3 item 2).

## The copy deck's key of each role the base mode has, by role id (#208); a role not named here
## shows its display name.
const ROLE_KEYS: Dictionary[StringName, String] = {
	&"crew": "role.engineer",
	&"dissident": "role.dissident",
}
## The copy deck's key of each item kind, by kind id; a kind not named here shows its display name.
const ITEM_KEYS: Dictionary[StringName, String] = {
	&"package": "item.package",
	&"knife": "item.knife",
	&"switch": "item.switch",
}
## The UI pack's icon of each item kind (ToyIcons); a kind with none shows its name instead.
const ITEM_ICONS: Dictionary[StringName, StringName] = {
	&"package": &"item",
	&"knife": &"knife",
}
## The copy deck's "Watching: {name}" (the handoff s09's `dead.watching`).
const WATCHING_KEY := "dead.watching"


## What the HUD knows besides the model and the mode.
class Local:
	extends RefCounted
	## The predicted stamina in points (PredictedStamina); negative when unknown.
	var stamina := -1.0
	## The item the crosshair is on within reach (ItemInteractions.target()); -1 for none.
	var aim := -1
	## Whether anyone may hear the own player now (VoiceSender.live()).
	var mic := false
	## The own raise's progress (LifeView.raise_shown()), 0 to 1; negative for none.
	var raising := -1.0
	## The peer a dead player watches (LifeView.target()); 0 for none.
	var watching := 0
	## The own body's place for the map screen (#253): whether it has one (the dead have none), the
	## place, and the heading in radians clockwise from north (-Z) seen from above.
	var placed := false
	var position := Vector3.ZERO
	var heading := 0.0


## One slot: empty, or an item by its name (a deck key, else the kind's display name) and icon.
class Slot:
	extends RefCounted
	## The item's name; "" for an empty slot.
	var item := ""
	## The pack icon (ToyIcons); &"" for a kind without one.
	var icon := &""
	## A two-handed item (the package) widens the hand slot and shows its name too.
	var two_handed := false

	func is_empty() -> bool:
		return item.is_empty()


## The HUD's state; a default one shows nothing.
class Shown:
	extends RefCounted
	## The time left as mm:ss; "" hides the timer.
	var time := ""
	## The own role's deck key (or display name); "" hides the chip.
	var role := ""
	## Health, stamina and the microphone show (the own player in the round, not spectating).
	var vitals := false
	## Health and stamina, 0 to 1.
	var health := 1.0
	var stamina := 1.0
	## Whether anyone hears the own player.
	var mic := false
	## The hand and belt show (the own ones, or a spectated player's).
	var slots := false
	var hand := Slot.new()
	var belt := Slot.new()
	## The name of the item under the crosshair; "" hides Aim.
	var aim := ""
	## The own raise's progress, 0 to 1; negative hides the bar (it replaces Aim).
	var raising := -1.0
	## The name of whom a dead player watches; "" hides the plate.
	var watching := ""


static func of(model: ClientModel, mode: GameMode, host_tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	if spectates(model):
		_spectated(shown, model, mode, local.watching)
		return shown
	var left := GameFlow.seconds_left(model.end_tick, floori(host_tick))
	if left >= 0:
		shown.time = clock_text(left)
	shown.role = role_key(model, mode)
	shown.vitals = true
	shown.health = health_of(model, mode)
	shown.stamina = stamina_of(local, mode)
	shown.mic = local.mic
	shown.slots = true
	shown.hand = slot_of(model, mode, model.hand_item(model.own_peer))
	shown.belt = slot_of(model, mode, model.belt_item(model.own_peer))
	shown.raising = local.raising
	if local.raising < 0.0 and local.aim >= 0:
		shown.aim = slot_of(model, mode, local.aim).item
	return shown


## Whether the own player spectates: dead (or gone), with no body of its own to show.
static func spectates(model: ClientModel) -> bool:
	var life := model.life_of(model.own_peer)
	return life == ClientModel.Life.DEAD or life == ClientModel.Life.LEFT


## Seconds as mm:ss ("07:22"), the timer's text.
static func clock_text(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


## The own role's deck key, its display name when the deck has none, "" before RoleAssigned.
static func role_key(model: ClientModel, mode: GameMode) -> String:
	if model.role.is_empty():
		return ""
	if ROLE_KEYS.has(model.role):
		return ROLE_KEYS[model.role]
	var role := mode.find_role(model.role)
	return role.display_name if role != null else String(model.role)


## The own health as a fraction of the mode's; full before the first SelfStatus.
static func health_of(model: ClientModel, mode: GameMode) -> float:
	var most := mode.player_rules.health * Ticks.THOUSANDTHS
	if model.health < 0 or most <= 0:
		return 1.0
	return clampf(model.health / float(most), 0.0, 1.0)


## The predicted stamina as a fraction of the mode's; full while unknown.
static func stamina_of(local: Local, mode: GameMode) -> float:
	var most := float(mode.player_rules.stamina)
	if local.stamina < 0.0 or most <= 0.0:
		return 1.0
	return clampf(local.stamina / most, 0.0, 1.0)


## The slot holding `item_id`: its kind's deck key (else display name, else id) and icon; an
## empty slot for -1 or an item the model does not know.
static func slot_of(model: ClientModel, mode: GameMode, item_id: int) -> Slot:
	var slot := Slot.new()
	var item: ClientModel.Item = model.items.get(item_id)
	if item == null:
		return slot
	var kind := mode.find_item_kind(item.kind)
	if ITEM_KEYS.has(item.kind):
		slot.item = ITEM_KEYS[item.kind]
	else:
		slot.item = kind.display_name if kind != null else String(item.kind)
	slot.icon = ITEM_ICONS.get(item.kind, &"")
	slot.two_handed = kind != null and kind.is_two_handed()
	return slot


## The spectator's HUD: whom it watches and that player's public slots; nothing for nobody.
static func _spectated(shown: Shown, model: ClientModel, mode: GameMode, target: int) -> void:
	if target == 0:
		return
	shown.watching = LifeHud.name_of(model, target)
	shown.slots = true
	shown.hand = slot_of(model, mode, model.hand_item(target))
	shown.belt = slot_of(model, mode, model.belt_item(target))
