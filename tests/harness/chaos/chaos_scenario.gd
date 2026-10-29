class_name ChaosScenario
extends RefCounted
## The honest match the chaos peers play in (ARCHITECTURE §9.7's steps, built in code: it is the
## chaos run's fixture, not content). Four bots of the base mode on the greybox at its default
## draw, Delivery alone (the zone task plays on the House alone since #804, GD13 (b)): one package.
## - bot 1, the host's own client, waits until bot 4 has walked away from its freeze (a fixed
##   AWAY_WAIT_S from the round's start), takes a knife, knocks bot 4 down with two hits and waits
##   for the end;
## - bot 2 takes the package to its circle, waits there until bot 4 is downed (with `until_dead`,
##   until it has died) and puts it down: the crew wins (every task done);
## - bot 3 draws its second place into the hand and then its first (two accepted Draws over the
##   network, #1377: its empty places, an empty hand), waits for the end and stays two seconds into
##   End;
## - bot 4 is the "hostile but valid" chaos peer's own bot: it gets ready, walks to STAND_AT,
##   stands there a second, then **freezes** (the zone task ADR's freeze row, ZE10): for FREEZE_S
##   (190 ticks) its client sends no claim while it polls on, and then one claim spends the stored
##   credit to walk AWAY at once. ChaosRun holds its claims in both runs, and ChaosHonestClaims
##   fails a Correction of that claim. Then it is downed (and with `until_dead` dead, once the
##   knockdown time runs out), and the match ends before it gets up or respawns. Its chaos traffic
##   rides on its connection (ChaosHostile), with no hostile claim up to its walk away; in the
##   baseline run it sends only this script's traffic. Its joining Hello carries bot KEY_BOT's
##   return key (ChaosRun._key_of). What the zone gained from the freeze (at most
##   ZoneTask.STALE_TICKS) is checked over the real wire by
##   tests/integration/server/host_session_zone_test.gd since the greybox lost its zones (#804).
## `until_dead` adds the knockdown time (10 s) to the round: the long run of the night job has it,
## the short one of `verify` not.
## Every role is forced (debug builds): bot 1 dissident, the rest crew, or, with `swapped`, bot 3
## dissident and bot 1 crew: the knife needs no role, so the match plays the same, and only
## hidden state (who the dissident is) differs between the two (the chaos rule of §4.1, class 8).

## The hostile chaos peer's bot.
const HOSTILE := 4
## The honest bot whose return key the hostile's joining Hello carries, sent once the host holds
## that bot's PlayerJoined (#639): the hostile still joins as a new number.
const KEY_BOT := 2
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
## Where bot 4 stands before its freeze: where the greybox's zone that the scenario's seed dealt
## stood until #804, so the claim after the freeze spans the same 39.6 m to AWAY.
const STAND_AT := Vector3(-9, 0, 7)
## How long bot 4 stands at STAND_AT before it freezes.
const SETTLE_S := 1.0
## The freeze (the ADR's freeze row): 190 host ticks without a claim, MovementRule.PUSH_TICKS (the
## lost-claim tolerance of §7.1) under MovementRule.MAX_TICK_CREDIT. The claim after it covers the
## silence, a tick more as the freeze starts between two client ticks, and any claims the fault
## shim dropped just before it (10% of LATEST over WebRTC). With a 200-tick freeze it covered 201
## ticks over WebRTC (#674, seed 7): past the credit, so corrected, and bot 4 stood corrected in
## the zone for the rest of the round (its script adopts no Correction outside a placement: ChaosRun
## takes each for a chaos claim's), which held back every hostile claim. Since #693 such a
## Correction of an honest claim fails the run (ChaosHonestClaims).
const FREEZE_TICKS := MovementRule.MAX_TICK_CREDIT - MovementRule.PUSH_TICKS
const FREEZE_S := FREEZE_TICKS * 1.0 / Ticks.RATE
## Where bot 4's one claim after the freeze takes it: 39.6 m from STAND_AT, within the 42.75 m
## that the freeze's 190 ticks of walking cover, and clear of every marker.
const AWAY := Vector3(20, 0, -20)
## A bound on bot 4's walk from its round spawn (z = 0) to STAND_AT, sprinting (7 m/s): 19.3 m at
## the most, under 3 s.
const WALK_IN_S := 6.0
## How long bot 1 waits from the round's start before it goes for bot 4: bot 4's walk in, its
## stand, its freeze and a margin, so the knife finds it walked away.
const AWAY_WAIT_S := WALK_IN_S + SETTLE_S + FREEZE_S + 1.5
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
	var stand := _target(ScenarioTarget.Kind.POINT)
	stand.point = STAND_AT
	var to_stand := _walk(stand, true)
	to_stand.stop_m = 0.0
	# Bot 4 has walked away by then: its walk in, stand and freeze take at most AWAY_WAIT_S.
	var away_left := _wait(AWAY_WAIT_S)
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
				away_left,
				to_knife,
				pick_knife,
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
		_script([StepReady.new(), round_started, _draw(1), _draw(0), ended, stay]),
		_script(
			[StepReady.new(), round_started, to_stand, _wait(SETTLE_S), freeze, walk_away, knocked]
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


static func _draw(place: int) -> StepDraw:
	var step := StepDraw.new()
	step.place = place
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
