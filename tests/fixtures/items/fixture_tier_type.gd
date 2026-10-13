class_name FixtureTierType
extends TaskType
## A task type for GiveItem's tiered cap (the photo ADR's PE10, #782): cap_tier answers `tiers`
## by item id (0 for any other item). It deals nothing; a test adds it with MatchState.add_task.

## Item id -> its tier.
var tiers: Dictionary[int, int] = {}


func cap_tier(_state: MatchState, item: ItemState) -> int:
	return tiers.get(item.id, 0)
