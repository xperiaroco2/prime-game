class_name FixtureError
extends RuleEffect
## Logs a match error with `text` (MatchContext.error), as a deal that cannot place its tasks does
## (ARCHITECTURE §4.5 "A failed deal is fatal").

@export var text := "fixture error"


func run(ctx: MatchContext) -> void:
	ctx.error(text)
