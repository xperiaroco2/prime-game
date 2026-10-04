class_name Cost
extends Condition
## A condition that is also paid (stamina, a cooldown, later a use; ARCHITECTURE §9.2). Every
## condition and cost of a rule is checked first, then every cost is paid in order, then the
## effects run: a refused intent pays nothing. A cost cannot be negated (ModeCheck).


## Pays the cost. Called only after every condition and cost of the rule passed.
func pay(_ctx: MatchContext) -> void:
	pass
