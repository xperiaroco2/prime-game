class_name GameFlow
extends RefCounted
## The game's flow as data (ARCHITECTURE §4.7, "The flow"): which screen shows and which level
## plays under World for the state of the session and of the client's ClientModel. Pure, so the
## game and its unit test read the same table. The phase is read from the client's own copy of the
## mode (PhaseSpec), never from the host.

## Where the session is.
enum Session {
	NONE,  ## no session: the main menu
	CONNECTING,  ## joined or hosting, no Welcome yet
	WELCOMED,  ## a player of the session
}

enum Screen {
	MENU,  ## address, port, Host, Join, Quit, and why the last session ended
	CONNECTING,  ## "Connecting to <address>", Cancel
	LOBBY,  ## the roster with ready flags, Ready, the countdown; the host's settings
	LOADING,  ## who has loaded
	ROUND,  ## the round (M4-8's HUD)
	END,  ## "The <side> won"; the host's Back to lobby
}


## The screen for `session` and `model` (the model is read only once welcomed).
static func screen(session: Session, model: ClientModel) -> Screen:
	match session:
		Session.NONE:
			return Screen.MENU
		Session.CONNECTING:
			return Screen.CONNECTING
	var spec := model.phase_spec()
	if spec == null:
		return Screen.CONNECTING
	if spec.level == PhaseSpec.Level.LOBBY:
		return Screen.LOBBY
	if spec.senders_of(Intents.LOAD_ACK) != 0:
		return Screen.LOADING
	if not model.winner.is_empty() or spec.senders_of(Intents.RETURN_TO_LOBBY) != 0:
		return Screen.END
	return Screen.ROUND


## The level that plays under World: the mode's lobby, the match's map, or none.
static func level(session: Session, model: ClientModel) -> PhaseSpec.Level:
	if session != Session.WELCOMED:
		return PhaseSpec.Level.NONE
	var spec := model.phase_spec()
	return spec.level if spec != null else PhaseSpec.Level.NONE


## Whether the local player stands still: Loading and End accept no MoveClaim (the map is not
## there yet, or the match is over), and nothing moves it before Welcome.
static func frozen(screen_now: Screen) -> bool:
	return screen_now != Screen.LOBBY and screen_now != Screen.ROUND


## Whether showing `screen_now` frees a captured mouse: every screen but the round has buttons
## (the lobby's Ready, the end screen's Back to lobby). In the lobby a click outside the panel
## captures it again for looking around.
static func frees_pointer(screen_now: Screen) -> bool:
	return screen_now != Screen.ROUND


## Seconds left until `end_tick` (a countdown's or the match clock's end), from the newest host
## tick this client knows; -1 when none runs. M4-7's SnapshotBuffer gives a better estimate.
static func seconds_left(end_tick: int, host_tick: int) -> int:
	if end_tick < 0 or host_tick < 0:
		return -1
	return maxi(0, ceili(float(end_tick - host_tick) / Ticks.RATE))
