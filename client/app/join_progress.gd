class_name JoinProgress
extends RefCounted
## How a join is going, in words for the connecting screen and the lobby (the M6 ADR §2.3, §2.5
## and §3; pure, so it is tested headless). The step: finding the game (a code, before the service
## answered `found`), connecting (WebRTC or ENet under way), joined (connected, waiting for the
## host's Welcome). The version check: the service's advisory `found` against this game's own
## protocol and content hash, before any ICE. It only ends a join early with both versions named;
## the host still decides with Hello (JoinRules), so a service that lies changes nothing.

enum Step { FINDING, CONNECTING, JOINED }

## Greybox wording (#150).
const STEP_WORDS: Dictionary[Step, String] = {
	Step.FINDING: "Finding the game",
	Step.CONNECTING: "Connecting",
	Step.JOINED: "Joined: waiting for the host",
}
## The lobby's line for a host whose code service went away (its room is gone, no reclaim).
const CODE_GONE := "Code: none (the code service closed or is unreachable): use Host Direct"
## The lobby's line for a host whose code service has not made the room yet.
const CODE_WAITING := "Code: waiting for the code service"


## The step of a join to a code (`by_code`) whose service answered `found_protocol` (-1: not yet),
## and whose transport is `connected`.
static func step(by_code: bool, found_protocol: int, connected: bool) -> Step:
	if connected:
		return Step.JOINED
	if by_code and found_protocol < 0:
		return Step.FINDING
	return Step.CONNECTING


static func step_text(by_code: bool, found_protocol: int, connected: bool) -> String:
	return STEP_WORDS[step(by_code, found_protocol, connected)]


## What the connecting screen names: "Joining the game with code ABCDEF" or "Joining 1.2.3.4:5".
static func target_text(target: JoinTarget) -> String:
	if target.is_code():
		return "Joining the game with code %s" % target.label()
	return "Joining %s" % target.label()


## The reason to end a join on the service's `found` (wrong_version or wrong_content), or &"" when
## it matches or has not come (`found_protocol` -1).
static func found_mismatch(
	found_protocol: int, found_content: int, own_protocol: int, own_content: int
) -> StringName:
	if found_protocol < 0:
		return &""
	if found_protocol != own_protocol:
		return &"wrong_version"
	if found_content != own_content:
		return &"wrong_content"
	return &""


## Both versions in words, after the reason's own: the host's first, then this game's.
static func found_detail(
	reason: StringName, found_protocol: int, found_content: int, own_protocol: int, own_content: int
) -> String:
	if reason == &"wrong_version":
		return "the host runs protocol %d, this game %d" % [found_protocol, own_protocol]
	if reason == &"wrong_content":
		return (
			"another build: the host's content is %s, this game's %s"
			% [SignalCodec.content_text(found_content), SignalCodec.content_text(own_content)]
		)
	return ""


## The lobby's code line: "Code: ABCDEF" to whoever knows the code; for a code host, CODE_WAITING
## before the service made the room and CODE_GONE once its service closed or could not be reached;
## "" (hidden) for a Direct game.
static func code_text(code: String, gone: bool, waiting := false) -> String:
	if gone:
		return CODE_GONE
	if code.is_empty():
		return CODE_WAITING if waiting else ""
	return "Code: %s" % code
