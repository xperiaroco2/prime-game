class_name SoundChooser
extends RefCounted
## Which world sound an event plays, and where (ARCHITECTURE §4.7, a hearing range;
## the M4 ADR's §3 item 10, E33 (a), D9; M4-8), pure. `Swung`, `ItemPickedUp` and `ItemPlaced`
## reach everyone with a position: a sound with no cut-off would tell every client, through the
## walls, where a package was just put down or a fight goes on. So a sound plays only within
## HEARING_RANGE_M of the ears (E40's amendment of E33, the engineer's: the own eye, the own body's
## head while downed, the spectated target's eye or body; LifeView's Ears), and nothing at all for
## an event from farther away; each player also sets `AudioStreamPlayer3D.max_distance` to it.
## Occlusion muffles, never cuts: WorldSounds casts one ray to a chosen sound's `aim` as it starts
## (M5-7).
##
## Where each one plays:
## - Swung: at the swinger: the local player for the own swing, else its interpolated pose;
## - ItemPickedUp: where the item lay (the model's fold keeps the item's last resting place);
## - ItemPlaced: at the event's position;
## - ItemThrown: at the launch's origin, the thrower's eye (37e: ItemViews hands it over when the
##   drawn item launches, and a thrown item's ItemPlaced when it lands at its rest). ItemThrown
##   reaches everyone with its origin: uncut, the launch would tell every client where a package
##   was just thrown to hide it;
## - a footstep (step(), #525, no event): at the feet of a walking player as this client draws it;
## - the photo task (#785, photo P6; the photo ADR §1.1 row 7, §4, PD15): ShotTaken's shutter at
##   the camera's lens (its station's marker plus `lens_m`, the mode's eye height, as PhotoTask's
##   lens), PhotoPrinted's print where the photo lies on the printer's tray (its ItemSpawned came
##   right before), PhotoHung's at the board's marker: a counted photo the task's success (#1341),
##   one without a person (not counted, PD6) its error. Each event reaches everyone with its place
##   already public (the stations, the tray; `counted` says no more than TaskProgress, PE5); the
##   same cut-off keeps a shot, a print or a hang beyond the hearing range silent, and the muffle
##   ray applies as to every sound.
## - the Generator (#801, G6): SwitchChanged's click at the switch's station, ButtonPressed's at the
##   generator's, each the place its StationPlaced already told everyone; the hum while it charges
##   is StationHums', not an event's;
## - Cooking (#776, the cooking ADR's CD14 (a), amended by #1101): IngredientPlaced's put click
##   at its place (never right or wrong: a burger is checked only when served), BurgerPlated's
##   chime at the place (the burger made), BurgerServed's success (right) or error (wrong) at the
##   order board of the client's own copy of the mode (`mode`; none: silent);
##   GrillLoaded's put click at the grill; ItemChanged's ding (a patty fried) or error (burnt) where
##   the patty lies, told by the new kind in the client's own copy of the mode (`mode`). A take is
##   the ItemPickedUp that follows its ItemSpawned (a pick-up's click); the sizzle while a patty
##   fries is StationHums', not an event's. No sound says who put what (the ADR's §3).
## - every task's success and error (#1341, ARCHITECTURE §4.7.60): SfxSet.TASK_SUCCESS whenever a
##   task or one of its subtasks is done, SfxSet.TASK_ERROR on a miss by the task's own rules, each
##   at the station of that task's event, cut and muffled like every sound here, the same whoever
##   caused it. Done: PackageDelivered at its circle or drop-off (Delivery, DeliveryByMeaning), a
##   done ZoneProgress at its zone or the generator (ZoneTask, Generator), a right BurgerServed,
##   PartFitted at the car, a counted PhotoHung at the board. A miss: a wrong BurgerServed, a
##   patty turned burnt and a PhotoHung not counted (a photo without a person). A delivery or a
##   charge done at the deal (a package that spawned in its circle, a generator dealt with no
##   switch) is no one's success: those two play only in play (in_play()).

