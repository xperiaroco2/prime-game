class_name HudText
extends RefCounted
## What the round's HUD shows (ARCHITECTURE §4.7.37, #489; M4-8 first), pure: from the own
## ClientModel, the client's own copy of the mode, the estimated host tick and what the game knows
## locally (the predicted stamina, the item under the crosshair, whether the own voice is heard, the
## own raise's progress). The Toy HUD (prime-game-ui `ui-0.4.0` `docs/handoff/s07-hud.md`) draws
## it: texts are copy deck keys (#208) or data.
##
## Only the own player's facts: the time left, its own role, its health and stamina as fractions,
## its microphone, its hand and belt, the item its crosshair is on, the raise it runs and the raise
## it could start (the rescuer's cue: the raise key's label alone, nothing of the downed). Never a
## key, walking or running, a player list, who knocked it down, a destination or task progress (the
## handoff), no other player's role, health or slots. The respawn's protection is LifeHud's chip.
##
## The downed and the dead (the handoff s09, #497; LifeScreen draws the rest): downed, only the
## microphone shows; dead (spectating, #168) nothing of the HUD shows (no time, role, bars, slots or
## mic), so nothing of the watched player's either (the M4 ADR's §3 item 2): its name is LifeHud's.

## The UI pack's icon of each item kind (ToyIcons); a kind with none shows its name instead.
const ITEM_ICONS: Dictionary[StringName, StringName] = {
	&"package": &"item",
	&"knife": &"knife",
}
## The rescuer's cue: the deck has no raise sentence (ui-0.4.0, ui-0.5.0), so this is a stopgap,
## the nearest key with `{key}`, the tutorial's raise step ("Hold {key} next to them"). 6B on
## PR #721 asked for a deck key; the engineer to confirm this one.
const RAISE_CUE := "tutorial.step.downed.how"
## The hand-over's cue (#1411): the deck's `hud.hand_over` "Press {key} to hand it over" (ui-2.5.2).
const HAND_OVER_CUE := "hud.hand_over"
## The offer's other cues (#1434), in the deck since ui-2.5.3 (#1446): `hud.take_offer` "Press
## {key} to take it" while a player offers the own player its hand item, `hud.offering` "Press
## {key} to take it back" while the own offer is open.
const TAKE_OFFER_CUE := "hud.take_offer"
const OFFERING_CUE := "hud.offering"


## What the HUD knows besides the model and the mode.
class Local:
	extends RefCounted
	## The predicted stamina in points (PredictedStamina); negative when unknown.
	var stamina := -1.0
	## The item the crosshair is on within reach (ItemInteractions.target()); -1 for none.
	var aim := -1
	## The station the crosshair is on that E would use (ItemInteractions.station_target(), #801);
	## -1 for none. Never both this and `aim`.
	var aim_station := -1
	## Whether the photo camera's viewfinder is up (PhotoViewfinder.active(), #786): no crosshair
	## and no Aim over the lens.
	var viewing := false
	## Whether anyone may hear the own player now (VoiceSender.live()).
	var mic := false
	## The own raise's progress (LifeView.raise_shown()), 0 to 1; negative for none.
	var raising := -1.0
	## The label of the raise key bound now while the crosshair is on a downed player E would raise
	## (LifeView.raise_cue()); "" for none.
	var raise_key := ""
	## The label of the interact key bound now while the crosshair is on a living player E would
	## hand the hand item to (HandOverUse.cue(), #1411); "" for none.
	var hand_over_key := ""
	## The deck key that words it (HandOverUse.cue_key(): HAND_OVER_CUE, TAKE_OFFER_CUE or
	## OFFERING_CUE, #1434); "" means HAND_OVER_CUE.
	var hand_over_cue_key := ""
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
	## The vitals' column shows (the own player in the round, not spectating): the microphone and,
	## when `bars`, health and stamina (not while downed).
	var vitals := false
	var bars := false
	## Health and stamina, 0 to 1.
	var health := 1.0
	var stamina := 1.0
	## Whether anyone hears the own player.
	var mic := false
	## The own three places show (GDD §6: the hand and the two belt slots, numbered 1 to 3).
	var slots := false
	## Each place's item, in place order (0 to 2).
	var places: Array[Slot] = [Slot.new(), Slot.new(), Slot.new()]
	## The place in the hand (0 to 2), lit.
	var selected := 0
	## The place in the hand.
	var hand: Slot:
		get:
			return places[selected]
		set(value):
			places[selected] = value
	## The first belt place (the lowest place not in the hand).
	var belt: Slot:
		get:
			return places[1 if selected == 0 else 0]
		set(value):
			places[1 if selected == 0 else 0] = value
	## The name of the item under the crosshair; "" hides Aim.
	var aim := ""
	## The own raise's progress, 0 to 1; negative hides the bar (it replaces Aim).
	var raising := -1.0
	## The rescuer's cue in Aim (#497, the engineer on PR #721): the raise key's label that fills
	## RAISE_CUE's `{key}`, in place of the item's name; "" for none.
	var raise_key := ""
	## The hand-over's cue in Aim (#1411): the interact key's label that fills HAND_OVER_CUE's
	## `{key}`; "" for none.
	var hand_over_key := ""
	## The deck key that words it (HandOverUse.cue_key(): HAND_OVER_CUE, TAKE_OFFER_CUE or
	## OFFERING_CUE, #1434); "" means HAND_OVER_CUE.
	var hand_over_cue_key := ""


