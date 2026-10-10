class_name LobbyText
extends RefCounted
## What the lobby's HUD shows (ARCHITECTURE §4.7.42, #495), pure: from the own ClientModel, the
## client's own copy of the mode and the estimated host tick. The Toy lobby HUD (prime-game-ui
## `ui-0.4.0` `docs/handoff/s04-lobby.md`, `LobbyHud`) draws it: the keys are the copy deck's
## (#208), names and numbers are data.
##
## Only what every peer of the lobby may see: the roster's names and ready flags (public: every
## Welcome and ReadyChanged reaches everyone), who the host is (peer 1), the lobby's name, the
## countdown's end, the mode's player limit and the host's shortfalls (SettingsChanged, the same to
## every peer, #548). Nothing of a role, a team or a match.

## The status plate's three states (the handoff's `wait`, `short` and `count`).
enum Status { WAITING, SHORT, COUNTDOWN }

## The copy deck's keys the HUD draws (`short`'s through HostTextView: `lobby.need_more`).
const WAITING_KEY := "lobby.waiting"
const COUNTDOWN_KEY := "lobby.countdown"
const PLAYER_COUNT_KEY := "lobby.player_count"
const HOST_MARK_KEY := "lobby.host_mark"
const YOU_KEY := "player.you"
const READY_NO_KEY := "lobby.ready_no"
const READY_YES_KEY := "lobby.ready_yes"


## One player's row.
class Row:
	extends RefCounted
	var peer := 0
	## The roster's name (data).
	var name := ""
	## The lobby's host (peer 1).
	var host := false
	## The own player: the row reads `player.you`.
	var own := false
	var ready := false

	## The row as a value: a change of any field rebuilds the rows.
	func key() -> String:
		return "%d|%s|%s|%s|%s" % [peer, name, host, own, ready]


## The HUD's state.
class Shown:
	extends RefCounted
	var status := Status.WAITING
	## WAITING and SHORT: the ready players; COUNTDOWN: the seconds left (5 to 1).
	var count := 0
	## SHORT: what holds the start back, the host's shortfalls in its order (core's HostTexts as
	## {id, ids, numbers}, as the model keeps them; HostTextView words them).
	var shortfalls: Array[Dictionary] = []
	## WAITING: the players in the lobby.
	var total := 0
	## The players in the lobby and the mode's limit (`lobby.player_count`).
	var players := 0
	var limit := 0
	## The lobby's name the host set; "" while it is the default (`lobby.default_name` with
	## `host_name`).
	var lobby_name := ""
	var host_name := ""
	## The host first, then the others in the order they joined.
	var rows: Array[Row] = []
	## Whether the own player is ready (the ready chip).
	var own_ready := false

	## The rows as a value (LobbyHud rebuilds its rows when it changes).
	func rows_key() -> String:
		var keys := PackedStringArray()
		for row in rows:
			keys.append(row.key())
		return "\n".join(keys)


## What the lobby HUD shows of `model` under `mode` (null: no limit known yet) at `host_tick`.
static func of(model: ClientModel, mode: GameMode, host_tick: int) -> Shown:
	var shown := Shown.new()
	shown.players = model.roster.size()
	shown.limit = mode.max_players if mode != null else 0
	shown.lobby_name = model.lobby_name
	shown.host_name = model.host_name()
	shown.rows = rows_of(model)
	for row in shown.rows:
		if row.ready:
			shown.count += 1
		if row.own:
			shown.own_ready = row.ready
	shown.total = shown.players
	var left := GameFlow.seconds_left(model.end_tick, host_tick)
	if left >= 0:
		shown.status = Status.COUNTDOWN
		# The phase ends at 0: the count reads 5 to 1, never 0.
		shown.count = maxi(1, left)
	elif not model.shortfalls.is_empty():
		# The host's word, never a count of this client's own: the host counts the players it has
		# against the mode it runs, and its other demands (markers, colours, the map's layout).
		shown.status = Status.SHORT
		shown.shortfalls.assign(model.shortfalls)
	return shown


## The roster's rows: the host first, then the others in the order the model got them (the
## Welcome's roster, then each PlayerJoined: the order they joined).
static func rows_of(model: ClientModel) -> Array[Row]:
	var rows: Array[Row] = []
	for peer: int in model.roster:
		var member: ClientModel.Member = model.roster[peer]
		var row := Row.new()
		row.peer = peer
		row.name = member.name
		row.host = peer == NetTransport.HOST_ID
		row.own = peer == model.own_peer
		row.ready = member.ready
		if row.host:
			rows.push_front(row)
		else:
			rows.append(row)
	return rows


## The status plate's text in the current language.
static func status_text(shown: Shown) -> String:
	match shown.status:
		Status.COUNTDOWN:
			return _tr(COUNTDOWN_KEY).format({"count": shown.count})
		Status.SHORT:
			# `players_few` reads `lobby.need_more` (tr_n); an id the deck has no key for, the
			# neutral line (HostTextView.plain); one line each.
			return HostTextView.shortfalls(shown.shortfalls)
	return _tr(WAITING_KEY).format({"count": shown.count, "total": shown.total})


## `lobby.player_count` in the current language.
static func head_text(shown: Shown) -> String:
	var line := _tr(PLAYER_COUNT_KEY)
	return line.format({"count": shown.players, "total": shown.limit})


## The lobby's name as shown: the host's, else `lobby.default_name` with the host's name ("" while
## the roster has no host).
static func title_text(shown: Shown) -> String:
	if not shown.lobby_name.is_empty():
		return shown.lobby_name
	if shown.host_name.is_empty():
		return ""
	return _tr(LobbyPanel.DEFAULT_NAME).format({"name": shown.host_name})


## A row's name as drawn in the current language: `player.you` for the own row, the host's
## `lobby.host_mark`, else the name alone.
static func row_text(row: Row) -> String:
	if row.own:
		return _tr(YOU_KEY)
	if row.host:
		return _tr(HOST_MARK_KEY).format({"name": row.name})
	return row.name


## `key` in the current language.
static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
