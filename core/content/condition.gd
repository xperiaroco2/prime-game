class_name Condition
extends ContentPart
## "Only if" (ARCHITECTURE §9.2): checked in order, changing nothing. The first that fails stops
## its rule: for an intent the sender gets Rejected with rejection_reason(); for a fact nothing
## happens. A subclass overrides _test() and _reason(), and says in its §9.4 entry what its
## refusal reveals: a reason may depend only on facts the sender is entitled to (§4.1).

## A negated condition passes when its test fails, and rejects with `not_allowed`.
@export var negate := false


## Whether the condition lets its rule go on, `negate` applied.
func passes(ctx: MatchContext) -> bool:
	return _test(ctx) != negate


## The reason the sender is told when this condition stops an intent.
func rejection_reason() -> StringName:
	if negate:
		return RejectReasons.NOT_ALLOWED
	return _reason()


## True when this condition reads the actor's role (ActorRole, #34): ModeCheck then warns about
## the rule's public events, which would reveal that role (§9.2).
func gates_on_role() -> bool:
	return false


## True when the condition reads the actor: its PlayerState (`MatchContext.actor_state()`) or
## anything kept per actor (its hand, its channel). A mode reaction runs, and a win condition is
## checked, for no player (actor 0), so there such a condition tests no player and its answer
## never changes; ModeCheck refuses it in both (§9.2, #299). True unless a subclass says
## otherwise, so a new condition that forgets is refused at load rather than silently never (or
## always) passing; one that reads only the match, the fact or the rule's target returns false.
func reads_actor_state() -> bool:
	return true


## The test itself, without `negate`.
func _test(_ctx: MatchContext) -> bool:
	return true


func _reason() -> StringName:
	return RejectReasons.NOT_ALLOWED
