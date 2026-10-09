class_name ChaosScenario
extends RefCounted
## The honest match the chaos peers play in (ARCHITECTURE §9.7's steps, built in code: it is the
## chaos run's fixture, not content). Four bots of the base mode at its default draw, both task
## types (#649): one package and one zone.
## - bot 1, the host's own client, takes a knife, waits until bot 4 has left the zone (the zone's
##   stop, then the freeze's time), knocks bot 4 down with two hits and waits for the end;
## - bot 2 takes the package to its circle, waits there until bot 4 is downed (with `until_dead`,
##   until it has died) and puts it down;
## - bot 3 waits until bot 4 has left the zone, then stands in the zone until the end; the crew wins
##   on the later of the delivery and the zone (every task done); it stays two seconds into End;
## - bot 4 is the "hostile but valid" chaos peer's own bot: it gets ready, walks into the zone,
##   stands there a second, then **freezes** (the zone task ADR's freeze row, ZE10): for FREEZE_S
##   (200 ticks) its client sends no claim while it polls on, and then one claim spends the stored
##   credit to walk AWAY at once. ChaosRun holds its claims in both runs and checks that the zone
##   gained at most ZoneTask.STALE_TICKS (10) from the silence. Then it is downed (and with
##   `until_dead` dead, once the knockdown time runs out), and the match ends before it gets up or
##   respawns. Its chaos traffic rides on its connection (ChaosHostile), with no hostile claim
##   while it is frozen or near a zone (a Correction there would change the zone's count, which
##   the honest bots see, from the baseline's); in the baseline run it sends only this script's
##   traffic.
## `until_dead` adds the knockdown time (10 s) to the round: the long run of the night job has it,
## the short one of `verify` not.
## Every role is forced (debug builds): bot 1 dissident, the rest crew, or, with `swapped`, bot 3
## dissident and bot 1 crew: the knife needs no role and counting in a zone reads none, so the
## match plays the same, and only hidden state (who the dissident is) differs between the two (the
## chaos rule of §4.1, class 8).

## The hostile chaos peer's bot.
const HOSTILE := 4
const BOTS := 4
const SEED := 488_000_000_001
const MODE := "res://content/modes/base_mode.tres"
const TIME_LIMIT_S := 90.0
## How long bot 3 stays into End after the match ended, so the chaos peers send there too.
const END_WAIT_S := 2.0
## How long an Expect waits for its event after the step that causes it.
const EXPECT_WITHIN_S := 1.0
## How long bot 2 waits at the circle for bot 4's knockdown, and then its death.
const WAIT_AT_CIRCLE_S := 45.0
## The zone's station kind, and the one zone the base mode deals.
const ZONE := &"zone"
## How long bot 4 stands counted in the zone before it freezes.
const SETTLE_S := 1.0
## The freeze: 200 host ticks without a claim (the ADR's freeze row).
const FREEZE_S := 10.0
## Where bot 4's one claim after the freeze takes it: about 30 m from the greybox's zones, within
## the 45 m that 200 ticks of walking cover, and clear of every marker.
const AWAY := Vector3(20, 0, -20)
## The name of bot 4's freeze step (ChaosRun holds its claims while it is the current step).
const FREEZE := &"freeze"
## The name of bot 4's walk away after it (ChaosHostile sends no claim in the round up to its end).
const WALK_AWAY := &"walk_away"


