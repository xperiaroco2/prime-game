class_name ScenarioPeers
extends RefCounted
## A runner's map from bot number to peer id (ARCHITECTURE §4.6, §9.7). A scenario names players by
## bot number, and nothing on the wire tells a bot which peer is bot i, so each runner owns its map
## and passes it to the steps (ScenarioPlay, ScenarioBot) and to ScenarioInvariants: the core runner
## keeps 1 and PEER_BASE + i, the one-process bots runner fills it as LoopbackHub hands out ids,
## and over ENet each instance learns it from the files the bots write (`refresh`). A bot that left
## and joined again (a Join after its Leave, P12 (a) of the returning-players ADR) is on a new peer:
## the map keeps its current one (peer_of) and maps each earlier one back to it (bot_of, peers_of).

## The core runner's bot i > 1 is peer PEER_BASE + i, so a scenario that confuses bot numbers with
## peer ids fails.
const PEER_BASE := 1000

## Called with this map when a lookup misses, so a map that grows out of band (the ENet runner's
## `peers` file) can be read again; it may add entries with set_peer().
var refresh := Callable()

var _peer_of: Dictionary[int, int] = {}
## Earlier peer -> its bot: the connections of bots that joined again.
var _earlier: Dictionary[int, int] = {}


## The core runner's map for `bots` bots: bot 1 is peer 1, bot i is PEER_BASE + i.
static func core(bots: int) -> ScenarioPeers:
	var made := ScenarioPeers.new()
	for bot in range(1, bots + 1):
		made.set_peer(bot, 1 if bot == 1 else PEER_BASE + bot)
	return made


## Bot `bot` is on `peer` now; its peer before, if another, becomes an earlier one. A peer the bot
## had before changes nothing, so a file read again in any order keeps the map.
func set_peer(bot: int, peer: int) -> void:
	var now: int = _peer_of.get(bot, 0)
	if now == peer or _earlier.get(peer, 0) == bot:
		return
	if now != 0:
		_earlier[now] = bot
	_peer_of[bot] = peer


## The peer id of bot `bot`, or 0 when it is not known (yet).
func peer_of(bot: int) -> int:
	if not _peer_of.has(bot) and refresh.is_valid():
		refresh.call(self)
	return _peer_of.get(bot, 0)


## Every peer id bot `bot` had, the earlier ones first and its current one last; empty when it is
## not known (yet).
func peers_of(bot: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for earlier: int in _earlier:
		if _earlier[earlier] == bot:
			found.append(earlier)
	var now := peer_of(bot)
	if now != 0:
		found.append(now)
	return found


## The bot number of peer `peer`, its current one or an earlier one, or 0 when no bot had it.
func bot_of(peer: int) -> int:
	for bot: int in _peer_of:
		if _peer_of[bot] == peer:
			return bot
	return _earlier.get(peer, 0)


func has_bot(bot: int) -> bool:
	return _peer_of.has(bot)


## A peer id no bot had in this session: one above every one mapped (the core runner's returning
## bot, which picks its own).
func fresh_peer() -> int:
	var top := PEER_BASE
	for bot: int in _peer_of:
		top = maxi(top, _peer_of[bot])
	for earlier: int in _earlier:
		top = maxi(top, earlier)
	return top + 1


## Bot number -> current peer id, a copy.
func to_dict() -> Dictionary[int, int]:
	return _peer_of.duplicate()
