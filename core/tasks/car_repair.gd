class_name CarRepair
extends TaskType
## The car repair (#688; ARCHITECTURE §3.3, §9.5; the car repair ADR, approved for the MVP only):
## one shared task whose subtasks are the N parts the car needs, fitted one at a time under the
## raised car, N the subtasks setting (RD4 (a)). Nobody owns it: any living player of any role holds
## the lift, takes a part from a bin or fits it (Interact, through the station kinds' rules), and
## no condition reads a role. R3 (#807) built the deal, the lift and the drop; R4 (#808) the fit
## and its parts.
##
## The deal (the ADR's §2.1; DealTasks calls deal() when the draw picks it): a station on every
## marker of the type's kinds (each a device, so the demands are exact counts, RE14): the car, the
## lift panel, one bin per part kind in `parts` order, then the picture (`part_picture`, a display
## kind: never used). The `car_end` marker gives the car's long axis (RE7); it is no station. The N
## needed parts are drawn in order from `parts` with the purpose `parts_rng`, each uniformly from
## the kinds other than the one before it (RD3 (g); with one kind, that kind every time). Then
## StationPlaced per station in id order, then PartNeeded(picture, first part). With N = 0 the task
## has no subtasks and is done at the deal (#79), and PartNeeded carries no kind.
##
## The hold (the ADR's §2.2): the lift panel's Interact rule ends in an endless HoldStation (RE1,
## RE3); its start emits LiftChanged(panel, true, tick) and records the tick (the car is fully up
## `rise_seconds` later, RD5 (b); computed where it is read, RE11, so the type never ticks). The
## panel refuses a new hold `unavailable` once the task is done; a running hold is never refused on
## its re-check (MatchContext.channel set; RD11 (a)).
##
## The drop (the ADR's §2.3): the hold stopping for any reason (HoldStation.stopped calls
## hold_stopped()) emits LiftChanged(panel, false, tick); unless the phase's end stopped it
## (Channel.phase_ended, RE4: the car comes down without a kill), every player whose feet (its last
## accepted position) lie inside the footprint box at the stop (in_box(), RE7) and who is living or
## knocked down (RD7, invulnerable or not) is queued through LifeRules.kill_later (RE17): the queue
## kills them in peer-id order once the command, the tick system or the channel's step has finished,
## so nobody dies halfway through someone's command.
##
## The fit (the ADR's §2.4, RD8 (a), RD10 (d)): the car's Interact rule ends in a timed
## HoldStation. After the rule's own refusals (`two_handed`, `out_of_reach`, `blocked`, `busy`)
## the type refuses it `unavailable` (the car not fully up, or the task done), `empty_hand` (no
## item in the hand) or `wrong_item` (an item other than the part needed now: another part or
## anything else, RD8 (a)). The same refusals run on every re-check, so the car going down or the
## part leaving the hand stops the fit, and AtStation stops a fitter whose last accepted claim is
## too old (RE2). Its start emits FitChanged(car, fitter, tick), a stop FitChanged(car, 0, tick):
## the progress is lost (RD10 (d)). Completed, the part leaves the hand, locked at the car's use
## spot (Items.lock_at, RE12), then PartFitted(car, item), the subtask (Tasks.subtask_done:
## TaskState, TaskProgress, subtask_done), then PartNeeded(picture, next part), with no kind once
## the last is fitted and the task is done. The hold goes on: the fitter must get out before the
## holder lets go.
##
## The bins (the ADR's §2.5, RE13): each bin's Interact rule is cooking's item source (a
## Cooldown, then GiveItem of its part: Items.give makes room, the kind's max_items caps it) with
## no busy-hands condition (RD17's belt rule: a package carrier's part goes onto the belt). A bin
## never refuses for the task's state.
##
## Emits: StationPlaced and PartNeeded (everyone) in the deal; LiftChanged (everyone) on a hold's
## start and stop; FitChanged (everyone) on a fit's start and stop; PartFitted, TaskState,
## TaskProgress and PartNeeded (everyone) on a fit's completion (hold_emits). LiftChanged names
## neither the holder nor who let go (the ADR's §3); FitChanged names the fitter (RD15 (a)).

