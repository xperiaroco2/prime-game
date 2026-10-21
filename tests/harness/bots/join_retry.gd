class_name JoinRetry
extends RefCounted
## The bounded retry of a join made at the start of a networked run (ARCHITECTURE §4.6.2; #284,
## #483, #509): one per joiner, over all its joins. NetPlay keeps one per bot and BotWatcher one per
## watcher (the lurker, the refused bot), so both join again by this one rule.
##
## A join that went unanswered (UNANSWERED: it failed UNANSWERED_USEC or more after it started, as
## EnetTransport ends a join the host never admitted after JOIN_TIMEOUT_MS) joins again at once:
## under load a process can start seconds before the host's listens (#284). A join that found no
## room (ROOM_NOT_UP, WebRTC: the host's process or room is not up yet, or the signalling socket
## did not open within Signaller.CONNECT_TIMEOUT_MS, the 5 s cap) joins again ROOM_RETRY_USEC after
## it ended. A host that refuses a join answers at once: before the admission a client ends
## `joins_closed` (refusing new connections, #1233) or `connect_failed` (an id in use, but
## within a poll or two), and after it (a Rejected Hello) `host_lost`; all stay failures, as do
## WebRTC's `joins_closed`, `full` and `host_unreachable`. Judged when the failure is first seen,
## on the caller's join clock. With max_joins above 0 it makes that many joins at most.

## A join that failed this long or more after it started went unanswered: half of
## EnetTransport.JOIN_TIMEOUT_MS, in microseconds (a frame's clock is read before its poll). A
## sooner `connect_failed` is a refusal.
const UNANSWERED_USEC := EnetTransport.JOIN_TIMEOUT_MS * 500
## Over WebRTC a join can also end at once because the host's room is not up yet (its process
## starts later, or its signalling has not opened the room): it joins again this long after.
const ROOM_RETRY_USEC := 500000
## The joins that end for no answer (ENet's connect_failed), and the ones that end because the
## room is not up yet (WebRTC). WebRTC's host_unreachable is no such case: the service answered and
## the connection never opened, a transport fault the run must not ride out.
const UNANSWERED: Array[StringName] = [ClientSession.CONNECT_FAILED]
const ROOM_NOT_UP: Array[StringName] = [
	NetTransport.JOIN_NO_ROOM, NetTransport.JOIN_SERVICE_UNREACHABLE
]

## The joins it makes at most; once the last ended, the join is lost for good. 0 is no bound.
var max_joins := 0
## When its current join started (start), on the caller's join clock.
var started_usec := 0
## The reasons its earlier joins ended, in order (join_again, before each new join).
var ends := PackedStringArray()

## When join_again first saw the current join fail; -1 while it did not.
var _failed_usec := -1


func _init(bound := 0) -> void:
	max_joins = bound


## A join started at `now_usec`.
func start(now_usec: int) -> void:
	started_usec = now_usec
	_failed_usec = -1


## Whether to join again now: the current join ended for `reason` (empty while it runs) on
## `transport`, judged at `now_usec`. Records the failure when it first sees it, and on true the
## reason in `ends`; the caller then starts the new join and calls start.
func join_again(reason: StringName, transport: NetTransport, now_usec: int) -> bool:
	if not _unanswered(reason, transport) and not reason in ROOM_NOT_UP:
		return false
	if _failed_usec < 0:
		_failed_usec = now_usec
	if not joins_again(reason, transport):
		return false
	if reason in ROOM_NOT_UP and now_usec - _failed_usec < ROOM_RETRY_USEC:
		return false
	ends.append(String(reason))
	return true


## Whether join_again joins again, now or after ROOM_RETRY_USEC: it saw the current join fail
## (only join_again records the failure, so a caller that never calls it joins nobody again) for a
## reason it retries, within max_joins. Writes nothing.
func joins_again(reason: StringName, transport: NetTransport) -> bool:
	if _failed_usec < 0:
		return false
	if max_joins > 0 and ends.size() + 1 >= max_joins:
		return false
	if reason in ROOM_NOT_UP:
		return true
	if not _unanswered(reason, transport):
		return false
	return _failed_usec - started_usec >= UNANSWERED_USEC


## "; earlier joins ended <reason>, ..." for the line of a join lost for good, or "" when there
## was none.
func earlier() -> String:
	if ends.is_empty():
		return ""
	return "; earlier joins ended %s" % ", ".join(ends)


## What a join that ended for `reason` and is joined again met, for the log line of the new join.
static func why(reason: StringName) -> String:
	if reason == NetTransport.JOIN_NO_ROOM:
		return "the host's room is not up yet"
	if reason == NetTransport.JOIN_SERVICE_UNREACHABLE:
		return "the signalling service did not answer in time"
	return "the host did not answer"


## Whether a join on `transport` ended for no answer (UNANSWERED). Over WebRTC connect_failed is a
## connection that closed or a bad ADMIT, never a missing answer.
static func _unanswered(reason: StringName, transport: NetTransport) -> bool:
	return reason in UNANSWERED and not transport is WebRtcTransport
