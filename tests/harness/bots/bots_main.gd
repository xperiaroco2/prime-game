extends SceneTree
## The bots runner's entry (ARCHITECTURE §4.6, §9.7), started by `tools/run.sh bots`:
## - `bots [scenario ...]`: every scenario in content/scenarios/ but the measurements
##   (BotScenario.measurement, M5-4's voice_load), or those named, in one headless process
##   (BotsRunner, simulated clock);
## - `bots <scenario> --instances N`: one scenario over ENet on 127.0.0.1, one process per bot, on
##   the real clock (BotsEnet; PRIME_INSTANCE is the bot).
## User arguments: scenario names, and over ENet `--port=<p>` and `--instances=<n>`. Prints one
## line per scenario; a failed one prints its seed, each failure (the bot, its step, its last
## events) and the command log that replays it (ReplayFiles, E13), next to the bots' view files in
## tools/out/bots/<scenario>/.
## Exits 1 when any scenario failed.

const SCENARIOS_DIR := "res://content/scenarios/"
const PORT_ARG := "--port="
const INSTANCES_ARG := "--instances="
## Frames per second over ENet: enough for 20 Hz claims, without spinning the CPU of N processes.
const ENET_FPS := 120

var _enet: BotsEnet
var _name := ""


func _initialize() -> void:
	var names := PackedStringArray()
	var port := 0
	var instances := 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port = arg.trim_prefix(PORT_ARG).to_int()
		elif arg.begins_with(INSTANCES_ARG):
			instances = arg.trim_prefix(INSTANCES_ARG).to_int()
		else:
			names.append(arg)
	if port > 0:
		_start_enet(names, port, instances)
		return
	quit(_run_in_one_process(names))


func _process(_delta: float) -> bool:
	if _enet == null:
		return false
	_enet.step(Time.get_ticks_usec())
	if not _enet.done():
		return false
	_enet.finish()
	var code := _report(_name, _enet.failures, _enet.scenario, _enet.replay_path, "")
	if not _enet.is_host():
		# The host reports every bot; a remote bot's own failures are in its view file too.
		code = 0 if _enet.failures.is_empty() else 1
	_enet = null
	quit(code)
	return false


func _run_in_one_process(names: PackedStringArray) -> int:
	var paths := _paths(names)
	if paths.is_empty():
		return 1
	var failed := 0
	for path: String in paths:
		var scenario := load(path) as BotScenario
		var name := path.get_file().get_basename()
		if scenario == null:
			print("BOTS %s: FAILED, not a BotScenario" % path)
			failed += 1
			continue
		var started := Time.get_ticks_msec()
		var runner := BotsRunner.play(scenario, ViewFile.dir_of(name))
		var took := (
			"%d frames (%.1f s simulated) in %d ms"
			% [
				runner.frames_run,
				runner.frames_run * BotsRunner.FRAME_USEC / 1000000.0,
				Time.get_ticks_msec() - started
			]
		)
		failed += _report(name, runner.failures, scenario, runner.replay_path, took)
	print("BOTS %d of %d scenarios passed" % [paths.size() - failed, paths.size()])
	return 1 if failed > 0 else 0


func _start_enet(names: PackedStringArray, port: int, instances: int) -> void:
	var paths := _paths(names)
	if paths.size() != 1:
		print("BOTS FAILED: --instances runs exactly one scenario, got %s" % [names])
		quit(1)
		return
	_name = paths[0].get_file().get_basename()
	var scenario := load(paths[0]) as BotScenario
	if scenario == null:
		print("BOTS %s: FAILED, not a BotScenario" % paths[0])
		quit(1)
		return
	var instance := OS.get_environment("PRIME_INSTANCE").to_int()
	_enet = BotsEnet.new(scenario, instance, port, ViewFile.dir_of(_name))
	Engine.max_fps = ENET_FPS
	if instances != scenario.bots:
		_enet.failures.append(
			(
				"%s has %d bots: run it with --instances %d, not %d"
				% [_name, scenario.bots, scenario.bots, instances]
			)
		)
	if not _enet.failures.is_empty() or not _enet.start(Time.get_ticks_usec()):
		_report(_name, _enet.failures, scenario, "", "instance %d" % instance)
		_enet = null
		quit(1)
		return
	print("BOTS %s: instance %d of %d on port %d" % [_name, instance, scenario.bots, port])


## Prints a scenario's result; 1 when it failed.
func _report(
	name: String,
	failures: PackedStringArray,
	scenario: BotScenario,
	replay_path: String,
	took: String
) -> int:
	if failures.is_empty():
		print("BOTS %s: passed%s" % [name, ", " + took if not took.is_empty() else ""])
		return 0
	print("BOTS %s: FAILED (seed %d)%s" % [name, scenario.session_seed, " " + took])
	for failure: String in failures:
		print("  %s" % failure)
	if not replay_path.is_empty():
		print("  command log (Match.replay with ReplayFiles.read): %s" % replay_path)
	return 1


func _paths(names: PackedStringArray) -> PackedStringArray:
	var found := PackedStringArray()
	if names.is_empty():
		for file: String in DirAccess.get_files_at(SCENARIOS_DIR):
			var path := SCENARIOS_DIR.path_join(file)
			if file.ends_with(".tres") and not _is_measurement(path):
				found.append(path)
		found.sort()
		return found
	for name: String in names:
		var path := SCENARIOS_DIR.path_join(name.trim_suffix(".tres") + ".tres")
		if not ResourceLoader.exists(path):
			print("BOTS FAILED: no scenario %s (%s)" % [name, path])
			return PackedStringArray()
		found.append(path)
	return found


## Whether the scenario at `path` is a measurement, played only when named.
func _is_measurement(path: String) -> bool:
	var scenario := load(path) as BotScenario
	return scenario != null and scenario.measurement