## About 12 m (E33 (a)): a placeholder, "not a decision".
const HEARING_RANGE_M := 12.0
## How far above where it plays the occlusion ray aims (M5-7). A swing plays at the swinger's feet
## and an item on what it lies on: a ray to a point on a floor, a step or a table reaches it only
## from above, so ears below that surface, or a curb in front of the feet, would muffle a sound in
## plain view. A swing aims at about a standing player's chest, an item a hand above its surface.
## Placeholders, "not a decision".
const SWING_AIM_M := 1.0
const ITEM_AIM_M := 0.3
## A launch plays at the thrower's eye, in the air: the ray aims at the origin itself.
const THROW_AIM_M := 0.0

const SWING := &"swing"
const PICK_UP := &"pick_up"
const PUT_DOWN := &"put_down"
const THROW := &"throw"
## A footstep (#525): WorldSounds plays one on the cadence of a walking player (FootstepCadence).
const FOOTSTEP := &"footstep"
## A step plays at the feet and aims like an item, a hand above the floor it is on: a ray to the
## feet would end in that floor. A placeholder, "not a decision".
const STEP_AIM_M := ITEM_AIM_M
## The photo task's sounds (#785, PD15): the shot's shutter, a photo printed (a photo hung plays
## SfxSet.TASK_SUCCESS when counted and SfxSet.TASK_ERROR when not, #1341).
const SHUTTER := &"shutter"
const PRINT := &"print"
## The shutter plays at the lens, in the air: the ray aims at the lens itself.
const SHUTTER_AIM_M := 0.0
## A hang plays at the board's marker, on the floor below the board: the ray aims at about where a
## photo goes on it, as a swing aims at a chest. A placeholder, "not a decision".
const HANG_AIM_M := SWING_AIM_M
## The Generator's clicks (#801, G6): a switch thrown, the generator's button pressed.
const SWITCH_CLICK := &"switch_click"
const BUTTON_CLICK := &"button_click"
## A switch and the button sit on a panel at about a chest's height above their station's marker on
## the floor: the ray aims there, as a swing aims at a chest. A placeholder, "not a decision".
const PANEL_AIM_M := SWING_AIM_M
## Cooking's own sounds (#776, CD14 (a)): a burger plated, a patty fried (the grill's sizzle loop is
## StationHums', not an id here). A serve and a burnt patty play SfxSet's task sounds (#1341).
const CHIME := &"chime"
const DING := &"ding"
## A plate and the grill's grate sit on a counter at about a chest's height above their station's
## marker on the floor: the ray aims there, as at a panel. A placeholder, "not a decision".
const COUNTER_AIM_M := PANEL_AIM_M
## The car repair's sounds (#811, the car repair ADR's RD14): the lift coming down, at its car,
## only in the round (the phase end's stop lowers the car without a crash, RE4; its LiftChanged
## comes before its PhaseChanged, so WorldSounds holds the crash to the next physics frame and plays
## it only while the round runs). A part fitted plays SfxSet.TASK_SUCCESS at the car (#1341).
## FitChanged makes no sound; a part taken from a bin is ItemPickedUp's pick-up.
const LIFT_CRASH := &"lift_crash"
## Where at the car its sounds aim: about its middle.
const CAR_AIM_M := SWING_AIM_M
## Where a delivery's success aims (#1341): a hand above its circle or drop-off on the floor, as an
## item. A zone's and the generator's: a chest's height above the station's marker, where a player
## stands in the zone and the generator's panel is. Placeholders, "not a decision".
const DELIVERY_AIM_M := ITEM_AIM_M
const ZONE_AIM_M := PANEL_AIM_M


## One sound to play: where it plays, and where the occlusion ray aims (`lift` above it).
class Sound:
	extends RefCounted
	var id: StringName
	var position := Vector3.ZERO
	var aim := Vector3.ZERO

	func _init(sound_id: StringName, at: Vector3, lift: float) -> void:
		id = sound_id
		position = at
		aim = at + Vector3.UP * lift


