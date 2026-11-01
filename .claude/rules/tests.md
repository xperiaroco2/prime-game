---
paths:
  - "tests/**"
---

# Tests (GdUnit4 6.2.1)

## Layout and names
- `tests/unit/`: pure logic, mostly `core/`, mirroring its path (`core/match/intents.gd` →
  `tests/unit/match/intents_test.gd`). `tests/integration/`: `server/` and `net/` together, and scene or physics
  suites that need real engine steps, mirroring the source path (`client/player/player_controller.gd` →
  `tests/integration/client/player/player_controller_test.gd`). Bot matches run with `tools\run.cmd bots`
  (`tests/harness/bots/`, scenarios in `content/scenarios/` and `tests/fixtures/scenarios/`), a step of
  `verify --full` (CI).
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
- One file: `tools\run.cmd test tests/unit/match/intents_test.gd`; everything: `tools\run.cmd test`. Shards, clocks,
  `--repeat` and reports: `tools\run.cmd test --help` and `docs/AGENT_WORKFLOW.md` §11.19, §11.20; a probe test in
  `tests/scratch/`: AGENT_WORKFLOW §8.2.4.

## Never
- Weaken, skip or delete a test to make it pass without the human's explicit approval. That includes loosening an
  assert, adding a skip, or catching the error the test is meant to see.
- Claim a test proves something you did not see fail. For the information-leak test: inject a leak, confirm the
  test fails, revert (`docs/history/KICKOFF.md` §4).
