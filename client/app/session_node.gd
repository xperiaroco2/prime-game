class_name SessionNode
extends Node
## Steps the game's ClientSession from the physics step (ARCHITECTURE §4.7, one physics frame):
## at priority -90, after the host's HostNode (-100), whose messages to the own client it reads in
## the same frame, and before the avatars (-80) and the local player (0), so a Correction
## teleports the player before it moves. It runs while the tree is paused, like HostNode.
##
## The session's clock is the count of physics steps, not the real clock, on purpose: the client
## tick is then the physics step divided by 3 at 60 Hz (§7.1 "The client tick's rate"), so a
## claim's travel always matches the client ticks it covers. On the real clock, Godot's
## back-to-back catch-up steps after a hitch (or steps running late on a fast display) put 4 or
## more steps of travel in a claim of one client tick, which the host's crawl check, with no fixed
## slack, corrects.
##
## After a hitch longer than Godot's catch-up (8 physics steps a frame), the steps would trail the
## real clock for good, and with them the host's stamina ledger, so the next sprint-jump would
## settle phantom sprint ticks and be refused. So right after a claim went out, a step count
## trailing the real clock by CATCH_UP_STEPS or more jumps forward by whole client ticks: the next
## claim covers those ticks with only one tick's travel, which every check accepts (the netcode
## review of PR #154).

const PHYSICS_PRIORITY := -90
## Steps behind the real clock that make the count jump forward (one client tick at 60 Hz).
const CATCH_UP_STEPS := 3

var session: ClientSession
## The real clock in microseconds: Time.get_ticks_usec() unless set (a test's simulated clock).
var real_clock := Callable()

## The physics steps run so far.
var _steps := 0
## The real clock at the first step less that step's time (the real clock's step 0); -1 before.
var _real_start := -1


func _init(client: ClientSession = null) -> void:
	session = client
	process_physics_priority = PHYSICS_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(
		Engine.physics_ticks_per_second % Ticks.RATE == 0,
		"the physics rate must be a multiple of the client tick rate (Ticks.RATE)"
	)


## Physics steps per client tick: 3 at 60 Hz.
static func steps_per_tick() -> int:
	@warning_ignore("integer_division")
	return Engine.physics_ticks_per_second / Ticks.RATE


## The session's clock in microseconds: the physics steps run so far, each 1 / the physics rate.
func now_usec() -> int:
	@warning_ignore("integer_division")
	return _steps * 1000000 / Engine.physics_ticks_per_second


## The physics steps counted so far (with the forward jumps).
func steps() -> int:
	return _steps


func _physics_process(_delta: float) -> void:
	var real := _real_now()
	_steps += 1
	if _real_start < 0:
		_real_start = real - _usec_of(_steps)
	if session == null or session.is_ended():
		return
	var claimed := session.last_claim_tick()
	session.step(now_usec())
	if session.last_claim_tick() != claimed:
		_catch_up(real)


## Jumps the step count forward by whole client ticks when it trails the real clock by
## CATCH_UP_STEPS steps or more.
func _catch_up(real: int) -> void:
	var real_steps := roundi((real - _real_start) * Engine.physics_ticks_per_second / 1000000.0)
	var behind := real_steps - _steps
	if behind < CATCH_UP_STEPS:
		return
	var per_tick := steps_per_tick()
	@warning_ignore("integer_division")
	_steps += behind / per_tick * per_tick


func _real_now() -> int:
	return real_clock.call() as int if real_clock.is_valid() else Time.get_ticks_usec()


static func _usec_of(steps_run: int) -> int:
	@warning_ignore("integer_division")
	return steps_run * 1000000 / Engine.physics_ticks_per_second
