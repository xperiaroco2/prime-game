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
## Dead in the dead's hall (#1489, s09's `dead-room`, #1570): only the microphone, with the other
## dead waiting there beside it (`others`; deaths are public, the roster's `dead`), since the dead
## hear and talk to each other there.

## The UI pack's icon of an item kind whose line icon is not `item-<kind>` (ToyIcons; the handoff
## s07 draws the item line icons, `icons/item-*.svg`); a kind with neither shows its name alone.
const ITEM_ICONS: Dictionary[StringName, StringName] = {
	&"package": &"item",
	&"knife": &"item-knife",
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
## The chair's cue (#1420): `hud.sit`, "{key}: sit" in the deck's wording ("E: sit"), with `{key}`
## like the hand-over's. The deck row comes with the UI track's next round; until then the HUD
## shows the raw key (the TranslationServer's answer for an unknown key).
const SIT_CUE := "hud.sit"
## The ship's zap's notice (#1585): the deck has no key for it yet, so its two lines, the engineer's
## words on the card, stand here until `hud.quest_item_area` lands (a request to the UI track).
const ZAP_NOTICE_KEY := "hud.quest_item_area"
const ZAP_NOTICE_EN := "Quest items can't leave the quest's area"
const ZAP_NOTICE_UK := "Квестові предмети не можна виносити із зони завдання"
## The roster's own and dead rows (the handoff s07).
const ROSTER_SELF := "hud.roster.self"
const ROSTER_DEAD := "hud.roster.dead"


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
	## The label of the interact key bound now while E would sit the own player at a chair
	## (ItemInteractions.sit_cue(), #1420); "" for none.
	var sit_key := ""
	## The ship's zap's notice is up (#1585; ShipZapScreen).
	var zap_notice := false
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


## One row of the roster (#1570, the handoff s07's Roster): a player of the round by its name and
## body colour, public to every player; `tag` is the own role's key on the own row and the
## teammates' rows of a role whose players know each other (the own Teammates knowledge, the
## same as the plates' mark, §4.7.29), else "".
class Row:
	extends RefCounted
	var peer := 0
	var name := ""
	var colour: Color
	## The own row (first, hud.roster.self).
	var own := false
	## Dead as the public events say (hud.roster.dead).
	var dead := false
	var tag := ""


## The HUD's state; a default one shows nothing.
class Shown:
	extends RefCounted
	## The time left as mm:ss; "" hides the timer.
	var time := ""
	## The own role's deck key (or display name); "" hides the chip.
	var role := ""
	## The role's tile takes the danger outline (ToyStickerAlert): the own role's players know each
	## other (the handoff's `human`, the hidden side), else ToySticker.
	var role_alert := false
	## The roster's rows, the own first; empty hides the roster.
	var roster: Array[Row] = []
	## The neighbours' anger, 0 to 1; negative hides the meter and its divider (the game's modes
	## have no anger yet, #1312: nothing sets it but a test or a preview).
	var anger := -1.0
	## The siren is on (the anger rises or is full).
	var siren := false
	## The cops' countdown as m:ss while the cops' minute runs; "" for none. It hides the round
	## timer (one clock, the engineer 2026-10-22) and shows the danger edge and banner.
	var cops := ""
	## The vitals' column shows (the own player in the round, not spectating): the microphone and,
	## when `bars`, health and stamina (not while downed).
	var vitals := false
	var bars := false
	## Health and stamina, 0 to 1.
	var health := 1.0
	var stamina := 1.0
	## Whether anyone hears the own player.
	var mic := false
	## Dead in the dead's hall: the names of the other dead waiting there (the mic's `Others`
	## chip, `dead.also_here`); empty hides the chip.
	var others := PackedStringArray()
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
	## The chair's cue in Aim (#1420): the interact key's label that fills SIT_CUE's `{key}`; ""
	## for none.
	var sit_key := ""
	## The HUD's notice plate, already in the language now; "" hides it (#1585).
	var notice := ""


static func of(model: ClientModel, mode: GameMode, host_tick: float, local: Local) -> Shown:
	var shown := Shown.new()
	if spectates(model):
		if model.waits_in_hall():
			shown.vitals = true
			shown.mic = local.mic
			shown.others = others_in_hall(model)
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
	shown.role_alert = role_alert(model, mode)
	shown.roster = roster_of(model, mode)
	shown.vitals = true
	shown.bars = true
	shown.health = health_of(model, mode)
	shown.stamina = stamina_of(local, mode)
	shown.mic = local.mic
	shown.slots = true
	if local.zap_notice:
		shown.notice = zap_notice_text()
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
	elif not local.sit_key.is_empty() and local.aim < 0 and local.aim_station < 0:
		# Only with nothing aimed at: an item or a station has E first (#1420).
		shown.sit_key = local.sit_key
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


## The zap's notice in the language now: the deck's, else its line until the key lands (#1585).
static func zap_notice_text() -> String:
	var word := String(TranslationServer.translate(ZAP_NOTICE_KEY))
	if word != ZAP_NOTICE_KEY:
		return word
	return ZAP_NOTICE_UK if TranslationServer.get_locale().begins_with("uk") else ZAP_NOTICE_EN


## The rescuer's cue in Aim, translated, with the raise key's label `key` (`RAISE_CUE`).
static func raise_cue(key: String) -> String:
	return String(TranslationServer.translate(RAISE_CUE)).format({"key": key})


## The hand-over's cue in Aim, translated, with the interact key's label `key`: the deck key
## `cue_key` (HAND_OVER_CUE when empty; TAKE_OFFER_CUE, OFFERING_CUE, #1434).
static func hand_over_cue(key: String, cue_key: String = "") -> String:
	var deck_key := HAND_OVER_CUE if cue_key.is_empty() else cue_key
	return String(TranslationServer.translate(deck_key)).format({"key": key})


## The chair's cue in Aim, translated, with the interact key's label `key` (`SIT_CUE`).
static func sit_cue(key: String) -> String:
	return String(TranslationServer.translate(SIT_CUE)).format({"key": key})


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


## Whether the own role's tile takes the danger outline: its players know each other (the mode's
## GameRole.knows_teammates; the handoff draws it for the hidden side, the humans).
static func role_alert(model: ClientModel, mode: GameMode) -> bool:
	if model.role.is_empty() or mode == null:
		return false
	var found := mode.find_role(model.role)
	return found != null and found.knows_teammates


## The roster's rows (the handoff s07): every player of the session in its order with the own row
## first, a player who left gone; names and colours are public, `dead` comes from the public
## events and `tag` from the own Teammates knowledge alone (never another role's).
static func roster_of(model: ClientModel, mode: GameMode) -> Array[Row]:
	var rows: Array[Row] = []
	var known: PackedInt32Array = model.teammates.get(model.role, PackedInt32Array())
	var tag := role_key(model, mode) if not known.is_empty() else ""
	var peers: Array[int] = []
	if model.roster.has(model.own_peer):
		peers.append(model.own_peer)
	for peer: int in model.roster:
		if peer != model.own_peer:
			peers.append(peer)
	for peer in peers:
		var life := model.life_of(peer)
		if life == ClientModel.Life.LEFT:
			continue
		var row := Row.new()
		row.peer = peer
		row.name = model.roster[peer].name
		row.colour = BodyColours.of(model.colour_of(peer))
		row.own = peer == model.own_peer
		row.dead = life == ClientModel.Life.DEAD
		row.tag = tag if row.own or known.has(peer) else ""
		rows.append(row)
	return rows


## The other dead of the session, in its order: who else waits in the dead's hall (deaths are
## public, the roster's `dead`; a player who left is gone).
static func others_in_hall(model: ClientModel) -> PackedStringArray:
	var names := PackedStringArray()
	for peer: int in model.roster:
		if peer != model.own_peer and model.life_of(peer) == ClientModel.Life.DEAD:
			names.append(model.roster[peer].name)
	return names


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
	# A kind the mode does not know has no icon: its id alone shows.
	slot.icon = icon_of(item.kind) if kind != null else &""
	slot.two_handed = kind != null and kind.is_two_handed()
	return slot


## The pack icon of item kind `kind`: ITEM_ICONS', else the pack's `item-<kind>` where the game
## imported one, else &"" (the slot shows the name alone).
static func icon_of(kind: StringName) -> StringName:
	if ITEM_ICONS.has(kind):
		return ITEM_ICONS[kind]
	var line_icon := StringName("item-%s" % kind)
	return line_icon if ResourceLoader.exists(ToyIcons.IMPORTED % line_icon) else &""


## A roster row's name as drawn, translated: the own through hud.roster.self, a dead player's
## through hud.roster.dead, else the bare name (data).
static func roster_name(row: Row) -> String:
	if row.own:
		return String(TranslationServer.translate(ROSTER_SELF)).format({"name": row.name})
	if row.dead:
		return String(TranslationServer.translate(ROSTER_DEAD)).format({"name": row.name})
	return row.name
