class_name Cost
extends Condition
## A condition that is also paid (stamina, a cooldown, later a use; ARCHITECTURE §9.2). Every
## condition and cost of a rule is checked first, then every cost is paid in order, then the
## effects run: a refused intent pays nothing. A cost cannot be negated (ModeCheck).


## Pays the cost. Called only after every condition and cost of the rule passed.
func pay(_ctx: MatchContext) -> void:
	pass


## True when the cost reads the actor's PlayerState (`MatchContext.actor_state()`), as
## `Cooldown` and `StaminaCost` do: a mode reaction runs for no player (actor 0, which has no
## PlayerState), so such a cost always refuses there and ModeCheck refuses it in a reaction
## (§9.2). True unless a subclass says otherwise, so a new cost that forgets is refused at load
## rather than silently never firing; one that reads only match-wide state returns false.
func reads_actor_state() -> bool:
	return true
