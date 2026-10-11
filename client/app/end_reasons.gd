class_name EndReasons
extends RefCounted
## Why a session ended, in words (ARCHITECTURE §4.7): the one table the game's main menu and
## tools/run/headless_session.gd both read. The reasons are ClientSession's (a refusal's, a
## Disconnecting's, its own constants) and the host session's own ends; client/ never names the
## host session (E18), so its reasons are written here as ids and a test pins them to server/'s.

## The host's own ends (HostSession's constants).
const CLOSED := &"closed"
const ROW_ERROR := &"row_error"
const OWN_CLIENT_MALFORMED := &"own_client_malformed"
const OWN_CLIENT_DISCONNECTED := &"own_client_disconnected"
## A host that could not start (the game's own reason; its errors follow it in the log).
const CANNOT_HOST := &"cannot_host"

const WORDS: Dictionary[StringName, String] = {
	&"wrong_version":
	"the host runs another protocol version: put both machines on the same commit",
	&"wrong_content":
	(
		"the host runs another build: its game content (content/ or levels/) differs from this"
		+ " machine's: put both machines on the same build"
	),
	&"joins_closed": "the host's match is under way: join again when it is back in the lobby",
	&"full": "the host's lobby is full",
	&"connect_failed":
	(
		"no answer from the host: check that it runs, the address and the port, and that its"
		+ " firewall lets UDP in"
	),
	&"no_room": "no game has that code: check the code with the host",
	&"service_unreachable":
	(
		"the code service could not be reached (or this build has none): join with the host's"
		+ " address under Direct (LAN or VPN) instead"
	),
	&"service_refused": "the code service refused the join: put both machines on the same build",
	&"host_unreachable":
	(
		"the host's lobby is full, or this machine could not reach the host directly: if the"
		+ " lobby has room, the host can share a playit.gg address to join under Direct (LAN or"
		+ " VPN)"
	),
	&"host_lost": "the host closed, or the connection was lost",
	&"unknown_map": "the host asked for a map this game does not have: put both on the same commit",
	&"load_failed": "the map did not load on this machine",
	&"load_deadline": "the map took too long to load here, and the host went on without you",
	&"left": "you left the session",
	CLOSED: "you closed the session you hosted",
	ROW_ERROR: "the host's match ran into an error it cannot go on from (see the log)",
	OWN_CLIENT_MALFORMED: "the host's own client sent messages it could not read (see the log)",
	OWN_CLIENT_DISCONNECTED: "the host's rules disconnected the host's own player (see the log)",
	CANNOT_HOST: "the session could not start (see the log)",
}

## The failure state of the connecting screen (prime-game-ui's s3 handoff at ui-0.4.0, its state
## table; #494) each end shows before the main menu. Leaving (`left`, `closed`) shows none: straight
## to the menu. A new reason in WORDS needs its row here or in NO_FAILURE (a test holds it).
const FAILURE_STATES: Dictionary[StringName, StringName] = {
	&"no_room": &"fail-no-room",
	&"joins_closed": &"fail-started",
	&"wrong_version": &"fail-version",
	&"wrong_content": &"fail-version",
	&"service_refused": &"fail-version",
	&"unknown_map": &"fail-version",
	&"full": &"fail-full",
	&"service_unreachable": &"fail-service",
	&"host_unreachable": &"fail-unreachable",
	&"connect_failed": &"fail-no-answer",
	&"host_lost": &"lost",
	&"load_failed": &"map-failed",
	&"load_deadline": &"map-failed",
	ROW_ERROR: &"error",
	OWN_CLIENT_MALFORMED: &"error",
	OWN_CLIENT_DISCONNECTED: &"error",
	CANNOT_HOST: &"host-failed",
}
## The ends the player chose: no failure screen.
const NO_FAILURE: Array[StringName] = [&"left", CLOSED]


## The reason in words; the id itself when the table has none.
static func words(reason: StringName) -> String:
	return WORDS.get(reason, String(reason))


## The connecting screen's failure state for `reason`, or &"" when it shows none (the player left,
## or an id outside the table).
static func failure_state(reason: StringName) -> StringName:
	return FAILURE_STATES.get(reason, &"")


## The id followed by its words: "full (the host's lobby is full)"; the id alone when unknown.
static func text(reason: StringName) -> String:
	if not WORDS.has(reason):
		return String(reason)
	return "%s (%s)" % [reason, WORDS[reason]]
