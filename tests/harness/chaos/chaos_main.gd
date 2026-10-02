extends SceneTree
## The chaos bots' entry (ARCHITECTURE §4.6 "Chaos"), started by `tools/run.sh bots --chaos`:
## - `--seed=<n>` (default SEED) and `--runs=<k>`: for each seed n, n + 1, ... n + k - 1, three
##   one-process runs over the loopback on the simulated clock: the baseline (the chaos peers joined
##   but idle), the chaos run, and the chaos run with the hidden roles swapped; each must pass
##   (ChaosRun), the honest bots' views of the chaos run must equal the baseline's, and the
##   hostile's Rejected streams of the two chaos runs must be equal;
## - `--port=<p>`: one chaos run over ENet on 127.0.0.1:<p> in one process, the invariants only.
## Prints one line per seed (`CHAOS seed <n>: passed` or `FAILED`, then each failure) and exits 1
## when one failed. A failed seed replays with `tools\run.cmd bots --chaos --seed <n>`.

const SEED := 188_001
const SEED_ARG := "--seed="
const RUNS_ARG := "--runs="
const PORT_ARG := "--port="
const MAX_LISTED := 12


func _initialize() -> void:
	var first_seed := SEED
	var runs := 1
	var port := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(SEED_ARG):
			first_seed = arg.trim_prefix(SEED_ARG).to_int()
		elif arg.begins_with(RUNS_ARG):
			runs = arg.trim_prefix(RUNS_ARG).to_int()
		elif arg.begins_with(PORT_ARG):
			port = arg.trim_prefix(PORT_ARG).to_int()
	if not OS.is_debug_build():
		print("CHAOS FAILED: the chaos bots run in debug builds only (ForceRole, the observer)")
		quit(1)
		return
	var failed := 0
	for i in maxi(runs, 1):
		var seed_value := first_seed + i
		var started := Time.get_ticks_msec()
		var problems := run_enet(seed_value, port) if port > 0 else run_seed(seed_value)
		var took := Time.get_ticks_msec() - started
		var what := "ENet on port %d" % port if port > 0 else "loopback"
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
static func run_seed(seed_value: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var baseline := ChaosRun.play_one(false, ChaosRun.Mode.BASELINE, seed_value)
	var chaos := ChaosRun.play_one(false, ChaosRun.Mode.CHAOS, seed_value)
	var swapped := ChaosRun.play_one(true, ChaosRun.Mode.CHAOS, seed_value)
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


## One chaos run over ENet; the problems.
static func run_enet(seed_value: int, port: int) -> PackedStringArray:
	var run := ChaosRun.play_one(false, ChaosRun.Mode.CHAOS, seed_value, port)
	if run.failures.is_empty():
		print(summary(run))
	return run.failures


## What a passed chaos run sent and what the host counted.
static func summary(run: ChaosRun) -> String:
	var checked := 0
	for peer: int in run.checked:
		checked += run.checked[peer]
	return (
		(
			"  %d chaos commands answered as ARCHITECTURE says, %d Rejected to the hostile;"
			+ " the host's rejects: hostile %s, malformed peer %s"
		)
		% [
			checked,
			run.hostile_rejected.size(),
			run.ledger.named(run.hostile_peer()),
			run.ledger.named(run.malformed.peer),
		]
	)
