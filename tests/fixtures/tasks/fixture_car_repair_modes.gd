class_name FixtureCarRepairModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the car repair (core/tasks/car_repair.gd,
## #807), built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its ids,
## tags and numbers are fixture values, not the engineer's provisional ones (those land in data,
## R6).
##
## basic(): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the knife, the
## raise, StopRaise, the give-up; Round lists LifeTicks with a Respawn, then ChannelTicks) with the
## settings `tasks` (1), `banned_task_types` and `car_parts` (0 to MAX_PARTS), the task type
## CarRepair with PARTS part kinds (one-handed, capped at MAX_ITEMS) and its kinds: `car` (the fit:
## HandNotTwoHanded, AtStation, StationInSight, ChannelFree, StationUsable; a timed HoldStation of
## FIT_SECONDS), `lift_panel` (the same conditions; an endless HoldStation that a hit does not
## stop), one bin per part (AtStation, StationInSight, a Cooldown of TAKE_SECONDS; GiveItem) and
## the display kind `part_picture`; the deal before PlacePlayers, Round accepting Interact from the
## living.
##
## winning(): FixtureWinModes.basic() (DealRoles, the clock, the base mode's win conditions,
## EndMatch and ResetMatch) with the car repair in place of Delivery, Interact, StopRaise and the
## Use of the knife in Round, ChannelTicks and LifeTicks' Respawn.
##
## layouts(): the fixture lobby and map plus the car at CAR_AT with its `car_end` at CAR_END_AT
## (the axis along +z, half-length 2 m), the panel at PANEL_AT, the bins at BIN_SPOTS and the
## picture at PICTURE_AT, far from the players (round_player markers at (10 + i, 0, 5)).

const PARTS: Array[StringName] = [&"spark_plug", &"filter", &"belt"]
const MAX_PARTS := 6
const MAX_ITEMS := 32
const FIT_SECONDS := 1.0
const RISE_SECONDS := 0.5
const RISE_TICKS := 10
const TAKE_SECONDS := 0.25
const HALF_WIDTH_M := 1.2
const CLEARANCE_M := 1.0
const CAR_AT := Vector3(0, 0, 30)
const CAR_END_AT := Vector3(0, 0, 32)
const PANEL_AT := Vector3(5, 0, 30)
## A lift panel beside the car, so a holder can stand inside the footprint box (x up to 1.2) and
## still within the panel's 1 m cylinder: the RE17 cases of a holder in the box.
const NEAR_PANEL_AT := Vector3(2, 0, 30)
const BIN_SPOTS: Array[Vector3] = [Vector3(0, 0, 40), Vector3(3, 0, 40), Vector3(6, 0, 40)]
const PICTURE_AT := Vector3(0, 0, 45)
## Where a player stands to use a station: 0.5 m short of its marker, inside its cylinder.
const SHORT := Vector3(0, 0, -0.5)


static func basic(parts: int = 3) -> GameMode:
	var mode := FixtureCombatModes.raising()
	_add_car_repair(mode, parts)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


static func winning(parts: int = 3) -> GameMode:
	var mode := FixtureWinModes.basic(0)
	mode.settings.erase(mode.find_setting(&"packages"))
	_add_car_repair(mode, parts)
	var round_phase := mode.find_phase(&"round")
	mode.actions.append(FixtureCombatModes.stop_raise_rule())
	round_phase.accepts.append(AcceptSpec.of(Intents.STOP_RAISE, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(ChannelTicks.new())
	var life := round_phase.tick_systems[0] as LifeTicks
	if life != null and life.respawn == null:
		life.respawn = FixtureCombatModes.respawn()
	return mode


static func car_repair_type() -> CarRepair:
	var made := CarRepair.new()
	made.id = &"car_repair"
	made.description = "Hold the lift up while a teammate fits the part under the car."
	made.subtasks_setting = &"car_parts"
	made.rise_seconds = RISE_SECONDS
	made.half_width_m = HALF_WIDTH_M
	made.clearance_m = CLEARANCE_M
	for part_id: StringName in PARTS:
		made.parts.append(part(part_id))
	made.car = kind(&"car", 1.0, CLEARANCE_M)
	made.car.actions = [FixtureStationModes.hold_rule(FixtureStationModes.hold(FIT_SECONDS))]
	made.lift_panel = kind(&"lift_panel", 1.0, 2.0)
	made.lift_panel.actions = [
		FixtureStationModes.hold_rule(FixtureStationModes.hold(0.0, true, false))
	]
	for item: ItemKind in made.parts:
		made.bins.append(bin(item))
	made.picture = kind(&"part_picture", 0.5, 1.0)
	made.picture.display = true
	return made


static func part(part_id: StringName) -> ItemKind:
	var made := ItemKind.new()
	made.id = part_id
	made.display_name = String(part_id)
	made.hands = 1
	made.max_items = MAX_ITEMS
	return made


## A station kind whose spawn tag is its id, with no rule.
static func kind(kind_id: StringName, radius: float, height: float) -> StationKind:
	var made := StationKind.new()
	made.id = kind_id
	made.spawn_tag = kind_id
	made.radius_m = radius
	made.height_m = height
	return made


## The bin of `item`: `bin_<id>`, its rule AtStation, StationInSight, a Cooldown; GiveItem.
static func bin(item: ItemKind) -> StationKind:
	var made := kind(StringName("bin_%s" % item.id), 1.0, 2.0)
	var give := GiveItem.new()
	give.kind = item
	made.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[
				AtStation.new(),
				StationInSight.new(),
				FixtureCombatModes.cooldown(&"car_part_take", TAKE_SECONDS)
			],
			[give]
		)
	]
	return made


## The mode's CarRepair.
static func type_of(mode: GameMode) -> CarRepair:
	for type: TaskType in mode.task_types:
		if type is CarRepair:
			return type as CarRepair
	return null


## The fixture layouts with the car repair's markers; `car_end_at` moves the `car_end` marker and
## `panel_at` the lift panel's (NEAR_PANEL_AT puts its cylinder over the footprint box's edge).
static func layouts(
	car_end_at: Vector3 = CAR_END_AT, panel_at: Vector3 = PANEL_AT
) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	var map := found[FixtureModes.MAP]
	map.add_marker(&"car", CAR_AT)
	map.add_marker(&"car_end", car_end_at)
	map.add_marker(&"lift_panel", panel_at)
	for i in PARTS.size():
		map.add_marker(StringName("bin_%s" % PARTS[i]), BIN_SPOTS[i])
	map.add_marker(&"part_picture", PICTURE_AT)
	return found


## A match of `mode` in `world` (flat, no walls, by default) on `found_layouts` (layouts() when
## empty), that keeps its history, with `peers` joined, `settings` over the defaults, `forced`
## roles (peer -> role id), and all ready: the deal has run and the match is in the round.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7,
	forced: Dictionary[int, StringName] = {},
	world: WorldQuery = null
) -> Match:
	var game := Match.new(
		mode,
		seed_value,
		world if world != null else FlatWorldQuery.new(),
		found_layouts if not found_layouts.is_empty() else layouts()
	)
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for id: StringName in settings:
		game.state.settings[id] = settings[id]
	for peer: int in forced:
		game.state.forced_roles[peer] = forced[peer]
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The match's car repair task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is CarRepair:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> CarRepair.State:
	return task_of(game).state as CarRepair.State