## The bounds of `rise_seconds` (RE14).
const MAX_RISE_SECONDS := 60.0
## The bounds of `half_width_m` and `clearance_m` (RE14).
const MIN_HALF_WIDTH_M := 0.2
const MAX_HALF_WIDTH_M := 10.0
const MIN_CLEARANCE_M := 0.5
const MAX_CLEARANCE_M := 10.0
## How far below the car's floor (its use spot's height) a player's feet still count as on that
## floor for the box test: a technical tolerance for the snapped markers and the claims' rounding,
## far less than a storey. Not a game rule.
const FLOOR_TOLERANCE_M := 0.25
## The centimetres of a metre, for the whole-number arguments of HostText.SHORT_AXIS.
const CM := 100.0


## The car repair's state (§9.1, RE11): the station ids, the needed parts drawn at the deal, how
## many are fitted, the tick the current hold began, and the car's long axis. Only CarRepair reads
## and writes it; who holds stays in Channels.
class State:
	extends TaskState

	## The car's station id (-1 before the deal placed it).
	var car := -1
	## The lift panel's station id.
	var panel := -1
	## The bins' station ids, in `parts` order: bin i gives part i.
	var bins := PackedInt32Array()
	## The picture's station id.
	var picture := -1
	## Where the `car_end` marker stands: the middle of the car's front, on the floor (RE7).
	var car_end := Vector3.ZERO
	## The needed parts' item kind ids, in the order they are fitted: subtask i is part i.
	var needed: Array[StringName] = []
	## Parts fitted so far.
	var fitted := 0
	## The host tick the running hold began; -1 when nobody holds.
	var held_since := -1

	func done_count() -> int:
		return fitted

	func total() -> int:
		return needed.size()

	## The part needed now, or empty when every part is fitted.
	func next_part() -> StringName:
		return needed[fitted] if fitted < needed.size() else &""


## The car's station kind: its use spot under the car, its middle (RE7, RE16).
@export var car: StationKind
## The lift panel's station kind.
@export var lift_panel: StationKind
## One bin station kind per part kind (RE13), each with its own spawn tag and an Interact rule
## ending in GiveItem of its part.
@export var bins: Array[StationKind] = []
## The picture of the needed part (RD3): a display station kind (StationKind.display) on the
## garage wall.
@export var picture: StationKind
## The part item kinds, one-handed, each given by exactly one bin (RE13).
@export var parts: Array[ItemKind] = []
## The spawn tag of the marker at the middle of the car's front (RE7): no station.
@export var car_end_tag: StringName = &"car_end"
## Seconds from a hold's start to the car fully up (RD5 (b)): 0 to 60. The neutral default is out
## of bounds on purpose: the data sets it.
@export var rise_seconds := -1.0
## Half the footprint box's width, metres (RE7): 0.2 to 10. The data sets it.
@export var half_width_m := 0.0
## The footprint box's height, the raised car's underside above its floor, metres (RE7): 0.5 to
## 10. The data sets it.
@export var clearance_m := 0.0
## The RNG purpose of the needed parts (§3.3, RD3 (g)).
@export var parts_rng: StringName = &"car_parts"


func new_state() -> TaskState:
	return State.new()


## The car, the lift panel, the bins in their order, then the picture: the order of the deal's
## StationPlaced events (DE4: the one finder of a type's kinds).
func station_kinds() -> Array[StationKind]:
	var found: Array[StationKind] = []
	for kind: StationKind in [car, lift_panel]:
		if kind != null:
			found.append(kind)
	for kind: StationKind in bins:
		if kind != null:
			found.append(kind)
	if picture != null:
		found.append(picture)
	return found


