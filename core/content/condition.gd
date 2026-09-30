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


## The test itself, without `negate`.
func _test(_ctx: MatchContext) -> bool:
	return true


func _reason() -> StringName:
	return RejectReasons.NOT_ALLOWED