## `peer` stands at `station` (SHORT of its marker) and names it in an Interact, applied on the
## next host tick.
static func use(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureItemModes.stand(game, peer, game.state.stations[station].position + SHORT)
	FixtureStationModes.interact(game, peer, station, seq)


## `peer` holds the lift: stands at the panel and presses E there.
static func hold(game: Match, peer: int, seq: int = 0) -> void:
	use(game, peer, state_of(game).panel, seq)


## A spot under the car: `along` metres from its middle along its axis, `side` metres across.
static func under(along: float = 0.0, side: float = 0.0) -> Vector3:
	return CAR_AT + Vector3(side, 0, along)


## The names of the events `peer` received among `names`, in order.
static func stream(game: Match, peer: int, names: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events:
		if event.event_name() in names:
			found.append(event.event_name())
	return found


## The events `peer` received among `names`, as plain data with their names, in order.
static func described(game: Match, peer: int, names: Array[StringName]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events:
		if event.event_name() in names:
			var entry := event.to_dict()
			entry["event"] = event.event_name()
			found.append(entry)
	return found


## Adds the `car_parts` setting (`parts` of 0 to MAX_PARTS), the car repair in place of the mode's
## task types (its parts among the item kinds), and Interact from the living in Round; the
## settings `tasks` and `banned_task_types` when missing.
static func _add_car_repair(mode: GameMode, parts: int) -> void:
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"car_parts", parts, 0, MAX_PARTS))
	var type := car_repair_type()
	mode.task_types = [type]
	mode.item_kinds.append_array(type.parts)
	var round_phase := mode.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