static func build(swapped := false, until_dead := false) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(MODE) as GameMode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.settings = {&"packages": 1}
	var dissident := 3 if swapped else 1
	var crew := 1 if swapped else 3
	scenario.forced_roles = {dissident: &"dissident", crew: &"crew", 2: &"crew", HOSTILE: &"crew"}
	scenario.expected_ends = [&"crew"]
	scenario.time_limit_s = TIME_LIMIT_S
	var ended := _wait_for(&"MatchEnded", {"side": "crew"})
	var hostile := _bot(HOSTILE)
	var knife := _target(ScenarioTarget.Kind.NEAREST)
	knife.item_kind = &"knife"
	var hit := StepUse.new()
	hit.towards = hostile
	var cooldown := StepWait.new()
	cooldown.seconds = 0.6
	var to_knife := _walk(knife, false)
	var pick_knife := StepPickUp.new()
	pick_knife.target = knife
	var to_hostile := _walk(hostile, false)
	var round_started := _wait_for(&"PhaseChanged", {"phase": "round"})
	var knocked := _wait_for(&"KnockedDown", {"peer": HOSTILE})
	# The hit's KnockedDown comes with its Swung, before a WaitFor after the hit would start.
	var hit_knocked := _expect(&"KnockedDown", {"peer": HOSTILE})
	var died := _wait_for(&"Died", {"peer": HOSTILE})
	var package := _target(ScenarioTarget.Kind.PACKAGE)
	var circle := _target(ScenarioTarget.Kind.CIRCLE_OF_HELD)
	var pick_package := StepPickUp.new()
	pick_package.target = package
	var put_down := StepPutDown.new()
	put_down.towards = circle
	var stay := StepWait.new()
	stay.seconds = END_WAIT_S
	var zone := _target(ScenarioTarget.Kind.STATION)
	zone.station_kind = ZONE
	var into_zone := _walk(zone, true)
	into_zone.stop_m = 0.0
	# The zone stops counting STALE_TICKS after bot 4's last claim; the freeze ends FREEZE_S after
	# that claim, so a wait of FREEZE_S from the stop ends after it.
	var stopped := _wait_for(&"ZoneProgress", {"counting": false})
	var freeze_left := _wait(FREEZE_S)
	var freeze := _wait(FREEZE_S)
	freeze.resource_name = FREEZE
	var away := _target(ScenarioTarget.Kind.POINT)
	away.point = AWAY
	var walk_away := _walk(away, false)
	walk_away.resource_name = WALK_AWAY
	scenario.scripts = [
		_script(
			[
				StepReady.new(),
				round_started,
				to_knife,
				pick_knife,
				stopped,
				freeze_left,
				to_hostile,
				hit,
				cooldown,
				hit,
				hit_knocked,
				ended
			]
		),
		_script(
			[
				StepReady.new(),
				round_started,
				_walk(package, true),
				pick_package,
				_walk(circle, true),
				_expect(&"KnockedDown", {"peer": HOSTILE}, WAIT_AT_CIRCLE_S),
			]
		),
		_script([StepReady.new(), round_started, stopped, freeze_left, into_zone, ended, stay]),
		_script(
			[StepReady.new(), round_started, into_zone, _wait(SETTLE_S), freeze, walk_away, knocked]
		),
	]
	if until_dead:
		scenario.scripts[1].steps.append(_expect(&"Died", {"peer": HOSTILE}, WAIT_AT_CIRCLE_S))
		scenario.scripts[3].steps.append(died)
	scenario.scripts[1].steps.append_array([put_down, _expect(&"PackageDelivered", {})])
	scenario.scripts[3].steps.append(ended)
	return scenario


## The index of bot 4's walk away in `steps` (-1 when there is none).
static func away_index(steps: Array[ScenarioStep]) -> int:
	for i in steps.size():
		if steps[i] != null and steps[i].resource_name == WALK_AWAY:
			return i
	return -1


## Whether `step` is bot 4's freeze.
static func is_freeze(step: ScenarioStep) -> bool:
	return step != null and step.resource_name == FREEZE


static func _script(steps: Array[ScenarioStep]) -> BotScript:
	var script := BotScript.new()
	script.steps = steps
	return script


static func _wait_for(event: StringName, fields: Dictionary) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = event
	step.fields = fields
	return step


static func _wait(seconds: float) -> StepWait:
	var step := StepWait.new()
	step.seconds = seconds
	return step


## An Expect: it looks back to the start of the step before it, so an event that came with that
## step's answer counts.
static func _expect(
	event: StringName, fields: Dictionary, within_s := EXPECT_WITHIN_S
) -> StepExpect:
	var step := StepExpect.new()
	step.event = event
	step.fields = fields
	step.within_s = within_s
	return step


static func _target(kind: ScenarioTarget.Kind) -> ScenarioTarget:
	var target := ScenarioTarget.new()
	target.kind = kind
	return target


static func _bot(number: int) -> ScenarioTarget:
	var target := _target(ScenarioTarget.Kind.BOT)
	target.bot = number
	return target


static func _walk(target: ScenarioTarget, sprint: bool) -> StepWalkTo:
	var step := StepWalkTo.new()
	step.target = target
	step.sprint = sprint
	step.stop_m = 1.0
	return step
