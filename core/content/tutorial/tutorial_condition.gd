class_name TutorialCondition
extends TutorialPart
## A tutorial step's condition: what must hold before it shows (`starts_when`), what completes it
## at once as it starts (`done_when`), or what must hold when a trigger fires (`conditions`)
## (docs/design/tutorial.md §3).


## Whether the condition reads the event that fired (ItemKindIs), so it fits only a step's
## `conditions`.
func reads_event() -> bool:
	return false