## The sound for event `event_name` (already folded into `model`) within `hearing_m` of
## `listener`, or null: a silent event, an unknown place, or too far. `position_of` gives a peer's
## position (a Vector3), or null when the client draws no such player. `lens_m`: how far above a
## camera's marker its lens is (the client's own copy of the mode's eye height, as PhotoTask's).
## `mode`: the client's own copy of the mode (which kinds are Cooking's fried and burnt patties);
## null leaves ItemChanged silent.
static func choose(
	event_name: StringName,
	fields: Dictionary,
	model: ClientModel,
	position_of: Callable,
	listener: Vector3,
	hearing_m := HEARING_RANGE_M,
	lens_m := 0.0,
	mode: GameMode = null
) -> Sound:
	var sound := source(event_name, fields, model, position_of, lens_m, mode)
	if sound == null or not audible(sound.position, listener, hearing_m):
		return null
	return sound


## The sound an event makes and where, wherever the listener is; null for a silent event or an
## unknown place.
static func source(
	event_name: StringName,
	fields: Dictionary,
	model: ClientModel,
	position_of: Callable,
	lens_m := 0.0,
	mode: GameMode = null
) -> Sound:
	match event_name:
		&"Swung":
			var at: Variant = position_of.call(fields["peer"] as int)
			return Sound.new(SWING, at as Vector3, SWING_AIM_M) if at is Vector3 else null
		&"ItemPickedUp":
			var item: ClientModel.Item = model.items.get(fields["item"] as int)
			return Sound.new(PICK_UP, item.position, ITEM_AIM_M) if item != null else null
		&"ItemPlaced":
			return Sound.new(PUT_DOWN, fields["position"] as Vector3, ITEM_AIM_M)
		&"ItemThrown":
			return Sound.new(THROW, fields["origin"] as Vector3, THROW_AIM_M)
		&"ShotTaken":
			var camera: ClientModel.Station = model.stations.get(fields["station"] as int)
			if camera == null:
				return null
			return Sound.new(SHUTTER, camera.position + Vector3.UP * lens_m, SHUTTER_AIM_M)
		&"PhotoPrinted":
			var photo: ClientModel.Item = model.items.get(fields["item"] as int)
			return Sound.new(PRINT, photo.position, ITEM_AIM_M) if photo != null else null
		&"PhotoHung":
			var board: ClientModel.Station = model.stations.get(fields["station"] as int)
			if board == null:
				return null
			var hung := SfxSet.TASK_SUCCESS if (fields["counted"] as bool) else SfxSet.TASK_ERROR
			return Sound.new(hung, board.position, HANG_AIM_M)
		&"PackageDelivered":
			var circle: ClientModel.Station = model.stations.get(fields["station"] as int)
			if circle == null or not in_play(model):
				return null
			return Sound.new(SfxSet.TASK_SUCCESS, circle.position, DELIVERY_AIM_M)
		&"ZoneProgress":
			var zone: ClientModel.Station = model.stations.get(fields["station"] as int)
			var needed: int = fields["needed"]
			if zone == null or needed <= 0 or (fields["ticks"] as int) < needed:
				return null
			if not in_play(model):
				return null
			return Sound.new(SfxSet.TASK_SUCCESS, zone.position, ZONE_AIM_M)
		&"SwitchChanged", &"ButtonPressed":
			var panel: ClientModel.Station = model.stations.get(fields["station"] as int)
			if panel == null:
				return null
			var id := SWITCH_CLICK if event_name == &"SwitchChanged" else BUTTON_CLICK
			return Sound.new(id, panel.position, PANEL_AIM_M)
		&"IngredientPlaced", &"GrillLoaded", &"BurgerPlated":
			var station: ClientModel.Station = model.stations.get(fields["station"] as int)
			if station == null:
				return null
			var put := CHIME if event_name == &"BurgerPlated" else PUT_DOWN
			return Sound.new(put, station.position, COUNTER_AIM_M)
		&"BurgerServed":
			var board := _order_board(model, mode, fields["station"] as int)
			if board == null:
				return null
			var served := SfxSet.TASK_SUCCESS if (fields["right"] as bool) else SfxSet.TASK_ERROR
			return Sound.new(served, board.position, COUNTER_AIM_M)
		&"ItemChanged":
			var changed: ClientModel.Item = model.items.get(fields["item"] as int)
			var id := _cooked_sound(mode, fields["kind"] as StringName)
			if changed == null or id == &"":
				return null
			return Sound.new(id, changed.position, COUNTER_AIM_M)
		&"LiftChanged":
			if fields["up"] as bool or not in_play(model):
				return null
			var car := _car_of(model, mode, fields["station"] as int)
			return Sound.new(LIFT_CRASH, car.position, CAR_AIM_M) if car != null else null
		&"PartFitted":
			var fitted: ClientModel.Station = model.stations.get(fields["station"] as int)
			if fitted == null:
				return null
			return Sound.new(SfxSet.TASK_SUCCESS, fitted.position, CAR_AIM_M)
	return null


