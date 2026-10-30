class_name OfferTicks
extends TickSystem
## Ends the hand-over offers that no longer hold (#1434; ARCHITECTURE §7.1, §9.4; GDD §6 "Handing
## over"), each tick in giver order (Offers.all): one OfferEnded for each offer whose item is no
## longer the giver's hand item (a Put down, Swap, Draw or Throw of it), whose giver or target is
## no longer present, alive and standing (limp, downed, dead, gone), whose players stand farther
## apart than `reach_m` (their last accepted positions, as TargetInReach measures), or that has
## been open `timeout_s` seconds. A phase whose rules offer, take or cancel lists it
## (problems()).
##
## Emits: OfferEnded (everyone). No demands.

## How long an offer stays open, in seconds (provisional, not a decision: #1434's 5 s).
@export var timeout_s := 0.0
## How far apart the giver and the target may stand while the offer is open, in metres: at least
## the reach of the mode's HandOver rule, else an offer would end as it opens.
@export var reach_m := 0.0


func run(ctx: MatchContext) -> void:
	for offer: Offers.Offer in Offers.all(ctx.state):
		if not holds(ctx, offer):
			Offers.close(ctx, offer)


## Whether `offer` still holds at `ctx.tick`.
func holds(ctx: MatchContext, offer: Offers.Offer) -> bool:
	if ctx.tick >= offer.opened_tick + maxi(1, Ticks.from_seconds(timeout_s)):
		return false
	if Offers.live(ctx.state, offer.giver) != offer:
		return false
	var giver := ctx.state.player(offer.giver)
	var target := ctx.state.player(offer.target)
	if not _standing(giver) or not _standing(target):
		return false
	return giver.position.distance_to(target.position) <= reach_m


func emits() -> Array[Script]:
	return [OfferEndedEvent]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("timeout_s", timeout_s, 0.5, 60),
			out_of_bounds("reach_m", reach_m, 0.5, 10),
		]
	)
	return found


## The problems of `mode`'s offers (HandOver.check): a phase that accepts an intent whose rule
## offers, takes or cancels (HandOver, TakeOffer, CancelOffer) lists an OfferTicks whose reach is
## at least the reach of the HandOver rules' TargetInReach; every row from a phase that lists one
## into a phase that does not runs an EndOffers, so no offer outlasts the phase that ends offers.
## Empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var reach := _hand_over_reach(mode)
	for phase: PhaseSpec in mode.phases:
		if phase == null:
			continue
		var ticks := _of(phase)
		var offering := _offering(mode, phase)
		if not offering.is_empty() and ticks == null:
			(
				found
				. append(
					(
						"phase %s accepts %s, which offers, takes or cancels an offer, but lists no OfferTicks"
						% [phase.id, offering]
					)
				)
			)
		if ticks != null and ticks.reach_m < reach:
			found.append(
				(
					"phase %s: OfferTicks reach_m %s is less than the HandOver reach %s"
					% [phase.id, ticks.reach_m, reach]
				)
			)
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var from := mode.find_phase(row.from)
		var to := mode.find_phase(row.to)
		if from == null or to == null or _of(from) == null or _of(to) != null:
			continue
		var ends := false
		for action: RuleEffect in row.actions:
			ends = ends or action is EndOffers
		if not ends:
			found.append(
				"row %s -> %s runs no EndOffers: an offer would outlast it" % [row.from, row.to]
			)
	return found


static func _standing(player: PlayerState) -> bool:
	return player != null and player.life == PlayerState.Life.ALIVE and not player.is_limp()


static func _of(phase: PhaseSpec) -> OfferTicks:
	for system: TickSystem in phase.tick_systems:
		if system is OfferTicks:
			return system as OfferTicks
	return null


## The intents `phase` accepts whose mode actions offer, take or cancel.
static func _offering(mode: GameMode, phase: PhaseSpec) -> Array[StringName]:
	var found: Array[StringName] = []
	for entry: AcceptSpec in phase.accepts:
		if entry == null or found.has(entry.intent):
			continue
		for rule: Rule in mode.actions:
			if rule == null or rule.trigger != entry.intent:
				continue
			for effect: RuleEffect in rule.effects:
				if effect is HandOver or effect is TakeOffer or effect is CancelOffer:
					found.append(entry.intent)
					break
	return found


## The largest reach of a TargetInReach in a mode action that holds a HandOver, or 0.
static func _hand_over_reach(mode: GameMode) -> float:
	var reach := 0.0
	for rule: Rule in mode.actions:
		if rule == null:
			continue
		var offers := false
		for effect: RuleEffect in rule.effects:
			offers = offers or effect is HandOver
		if not offers:
			continue
		for condition: Condition in rule.conditions:
			if condition is TargetInReach and not condition.negate:
				reach = maxf(reach, (condition as TargetInReach).reach_m)
	return reach
