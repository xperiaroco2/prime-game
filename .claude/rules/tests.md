---
paths:
  - "tests/**"
---

# Tests (GdUnit4 6.2.1)

## Layout and names
- `tests/unit/`: pure logic, mostly `core/`, mirroring its path (`core/match/vote.gd` →
  `tests/unit/match/vote_test.gd`). `tests/integration/`: `server/` and `net/` together, and scene or physics
  suites that need real engine steps, mirroring the source path (`client/player/player_controller.gd` →
  `tests/integration/client/player/player_controller_test.gd`). Bot matches run with `tools\run.cmd bots`
  (`tests/harness/bots/`, scenarios in `content/scenarios/`), also a `verify` step.
- A suite that outgrows gdlint's 40 public methods splits by topic (`player_controller_downed_test.gd`); builders it
  shares go in a plain script next to it, preloaded by each suite (`player_test_world.gd`).
- A suite is `<name>_test.gd` (GdUnit4's snake_case convention) and `extends GdUnitTestSuite`. Test functions start
  with `test_`, are typed like all GDScript, and return `void`.
- Hooks: `before()` and `after()` once per suite; `before_test()` and `after_test()` around each test.
- The first import creates a `<name>_test.gd.uid` sidecar. Commit it with the suite, or `check` fails.

## Writing tests
- Fluent asserts: `assert_int(x).is_equal(3)`, `assert_str(s).contains("a")`, `assert_bool(b).is_true()`,
  `assert_array(a).contains_exactly([1, 2])`, `assert_object(o).is_not_null()`. Check any other assert in
  `addons/gdUnit4/src/GdUnitTestSuite.gd` before using it.
- Orphan nodes fail the build. Wrap every `Node` a test creates in `auto_free(...)`, or free it in the test or
  `after_test()`. `test` names the leaking test, or the suite's `before()`/`after()`.
- Deterministic only: seed every `RandomNumberGenerator`; no sleeps or wall-clock waits.
- Under load one idle frame runs several physics frames (up to `Engine.max_physics_steps_per_frame`, 8 here)
  before its `_process`, and `process_frame` is emitted before that `_process`. So a fixed count of physics frames
  proves nothing about what a `_process` writes (a label, a button, `Game`'s per-frame flags): after the state it
  follows, `await get_tree().process_frame` twice (#222). To see such a test fail, copy the suite's `.gd` (never
  its `.gd.uid`) into `tests/scratch/` and add in its `before_test()` a node whose `_process` calls
  `OS.delay_msec(120)`; a script that only `extends` the suite runs none of its tests (GdUnit4 runs a script's own
  `test_` functions only, #238).
- Headless runs have no `InputEvent`s: UI and input need `shot`, `playcheck` (off-screen, keys only) and a playtest.
- A bug fix starts with a test that fails for the bug; run it and see it fail before the fix.

## Running
- One file: `tools\run.cmd test tests/unit/match/vote_test.gd`. Everything: `tools\run.cmd test`, which with no
  paths runs in shards: K GdUnit4 processes at once, each with its own `user://` (K from the CPU count, at most 4;
  `--shards K` sets it, 1 is one process). Named paths run one process unless `--shards K`; `--repeat` always one.
- The runner trusts only GdUnit4's exit code and `results.xml` (never the console summary). Zero tests is a failure.
  Reports: `tools/out/gdunit/`; log: `tools/out/logs/test.log`.
- Flaky hunt: `tools\run.cmd test --repeat N [paths]` runs them N times in a row; per-run reports in
  `tools/out/gdunit-runs/`, the flaky comparison in its `summary.json` (`docs/AGENT_WORKFLOW.md` §15).
- Perf matches live in `tests/harness/perf/` and run with `tools\run.cmd perf` (host tick time and bytes per peer
  with 10 bots, compared with the last run; not a `verify` step; `docs/ARCHITECTURE.md` §9.7).
- Chaos bots live in `tests/harness/chaos/` and run with `tools\run.cmd bots --chaos [--seed N]` (a hostile player
  and a malformed peer against the host; a failure prints the seed that replays it; the `verify` step `chaos`;
  `docs/ARCHITECTURE.md` §4.6 "Chaos bots").
- Agent `test-runner` runs them and returns only failures.
- A throwaway probe test goes in the gitignored `tests/scratch/`, never beside real tests: run it with
  `tools\run.cmd test tests/scratch/probe_test.gd`, delete it with its `.gd.uid` (`rm -r tests/scratch/...`, no
  prompt). Full `check` (its UID lint too, #264), `test` and `lint` runs leave the folder out, but Godot imports it:
  no `class_name` there, and no uid copied from a project file (a `.tscn` or `.tres` header, a suite's `.gd.uid`),
  which clashes with the real file and fails `check`. No link or junction there: a recursive delete through one
  removes its target.

## Never
- Weaken, skip or delete a test to make it pass without the human's explicit approval. That includes loosening an
  assert, adding a skip, or catching the error the test is meant to see.
- Claim a test proves something you did not see fail. For the information-leak test: inject a leak, confirm the
  test fails, revert (`docs/history/KICKOFF.md` §4).
