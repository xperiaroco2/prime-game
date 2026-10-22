class_name StepMeter
extends RefCounted
## The host step's time by stage, for the perf run (#1255; ARCHITECTURE §9.7): HostSession times
## its stages only while its step_meter is set, which PerfRun alone does. In play it stays null and
## step() reads no clock for it, so a match does the same work as before.
##
## Each stage is Time.get_ticks_usec() around HostSession's own calls in one step: every Match.tick
## (the catch-up ticks and the due one, each with its delivery and route refresh), every queue
## apply (each Match.apply with its delivery), the voice relay after the poll, and the snapshot
## sends. What the step spends elsewhere (the refill, the poll, the bodies' reports, the deadlines)
## is the step's whole time minus these. The owner reads the stages after a step and clears them
## before the next.

## Microseconds of the current step in its Match.tick calls.
var match_tick_usec := 0
## Microseconds of the current step in applying its queued commands.
var apply_usec := 0
## Microseconds of the current step in relaying voice (HostSession._send_voice).
var voice_usec := 0
## Microseconds of the current step in sending snapshots (HostSession._send_snapshots).
var snapshots_usec := 0


## Zeroes every stage, before the next step.
func clear() -> void:
	match_tick_usec = 0
	apply_usec = 0
	voice_usec = 0
	snapshots_usec = 0
