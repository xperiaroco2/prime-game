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
	FAILED,  ## no session: the last one failed, and its failure shows until Back (#494)
}

enum Screen {
	MENU,  ## the main menu (#493): the name, Host, Join, Join by address, Settings, Quit
	CONNECTING,  ## the spinner, the step, the code and the time since Join, Cancel (#494)
	LOBBY,  ## walking in the lobby: the keys' hint, the roster, the countdown (Esc: Ready, settings)
	LOADING,  ## who has loaded
	PREGAME,  ## dark, the own role (#213): silent, frozen, before the round's clock runs
	ROUND,  ## the round (M4-8's HUD)
	END,  ## "The <side> won"; "Back to the lobby in 3" (#212)
	FAILURE,  ## what failed in plain words, then Try again or Join directly, and Back (#494)
}

## What showing a screen asks of the mouse (#169, #517).
enum Pointer {
	CAPTURE,  ## the lobby and the round: the player looks around
	KEEP,  ## Loading and Pregame: nothing to click; a mouse captured in the lobby reaches the round
	FREE,  ## the menu, Connecting, a failure and the end screen: their buttons
}


## The screen for `session` and `model` (the model is read only once welcomed).
static func screen(session: Session, model: ClientModel) -> Screen:
	match session:
		Session.NONE:
			return Screen.MENU
		Session.CONNECTING:
			return Screen.CONNECTING
		Session.FAILED:
			return Screen.FAILURE
	var spec := model.phase_spec()
	if spec == null:
		return Screen.CONNECTING
	if spec.level == PhaseSpec.Level.LOBBY:
		return Screen.LOBBY
	if spec.senders_of(Intents.LOAD_ACK) != 0:
		return Screen.LOADING
	if spec.phase_class == PregamePhase:
		return Screen.PREGAME
	if not model.winner.is_empty() or spec.senders_of(Intents.RETURN_TO_LOBBY) != 0:
		return Screen.END
	return Screen.ROUND


## The level that plays under World: the mode's lobby, the match's map, or none.
static func level(session: Session, model: ClientModel) -> PhaseSpec.Level:
	if session != Session.WELCOMED:
		return PhaseSpec.Level.NONE
	var spec := model.phase_spec()
	return spec.level if spec != null else PhaseSpec.Level.NONE


## Whether the local player stands still: Loading, Pregame and End accept no MoveClaim (the map is
## not there yet, the round has not begun, or the match is over), and nothing moves it before
## Welcome.
static func frozen(screen_now: Screen) -> bool:
	return screen_now != Screen.LOBBY and screen_now != Screen.ROUND


## What showing `screen_now` does to the mouse. In the lobby and the round the player looks around:
## the screen captures the mouse, Esc's menu frees it and closing the menu captures it again (#169).
## Loading and Pregame, between the countdown and the round, keep it as it was: freeing it there
## left the round with the cursor showing until a click (#517). Every other screen frees it: the
## menu and Connecting's Cancel are buttons, and the end screen (no button since #212) only counts
## down.
static func pointer_on(screen_now: Screen) -> Pointer:
	match screen_now:
		Screen.LOBBY, Screen.ROUND:
			return Pointer.CAPTURE
		Screen.LOADING, Screen.PREGAME:
			return Pointer.KEEP
	return Pointer.FREE


## Seconds left until `end_tick` (a countdown's or the match clock's end), from the newest host
## tick this client knows; -1 when none runs. M4-7's SnapshotBuffer gives a better estimate.
static func seconds_left(end_tick: int, host_tick: int) -> int:
	if end_tick < 0 or host_tick < 0:
		return -1
	return maxi(0, ceili(float(end_tick - host_tick) / Ticks.RATE))