## The host ticks from a hold's start to the car fully up: `rise_seconds` by the one rounding
## rule (Ticks).
func rise_ticks() -> int:
	return maxi(0, Ticks.from_seconds(rise_seconds))


## Whether the car is fully up at host tick `at_tick` (RE11): a hold runs and began at least
## rise_ticks() ago.
func is_up(task_state: State, at_tick: int) -> bool:
	return task_state.held_since >= 0 and at_tick - task_state.held_since >= rise_ticks()


func kills() -> bool:
	return true


func deal(ctx: MatchContext) -> void:
	var count := maxi(ctx.setting(subtasks_setting), 0)
	if not _fits(ctx):
		return
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	var placed: Array[StationState] = []
	placed.append(_place(ctx, car))
	placed.append(_place(ctx, lift_panel))
	task_state.car = placed[0].id
	task_state.panel = placed[1].id
	for part: ItemKind in parts:
		var bin := _place(ctx, bin_of(part))
		placed.append(bin)
		task_state.bins.append(bin.id)
	var shown := _place(ctx, picture)
	placed.append(shown)
	task_state.picture = shown.id
	task_state.car_end = ctx.layout.positions(car_end_tag)[0]
	task_state.needed = draw(count, ctx.rng(parts_rng))
	for station: StationState in placed:
		ctx.emit(
			StationPlacedEvent.new(station.id, station.kind.id, station.colour, station.position)
		)
	ctx.emit(PartNeededEvent.new(task_state.picture, task_state.next_part()))