## Whether the model's current phase is the play phase, asked of the client's copy of the mode's
## PhaseSpec, not of a phase id: the one whose match clock runs (`clock_runs`: the round's time is
## what a lift crash belongs to; `checks_wins` is the win rule, a different question). False for no
## model or an unknown phase.
static func in_play(model: ClientModel) -> bool:
	if model == null:
		return false
	var spec := model.phase_spec()
	return spec != null and spec.clock_runs


## The car of the car repair whose station `id` is (its lift panel), or null; null without a mode.
static func _car_of(model: ClientModel, mode: GameMode, id: int) -> ClientModel.Station:
	var station: ClientModel.Station = model.stations.get(id)
	if station == null or mode == null:
		return null
	var type := CarRepairUse.type_of(mode, station.kind)
	return CarRepairUse.station_of(model, type, CarRepairUse.Role.CAR) if type != null else null


## The order board of the Cooking whose place is station `place_id` in `model`, where a serve
## sounds; null for an unknown place, no mode or no board placed.
static func _order_board(model: ClientModel, mode: GameMode, place_id: int) -> ClientModel.Station:
	var place: ClientModel.Station = model.stations.get(place_id)
	if place == null:
		return null
	var type := CookingUse.type_of(mode, place.kind)
	var boards := CookingUse.stations_of(model, type, CookingUse.Role.ORDER_BOARD)
	return model.stations[boards[0]] if not boards.is_empty() else null


## The sound of an item turning into kind `kind_id`: a ding for a fried patty of a Cooking of
## `mode`, the task's error for its burnt patty (#1341); empty for any other change, or no mode.
static func _cooked_sound(mode: GameMode, kind_id: StringName) -> StringName:
	if mode == null:
		return &""
	for type: Cooking in CookingUse.types_of(mode):
		if type.burnt != null and type.burnt.id == kind_id:
			return SfxSet.TASK_ERROR
		for fried: ItemKind in type.fried_patties:
			if fried != null and fried.id == kind_id:
				return DING
	return &""


## The footstep of feet at `at` within `hearing_m` of `listener`, or null when too far (#525): the
## same cut-off as every world sound, before any ray.
static func step(at: Vector3, listener: Vector3, hearing_m := HEARING_RANGE_M) -> Sound:
	if not audible(at, listener, hearing_m):
		return null
	return Sound.new(FOOTSTEP, at, STEP_AIM_M)


## Whether a sound at `at` is within `hearing_m` of `listener`.
static func audible(at: Vector3, listener: Vector3, hearing_m := HEARING_RANGE_M) -> bool:
	return at.distance_to(listener) <= hearing_m