static func of(model: ClientModel, mode: GameMode, host_tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	if spectates(model):
		return shown
	if model.life_of(model.own_peer) == ClientModel.Life.DOWNED:
		# The handoff s09's `down` and `raise`: the plates and the microphone (off) alone.
		shown.vitals = true
		shown.mic = local.mic
		return shown
	var left := GameFlow.seconds_left(model.end_tick, floori(host_tick))
	if left >= 0:
		shown.time = clock_text(left)
	shown.role = role_key(model, mode)
	shown.vitals = true
	shown.bars = true
	shown.health = health_of(model, mode)
	shown.stamina = stamina_of(local, mode)
	shown.mic = local.mic
	shown.slots = true
	shown.selected = model.selected_place(model.own_peer)
	for place in shown.places.size():
		var item_id := model.item_in_place(model.own_peer, place)
		shown.places[place] = slot_of(model, mode, item_id)
	shown.raising = local.raising
	if local.raising >= 0.0:
		return shown
	# A downed player under the crosshair matters more than an item lying near it: E raises it.
	if not local.raise_key.is_empty():
		shown.raise_key = local.raise_key
	elif not local.hand_over_key.is_empty():
		# HandOverUse offers one only where E has no item or station (#1411).
		shown.hand_over_key = local.hand_over_key
		shown.hand_over_cue_key = local.hand_over_cue_key
	else:
		shown.aim = aim_of(model, mode, local)
	return shown


## Aim's text: the deck key (else name) of the item under the crosshair, else of the station E
## would use there; "" for neither. The round's HUD and the lobby's (#1408: the tap, the hall's
## items) show it.
static func aim_of(model: ClientModel, mode: GameMode, local: Local) -> String:
	if local.aim >= 0:
		return slot_of(model, mode, local.aim).item
	if model.stations.has(local.aim_station):
		# The station's name alone: never a switch's on or off (#801).
		return ContentNames.station(model.stations[local.aim_station].kind)
	return ""


## The rescuer's cue in Aim, translated, with the raise key's label `key` (`RAISE_CUE`).
static func raise_cue(key: String) -> String:
	return String(TranslationServer.translate(RAISE_CUE)).format({"key": key})


## The hand-over's cue in Aim, translated, with the interact key's label `key`: the deck key
## `cue_key` (HAND_OVER_CUE when empty; TAKE_OFFER_CUE, OFFERING_CUE, #1434).
static func hand_over_cue(key: String, cue_key: String = "") -> String:
	var deck_key := HAND_OVER_CUE if cue_key.is_empty() else cue_key
	return String(TranslationServer.translate(deck_key)).format({"key": key})


## Whether the own player spectates: dead (or gone), with no body of its own to show.
static func spectates(model: ClientModel) -> bool:
	var life := model.life_of(model.own_peer)
	return life == ClientModel.Life.DEAD or life == ClientModel.Life.LEFT


## Seconds as mm:ss ("07:22"), the timer's text.
static func clock_text(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


## The own role's deck key, its display name when the deck has none (ContentNames), "" before
## RoleAssigned.
static func role_key(model: ClientModel, mode: GameMode) -> String:
	if model.role.is_empty():
		return ""
	return ContentNames.role(model.role, mode)


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
	slot.item = ContentNames.item(item.kind, mode)
	slot.icon = ITEM_ICONS.get(item.kind, &"")
	slot.two_handed = kind != null and kind.is_two_handed()
	return slot
