extends NetPlay
## The bots of a `tools\run.cmd playcheck` run (#186; docs/AGENT_WORKFLOW.md §11): the players
## after the game windows, all in one headless process, each a BotClient joined over ENet to the
## game that window 1 hosts on 127.0.0.1, playing its script of a BotScenario (ARCHITECTURE §9.7).
##
## Player numbers are the scenario's: 1 is the host's window, 2 up to `first - 1` the other
## windows, `first` up to BotScenario.bots the bots. Peer ids travel out of band, as over ENet in
## `bots --instances` (harmless: they are public in the roster): every window and bot writes
## peer-<number> into the run's peers folder, and a bot plays only once it knows every player's.
## The setup (forced roles, clock, settings) is the scenario file's and window 1 sends it as the
## host's own client: a BotScenario here keeps its own empty. The bots stay silent (no synthetic
## voice reaches a window) and stand still once their scripts are done; the runner stops them.

const ADDRESS := "127.0.0.1"
const USEC_PER_SECOND := 1000000

var port := 0
## The run's peers folder.
var dir := ""
## The first bot's player number: the windows come before it.
var first := 2

var _start_usec := 0
var _reported: Dictionary[int, int] = {}


func _init(bot_scenario: BotScenario, first_bot: int, on_port: int, peers_dir: String) -> void:
	super(bot_scenario, ScenarioPeers.new())
	first = first_bot
	port = on_port
	dir = peers_dir
	peers.refresh = _read_peers


## Joins every bot; false with `failures` when the scenario does not fit a playcheck run.
func start(now: int) -> bool:
	for problem: String in scenario.problems():
		failures.append("scenario: %s" % problem)
	if first < 2 or first > scenario.bots:
		failures.append(
			"the bots are players %d to %d: none after the windows" % [first, scenario.bots]
		)
	if not scenario.forced_roles.is_empty() or not scenario.settings.is_empty():
		failures.append("its roles and settings go in the playcheck file (window 1 sends them)")
	if scenario.clock_s != 0 or not scenario.map.is_empty():
		failures.append("its clock and map go in the playcheck file, or stay the mode's")
	for number in range(1, first):
		if not scenario.steps_of(number).is_empty():
			failures.append("player %d is a window: its script stays empty" % number)
	if not OS.is_debug_build():
		failures.append("the bots run in debug builds only (ForceRole's kind)")
	if not failures.is_empty():
		return false
	now_usec = now
	_start_usec = now
	for number in range(first, scenario.bots + 1):
		var bot := ScenarioBot.new(number, 0, scenario.steps_of(number), peers)
		if bot.joins_late():
			failures.append("bot %d: a playcheck bot joins at the start (no Join step)" % number)
			return false
		bots.append(bot)
		_connect(bot)
	return failures.is_empty()


## One frame at `now` (microseconds of the real clock).
func step(now: int) -> void:
	now_usec = now
	@warning_ignore("integer_division")
	tick_now = (now - _start_usec) * Ticks.RATE / USEC_PER_SECOND
	step_clients()
	if _every_peer_known():
		play_frame(tick_now)


## The step each bot is on, as "bot <n> step <i> (<name>)", once per change; "" when none changed.
func progress() -> PackedStringArray:
	var lines := PackedStringArray()
	for bot: ScenarioBot in bots:
		if _reported.get(bot.number, -1) == bot.step_index:
			continue
		_reported[bot.number] = bot.step_index
		var step := bot.current_step()
		var what := step.step_name() if step != null else &"its script is done"
		lines.append("bot %d step %d (%s)" % [bot.number, bot.step_index + 1, what])
	return lines


## A bot whose session ended (the host closed or dropped it), with the reason; "" when none.
func ended() -> String:
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client != null and client.is_ended():
			return "bot %d: its session ended (%s)" % [bot.number, client.end_reason]
	return ""


## Every bot leaves.
func finish() -> void:
	for client: BotClient in clients.values():
		if not client.is_ended():
			client.leave()


func _join_host(bot: ScenarioBot) -> String:
	var transport := EnetTransport.new(schema.kind_table())
	var joined := transport.join(ADDRESS, port)
	if joined != OK:
		failures.append("cannot join %s:%d: %s" % [ADDRESS, port, error_string(joined)])
	add_client(bot, transport)
	return ""


func _every_peer_known() -> bool:
	for number in range(1, scenario.bots + 1):
		if peers.peer_of(number) == 0:
			return false
	return true


## A bot's id, for the windows and window 1's setup.
func _peer_known(bot: ScenarioBot) -> void:
	var part := dir.path_join("peer-%d.part" % bot.number)
	var file := FileAccess.open(part, FileAccess.WRITE)
	if file == null:
		failures.append("cannot write %s" % part)
		return
	file.store_string(str(bot.peer))
	file.close()
	if DirAccess.rename_absolute(part, dir.path_join("peer-%d" % bot.number)) != OK:
		failures.append("cannot rename %s" % part)


## The windows' ids (ScenarioPeers.refresh); the bots' own come from `connected`.
func _read_peers(map: ScenarioPeers) -> void:
	for number in range(1, first):
		if map.has_bot(number):
			continue
		var path := dir.path_join("peer-%d" % number)
		var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		if text.is_valid_int():
			map.set_peer(number, text.to_int())


## No synthetic voice: a window would play it (NetPlay's frames are for the leak test).
func _speak(_bot: ScenarioBot) -> void:
	pass
