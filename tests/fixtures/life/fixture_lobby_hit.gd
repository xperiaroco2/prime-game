class_name FixtureLobbyHit
extends RefCounted
## FixtureLimp's hall with the knife's hit (#1439; a part's unit test never loads `content/`,
## ARCHITECTURE §9.6): the item kind `knife` (FixtureCombatModes.knife_rule(): 50 damage, a cooldown
## of 0.5 s, 25 stamina), and Lobby and Countdown with a PhaseSpec.hit_limp of LIMP_S, so a hit to
## 0 health there lays the victim limp instead of down. The `countdown_done` row's EndLimps restores
## health when mode() is asked to. armed() puts P1, a knife in its hand, before P2.

const P1 := FixtureLimp.P1
const P2 := FixtureLimp.P2
const P3 := FixtureLimp.P3
const LIMP_S := FixtureLimp.LIMP_S
## FixtureModes.player_rules()' 100 health, in thousandths.
const HEALTH := 100000
## One knife hit, in thousandths.
const HIT := 50000
## Where armed() stands P1 (the attacker), P2 (the victim, 1 m before it) and P3 (out of reach).
const AT_P1 := Vector3(0, 0, 0)
const AT_P2 := Vector3(0, 0, 1)
const AT_P3 := Vector3(4, 0, 4)
## P1's facing toward P2.
const FACING := Vector3(0, 0, 1)


## The mode, with EndLimps.restore_health set to `restore` on the `countdown_done` row.
static func mode(restore := true) -> GameMode:
	var made := FixtureLimp.mode()
	made.item_kinds.append(FixtureItemModes.item_kind(&"knife", [FixtureCombatModes.knife_rule()]))
	var go := GoLimp.new()
	go.limp_s = LIMP_S
	for phase_id: StringName in [&"lobby", &"countdown"]:
		made.find_phase(phase_id).hit_limp = go
	for row: Transition in made.transitions:
		for action: RuleEffect in row.actions:
			if action is EndLimps:
				(action as EndLimps).restore_health = restore
	return made


## A started lobby of `made` with `peers` at the bar, P1 holding a knife and facing P2 1 m away,
## P3 (if there) out of reach.
static func armed(made: GameMode, peers: Array[int]) -> Match:
	var game := FixtureBar.at_bar(made, peers)
	FixtureCombatModes.arm(game, P1, AT_P1)
	FixtureItemModes.stand(game, P2, AT_P2)
	if peers.has(P3):
		FixtureItemModes.stand(game, P3, AT_P3)
	return game


## P1 strikes toward P2 with `seq`, then waits out the knife's cooldown.
static func hit(game: Match, seq: int) -> void:
	FixtureCombatModes.use(game, P1, FACING, seq)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
