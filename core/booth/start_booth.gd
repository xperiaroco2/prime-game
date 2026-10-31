class_name StartBooth
extends RuleEffect
## The photo booth's button (#1396; GDD §3 "The photo booth"; ARCHITECTURE §9.4.2, §9.5.29): an
## accepted Interact at the booth's station starts a booth session (BoothSessions.start): a
## countdown of `countdown_s`, then `frames` flashes `gap_s` apart, on the host's clock
## (BoothTicks), each recording every living present player inside the station's own cylinder
## (the booth's volume: StationKind.radius_m and height_m); after the last one, a strip of `strip`
## for each of them. Its numbers are the data's (provisional in the base mode, #1396). Not a
## Channel: every applied action of a channel's actor stops it (Channels.interrupt), and the
## presser picks up, swaps or poses inside the booth like everyone else.
##
## Refused `unavailable` (refusal(), before anything is paid) while a session runs (one booth
## session at a time) and in a phase that lists no BoothTicks, where it would never tick (the base
## mode's Countdown still holds the booth's station and accepts Interact).
##
## Emits: BoothStep (STARTED; everyone). No demands: the station's own StationTicks demands its
## marker.

## The most flashes a strip holds.
const MAX_FRAMES := 8
## The bounds of countdown_s and gap_s.
const COUNTDOWN_LOW_S := 0.5
const COUNTDOWN_HIGH_S := 30.0

## The strip's item kind: one-handed and capped (`max_items` set), an item kind of the mode.
@export var strip: ItemKind
## How many flashes a strip holds: 1..MAX_FRAMES.
@export var frames := 0
## The seconds from the press to the first flash: COUNTDOWN_LOW_S..COUNTDOWN_HIGH_S.
@export var countdown_s := 0.0
## The seconds between two flashes: COUNTDOWN_LOW_S..COUNTDOWN_HIGH_S.
@export var gap_s := 0.0


func run(ctx: MatchContext) -> void:
	BoothSessions.start(ctx, self)


func refusal(ctx: MatchContext) -> StringName:
	if BoothSessions.running(ctx.state) != null or not BoothTicks.listed_in(ctx.phase_spec()):
		return ItemOnGround.UNAVAILABLE
	return &""


func emits() -> Array[Script]:
	return [BoothStepEvent]


## The ticks from the press to the first flash.
func countdown_ticks() -> int:
	return Ticks.from_seconds(countdown_s)


## The ticks between two flashes.
func gap_ticks() -> int:
	return Ticks.from_seconds(gap_s)


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if strip == null:
		found.append("StartBooth has no strip")
	else:
		if mode.find_item_kind(strip.id) == null:
			found.append("StartBooth: item kind %s is not an item kind of the mode" % strip.id)
		if strip.is_two_handed() or not strip.is_capped():
			found.append(
				"StartBooth: strip %s must be one-handed and set max_items (its cap)" % strip.id
			)
	append_found(
		found,
		[
			out_of_bounds("frames", frames, 1, MAX_FRAMES),
			out_of_bounds("countdown_s", countdown_s, COUNTDOWN_LOW_S, COUNTDOWN_HIGH_S),
			out_of_bounds("gap_s", gap_s, COUNTDOWN_LOW_S, COUNTDOWN_HIGH_S),
		]
	)
	return found
