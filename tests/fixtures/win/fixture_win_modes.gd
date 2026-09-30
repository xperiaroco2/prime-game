class_name FixtureWinModes
extends RefCounted
## Game modes and drivers for the unit tests of core/win/, built in code (a part's unit tests
## never load `content/`, ARCHITECTURE §9.6).
##
## basic(): FixtureDeliveryModes.basic() (PickUp 2 m, PutDown 1 m, Delivery's one shared task of
## `packages` packages, a note on subtask_done to the server) plus the knife of FixtureCombatModes
## and the settings `match_duration` (1 min, 1 to 60) and `dissidents` (1, 0 to 9), with the base
## mode's win conditions and rows (§3.2, §9.5): `lobby, all_ready -> round` runs DealRoles
## (Dissident by `dissidents`, leaving at least 1; default Crew), DealTasks, PlacePlayers, then
## StartClock; `round, won -> end` runs EndMatch; `end, back -> lobby` runs ResetMatch, then
## PlacePlayers. The win conditions, in the base mode's order: every task done (crew:
## AllSubtasksDone), no crew alive (dissidents: NoneAlive of crew), time up (dissidents:
## ClockEnded, AllSubtasksDone negated).

## The fixture's round length, in minutes, and in host ticks at 20 Hz.
const MINUTES := 1
const CLOCK_TICKS := 1200
const NORTH := Vector3(0, 0, 1)


static func basic(packages: int = 2) -> GameMode:
	var mode := FixtureDeliveryModes.basic(packages)
	mode.item_kinds.append(FixtureItemModes.item_kind(&"knife", [FixtureCombatModes.knife_rule()]))
	mode.settings.append(FixtureModes.setting(&"match_duration", MINUTES, 1, 60))
	mode.settings.append(FixtureModes.setting(&"dissidents", 1, 0, 9))
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(
		0, FixtureDealModes.deal_roles(mode.find_role(&"dissident"), mode.find_role(&"crew"))
	)
	deal.actions.append(start_clock())
	mode.find_transition(&"round", Match.WON).actions = [EndMatch.new()]
	var back := mode.find_transition(&"end", &"back")
	back.actions.insert(0, ResetMatch.new())
	mode.win_conditions = [every_task_done(), no_crew_alive(), time_up()]
	return mode


static func start_clock(setting_id: StringName = &"match_duration") -> StartClock:
	var effect := StartClock.new()
	effect.minutes_setting = setting_id
	return effect


## The crew's win condition of §9.5: AllSubtasksDone.
static func every_task_done() -> WinCondition:
	return _win(&"every_task_done", &"crew", [AllSubtasksDone.new()])


## "No crew alive" of §9.5: NoneAlive of the side crew.
static func no_crew_alive() -> WinCondition:
	return _win(&"no_crew_alive", &"dissidents", [NoneAlive.of(&"crew")])


## "Time up" of §9.5: ClockEnded, then AllSubtasksDone negated.
static func time_up() -> WinCondition:
	var not_done := AllSubtasksDone.new()
	not_done.negate = true
	return _win(&"time_up", &"dissidents", [ClockEnded.new(), not_done])


## A match of `mode` on Delivery's fixture layouts that keeps its history, with `peers` joined,
## `settings` over the defaults, and all ready: the deal has run and the match is in the round.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7
) -> Match:
	var game := Match.new(mode, seed_value, FlatWorldQuery.new(), FixtureDeliveryModes.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for id: StringName in settings:
		game.state.settings[id] = settings[id]
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The tick on which the round's clock ends, as the round's PhaseChanged announced it to `peer`.
static func announced_end(game: Match, peer: int) -> int:
	for event: MatchEvent in game.view_of(peer).events_named(&"PhaseChanged"):
		var changed := event as PhaseChangedEvent
		if changed.phase == &"round":
			return changed.end_tick
	return -1


## Runs ticks until `last` has run.
static func run_through(game: Match, last: int) -> void:
	while game.ticked_through() < last:
		game.tick(game.ticked_through() + 1)


## `peer` picks up the package of subtask `index` (standing beside it) and stands at its circle,
## holding it: the package is over its circle but not delivered, since a held package never
## counts. Returns the package.
static func hold_over_circle(game: Match, peer: int, index: int) -> ItemState:
	var task := FixtureDeliveryModes.task_of(game)
	var package := FixtureDeliveryModes.package_of(game, task, index)
	FixtureItemModes.stand(game, peer, package.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, peer, package)
	FixtureItemModes.stand(game, peer, FixtureDeliveryModes.circle_of(game, task, index).position)
	return package


## Delivers the package of subtask `index`: `peer` carries it into its circle and puts it down.
static func deliver(game: Match, peer: int, index: int) -> void:
	var task := FixtureDeliveryModes.task_of(game)
	var package := FixtureDeliveryModes.package_of(game, task, index)
	var circle := FixtureDeliveryModes.circle_of(game, task, index)
	FixtureDeliveryModes.carry_to(game, peer, package, circle.position)


## `attacker` takes a knife 1 m south of `victim` and hits it twice, the cooldown apart: at 50
## damage a hit, the second kills.
static func kill(game: Match, attacker: int, victim: int) -> void:
	var at := game.state.player(victim).position
	FixtureCombatModes.arm(game, attacker, at - NORTH)
	FixtureCombatModes.use(game, attacker, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureItemModes.stand(game, attacker, at - NORTH)
	FixtureCombatModes.use(game, attacker, NORTH)


## The sides of every MatchEnded that `peer` received, in order.
static func ended(game: Match, peer: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"MatchEnded"):
		found.append((event as MatchEndedEvent).side)
	return found


static func _win(id: StringName, side_id: StringName, conditions: Array[Condition]) -> WinCondition:
	var made := WinCondition.new()
	made.id = id
	made.side = side_id
	made.conditions = conditions
	return made