## `count` part kind ids drawn from `rng` (RD3 (g)): the first uniformly from `parts`, each later
## one uniformly from the kinds other than the one before it; with one kind, that kind every time.
func draw(count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var found: Array[StringName] = []
	var before := -1
	for i in count:
		var index := 0
		if parts.size() > 1:
			if before < 0:
				index = rng.randi_range(0, parts.size() - 1)
			else:
				index = rng.randi_range(0, parts.size() - 2)
				if index >= before:
					index += 1
		found.append(parts[index].id)
		before = index
	return found


## The bin station kind whose Interact rule gives `part`, or null.
func bin_of(part: ItemKind) -> StationKind:
	for bin: StationKind in bins:
		if bin != null and _given_by(bin) == part:
			return bin
	return null


## The lift panel takes a new hold until the task is done; a running hold passes its re-check
## whatever the task's state (RD11 (a): MatchContext.channel is set there). The car takes a fit
## (the ADR's §2.4) only while it is fully up and the task is not done (`unavailable`), from an
## actor holding the part needed now in its hand (`empty_hand`, then `wrong_item`: RD8 (a)); a
## running fit's re-check asks the same, so it stops when the car goes down or the part leaves the
## hand. A bin never refuses for the task's state (the ADR's §2.5). Reads no role: only the car's
## public state and what the actor holds.
func use_problem(ctx: MatchContext, task: MatchTask, station: StationState) -> StringName:
	if task == null:
		return StationUsable.UNAVAILABLE
	var task_state := task.state as State
	if station.id == task_state.panel:
		if ctx.channel != null:
			return &""
		return StationUsable.UNAVAILABLE if task_state.is_done() else &""
	if station.id == task_state.car:
		return _fit_problem(ctx, task_state)
	return &""


## Why the car refuses a fit by the actor of `ctx` now, or empty (the ADR's §2.4, RD8 (a)).
func _fit_problem(ctx: MatchContext, task_state: State) -> StringName:
	if task_state.is_done() or not is_up(task_state, ctx.tick):
		return StationUsable.UNAVAILABLE
	var held := Items.held_by(ctx.state, ctx.actor)
	if held == null:
		return StationUsable.EMPTY_HAND
	if held.kind == null or held.kind.id != task_state.next_part():
		return StationUsable.WRONG_ITEM
	return &""


## The car's refusals and the panel's (the cooking ADR's CE11): StationUsable lists each.
func use_reasons() -> Array[StringName]:
	return [StationUsable.UNAVAILABLE, StationUsable.EMPTY_HAND, StationUsable.WRONG_ITEM]


## A hold at the lift panel started: the car starts rising (LiftChanged, up). A fit at the car
## started: FitChanged names its fitter.
func hold_started(
	ctx: MatchContext, task: MatchTask, station: StationState, channel: Channel
) -> void:
	if task == null:
		return
	var task_state := task.state as State
	if station.id == task_state.car:
		ctx.emit(FitChangedEvent.new(station.id, channel.actor, ctx.tick))
		return
	if station.id != task_state.panel:
		return
	task_state.held_since = ctx.tick
	ctx.emit(LiftChangedEvent.new(station.id, true, ctx.tick))


## A hold at the lift panel stopped: the drop. LiftChanged (down) first, then, unless the phase's
## end stopped it (RE4), every living or downed player inside the footprint box is queued for the
## kill (RE7, RE17), in peer-id order. A fit at the car stopped before it completed, for any
## reason: FitChanged(car, 0, tick); its progress is lost with the channel (RD10 (d)).
func hold_stopped(
	ctx: MatchContext, task: MatchTask, station: StationState, channel: Channel
) -> void:
	if task == null:
		return
	var task_state := task.state as State
	if station.id == task_state.car:
		ctx.emit(FitChangedEvent.new(station.id, 0, ctx.tick))
		return
	if station.id != task_state.panel:
		return
	task_state.held_since = -1
	ctx.emit(LiftChangedEvent.new(station.id, false, ctx.tick))
	if channel.phase_ended:
		return
	var car_station: StationState = ctx.state.stations.get(task_state.car)
	if car_station == null:
		ctx.error("CarRepair: the car's station %d is not placed" % task_state.car)
		return
	var peers: Array[int] = []
	peers.assign(ctx.state.players.keys())
	peers.sort()
	for peer: int in peers:
		var player := ctx.state.players[peer]
		if player.life != PlayerState.Life.ALIVE and player.life != PlayerState.Life.DOWNED:
			continue
		if in_box(car_station.position, task_state.car_end, player.position):
			LifeRules.kill_later(ctx, peer)


## A fit at the car completed (the ADR's §2.4, RE12): the part leaves the fitter's hand, locked at
## the car's use spot (Items.lock_at, as a delivered package: no PickUp takes it and it never
## vanishes), then PartFitted(car, item), the subtask done (Tasks.subtask_done: TaskState,
## TaskProgress, the fact with the subtask's index and the car), then PartNeeded(picture, next
## part), with no kind once the last part is fitted. The completing step's re-check passed just
## before (Channels: re-check, then completion), so the hand holds the needed part; anything else
## is a rule error and nothing is fitted.
func hold_completed(
	ctx: MatchContext, task: MatchTask, station: StationState, channel: Channel
) -> void:
	if task == null:
		return
	var task_state := task.state as State
	if station.id != task_state.car:
		return
	var part := Items.held_by(ctx.state, channel.actor)
	if part == null or part.kind == null or part.kind.id != task_state.next_part():
		ctx.error("CarRepair: peer %d completed a fit without the needed part" % channel.actor)
		return
	Items.lock_at(ctx, part, station.position)
	ctx.emit(PartFittedEvent.new(station.id, part.id))
	var index := task_state.fitted
	task_state.fitted += 1
	Tasks.subtask_done(ctx, task, {"subtask": index, "station": station.id})
	ctx.emit(PartNeededEvent.new(task_state.picture, task_state.next_part()))


## Whether `feet` lie inside the car's footprint box (RE7): the oriented box on the floor around
## the car's use spot `car_at` (its middle), its half-length the horizontal distance to `end_at`
## (the `car_end` marker, the middle of its front), its half-width `half_width_m`, from just below
## the floor (FLOOR_TOLERANCE_M) up to `clearance_m`. Pure geometry; edges count as inside.
func in_box(car_at: Vector3, end_at: Vector3, feet: Vector3) -> bool:
	var height := feet.y - car_at.y
	if height < -FLOOR_TOLERANCE_M or height > clearance_m:
		return false
	var axis := Vector2(end_at.x - car_at.x, end_at.z - car_at.z)
	var half_length := axis.length()
	var offset := Vector2(feet.x - car_at.x, feet.z - car_at.z)
	if is_zero_approx(half_length):
		return offset.length() <= half_width_m
	var along := axis / half_length
	var side := Vector2(-along.y, along.x)
	return absf(offset.dot(along)) <= half_length and absf(offset.dot(side)) <= half_width_m


## Exactly one marker of each station kind's tag (each a device, GE11) and one `car_end` marker,
## whatever the setting and the players (RE14). No colours.
func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	for kind: StationKind in station_kinds():
		into.add_markers(kind.spawn_tag, 1, true)
	if not car_end_tag.is_empty():
		into.add_markers(car_end_tag, 1, true)


## RE14: a `car_end` marker nearer the `car` marker than the car kind's radius (a short axis: the
## footprint box would be shorter than the car's cylinder, so a player could fit from beyond the
## box's end) is a problem, HostText.SHORT_AXIS. Only when the map holds one marker of each (the
## demands report any other count).
func layout_problems(layout: LevelLayout) -> Array[HostText]:
	var found: Array[HostText] = []
	if car == null or car_end_tag.is_empty():
		return found
	if layout.count(car.spawn_tag) != 1 or layout.count(car_end_tag) != 1:
		return found
	var car_at := layout.positions(car.spawn_tag)[0]
	var end_at := layout.positions(car_end_tag)[0]
	var length := Vector2(end_at.x - car_at.x, end_at.z - car_at.z).length()
	if length < car.radius_m:
		found.append(
			HostText.of(
				HostText.SHORT_AXIS,
				PackedStringArray([car_end_tag, car.spawn_tag]),
				{&"need": ceili(car.radius_m * CM), &"have": floori(length * CM)}
			)
		)
	return found


func most_layout_problems() -> int:
	return 1


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		PartNeededEvent,
		LiftChangedEvent,
		FitChangedEvent,
		PartFittedEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


func hold_emits() -> Array[Script]:
	return [
		LiftChangedEvent,
		FitChangedEvent,
		PartFittedEvent,
		TaskStateEvent,
		TaskProgressEvent,
		PartNeededEvent,
	]


## RE14: the car, panel, bin and picture kinds set, the picture a display kind and the others not;
## the `car_end` tag set and apart from the kinds' tags (ModeCheck keeps the kinds' tags apart
## across the mode, ZE3); `parts` non-empty and distinct, each given by exactly one bin (one bin per
## part) and listed in the mode's `item_kinds`, each capped at least at twice the mode's maximum
## of players plus the subtasks maximum plus 1 (CE3's bound: the hands and the car never hold every
## part of a kind); every bin's Interact rule holding a Cooldown and no HandNotTwoHanded (RD17's
## belt rule) and ending in GiveItem; the car's
## rule ending in a timed HoldStation and the panel's in an endless one; `rise_seconds`,
## `half_width_m` and `clearance_m` within bounds; the car kind's cylinder within the box (its
## `radius_m` at most `half_width_m`, its `height_m` at most `clearance_m`); a non-empty RNG
## purpose. The subtasks setting, from at least 0, is TaskType.check's (G0).
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	var named: Dictionary[String, StationKind] = {
		"car": car, "lift_panel": lift_panel, "picture": picture
	}
	for label: String in named:
		var kind := named[label]
		if kind == null:
			found.append("CarRepair %s has no %s station kind" % [id, label])
		elif kind.display != (label == "picture"):
			var text := "CarRepair %s: station kind %s (%s) %s a display kind"
			found.append(text % [id, kind.id, label, "is not" if label == "picture" else "is"])
	if car_end_tag.is_empty():
		found.append("CarRepair %s has no car_end_tag" % id)
	else:
		for kind: StationKind in station_kinds():
			if kind.spawn_tag == car_end_tag:
				found.append(
					(
						"CarRepair %s: station kind %s has the car_end tag %s"
						% [id, kind.id, car_end_tag]
					)
				)
	_check_parts(mode, found)
	_check_holds(found)
	append_found(
		found,
		[
			out_of_bounds("CarRepair %s rise_seconds" % id, rise_seconds, 0, MAX_RISE_SECONDS),
			out_of_bounds(
				"CarRepair %s half_width_m" % id, half_width_m, MIN_HALF_WIDTH_M, MAX_HALF_WIDTH_M
			),
			out_of_bounds(
				"CarRepair %s clearance_m" % id, clearance_m, MIN_CLEARANCE_M, MAX_CLEARANCE_M
			),
		]
	)
	if car != null and car.radius_m > half_width_m:
		var wide := "CarRepair %s: the car's radius_m %s is above half_width_m %s"
		found.append(wide % [id, number(car.radius_m), number(half_width_m)])
	if car != null and car.height_m > clearance_m:
		var tall := "CarRepair %s: the car's height_m %s is above clearance_m %s"
		found.append(tall % [id, number(car.height_m), number(clearance_m)])
	if parts_rng.is_empty():
		found.append("CarRepair %s has an empty RNG purpose" % id)
	return found


func _check_parts(mode: GameMode, found: PackedStringArray) -> void:
	if parts.is_empty():
		found.append("CarRepair %s has no parts" % id)
	var ids: Array[StringName] = []
	for part: ItemKind in parts:
		if part == null:
			found.append("CarRepair %s has an empty part" % id)
			continue
		if ids.has(part.id):
			found.append("CarRepair %s lists the part %s twice" % [id, part.id])
		ids.append(part.id)
		var givers := 0
		for bin: StationKind in bins:
			if bin != null and _given_by(bin) == part:
				givers += 1
		if givers != 1:
			found.append(
				"CarRepair %s: part %s is given by %d bins, not exactly 1" % [id, part.id, givers]
			)
		if mode != null and not mode.item_kinds.has(part):
			found.append(
				"CarRepair %s: part %s is not one of the mode's item_kinds" % [id, part.id]
			)
		var most := _most_parts(mode)
		if most >= 0 and part.max_items < most:
			found.append(
				(
					(
						"CarRepair %s: part %s has max_items %d, below %d (twice the players, the"
						+ " subtasks maximum and 1)"
					)
					% [id, part.id, part.max_items, most]
				)
			)
	for bin: StationKind in bins:
		if bin == null:
			found.append("CarRepair %s has an empty bin" % id)
			continue
		var part := _given_by(bin)
		if part == null or not parts.has(part):
			found.append("CarRepair %s: bin %s gives none of its parts" % [id, bin.id])
		if not _has_cooldown(bin):
			found.append("CarRepair %s: bin %s has no Interact rule with a Cooldown" % [id, bin.id])
		if _has_busy_hands(bin):
			var busy := "CarRepair %s: bin %s's take holds HandNotTwoHanded: a bin refuses no busy hands"
			found.append(busy % [id, bin.id])


## The fewest items a part kind must be capped at (RE14, CE3), or -1 when the mode does not say.
func _most_parts(mode: GameMode) -> int:
	if mode == null:
		return -1
	var subtasks := 0
	var spec := mode.find_setting(subtasks_setting) if not subtasks_setting.is_empty() else null
	if spec != null and spec.is_number():
		subtasks = spec.max_value
	return 2 * mode.max_players + subtasks + 1


func _check_holds(found: PackedStringArray) -> void:
	var holds: Dictionary[String, Array] = {"car": [car, false], "lift_panel": [lift_panel, true]}
	for label: String in holds:
		var kind := holds[label][0] as StationKind
		var endless := holds[label][1] as bool
		if kind == null:
			continue
		var rule := _hold_rule(kind)
		var hold: HoldStation = null
		if rule != null:
			hold = rule.effects[rule.effects.size() - 1] as HoldStation
		if hold == null or hold.endless != endless:
			found.append(
				(
					"CarRepair %s: the %s's Interact rule does not end in %s HoldStation"
					% [id, label, "an endless" if endless else "a timed"]
				)
			)
			continue
		# The ADR's §1.1 rows 5, 8 and 18 (RD10 (c)): a hit never drops the car and always stops
		# a fit; use_problem reads the task's state only through StationUsable.
		if hold.hit_stops == endless:
			found.append(
				(
					"CarRepair %s: the %s's HoldStation must %s when hit"
					% [id, label, "go on" if endless else "stop"]
				)
			)
		if not _has_station_usable(rule):
			found.append("CarRepair %s: the %s's Interact rule has no StationUsable" % [id, label])


## The Interact rule of `kind` that ends in a HoldStation, or null.
static func _hold_rule(kind: StationKind) -> Rule:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if rule.effects[rule.effects.size() - 1] is HoldStation:
			return rule
	return null


static func _has_station_usable(rule: Rule) -> bool:
	for condition: Condition in rule.conditions:
		if condition is StationUsable and not condition.negate:
			return true
	return false


## The part `bin`'s Interact rule gives (its last effect, a GiveItem), or null.
static func _given_by(bin: StationKind) -> ItemKind:
	for rule: Rule in bin.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		var last := rule.effects[rule.effects.size() - 1]
		if last is GiveItem:
			return (last as GiveItem).kind
	return null


## Whether the Interact rule of `bin` that ends in a GiveItem holds a Cooldown (cooking's CE17:
## a take's `too_soon`): the cooldown and the give are one rule.
static func _has_cooldown(bin: StationKind) -> bool:
	for rule: Rule in bin.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if not rule.effects[rule.effects.size() - 1] is GiveItem:
			continue
		for condition: Condition in rule.conditions:
			if condition is Cooldown and not condition.negate:
				return true
	return false


## Whether the Interact rule of `bin` that ends in a GiveItem holds HandNotTwoHanded, not negated:
## RD17's belt rule (cooking's CD3 (b), CE21) gives a package carrier its part onto the belt, so a
## take refuses no busy hands (the ADR's §2.5).
static func _has_busy_hands(bin: StationKind) -> bool:
	for rule: Rule in bin.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if not rule.effects[rule.effects.size() - 1] is GiveItem:
			continue
		for condition: Condition in rule.conditions:
			if condition is HandNotTwoHanded and not condition.negate:
				return true
	return false


func _place(ctx: MatchContext, kind: StationKind) -> StationState:
	return ctx.state.add_station(kind, ctx.layout.positions(kind.spawn_tag)[0], Color.WHITE)


## Whether the level being entered has one marker of each station kind's tag and a `car_end`
## marker, and every part a bin; the lobby's fit check (§9.4) keeps a match from getting here
## without them.
func _fits(ctx: MatchContext) -> bool:
	if not has_layout(ctx, "CarRepair"):
		return false
	var needs: Dictionary[StringName, int] = {}
	for kind: StationKind in station_kinds():
		needs[kind.spawn_tag] = 1
	needs[car_end_tag] = 1
	var missing := PackedStringArray()
	for tag: StringName in short_markers(ctx.layout, needs):
		missing.append(tag)
	for part: ItemKind in parts:
		if bin_of(part) == null:
			missing.append("a bin of %s" % part.id)
	if car == null or lift_panel == null or picture == null:
		missing.append("a station kind")
	if missing.is_empty():
		return true
	ctx.error("CarRepair: the map lacks %s" % ", ".join(missing))
	return false
