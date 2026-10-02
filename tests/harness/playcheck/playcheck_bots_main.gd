extends SceneTree
## The bots process of `tools\run.cmd playcheck` (#186; docs/AGENT_WORKFLOW.md §11), headless:
##   godot --headless -s res://tests/harness/playcheck/playcheck_bots_main.gd
##       -- --scenario=<res://...tres> --first=<n> --peers=<dir> --port=<p>
##          --stop-file=<path> --alive-file=<path>
## Plays the players `first` and up of the BotScenario (playcheck_bots.gd) against the game that
## window 1 hosts. Prints PLAYCHECK at bot <n> step <i> (<name>) as each bot starts a step, and
## PLAYCHECK fail <why> before it exits 1: a failed step, a session the host ended, wrong
## arguments. Stops with exit 0 once the runner's stop file exists, or its alive file is gone or
## stale (LaunchOptions' rules: a killed runner leaves no bot running).

const Bots := preload("res://tests/harness/playcheck/playcheck_bots.gd")
const PREFIX := "PLAYCHECK "
## Enough for 20 Hz claims without spinning a core (bots_main.gd's ENET_FPS).
const FPS := 120
const STOP_CHECK_MS := 200

var _play: Bots
var _options := LaunchOptions.new()
var _last_stop_check_ms := 0


func _initialize() -> void:
	var path := ""
	var first := 0
	var peers := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			path = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--first="):
			first = arg.trim_prefix("--first=").to_int()
		elif arg.begins_with("--peers="):
			peers = arg.trim_prefix("--peers=")
		elif arg.begins_with(LaunchOptions.PORT_ARG):
			_options.port = arg.trim_prefix(LaunchOptions.PORT_ARG).to_int()
		elif arg.begins_with(LaunchOptions.STOP_ARG):
			_options.stop_file = arg.trim_prefix(LaunchOptions.STOP_ARG)
		elif arg.begins_with(LaunchOptions.ALIVE_ARG):
			_options.alive_file = arg.trim_prefix(LaunchOptions.ALIVE_ARG)
		else:
			_fail("unknown argument '%s'" % arg)
			return
	var scenario := load(path) as BotScenario if ResourceLoader.exists(path) else null
	if scenario == null:
		_fail("'%s' is not a BotScenario" % path)
		return
	Engine.max_fps = FPS
	_play = Bots.new(scenario, first, _options.port, peers)
	if not _play.start(Time.get_ticks_usec()):
		_fail("; ".join(_play.failures))
		return
	print(
		(
			"%sbots: players %d to %d join %s:%d"
			% [PREFIX, first, scenario.bots, Bots.ADDRESS, _options.port]
		)
	)


func _process(_delta: float) -> bool:
	if _play == null:
		return false
	if _stop_due():
		_end(0, "")
		return false
	_play.step(Time.get_ticks_usec())
	for line: String in _play.progress():
		print("%sat %s" % [PREFIX, line])
	var why := "; ".join(_play.failures) if not _play.failures.is_empty() else _play.ended()
	if not why.is_empty():
		# A session that just ended may be the host stopping for the runner: then it is no failure.
		_end(0 if _stop_requested() else 1, why)
	return false


## The runner's stop, checked every STOP_CHECK_MS.
func _stop_due() -> bool:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_stop_check_ms < STOP_CHECK_MS:
		return false
	_last_stop_check_ms = now_ms
	return _stop_requested()


## The runner's stop file, or its alive file gone or stale.
func _stop_requested() -> bool:
	return _options.stop_requested() or _options.runner_gone()


## The bots leave and the process exits with `code`; a failure prints `why` first.
func _end(code: int, why: String) -> void:
	if _play != null:
		_play.finish()
		_play = null
	if code != 0:
		_fail(why)
		return
	quit(0)


func _fail(why: String) -> void:
	print("%sfail %s" % [PREFIX, why])
	quit(1)
