class_name ChaosScenario
extends RefCounted
## The honest match the chaos peers play in (ARCHITECTURE §9.7's steps, built in code: it is the
## chaos run's fixture, not content). Four bots of the base mode, one package:
## - bot 1, the host's own client, takes a knife, knocks bot 4 down with two hits and waits for the
##   end;
## - bot 2 takes the package to its circle, waits there until bot 4 is downed (with `until_dead`,
##   until it has died) and puts it down: the crew wins at once (every task done);
## - bot 3 waits for the end, then stays two seconds into End;
## - bot 4 is the "hostile but valid" chaos peer's own bot: it gets ready and only waits, so it is
##   living in the lobby, the countdown, loading and the round, then downed (and with `until_dead`
##   dead, once the knockdown time runs out), and the match ends before it gets up or respawns.
##   Its chaos traffic rides on its connection (ChaosHostile); in the baseline run it sends only
##   this script's traffic.
## `until_dead` adds the knockdown time (10 s) to the round: the long run of the night job has it,
## the short one of `verify` not.
## Every role is forced (debug builds): bot 1 dissident, the rest crew, or, with `swapped`, bot 3
## dissident and bot 1 crew: the knife needs no role, so the match plays the same, and only hidden
## state (who the dissident is) differs between the two (the chaos rule of §4.1, class 8).

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
const WAIT_AT_CIRCLE_S := 30.0


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
	scenario.scripts = [
		_script(
			[
				StepReady.new(),
				round_started,
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
		_script([StepReady.new(), ended, stay]),
		_script([StepReady.new(), knocked]),
	]
	if until_dead:
		scenario.scripts[1].steps.append(_expect(&"Died", {"peer": HOSTILE}, WAIT_AT_CIRCLE_S))
		scenario.scripts[3].steps.append(died)
	scenario.scripts[1].steps.append_array([put_down, _expect(&"PackageDelivered", {})])
	scenario.scripts[3].steps.append(ended)
	return scenario


static func _script(steps: Array[ScenarioStep]) -> BotScript:
	var script := BotScript.new()
	script.steps = steps
	return script


static func _wait_for(event: StringName, fields: Dictionary) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = event
	step.fields = fields
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
