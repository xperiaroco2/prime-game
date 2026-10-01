class_name FixtureCombatModes
extends RefCounted
## Game modes and drivers for the unit tests of core/combat/ and core/life/, built in code on
## FixtureItemModes.basic() (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): FixtureItemModes.basic() (PickUp and PutDown from the living, item kinds `package` and
## `tool`, the eye at 1.6 m, capsules of 0.4 m by 1.8 m) plus the item kind `knife`, whose Use rule
## is the knife of §9.5 written out: Cooldown (`hit`, 0.5 s), StaminaCost (25), Strike (30°, 1.5 m,
## 50). Round accepts Use from the living (FixtureModes.basic()). The win conditions are
## FixtureModes.basic()'s counters, which these tests never bump.

const ANGLE_DEG := 30.0
const REACH_M := 1.5
const DAMAGE := 50
const COOLDOWN_S := 0.5
const STAMINA_COST := 25
## Host ticks of the knife's interval: 0.5 s at 20 Hz.
const COOLDOWN_TICKS := 10
## The raise of raising(): 3 s, the pick-up's 2 m, 50 health (the base mode's, §9.5).
const RAISE_S := 3.0
const RAISE_REACH_M := 2.0
const REVIVE_HEALTH := 50
## Host ticks of the raise: 3 s at 20 Hz.
const RAISE_TICKS := 60


static func basic() -> GameMode:
	var mode := FixtureItemModes.basic()
	mode.item_kinds.append(FixtureItemModes.item_kind(&"knife", [knife_rule()]))
	return mode


## The knife's Use rule with the given numbers.
static func knife_rule(
	angle_deg: float = ANGLE_DEG,
	reach_m: float = REACH_M,
	damage: int = DAMAGE,
	cooldown_s: float = COOLDOWN_S,
	stamina: int = STAMINA_COST
) -> Rule:
	return FixtureModes.rule(
		Intents.USE,
		[cooldown(&"hit", cooldown_s), stamina_cost(stamina)],
		[strike(angle_deg, reach_m, damage)]
	)


static func cooldown(key: StringName, seconds: float) -> Cooldown:
	var cost := Cooldown.new()
	cost.key = key
	cost.seconds = seconds
	return cost


static func stamina_cost(amount: int) -> StaminaCost:
	var cost := StaminaCost.new()
	cost.amount = amount
	return cost


static func strike(angle_deg: float, reach_m: float, damage: int) -> Strike:
	var effect := Strike.new()
	effect.angle_deg = angle_deg
	effect.reach_m = reach_m
	effect.damage = damage
	return effect


## basic() whose Round's LifeTicks respawns the dead: a Respawn on FixtureModes.RESPAWN_TAG
## markers with the RNG purpose `respawn` (the fixture's respawn time of 30 s, 3 s of
## invulnerability, a free radius of 1 m: FixtureModes.player_rules()).
static func respawning() -> GameMode:
	var mode := basic()
	life_ticks(mode).respawn = respawn()
	return mode


static func respawn() -> Respawn:
	var effect := Respawn.new()
	effect.tag = FixtureModes.RESPAWN_TAG
	effect.rng_purpose = &"respawn"
	return effect


## The Round's LifeTicks of a mode built on FixtureModes.basic().
static func life_ticks(mode: GameMode) -> LifeTicks:
	return mode.find_phase(&"round").tick_systems[0] as LifeTicks


## A round of `mode` in `world` whose `peers` joined, readied and were placed.
static func in_round(
	mode: GameMode, peers: Array[int], world: WorldQuery = null, seed_value: int = 7
) -> Match:
	return FixtureItemModes.in_round(mode, peers, world, seed_value)


## Puts `peer` at `at` and a knife into its hand (laid at its feet and picked up). Returns it.
static func arm(game: Match, peer: int, at: Vector3) -> ItemState:
	FixtureItemModes.stand(game, peer, at)
	var knife := FixtureItemModes.lay(game, &"knife", at)
	FixtureItemModes.pick_up(game, peer, knife)
	return knife


## `peer` sends Use with `facing`, applied on the next host tick.
static func use(game: Match, peer: int, facing: Vector3, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.USE, peer, {"facing": facing}, seq)


## The health of `peer`, in whole points.
static func health(game: Match, peer: int) -> float:
	return game.state.player(peer).health / float(Ticks.THOUSANDTHS)


## The events of `name` that `peer` received, in order.
static func received(game: Match, peer: int, name: StringName) -> Array[MatchEvent]:
	return game.view_of(peer).events_named(name)


## respawning() with the raise and the give-up of the base mode (§9.5) written out: the mode's
## actions Raise (TargetDowned, ChannelFree, TargetInReach 2 m, TargetInSight; RaiseDowned 3 s,
## revive health 50), StopRaise (Channeling) and GiveUp (Die); Round accepts Raise and StopRaise
## from the living, GiveUp from the downed, and lists ChannelTicks after LifeTicks.
static func raising() -> GameMode:
	var mode := respawning()
	mode.actions.append_array([raise_rule(), stop_raise_rule(), give_up_rule()])
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts.append(AcceptSpec.of(Intents.RAISE, AcceptSpec.From.LIVING))
	round_spec.accepts.append(AcceptSpec.of(Intents.STOP_RAISE, AcceptSpec.From.LIVING))
	round_spec.accepts.append(AcceptSpec.of(Intents.GIVE_UP, AcceptSpec.From.DOWNED))
	round_spec.tick_systems.append(ChannelTicks.new())
	return mode


static func raise_rule(
	seconds: float = RAISE_S, reach_m: float = RAISE_REACH_M, revive_health: int = REVIVE_HEALTH
) -> Rule:
	var reach := TargetInReach.new()
	reach.reach_m = reach_m
	var raise := RaiseDowned.new()
	raise.seconds = seconds
	raise.revive_health = revive_health
	return FixtureModes.rule(
		Intents.RAISE, [TargetDowned.new(), ChannelFree.new(), reach, TargetInSight.new()], [raise]
	)


static func stop_raise_rule() -> Rule:
	return FixtureModes.rule(Intents.STOP_RAISE, [Channeling.new()], [])


static func give_up_rule() -> Rule:
	return FixtureModes.rule(Intents.GIVE_UP, [], [Die.new()])


## `raiser` sends Raise of `target`, applied on the next host tick.
static func raise(game: Match, raiser: int, target: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.RAISE, raiser, {"target": target}, seq)


static func stop_raise(game: Match, raiser: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.STOP_RAISE, raiser, {}, seq)


static func give_up(game: Match, peer: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.GIVE_UP, peer, {}, seq)
