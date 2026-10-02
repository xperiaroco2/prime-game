extends SceneTree
## The perf run's entry (ARCHITECTURE §9.7, #187), started by `tools\run.cmd perf`: one PerfRun of
## a PerfScenario, stepped from _physics_process like HostNode steps the game's host, so
## Performance's TIME_PHYSICS_PROCESS covers the host's step (and the bots' clients, in the same
## process). Over the loopback the runner adds `--fixed-fps 60`, so frames run as fast as the
## machine allows on the simulated clock; over ENet, the real clock at 60 physics frames a second.
## User arguments: `--bots=<n>`, `--seconds=<s>` (the round), `--out=<file>` (the JSON the runner
## summarises), and `--enet --port=<p>`. Prints one line; a failed run prints each failure and
## exits 1.

const BOTS_ARG := "--bots="
const SECONDS_ARG := "--seconds="
const PORT_ARG := "--port="
const OUT_ARG := "--out="
const ENET_ARG := "--enet"
const DEFAULT_BOTS := 10
const DEFAULT_SECONDS := 60

var _run: PerfRun
var _out := ""


func _initialize() -> void:
	var bots := DEFAULT_BOTS
	var seconds := DEFAULT_SECONDS
	var port := 0
	var enet := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(BOTS_ARG):
			bots = arg.trim_prefix(BOTS_ARG).to_int()
		elif arg.begins_with(SECONDS_ARG):
			seconds = arg.trim_prefix(SECONDS_ARG).to_int()
		elif arg.begins_with(PORT_ARG):
			port = arg.trim_prefix(PORT_ARG).to_int()
		elif arg.begins_with(OUT_ARG):
			_out = arg.trim_prefix(OUT_ARG)
		elif arg == ENET_ARG:
			enet = true
		else:
			print("PERF FAILED: unknown argument %s" % arg)
			quit(1)
			return
	if _out.is_empty() or (enet and port <= 0):
		print("PERF FAILED: give --out=<file>, and --port=<p> with --enet")
		quit(1)
		return
	_run = PerfRun.new(PerfScenario.build(bots, seconds), enet, port)
	if not _run.start():
		_finish()
		return
	print(
		(
			"PERF %d bots over %s, a %d s round, seed %d"
			% [bots, "ENet" if enet else "the loopback", seconds, _run.scenario.session_seed]
		)
	)


func _physics_process(_delta: float) -> bool:
	if _run == null:
		return false
	_run.sample()
	_run.frame()
	if _run.done():
		_finish()
	return false


func _finish() -> void:
	_run.finish()
	var code := 0 if _run.failures.is_empty() else 1
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		print("PERF FAILED: cannot write %s" % _out)
		code = 1
	else:
		file.store_string(JSON.stringify(_run.to_dict()))
		file.close()
	if code == 0:
		print(
			(
				"PERF passed: %d frames, %d host ticks, ends %s"
				% [_run.frames_run, _run.session.game.ticked_through(), _run.ends]
			)
		)
	else:
		print("PERF FAILED (seed %d)" % _run.scenario.session_seed)
		for failure: String in _run.failures:
			print("  %s" % failure)
	_run = null
	quit(code)
