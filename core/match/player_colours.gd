class_name PlayerColours
extends RefCounted
## A player's body colour (ARCHITECTURE §3.5, #551, the engineer's answers on #73): one of COUNT
## preset colours, held as its index 0..COUNT-1. core/ only counts colours and never holds a Color:
## the client maps an index to what it draws (BodyColours). A joiner takes the first colour no
## present player has; SetProfile asks for one, and a colour another player has gives the first
## free one instead. The colour is public.

## The preset colours (MVP rules: 10, no colour picker). GameMode.check refuses a mode with more
## players than this, so a free colour always exists for every player.
const COUNT := 10


## Whether `value` names a colour: an int in 0..COUNT-1 (a float, a String or null never does).
static func is_valid(value: Variant) -> bool:
	return value is int and (value as int) >= 0 and (value as int) < COUNT


## The lowest colour not in `taken`. When every colour is taken, which GameMode.check makes
## unreachable (at most COUNT players), colour 0: a duplicate colour, never a refused join.
static func first_free(taken: Array[int]) -> int:
	for colour: int in COUNT:
		if not taken.has(colour):
			return colour
	return 0


## `wanted` when it is a valid colour not in `taken`, else first_free(taken) (the engineer's answer
## on #73: a taken colour makes the host give the first free one).
static func resolve(wanted: int, taken: Array[int]) -> int:
	if is_valid(wanted) and not taken.has(wanted):
		return wanted
	return first_free(taken)
