extends SceneTree
## The chaos bots' entry (ARCHITECTURE §4.6 "Chaos"), started by `tools/run.sh bots --chaos`:
## - `--seed=<n>` (default SEED) and `--runs=<k>`: for each seed n, n + 1, ... n + k - 1, three
##   one-process runs over the loopback on the simulated clock: the baseline (the chaos peers joined
##   but idle), the chaos run, and the chaos run with the hidden roles swapped; each must pass
##   (ChaosRun), the honest bots' views of the chaos run must equal the baseline's, and the
##   hostile's Rejected streams of the two chaos runs must be equal;
## - `--port=<p>`: one chaos run over ENet on 127.0.0.1:<p> in one process, the invariants only;
##   with `--transport=webrtc` over WebRTC there (M6-6: LanSignalling on the port, the fault
##   shim on, paced to the real clock, plus the order check);
## - `--long`: the match in which the hostile also dies (ChaosScenario's `until_dead`), the night
##   job's; without it the round ends while it is downed (`verify`'s, under 15 s).
## Prints one line per seed (`CHAOS seed <n>: passed` or `FAILED`, then each failure) and exits 1
## when one failed. A failed seed replays with `tools\run.cmd bots --chaos --seed <n>`.

const SEED := 188_001
const SEED_ARG := "--seed="
const RUNS_ARG := "--runs="
const PORT_ARG := "--port="
const TRANSPORT_ARG := "--transport="
const WEBRTC := "webrtc"
## The long match: the hostile also dies (the night job's).
const LONG_ARG := "--long"
const MAX_LISTED := 12


func _initialize() -> void:
	var first_seed := SEED
	var runs := 1
	var port := 0
	var long := false
	var webrtc := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == LONG_ARG:
			long = true
		elif arg.begins_with(SEED_ARG):
			first_seed = arg.trim_prefix(SEED_ARG).to_int()
		elif arg.begins_with(RUNS_ARG):
			runs = arg.trim_prefix(RUNS_ARG).to_int()
		elif arg.begins_with(PORT_ARG):
			port = arg.trim_prefix(PORT_ARG).to_int()
		elif arg.begins_with(TRANSPORT_ARG):
			webrtc = arg.trim_prefix(TRANSPORT_ARG) == WEBRTC
	if not OS.is_debug_build():
		print("CHAOS FAILED: the chaos bots run in debug builds only (ForceRole, the observer)")
		quit(1)
		return
	var failed := 0
	for i in maxi(runs, 1):
		var seed_value := first_seed + i
		var started := Time.get_ticks_msec()
		var problems := (
			run_network(seed_value, port, long, webrtc) if port > 0 else run_seed(seed_value, long)
		)
		var took := Time.get_ticks_msec() - started
		var what := "loopback"
		if port > 0:
			what = "%s on port %d" % ["WebRTC" if webrtc else "ENet", port]
		if problems.is_empty():
			print("CHAOS seed %d: passed (%s, %d ms)" % [seed_value, what, took])
			continue
		failed += 1
		print("CHAOS seed %d: FAILED (%s, %d ms)" % [seed_value, what, took])
		for problem: String in problems.slice(0, MAX_LISTED):
			print("  %s" % problem)
		if problems.size() > MAX_LISTED:
			print("  and %d more" % (problems.size() - MAX_LISTED))
	print("CHAOS %d of %d seeds passed" % [maxi(runs, 1) - failed, maxi(runs, 1)])
	quit(1 if failed > 0 else 0)


## The three loopback runs of one seed and their comparisons; the problems, each labelled.
static func run_seed(seed_value: int, long: bool) -> PackedStringArray:
	var problems := PackedStringArray()
	var started := Time.get_ticks_msec()
	var baseline := ChaosRun.play_one(false, ChaosRun.Mode.BASELINE, seed_value, 0, long)
	var chaos := ChaosRun.play_one(false, ChaosRun.Mode.CHAOS, seed_value, 0, long)
	var swapped := ChaosRun.play_one(true, ChaosRun.Mode.CHAOS, seed_value, 0, long)
	print(
		(
			"  three runs of %d frames (%.1f s simulated) each, in %d ms"
			% [
				chaos.frames_run,
				chaos.frames_run * BotsRunner.FRAME_USEC / 1000000.0,
				Time.get_ticks_msec() - started
			]
		)
	)
	for named: Array in [["baseline", baseline], ["chaos", chaos], ["swapped roles", swapped]]:
		var run: ChaosRun = named[1]
		for failure: String in run.failures:
			problems.append("%s: %s" % [named[0], failure])
	if problems.is_empty():
		for problem: String in ChaosRun.compare_honest(baseline, chaos):
			problems.append("baseline against chaos: %s" % problem)
		for problem: String in ChaosRun.compare_rejected(chaos, swapped):
			problems.append("chaos against swapped roles: %s" % problem)
	if problems.is_empty():
		print(summary(chaos))
	return problems


## One chaos run over ENet, or WebRTC; the problems.
static func run_network(seed_value: int, port: int, long: bool, webrtc: bool) -> PackedStringArray:
	var run := ChaosRun.play_one(false, ChaosRun.Mode.CHAOS, seed_value, port, long, webrtc)
	if run.failures.is_empty():
		print(summary(run))
	return run.failures


## What a passed chaos run sent and what the host counted.
static func summary(run: ChaosRun) -> String:
	var checked := 0
	for peer: int in run.checked:
		checked += run.checked[peer]
	var reasons: Dictionary[String, int] = {}
	for answer: String in run.hostile_rejected:
		var reason := answer.get_slice(" ", 1)
		reasons[reason] = reasons.get(reason, 0) + 1
	return (
		(
			"  %d chaos commands answered as ARCHITECTURE says, %d Rejected to the hostile %s;"
			+ " the host's rejects: hostile %s, malformed peer %s"
		)
		% [
			checked,
			run.hostile_rejected.size(),
			reasons,
			run.ledger.named(run.hostile_peer()),
			run.ledger.named(run.malformed.peer),
		]
	)
