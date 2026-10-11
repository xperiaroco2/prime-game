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
## The placed station it runs on (a HoldStation's: the car repair ADR's RE2, #805), or -1 when it
## runs on none. A station channel targets no player (target 0), so a knockdown of the peer whose
## number is the station's never stops it (Channels.interrupt_involving compares players only).
var station := -1
## Set by Channels.stop_all before the effect's stopped() runs: the channel stops because its phase
## ends, not because its actor let go or was stopped (RE4: the car comes down without a kill).
var phase_ended := false
## The host tick it started on.
var started_tick := 0
## The ticks it has run: ChannelTicks adds one per tick, from the tick it started on.
var done_ticks := 0
## The ticks it needs: it completes in the tick that reaches them.
var total_ticks := 0
