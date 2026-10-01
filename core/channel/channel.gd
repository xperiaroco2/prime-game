class_name Channel
extends RefCounted
## One running channel (ARCHITECTURE §9.1, §9.4; M4-4): an action that takes time, such as the
## raise of a downed player. Match state, not a part: Channels keeps every running one in
## MatchState's per-part state, at most one per actor. The ChannelEffect that started it decides
## what its start, its stop and its completion do; ChannelTicks advances it one tick at a time.

## The definition that started it, which ends it (ChannelEffect.stopped and completed).
var effect: ChannelEffect
## The action whose conditions are checked again every tick (its costs are not paid again), or
## null: then only the stops end it early.
var rule: Rule
## The player who runs it.
var actor := 0
## The player it targets (the downed player of a raise), or 0 when it targets none.
var target := 0
## The host tick it started on.
var started_tick := 0
## The ticks it has run: ChannelTicks adds one per tick, from the tick it started on.
var done_ticks := 0
## The ticks it needs: it completes in the tick that reaches them.
var total_ticks := 0
