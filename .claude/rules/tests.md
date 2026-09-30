---
paths:
  - "tests/**"
---

# Tests (GdUnit4 6.2.1)

## Layout and names
- `tests/unit/`: pure logic, mostly `core/`, mirroring its path (`core/match/vote.gd` →
  `tests/unit/match/vote_test.gd`). `tests/integration/`: `server/` and `net/` together, and scene or physics
  suites that need real engine steps, mirroring the source path (`client/player/player_controller.gd` →
  `tests/integration/client/player/player_controller_test.gd`). Bot matches come with the bot harness (M3).
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
- Headless runs have no `InputEvent`s: UI and input need `shot` and a playtest instead.
- A bug fix starts with a test that fails for the bug; run it and see it fail before the fix.

## Running
- One file: `tools\run.cmd test tests/unit/match/vote_test.gd`. Everything: `tools\run.cmd test`.
- The runner trusts only GdUnit4's exit code and `results.xml` (never the console summary). Zero tests is a failure.
  Reports: `tools/out/gdunit/`; log: `tools/out/logs/test.log`.
- Agent `test-runner` runs them and returns only failures.
- A throwaway probe test goes in the gitignored `tests/scratch/`, never beside real tests: run it with
  `tools\run.cmd test tests/scratch/probe_test.gd`, delete it with `rm -r tests/scratch/...` (no prompt). Full
  `check`, `test` and `lint` runs leave the folder out. No `class_name` there, and no copy of a `.tscn` or `.tres`
  with its uid: Godot still imports the folder, so both clash with the real file. No link or junction there: a
  recursive delete through one removes its target.

## Never
- Weaken, skip or delete a test to make it pass without the human's explicit approval. That includes loosening an
  assert, adding a skip, or catching the error the test is meant to see.
- Claim a test proves something you did not see fail. For the information-leak test: inject a leak, confirm the
  test fails, revert (`docs/history/KICKOFF.md` §4).
