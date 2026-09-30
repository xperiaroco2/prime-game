class_name Rule
extends ContentPart
## The unit of behaviour (ARCHITECTURE §9.2): a trigger, then conditions, then effects. An
## **action** is a rule on an intent (`PickUp`, `Use`), held by an item kind, a role or the mode;
## a **reaction** is a rule on a fact (`item_rested`), held by the mode. The owner decides whom
## the rule applies to, so the rule needs no condition for that.

## The intent (Intents) or fact (Facts) the rule runs on.
@export var trigger: StringName
## Checked in order; costs (Cost) are paid only after all of them passed.
@export var conditions: Array[Condition] = []
## Run in order.
@export var effects: Array[RuleEffect] = []


func costs() -> Array[Cost]:
	var found: Array[Cost] = []
	for condition: Condition in conditions:
		if condition is Cost and not condition.negate:
			found.append(condition as Cost)
	return found
