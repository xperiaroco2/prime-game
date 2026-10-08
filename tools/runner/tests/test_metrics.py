"""`metrics` (#178): small synthetic transcripts written here (never real ones) for the dedup by message id, the
--since/--until window, the price weights, the parsers, the verify history and the compact summary."""

import io
import json
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path

from runner import cli, metrics
from runner.common import Failure

T0 = datetime(2026, 10, 2, 8, 0, tzinfo=timezone.utc)
SESSION = "11111111-2222-3333-4444-555555555555"
UNTIL = "2026-10-02T11:00:00Z"
SUMMARY = (
    "verify summary\n"
    "  passed  doctor        1.0s\n"
    "  passed  lint         20.0s\n"
    "  FAILED  test        100.0s\n"
    "  passed  selftest    150.0s\n"
    "verify: FAILED in 271.0s\n"
)


def at(minutes: float) -> str:
    return (T0 + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def usage(inp: int = 0, write: int = 0, read: int = 0, out: int = 0, write_1h: int = 0) -> dict:
    return {
        "input_tokens": inp,
        "cache_creation_input_tokens": write,
        "cache_read_input_tokens": read,
        "output_tokens": out,
        "cache_creation": {"ephemeral_5m_input_tokens": write - write_1h, "ephemeral_1h_input_tokens": write_1h},
    }


def assistant(
    minutes: float, mid: str, u: dict, *, model: str = "claude-opus-5-5", tool: dict | None = None, effort: str = "high"
) -> dict:
    content: list[dict] = [{"type": "text", "text": "working"}]
    if tool:
        content = [{"type": "tool_use", **tool}]
    return {
        "type": "assistant",
        "timestamp": at(minutes),
        "effort": effort,
        "message": {"id": mid, "model": model, "usage": u, "content": content},
    }


def bash(tool_id: str, command: str) -> dict:
    return {"id": tool_id, "name": "Bash", "input": {"command": command}}


def tool_result(minutes: float, tool_id: str, text: str = "done") -> dict:
    return {
        "type": "user",
        "timestamp": at(minutes),
        "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tool_id, "content": text}]},
    }


def write_lines(path: Path, lines: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(json.dumps(line) + "\n" for line in lines))


class Fixture:
    """One project folder: a manager session with four workflow runs and a hand-run subagent.

    wf_done   #5, finished, starts 08:00: an implementer retried once (the first attempt died), whose message msg-i1 is
              written twice (one line per content block, the same usage), a verify summary printed by a verify call
              and again by publish, a 6-minute wait before its next call; a code review (a major and a nit) and a
              godot-api check on Sonnet; a publisher that watches CI for 3 minutes and opens PR 9.
    wf_open   #6, unfinished (the journal ends with a started agent).
    wf_resume #7, a resumed run: only a publisher.
    wf_late   #8, finished but its last line is after --until (11:00).
    """

    def __init__(self, root: Path) -> None:
        self.dir = root / "projects" / "D--prime-game"
        wf = self.dir / SESSION / "subagents" / "workflows"
        self.run(wf / "wf_done", [
            ("k-impl", "a-dead", "implement:#5", "Implement", None, [
                assistant(0, "msg-dead", usage(inp=5, write=1000, out=10)),
                assistant(2, "msg-dead2", usage(inp=5, read=1000, out=10)),
            ]),
            ("k-impl", "a-impl", "implement:#5", "Implement", {"verify_green": True}, [
                assistant(3, "msg-i1", usage(inp=10, write=20000, out=100)),
                assistant(3, "msg-i1", usage(inp=10, write=20000, out=100), tool=bash("t1", "tools/run.sh verify")),
                tool_result(8, "t1", "lint ok\n" + SUMMARY),
                assistant(9, "msg-i2", usage(inp=1, write=19000, read=1000, out=50)),
                assistant(9.5, "msg-i3", usage(inp=1, read=20000, out=50), tool=bash("t2", "tools/run.sh publish")),
                tool_result(10, "t2", SUMMARY),
                assistant(10.5, "msg-i4", usage(inp=1, read=20100, out=20)),
            ]),
            ("k-code", "a-code", "review:code:#5", "Review",
             {"findings": [{"severity": "major"}, {"severity": "nit"}]}, [
                assistant(11, "msg-c1", usage(inp=2, write=5000, out=30)),
                assistant(13, "msg-c2", usage(inp=2, read=5000, out=30)),
            ]),
            ("k-godot", "a-godot", "review:godot-api:#5", "Review", {"findings": []}, [
                assistant(11, "msg-g1", usage(inp=1_000_000, out=1_000_000), model="claude-sonnet-5-5"),
                assistant(12, "msg-g2", usage(read=1_000_000, write=1_000_000), model="claude-sonnet-5-5"),
            ]),
            ("k-pub", "a-pub", "publish:#5", "Publish", {"pr_number": 9, "ci_green": True}, [
                assistant(14, "msg-p1", usage(inp=3, write=8000, out=40), tool=bash("t3", "gh pr checks 9 --watch")),
                tool_result(17, "t3"),
                assistant(18, "msg-p2", usage(inp=3, read=8000, out=40)),
            ]),
        ])
        self.run(wf / "wf_open", [
            ("k-o", "a-open", "implement:#6", "Implement", None, [assistant(30, "msg-o1", usage(inp=1, write=100))]),
        ], finished=False)
        self.run(wf / "wf_resume", [
            ("k-r", "a-res", "publish:#7", "Publish", {"pr_number": 10}, [
                assistant(40, "msg-r1", usage(inp=1, write=100)),
                assistant(41, "msg-r2", usage(inp=1, read=100)),
            ]),
        ])
        self.run(wf / "wf_late", [
            ("k-l", "a-late", "implement:#8", "Implement", {"x": 1}, [
                assistant(170, "msg-l1", usage(inp=1, write=100)),
                assistant(190, "msg-l2", usage(inp=1, read=100)),  # 11:10, after --until
            ]),
        ])
        write_lines(self.dir / f"{SESSION}.jsonl", [
            {"type": "custom-title", "customTitle": "M9 manager", "sessionId": SESSION},
            assistant(0, "msg-m1", usage(inp=10, write=1000, write_1h=1000, out=10),
                      tool=bash("m1", "tools/run.sh verify")),
            tool_result(6, "m1", SUMMARY),
            assistant(7, "msg-m2", usage(inp=10, read=1000, out=10)),
            assistant(200, "msg-m3", usage(inp=10, read=1000, out=10)),  # after --until
        ])
        hand = self.dir / SESSION / "subagents" / "agent-h1.jsonl"
        write_lines(hand, [assistant(50, "msg-h1", usage(inp=100, out=100), model="claude-haiku-4-5-20251001")])
        hand.with_name("agent-h1.meta.json").write_text(json.dumps({"agentType": "test-runner"}), encoding="utf-8")
        # A session that ran no workflow: not read, only counted.
        write_lines(self.dir / "99999999-0000.jsonl", [assistant(5, "msg-z", usage(inp=1))])

    @staticmethod
    def run(folder: Path, agents: list[tuple], finished: bool = True) -> None:
        journal: list[dict] = [{"type": "launched"}]
        for key, aid, label, phase, result, lines in agents:
            write_lines(folder / f"agent-{aid}.jsonl", lines)
            meta = {"agentType": "workflow-subagent", "description": label, "workflowPhase": phase}
            (folder / f"agent-{aid}.meta.json").write_text(json.dumps(meta), encoding="utf-8")
            journal.append({"type": "started", "key": key, "agentId": aid, "label": label, "phase": phase})
            if result is not None and finished:
                journal.append({"type": "result", "key": key, "agentId": aid, "result": result})
        write_lines(folder / "journal.jsonl", journal)


class MetricsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fx = Fixture(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def collect(self, since: str | None = None, until: str = UNTIL, sessions: dict | None = None) -> dict:
        return metrics.collect(
            [self.fx.dir], sessions or {}, metrics.parse_time(since) if since else None, metrics.parse_time(until)
        )

    def build(self, since: str | None = None, history: list[dict] | None = None, ci: dict | None = None):
        data = self.collect(since)
        return metrics.build(
            data, history or [], ci, metrics.parse_time(since) if since else None, metrics.parse_time(UNTIL)
        )

    def runs(self, data: dict) -> dict[str, dict]:
        return {r["wf"]: r for r in data["runs"]}

    def agent(self, run: dict, aid: str) -> dict:
        return next(x for x in run["agents"] if x["id"] == aid)

    def test_usage_is_deduplicated_by_message_id(self) -> None:
        impl = self.agent(self.runs(self.collect())["wf_done"], "a-impl")["data"]
        self.assertEqual(impl["api_calls"], 4)
        self.assertEqual(impl["tokens"]["cache_creation_input_tokens"], 20000 + 19000)
        self.assertEqual(impl["tokens"]["input_tokens"], 10 + 1 + 1 + 1)
        self.assertEqual(impl["last_ctx"], 1 + 20100 + 20)

    def test_the_window_counts_runs_by_their_first_and_last_line(self) -> None:
        runs = self.runs(self.collect())
        self.assertTrue(runs["wf_done"]["counted"])
        self.assertFalse(runs["wf_late"]["counted"], "its last line is after --until")
        runs = self.runs(self.collect(since="2026-10-02T08:20:00Z"))
        self.assertFalse(runs["wf_done"]["counted"], "it started before --since")
        self.assertTrue(runs["wf_open"]["counted"])

    def test_the_manager_counts_only_its_lines_in_the_window(self) -> None:
        session = self.collect()["sessions"][0]
        self.assertEqual(session["title"], "M9 manager")
        self.assertEqual(session["manager"]["api_calls"], 2)
        self.assertAlmostEqual(session["manager"]["tokens"]["usd_cache_write"], 1000 * 8.0 / 1e6, msg="1-hour writes")
        self.assertEqual(len(session["hand"]), 1)
        self.assertEqual(self.collect(since="2026-10-02T08:01:00Z")["sessions"][0]["manager"]["api_calls"], 1)

    def test_a_hand_run_subagent_is_cut_to_the_window(self) -> None:
        late = self.fx.dir / SESSION / "subagents" / "agent-h2.jsonl"
        write_lines(late, [
            assistant(170, "msg-h2a", usage(inp=1_000_000), model="claude-haiku-4-5-20251001"),
            assistant(190, "msg-h2b", usage(inp=1_000_000), model="claude-haiku-4-5-20251001"),  # after --until
        ])
        hand = {h["id"]: h["data"] for h in self.collect()["sessions"][0]["hand"]}
        self.assertEqual(sorted(hand), ["h1", "h2"])
        self.assertEqual(hand["h2"]["api_calls"], 1, "only its line before --until")
        self.assertAlmostEqual(metrics.usd(hand["h2"]["tokens"]), 1.0)
        hand = {h["id"] for h in self.collect(since="2026-10-02T08:55:00Z")["sessions"][0]["hand"]}
        self.assertEqual(hand, {"h2"}, "h1 ran at 08:50, before --since")

    def test_price_weights(self) -> None:
        # The shape read_agent keeps per message: the four token kinds, the 1-hour share of the writes, the model.
        opus = {**usage(inp=1_000_000, write=2_000_000, read=1_000_000, out=1_000_000), "cache_write_1h": 1_000_000,
                "model": "claude-opus-5-5"}
        parts = metrics.usd_of(opus)
        self.assertAlmostEqual(parts["usd_input"], 4.0)
        self.assertAlmostEqual(parts["usd_cache_write"], 5.0 + 8.0)
        self.assertAlmostEqual(parts["usd_cache_read"], 0.20)
        self.assertAlmostEqual(parts["usd_output"], 20.0)
        sonnet = self.agent(self.runs(self.collect())["wf_done"], "a-godot")["data"]["tokens"]
        self.assertAlmostEqual(metrics.usd(sonnet), 2.0 + 10.0 + 0.20 + 2.5)
        haiku = {**usage(inp=1_000_000, out=1_000_000), "model": "claude-haiku-4-5-20251001"}
        self.assertAlmostEqual(metrics.usd(metrics.usd_of(haiku)), 1.0 + 5.0)
        self.assertEqual(metrics.price_of("claude-unknown-9")[1], False)

    def test_a_retried_agent_counts_both_attempts(self) -> None:
        done = self.runs(self.collect())["wf_done"]
        self.assertEqual([x["id"] for x in done["agents"] if x["role"] == "implementer"], ["a-dead", "a-impl"])
        self.assertIsNone(self.agent(done, "a-dead")["result"])
        self.assertTrue(done["finished"])
        task = metrics.per_task(done)
        self.assertEqual(round(task["wall"]), 18 * 60)
        self.assertEqual(round(task["span"]["Implement"]), round(10.5 * 60))

    def test_kinds_and_unfinished_runs(self) -> None:
        runs = self.runs(self.collect())
        self.assertEqual(runs["wf_done"]["kind"], "issue-task")
        self.assertEqual(runs["wf_open"]["kind"], "issue-task")
        self.assertFalse(runs["wf_open"]["finished"])
        self.assertEqual(runs["wf_resume"]["kind"], "issue-task (resumed)")
        self.assertEqual(runs["wf_done"]["issue"], 5)
        md, record, _compact = self.build()
        self.assertEqual([t["issue"] for t in record["tasks"]], [5])
        self.assertIn("1 other sessions of this checkout ran no workflow", "\n".join(md))
        self.assertEqual(sorted(r["wf"] for r in record["runs"]), ["wf_done", "wf_open", "wf_resume"])

    def test_the_task_row(self) -> None:
        _md, record, _compact = self.build()
        task = record["tasks"][0]
        self.assertEqual(task["sev"], {"major": 1, "nit": 1})
        self.assertEqual((task["pr"], task["ci_green"]), (9, True))
        self.assertEqual(task["summaries"], 1, "one summary, printed by verify and again by publish")
        self.assertEqual(task["summaries_failed"], 1)
        self.assertEqual(task["summary_s"], 271.0)
        self.assertEqual(task["verify_calls"], 2)
        self.assertEqual(round(task["ci_s"]), 180)
        stage = record["stages"][0]
        self.assertEqual((stage["session"], stage["runs"], stage["majors"]), ("11111111", 1, 1))

    def test_the_wait_before_a_call_lands_in_its_bucket(self) -> None:
        impl = self.agent(self.runs(self.collect())["wf_done"], "a-impl")["data"]
        gap = next(g for g in impl["gaps"] if g[0] == 360.0)
        self.assertEqual(gap[:3], (360.0, 19000, 1000))
        self.assertAlmostEqual(gap[3], 19000 * (5.0 - 0.20) / 1e6, msg="Opus 5.5 write minus read, from PRICES")
        md, _record, _compact = self.build()
        text = "\n".join(md)
        self.assertIn("| 5 to 10 min | 1 | 19k | 1k | 19k | 100% |", text)
        self.assertIn("about $0.09 list more than reading them", text)

    def test_the_cache_premium_after_a_wait_is_priced_by_each_calls_model(self) -> None:
        sonnet = {**usage(write=1_000_000), "cache_write_1h": 0, "model": "claude-sonnet-5-5"}
        self.assertAlmostEqual(metrics.write_premium(sonnet), 2.5 - 0.20)
        opus_1h = {**usage(write=1_000_000, write_1h=1_000_000), "cache_write_1h": 1_000_000,
                   "model": "claude-opus-5-5"}
        self.assertAlmostEqual(metrics.write_premium(opus_1h), 8.0 - 0.20)

    def test_parsers(self) -> None:
        v = metrics.parse_verify("noise\n" + SUMMARY)
        self.assertEqual(v["status"], "FAILED")
        self.assertEqual(v["total"], 271.0)
        self.assertEqual(v["steps"]["test"], ("FAILED", 100.0))
        self.assertEqual(metrics.parse_verify("verify summary\nnothing"), None)
        self.assertEqual(metrics.parse_verify("  passed clean tree 0.0s"), None)
        self.assertEqual(metrics.parse_verify("verify summary\n  FAILED  clean tree     0.0s\n")["steps"],
                         {"clean tree": ("FAILED", 0.0)})
        self.assertEqual(metrics.role_of("review:netcode:#154"), "netcode-security-reviewer")
        self.assertEqual(metrics.role_of("implement:#5"), "implementer")
        self.assertEqual(metrics.role_of("fix:#154#2"), "pr-rebase fix")
        self.assertEqual(metrics.role_of("research"), "other")
        self.assertEqual(metrics.cmd_kind("cd x && tools\\run.cmd verify"), "verify")
        self.assertEqual(metrics.cmd_kind("gh run watch 12"), "ci-wait")
        self.assertEqual(metrics.parse_time("2026-10-02"), metrics.parse_time("2026-10-02T00:00:00Z"))
        self.assertEqual(metrics.stamp(1790939154860), 1790939154.86)
        with self.assertRaises(Failure):
            metrics.parse_time("yesterday")

    def test_each_v2_agent_label_has_its_role(self) -> None:
        # issue-task v2 (#180) and pr-rebase label their optional agents so; each is a fixture agent of its own run.
        labels = {
            "plan:#21": "planner",
            "review:plan:#21": "plan-reviewer",
            "review:netcode-second:#21": "netcode-second-reviewer",
            "test-review:#21": "test-reviewer",
            "skeptic:#21": "skeptic",
        }
        wf = self.fx.dir / SESSION / "subagents" / "workflows"
        agents = [
            (f"k{i}", f"a-v2-{i}", label, "Review", {"findings": [{"severity": "minor"}]},
             [assistant(60 + i, f"msg-v2-{i}", usage(inp=1, write=100)),
              assistant(61 + i, f"msg-v2b-{i}", usage(inp=1))])
            for i, label in enumerate(labels)
        ]  # fmt: skip
        Fixture.run(wf / "wf_v2", [("k-impl21", "a-impl21", "implement:#21", "Implement", {"x": 1},
                                    [assistant(55, "msg-i21", usage(inp=1))]), *agents])  # fmt: skip
        run = self.runs(self.collect())["wf_v2"]
        for i, (label, role) in enumerate(labels.items()):
            with self.subTest(label=label):
                self.assertEqual(metrics.role_of(label), role)
                self.assertEqual(self.agent(run, f"a-v2-{i}")["role"], role)
        md, _record, _compact = self.build()
        text = "\n".join(md)
        for role in labels.values():
            self.assertIn(f"| {role} |", text)
        reviews = text[text.index("## Review findings by reviewer") :]
        for role in ("plan-reviewer", "netcode-second-reviewer", "test-reviewer"):
            self.assertIn(f"| {role} | 1 | 0 | 0 | 1 |", reviews)

    def test_the_slot_wait_from_the_history_and_from_a_printed_summary(self) -> None:
        waited = "in 271.0s (after 45.0s waiting for a verify slot)"
        printed = metrics.parse_verify(SUMMARY.replace("in 271.0s", waited))
        self.assertEqual((printed["total"], printed["wait"], printed["over"]), (271.0, 45.0, False))
        over = SUMMARY.replace("in 271.0s", "in 271.0s (after 150.0s waiting for a verify slot); it ran OVER THE LIMIT")
        self.assertEqual(metrics.parse_verify(over)["over"], True)
        self.assertEqual(metrics.parse_verify(SUMMARY)["wait"], None)
        path = self.root / "verify-history.jsonl"
        write_lines(path, [
            {"start": "2026-10-02T09:00:00Z", "worktree": "a", "seconds": 250, "slot": {"waited": 30.0, "over": False},
             "steps": [{"name": "lint", "status": "passed", "seconds": 20}]},
            {"start": "2026-10-02T09:10:00Z", "worktree": "b", "seconds": 260, "slot": {"waited": 150.0, "over": True},
             "steps": [{"name": "lint", "status": "passed", "seconds": 20}]},
            {"start": "2026-10-02T09:20:00Z", "worktree": "c", "seconds": 240, "slot": None,
             "steps": [{"name": "lint", "status": "passed", "seconds": 20}]},
        ])  # fmt: skip
        found = metrics.read_history([path], None, metrics.parse_time(UNTIL))
        self.assertEqual([(v["wait"], v["over"]) for v in found], [(30.0, False), (150.0, True), (None, False)])
        md, _record, compact = self.build(history=found)
        line = next(line for line in compact if line.startswith("local verify (history file)"))
        self.assertIn("slot wait median 90 s (max 150), 1 over the limit", line)
        text = "\n".join(md)
        self.assertIn("slot wait (median / max) | over the limit |", text)
        self.assertIn("| 90 / 150 | 1 |", text)

    def test_the_verify_history_file(self) -> None:
        path = self.root / "verify-history.jsonl"
        write_lines(path, [
            {"start": "2026-10-02T09:00:00Z", "worktree": "a", "seconds": 250,
             "steps": [{"name": "lint", "status": "passed", "seconds": 20},
                       {"name": "test", "status": "FAILED", "seconds": 90}]},
            {"start": int(metrics.parse_time("2026-10-02T10:00:00Z")), "worktree": "b",
             "steps": {"lint": {"status": "passed", "seconds": 10}}},
            {"start": "2026-10-02T12:00:00Z", "worktree": "c", "steps": {"lint": {"status": "passed", "seconds": 1}}},
            {"start": "2026-10-02T09:00:00Z", "worktree": "a", "seconds": 250, "steps": {"x": {"status": "passed"}}},
        ])
        found = metrics.read_history([path, path], None, metrics.parse_time(UNTIL))
        self.assertEqual(len(found), 2, "after --until and duplicates left out")
        self.assertEqual((found[0]["status"], found[0]["total"]), ("FAILED", 250.0))
        self.assertEqual((found[1]["status"], found[1]["total"]), ("passed", 10.0))
        md, record, compact = self.build(history=found)
        self.assertEqual(len(record["verifies"]["history file"]), 2)
        self.assertTrue(any(line.startswith("local verify (history file): 2 runs, 1 red") for line in compact))
        # Records older than #273 carry no failing tests or failure lines: nothing to list, and no error.
        self.assertEqual([(v["failed_tests"], v["step_failures"], v["shard_exits"]) for v in found], [([], [], [])] * 2)
        self.assertNotIn("Failing tests of red runs", "\n".join(md))

    def test_a_step_a_fail_fast_run_never_ran_is_neither_a_pass_nor_a_red(self) -> None:
        # #556: verify --fail-fast records the steps it stopped before as "not run"; the run's short total is no
        # verify's length either.
        path = self.root / "verify-history.jsonl"
        write_lines(path, [
            {"start": "2026-10-02T09:00:00Z", "worktree": "a", "seconds": 300,
             "steps": [{"name": "lint", "status": "passed", "seconds": 20},
                       {"name": "test", "status": "passed", "seconds": 90}], "stopped": None},
            {"start": "2026-10-02T09:10:00Z", "worktree": "a", "seconds": 30,
             "steps": [{"name": "lint", "status": "FAILED", "seconds": 25},
                       {"name": "test", "status": "not run", "seconds": 0}],
             "stopped": {"at": "lint", "not_run": ["test"]}},
        ])  # fmt: skip
        found = metrics.read_history([path], None, metrics.parse_time(UNTIL))
        self.assertEqual([v["steps"] for v in found], [{"lint": ("passed", 20.0), "test": ("passed", 90.0)},
                                                       {"lint": ("FAILED", 25.0)}])  # fmt: skip
        self.assertEqual([(v["status"], v["stopped"]) for v in found], [("passed", False), ("FAILED", True)])
        _md, _record, compact = self.build(history=found)
        line = next(line for line in compact if line.startswith("local verify (history file)"))
        self.assertIn("2 runs, 1 red, median 300 s (max 300)", line)
        self.assertIn("test 90", line)

    def test_checks_that_passed_after_godot_crashed_at_exit_are_counted(self) -> None:
        # #449: the history record's `exit_crash` on the check step (#442's loud pass) gives the crash rate over the
        # window's check steps; a run without a check step does not count, and neither does a record older than #449
        # (its check step has no `exit_crash`: it could not show a crash, so it must not lower the rate).
        path = self.root / "verify-history.jsonl"

        def run(minute: int, *, crash: bool | None = False, check: bool = True) -> dict:
            steps = [{"name": "lint", "status": "passed", "seconds": 20}]
            if check:
                steps.append({"name": "check", "status": "passed", "seconds": 28.3,
                              **({} if crash is None else {"exit_crash": crash})})  # fmt: skip
            return {"start": f"2026-10-02T09:{minute:02d}:00Z", "worktree": "a", "seconds": 250, "steps": steps}

        write_lines(path, [run(1, crash=True), run(2), run(3), run(4), run(5, check=False), run(6, crash=None)])
        found = metrics.read_history([path], None, metrics.parse_time(UNTIL))
        self.assertEqual([v["exit_crashes"] for v in found], [["check"], [], [], [], [], []])
        md, record, _compact = self.build(history=found)
        self.assertIn("Godot crashed at exit after a clean project check (#442; history file, check steps recorded "
                      "since #449): 1 of 4 (25.0%).", md)  # fmt: skip
        self.assertEqual(record["verifies"]["history file"][0]["exit_crashes"], ["check"])
        write_lines(path, [run(1, check=False), run(2, crash=None)])
        md, _record, _compact = self.build(history=metrics.read_history([path], None, metrics.parse_time(UNTIL)))
        self.assertFalse(any("crashed at exit" in line for line in md), "no check step with the field: no rate to give")

    def test_a_summary_row_with_a_note_is_still_read(self) -> None:
        # verify's summary names a check that passed after Godot crashed at exit after its seconds (#449).
        text = SUMMARY.replace("  passed  lint         20.0s\n",
                               "  passed  check        28.3s  (Godot crashed at exit, #442)\n")  # fmt: skip
        v = metrics.parse_verify(text)
        self.assertEqual(v["steps"]["check"], ("passed", 28.3))
        self.assertEqual(len(v["steps"]), 4)
        self.assertEqual(v["exit_crashes"], ["check"])
        self.assertEqual(metrics.parse_verify(SUMMARY)["exit_crashes"], [])

    def test_the_failing_tests_and_first_failure_lines_of_red_runs(self) -> None:
        path = self.root / "verify-history.jsonl"
        crashed = {"shard": 2, "rc": 3221225477, "seconds": 12.5, "results": False}

        def red(minute: int, tests: list[dict], shard2: dict, bots: str | None = None) -> dict:
            steps = [{"name": "lint", "status": "passed", "seconds": 20},
                     {"name": "test", "status": "FAILED", "seconds": 90, "failure": f"shard 2: exit {shard2['rc']}",
                      "shards": [{"shard": 1, "rc": 0, "seconds": 80}, shard2], "failed_tests": tests}]  # fmt: skip
            if bots:
                steps.append({"name": "bots-enet", "status": "FAILED", "seconds": 48, "failure": bots})
            return {"start": f"2026-10-02T09:{minute:02d}:00Z", "worktree": "a", "seconds": 250, "steps": steps}

        one = {"test": "a_test::test_one", "message": "Expecting: 1 but was 2"}
        leak = {"test": "b_test::test_b", "orphans": 2}
        correction = "bots_main #{} | a Correction outside a placement (epoch {}, at (1.5, 0, -2))"
        write_lines(path, [
            red(1, [one], {"shard": 2, "rc": 100, "seconds": 70}, correction.format(2, 3)),
            red(2, [one, leak], {"shard": 2, "rc": 101, "seconds": 70}),
            red(3, [], crashed, correction.format(3, 41)),
            # A green run: its shards ended with exit 0 and name no tests.
            {"start": "2026-10-02T09:04:00Z", "worktree": "a", "seconds": 240,
             "steps": [{"name": "test", "status": "passed", "seconds": 90,
                        "shards": [{"shard": 1, "rc": 0, "seconds": 80}, {"shard": 2, "rc": 0, "seconds": 75}]}]},
        ])  # fmt: skip
        found = metrics.read_history([path], None, metrics.parse_time(UNTIL))
        self.assertEqual([v["failed_tests"] for v in found], [[one["test"]], [one["test"], leak["test"]], [], []])
        self.assertEqual(found[2]["shard_exits"], ["exit 3221225477 without results.xml"])
        md, record, _compact = self.build(history=found)
        text = "\n".join(md)
        self.assertIn("| `a_test::test_one` | 2 |", text)
        self.assertIn("| `b_test::test_b` | 1 |", text)
        self.assertIn("| bots-enet | bots_main #N \\| a Correction outside a placement (epoch N, at (N, N, -N)) | 2 |",
                      text)  # fmt: skip
        self.assertIn("| test | shard N: exit N | 3 |", text)
        self.assertIn("exit 100 1, exit 101 1, exit 3221225477 without results.xml 1.", text)
        self.assertEqual(record["verifies"]["history file"][1]["failed_tests"], [one["test"], leak["test"]])
        self.assertEqual(metrics.numbers_as_n("shard 2: GdUnit4 crashed (exit 3221225501); log: test-shard2.log"),
                         "shard N: GdUnit4 crashed (exit N); log: test-shard2.log")  # fmt: skip
        self.assertEqual(metrics.numbers_as_n("shard 12: probe_273_fail_test::test_2_steps (log: test-shard12.log)"),
                         "shard N: probe_273_fail_test::test_2_steps (log: test-shard12.log)")  # fmt: skip

    def test_the_compact_summary(self) -> None:
        ci = {"runs": 3, "by_outcome": {"push success": 3}, "reruns": 0, "queue_s": 0.0, "green": 2,
              "job_s": [360.0, 420.0], "steps": {"verify total": [380.0, 390.0]}}
        md, record, compact = self.build(ci=ci)
        self.assertLessEqual(len(compact), 10)
        self.assertTrue(compact[0].startswith("metrics, the first transcript to 2026-10-02T11:00:00Z: 1 finished"))
        self.assertIn("#5 18 min $", compact[1])
        # The headline is at the central weight whatever the share of cache reads (the fixture's are 1% of list $).
        self.assertIn("% of a Max 20x week: 0.6% with cache reads at 75% of their list $ ($23.0 per 1%); 0.7 to 0.6% "
                      "if the limit counts them at 60 to 100%", compact)  # fmt: skip
        self.assertTrue(any(line.startswith("local verify (agents): 1 runs, 1 red, median 271 s") for line in compact))
        self.assertEqual(compact[-1], "CI: 3 runs in the window; last 2 green: job 6.5 min median, verify 385 s")
        self.assertIn("## CI (GitHub Actions)", md)

    def test_the_percent_of_the_week_and_its_bracket(self) -> None:
        # #307 measured the weight of cache reads (the baseline ADR's #307 amendment): w = 0.75 at $23.0 per 1%, the
        # headline; range 0.6 to 1, the bracket, k(1) full list $.
        self.assertEqual(metrics.WEEK_CENTRAL, (0.75, 23.0))
        self.assertEqual(metrics.WEEK_BRACKET, ((0.6, 21.5), (1.0, 25.5)))
        # The calibration reading (#304): $1,690 list, 40% of it cache reads, was 66% of the week; the headline and
        # both ends of the bracket round to it.
        week = metrics.week_percent(1690.0, 676.0)
        self.assertAlmostEqual(week["percent"], (1690.0 - 676.0 + 0.75 * 676.0) / 23.0, msg="cache reads at 75%")
        self.assertAlmostEqual(week["bracket"][0], (1690.0 - 676.0 + 0.6 * 676.0) / 21.5, msg="cache reads at 60%")
        self.assertAlmostEqual(week["bracket"][1], 1690.0 / 25.5, msg="cache reads at full list $")
        self.assertEqual([round(v) for v in (week["percent"], *week["bracket"])], [66, 66, 66])
        # #307's last reading: 77% at 2026-10-04 05:05 UTC, $1,981.7 list since the restart, $805.3 of it cache reads.
        # The headline rounds to the reading; full list $ reads a point high.
        week = metrics.week_percent(1981.7, 805.3)
        self.assertEqual([round(v) for v in (week["percent"], *week["bracket"])], [77, 77, 78])
        # The probe's 5-hour window to 05:05:30 ($3.51 non-read + $21.77 cache reads, 86% of list $; the ADR's $21.53
        # runs to the last reading at 05:04:57): 0.86% of the week, as the ADR gives it, in a bracket of 0.77 to 0.99%.
        week = metrics.week_percent(25.28, 21.77)
        self.assertEqual([round(v, 2) for v in (week["percent"], *week["bracket"])], [0.86, 0.77, 0.99])
        # The fixture: $14.99 list, $0.21 of it cache reads (Sonnet's 1M at $0.20 and Opus's 56.2k at $0.20 per 1M).
        md, record, _compact = self.build()
        read = 0.20 + (1000 + 1000 + 20000 + 20100 + 5000 + 8000 + 100 + 1000) * 0.20 / 1e6
        self.assertAlmostEqual(record["week"]["read_usd"], read)
        spent = record["week"]["usd"]
        self.assertAlmostEqual(spent, sum(r["usd"] for r in record["runs"]) + 0.00868 + 0.0006)
        self.assertAlmostEqual(record["week"]["percent"], (spent - read + 0.75 * read) / 23.0)
        self.assertAlmostEqual(record["week"]["bracket"][0], (spent - read + 0.6 * read) / 21.5)
        self.assertAlmostEqual(record["week"]["bracket"][1], spent / 25.5)
        session = record["sessions"][0]
        self.assertEqual((session["week_percent"], session["week_bracket"]), (record["week"]["percent"],
                                                                              record["week"]["bracket"]))
        text = "\n".join(md)
        self.assertIn("| 1 | $0.00 | 3 | $15 | 2.03M | 0.6% (0.7 to 0.6%) |", text)
        self.assertIn("workflow subagents together, (list $ without cache reads + 0.75 x cache-read $) / $23.0 per 1%, "
                      "the limit counting cache reads at 75% of their list $ (#307's central weight); in brackets, at "
                      "60 to 100% ((list $ without cache reads + 0.6 or 1 x cache-read $) / $21.5 or $25.5).",
                      text)  # fmt: skip

    def test_ci_from_gh(self) -> None:
        listed = [
            {"databaseId": 1, "event": "push", "conclusion": "success", "createdAt": "2026-10-02T09:00:00Z",
             "startedAt": "2026-10-02T09:00:05Z", "attempt": 1},
            {"databaseId": 2, "event": "pull_request", "conclusion": "failure", "createdAt": "2026-10-02T09:10:00Z",
             "startedAt": "2026-10-02T09:10:00Z", "attempt": 2},
            {"databaseId": 3, "event": "push", "conclusion": "success", "createdAt": "2026-10-02T12:00:00Z",
             "startedAt": "2026-10-02T12:00:00Z", "attempt": 1},
        ]
        prefix = "verify\tRun\t2026-10-02T09:05:00.1234567Z "  # gh run view --log: job, step, time, then the line
        log = prefix + SUMMARY.replace("\n", "\n" + prefix)

        def gh(args: list[str]) -> str:
            if args[:2] == ["run", "list"]:
                self.assertEqual(args[2:4], ["--workflow", "ci.yml"], "only the verify workflow, not a nightly one")
                return json.dumps(listed)
            if "--log" in args:
                return log
            # Two jobs (verify in two lanes): the run's job time spans both.
            return json.dumps({"jobs": [{"startedAt": "2026-10-02T09:00:05Z", "completedAt": "2026-10-02T09:04:05Z"},
                                        {"startedAt": "2026-10-02T09:00:10Z", "completedAt": "2026-10-02T09:06:05Z"}]})

        ci = metrics.ci_data(None, metrics.parse_time(UNTIL), 12, gh)
        self.assertEqual((ci["runs"], ci["green"], ci["reruns"]), (2, 1, 1))
        self.assertFalse(ci["cut"])
        self.assertEqual(ci["job_s"], [360.0])
        self.assertEqual(ci["steps"]["test"], [100.0])
        self.assertEqual(ci["steps"]["verify total"], [271.0])

    def test_main_writes_the_report_and_names_the_session(self) -> None:
        out = self.root / "out"
        printed = io.StringIO()
        with redirect_stdout(printed):
            rc = metrics.main(
                [f"{SESSION[:4]}=M9"], until=UNTIL, out=str(out), compact=True, dirs=[self.fx.dir], history=[],
                gh=EMPTY_GH,
            )
        self.assertEqual(rc, 0)
        record = json.loads((out / "metrics.json").read_text(encoding="utf-8"))
        self.assertEqual(record["sessions"][0]["label"], "M9")
        self.assertEqual(record["tasks"][0]["session"], "M9")
        self.assertIn("## Per finished issue-task run", (out / "metrics.md").read_text(encoding="utf-8"))
        self.assertNotIn("## Per finished issue-task run", printed.getvalue())
        self.assertNotIn("metrics: wrote", printed.getvalue(), "--compact prints only the summary")
        self.assertLessEqual(len(printed.getvalue().strip().splitlines()), 10)

    def test_no_transcripts_says_so_and_passes(self) -> None:
        out = self.root / "none"
        printed = io.StringIO()
        with redirect_stdout(printed):
            self.assertEqual(metrics.main(until=UNTIL, out=str(out), dirs=[], history=[], gh=no_gh), 0)
            self.assertEqual(
                metrics.main(["0000"], until=UNTIL, out=str(out), dirs=[self.fx.dir], history=[], gh=no_gh), 0
            )
        self.assertIn("no Claude Code transcripts of this checkout", printed.getvalue())
        self.assertFalse(out.exists())
        with self.assertRaises(Failure):
            metrics.main(since=UNTIL, until=UNTIL, dirs=[], history=[])
        with self.assertRaises(Failure):
            metrics.main(until=UNTIL, ci=-1, dirs=[], history=[])

    def test_an_empty_window_says_so_and_replaces_an_older_report(self) -> None:
        out = self.root / "out"
        with redirect_stdout(io.StringIO()):
            metrics.main(until=UNTIL, out=str(out), dirs=[self.fx.dir], history=[], gh=EMPTY_GH)
        self.assertIn("## Per finished issue-task run", (out / "metrics.md").read_text(encoding="utf-8"))
        printed = io.StringIO()
        with redirect_stdout(printed):
            rc = metrics.main(since="2026-10-01T00:00:00Z", until="2026-10-01T12:00:00Z", out=str(out),
                              dirs=[self.fx.dir], history=[], gh=no_gh)
        self.assertEqual(rc, 0)
        self.assertIn("metrics: nothing in the window 2026-10-01T00:00:00Z to 2026-10-01T12:00:00Z", printed.getvalue())
        self.assertNotIn("no Claude Code transcripts", printed.getvalue())
        self.assertNotIn("## Per finished issue-task run", (out / "metrics.md").read_text(encoding="utf-8"))
        self.assertEqual(json.loads((out / "metrics.json").read_text(encoding="utf-8"))["tasks"], [])

    def test_one_label_for_two_sessions_is_one_stage(self) -> None:
        other = self.fx.dir / "22222222-0000" / "subagents" / "workflows" / "wf_done"
        shutil.copytree(self.fx.dir / SESSION / "subagents" / "workflows" / "wf_done", other)
        data = self.collect(sessions={"1111": "M9", "2222": "M9"})
        _md, record, _compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        self.assertEqual([(s["session"], s["runs"]) for s in record["stages"]], [("M9", 2)])
        self.assertEqual([(m["label"], m["runs"]) for m in record["sessions"]], [("M9", 3), ("M9", 1)])

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(
            ["metrics", "--session", "aa", "bb", "--session", "cc=M4", "--until", UNTIL, "--ci", "12", "--compact"]
        )
        self.assertEqual(args.session, ["aa", "bb", "cc=M4"])
        self.assertEqual(metrics.session_filter(args.session), {"aa": None, "bb": None, "cc": "M4"})
        self.assertEqual((args.ci, args.compact, args.out), (12, True, None))


def background(tool_id: str, command: str, name: str = "Bash", timeout: int | None = 3_300_000) -> dict:
    inp: dict = {"command": command, "run_in_background": True}
    if timeout is not None:
        inp["timeout"] = timeout
    return {"id": tool_id, "name": name, "input": inp}


def notification(minutes: float, tool_id: str) -> dict:
    """A background task's end, as Claude Code queues it for the session."""
    content = (f"<task-notification>\n<task-id>x{tool_id}</task-id>\n<tool-use-id>{tool_id}</tool-use-id>\n"
               "<status>completed</status>\n</task-notification>")  # fmt: skip
    return {"type": "queue-operation", "operation": "enqueue", "timestamp": at(minutes), "content": content}


class ManagerRewriteTest(unittest.TestCase):
    """#305: a manager's cache re-writes after an idle gap over 1 hour, by what held when the gap began."""

    SID = "33333333-0000-0000-0000-000000000000"
    UNTIL = "2026-10-02T18:00:00Z"

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "projects" / "D--prime-game"
        run = self.dir / self.SID / "subagents" / "workflows" / "wf_run"
        Fixture.run(run, [("k-i", "a-i", "implement:#12", "Implement", {"verify_green": True}, [
            assistant(4, "w1", usage(inp=1, write=100)),
            assistant(100, "w2", usage(inp=1, read=100)),
        ])])

        def h(write: int = 0, read: int = 0) -> dict:  # the manager's calls write 1-hour cache entries
            return usage(inp=1, write=write, read=read, out=10, write_1h=write)

        write_lines(self.dir / f"{self.SID}.jsonl", [
            assistant(0, "m1", h(write=200_000)),
            assistant(5, "m2", h(read=200_000)),
            # 75 minutes idle while its run (minutes 4 to 100) works: a re-write with a run in flight.
            assistant(80, "m3", h(write=210_000)),
            assistant(81, "m4", h(read=210_000), tool=background("k1", "sleep 3000")),
            tool_result(81.2, "k1", "Command running in background"),
            assistant(81.5, "m5", h(read=210_000)),
            notification(131, "k1"),
            # The timer woke it after 50 minutes: the cache was still warm; it re-arms.
            assistant(131.1, "m6", h(read=210_000), tool=background("k2", 'sleep 3000; echo "keep-alive"')),
            tool_result(131.3, "k2", "Command running in background"),
            assistant(131.5, "m7", h(read=210_000)),
            # k2 never wakes it (the sleep died with no notification): 90 minutes idle with a timer armed.
            assistant(221.5, "m8", h(write=220_000)),
            # Not a timer: the sleep is part of another command.
            assistant(222, "m9", h(read=220_000), tool=background("k3", "sleep 30; gh pr checks 9 --watch")),
            tool_result(222.1, "k3", "Command running in background"),
            notification(223, "k3"),
            assistant(223.5, "m10", h(read=220_000)),
            # 120 minutes idle at a stop for the human, nothing armed.
            assistant(343.5, "m11", h(write=230_000)),
            assistant(344, "m12", h(read=230_000),
                      tool=background("k4", "Start-Sleep -Seconds 3000", name="PowerShell", timeout=None)),
            tool_result(344.1, "k4", "Command running in background"),
            notification(374, "k4"),  # its default 30-minute timeout stopped it: it still woke the session
            assistant(374.2, "m13", h(read=230_000)),
            # Over an hour idle, but the cache held (a read): not a re-write.
            assistant(440, "m14", h(read=230_000, write=1000)),
            # A re-write after under an hour: not one of these.
            assistant(490, "m15", h(write=240_000)),
        ])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_timers_are_armed_until_their_notification_or_their_seconds(self) -> None:
        until = metrics.parse_time(self.UNTIL)
        manager = metrics.collect([self.dir], {}, None, until)["sessions"][0]["manager"]
        t0 = metrics.parse_time(at(0))
        self.assertEqual([(round((a - t0) / 60, 1), round((b - t0) / 60, 1)) for a, b in manager["timers"]],
                         [(81.0, 131.0), (131.1, 181.1), (344.0, 374.0)])  # fmt: skip

    def test_the_rewrites_by_what_held_when_the_gap_began(self) -> None:
        until = metrics.parse_time(self.UNTIL)
        md, record, _compact = metrics.build(metrics.collect([self.dir], {}, None, until), [], None, None, until)
        row = record["manager_rewrites"][0]
        self.assertEqual((row["label"], row["rewrites"], row["tokens"]), ("33333333", 3, 660_000))
        self.assertAlmostEqual(row["usd"], 660_000 * 8.0 / 1e6, msg="1-hour cache writes at Opus 5.5's $8 per 1M")
        self.assertEqual([(f["while"], f["tokens"], round(f["idle_hours"], 2)) for f in row["found"]],
                         [("run", 210_000, 1.25), ("timer", 220_000, 1.5), ("stop", 230_000, 2.0)])  # fmt: skip
        self.assertEqual(row["found"][0]["at"], "2026-10-02T09:20:00Z")
        self.assertEqual({k: row[k]["rewrites"] for k in metrics.REWRITE_KINDS}, {"timer": 1, "run": 1, "stop": 1})
        self.assertAlmostEqual(row["timer"]["usd"], 220_000 * 8.0 / 1e6)
        self.assertEqual((row["timers"], row["last_ctx"]), (3, 1 + 240_000 + 10))
        text = "\n".join(md)
        self.assertIn("## Manager cache re-writes after an idle gap over 1 hour (#305)", text)
        self.assertIn("| 33333333 | 3 | 0.66M | $5.28 | 1 ($1.76) | 1 ($1.68) | 1 ($1.84) | 3 | 0.24M |", text)

    def test_a_window_counts_only_its_own_gaps(self) -> None:
        until = metrics.parse_time(self.UNTIL)
        since = metrics.parse_time(at(200))
        data = metrics.collect([self.dir], {self.SID[:8]: "M"}, since, until)
        _md, record, _compact = metrics.build(data, [], None, since, until)
        row = record["manager_rewrites"][0]
        self.assertEqual([f["while"] for f in row["found"]], ["stop"], "the gap before 221.5 began before --since")
        self.assertEqual(row["timers"], 1)

    def lone_timer(self) -> Path:
        """A second manager whose only timer has no timeout and never sends a notification."""
        other = Path(self.tmp.name) / "lone" / "projects" / "D--prime-game"
        h = usage(inp=1, write=200_000, out=10, write_1h=200_000)
        write_lines(other / "44444444-0000-0000-0000-000000000000.jsonl", [
            assistant(0, "n1", h),
            assistant(1, "n2", usage(inp=1, read=200_000), tool=background("k5", "sleep 3000", timeout=None)),
            tool_result(1.1, "k5", "Command running in background"),
            assistant(2, "n3", usage(inp=1, read=200_000)),
            # 98 minutes idle from minute 2, while k5 was armed (minutes 1 to 31).
            assistant(100, "n4", h),
        ])  # fmt: skip
        return other

    def test_a_timer_with_no_timeout_ends_after_the_default_30_minutes(self) -> None:
        until = metrics.parse_time(self.UNTIL)
        manager = metrics.collect([self.lone_timer()], {"44444444": "L"}, None, until)["sessions"][0]["manager"]
        t0 = metrics.parse_time(at(0))
        self.assertEqual([(round((a - t0) / 60, 1), round((b - t0) / 60, 1)) for a, b in manager["timers"]],
                         [(1.0, 31.0)], "min(its 3000 seconds, the 1800-second default timeout)")  # fmt: skip

    def test_a_timer_armed_before_the_window_still_holds_in_it(self) -> None:
        until = metrics.parse_time(self.UNTIL)
        since = metrics.parse_time(at(1.5))
        data = metrics.collect([self.lone_timer()], {"44444444": "L"}, since, until)
        _md, record, _compact = metrics.build(data, [], None, since, until)
        row = record["manager_rewrites"][0]
        self.assertEqual([f["while"] for f in row["found"]], ["timer"], "k5 was armed when the gap began")
        self.assertEqual(row["timers"], 0, "the count is of the timers armed in the window")


SONNET = "claude-sonnet-5-5"
REPO = "https://github.com/o/r/pull/"


def gh_stub(github: dict, calls: list | None = None):
    """A stand-in for `gh` serving the PR, CI run and issue lists of `github`."""

    def gh(args: list[str]) -> str:
        if calls is not None:
            calls.append(args)
        for prefix, key in ((["pr", "list"], "prs"), (["run", "list"], "runs"), (["issue", "list"], "issues")):
            if args[:2] == prefix:
                return json.dumps(github[key])
        raise AssertionError(f"unexpected gh call: {args}")

    return gh


def no_gh(args: list[str]) -> str:
    raise AssertionError(f"gh was called: {args}")


EMPTY_GH = gh_stub({"prs": [], "runs": [], "issues": []})


def ci_run(branch: str, sha: str, conclusion: str, minutes: float, event: str = "pull_request") -> dict:
    return {"databaseId": hash((branch, sha, minutes)) % 10**6, "event": event, "headBranch": branch, "headSha": sha,
            "conclusion": conclusion, "createdAt": at(minutes), "attempt": 1}  # fmt: skip


def pull(number: int, branch: str, minutes: float, title: str = "feat(tooling): a change", body: str = "",
         state: str = "OPEN") -> dict:  # fmt: skip
    return {"number": number, "url": f"{REPO}{number}", "title": title, "body": body, "headRefName": branch,
            "state": state, "createdAt": at(minutes), "mergedAt": at(170) if state == "MERGED" else None}  # fmt: skip


def new_pub(number: int, url: str | None = None, **extra: object) -> dict:
    """The publisher's result in the current shape (issue-task.js PUB)."""
    return {"published": True, "handoff_posted": True, "pr_number": number, "pr_url": url or f"{REPO}{number}",
            "ci_green": True, "fixed": [], "not_fixed": [], "needs_engineer": [], **extra}  # fmt: skip


class QualityTest(unittest.TestCase):
    """#314: the quality scorecard per finished issue-task run, from fixture journals and a stand-in for `gh`.

    wf_a #31 (minutes 0-30), the current shapes: a major and a minor from the code review, a godot-api check on Sonnet
             at effort medium, a skeptic that refuted the major, a publisher retried once (an Opus attempt that died
             after one publish, then Sonnet with one more) that opened PR 41 (merged): first CI round red, a red round
             after the run, a Found-by follow-up issue, a fix-up PR and a GitHub revert.
    wf_b #32 (40-60), an older shape: a blocker no skeptic checked, a publisher result with only pr_url and `green`;
             PR 42: a cancelled run, then green on its first round, red after the run.
    wf_c #33 (62-80): no PR (published false).
    wf_d #34 (82-100): a PR in another repository, and no diff reviewer.
    wf_e #35 (102-120): PR 43, its only CI run still pending.
    wf_f #31 (122-140): a fresh relaunch of #31 that ends on the same PR 41.
    """

    SID = "55555555-0000-0000-0000-000000000000"
    GITHUB = {
        "prs": [
            pull(41, "tooling/31-a", 17, title="feat(tooling): a (#31)", body="Closes #31", state="MERGED"),
            pull(42, "tooling/32-b", 55),
            pull(43, "tooling/35-e", 115),
            pull(40, "tooling/90-old", 5, title="fix(tooling): older", body="#41"),  # before PR 41: not a fix-up
            pull(50, "tooling/99-x", 150, title="fix(tooling): a regression", body="a regression from #41"),
            pull(51, "tooling/98-y", 151, title="feat: builds on #41"),  # not a fix
            pull(52, "tooling/97-z", 152, title="fix(x): another", body="Found by: #31's implementer (PR #41)"),
            pull(53, "tooling/31-c", 153, title="fix(tooling): own", body="#31"),  # the task's own branch
            pull(54, "revert-41-tooling/31-a", 154, title='Revert "feat(tooling): a"', body="Reverts o/r#41"),
            pull(55, "tooling/96-q", 155, title="fix: unrelated", body="see #410 and o/other#41"),
            # Sibling PRs listed as a matter of course, and a PR cited as context: not fix-ups of 41.
            pull(56, "tooling/95-r", 156, title="fix(bots): a stall",
                 body="## Summary\nThe bots stall.\n\n## Verification\nmerge-check: no regression against #41.\n\n"
                      "## Merge order\nIndependent of #41 and #42, which broke nothing here."),
            pull(57, "tooling/94-s", 157, title="fix(tests): a flaky test", body="PR #41's test was flaky. Fixed."),
        ],
        "runs": [
            ci_run("tooling/31-a", "sha1", "failure", 18),
            ci_run("tooling/31-a", "sha1", "cancelled", 18.5),
            ci_run("tooling/31-a", "sha2", "success", 25),
            ci_run("tooling/31-a", "sha3", "failure", 145),  # after both #31 runs ended
            ci_run("tooling/31-a", "sha4", "success", 147),
            ci_run("main", "sha9", "failure", 20, event="push"),
            ci_run("tooling/32-b", "sha0", "cancelled", 55.5),
            ci_run("tooling/32-b", "sha5", "success", 56),
            ci_run("tooling/32-b", "sha6", "timed_out", 70),  # after wf_b ended
            ci_run("tooling/35-e", "sha7", "", 116),
        ],
        "issues": [
            {"number": 60, "title": "a bug", "body": "Found by: #31's publisher (PR #41).", "createdAt": at(150)},
            {"number": 61, "title": "a note", "body": "see #41 for context", "createdAt": at(151)},
            {"number": 62, "title": "drift", "body": "Found by: night-audit docs (#410)", "createdAt": at(152)},
        ],
    }

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "projects" / "D--prime-game"
        wf = self.dir / self.SID / "subagents" / "workflows"
        lines = self.lines
        review = "Review"

        def implement(n: int, start: float) -> tuple:
            return (f"k-i{n}", f"a-i{start:g}", f"implement:#{n}", "Implement", {"verify_green": True},
                    lines(f"i{start:g}", start, start + 8))  # fmt: skip

        def code(n: int, start: float, findings: list[dict]) -> tuple:
            return (f"k-c{n}", f"a-c{start:g}", f"review:code:#{n}", review, {"findings": findings},
                    lines(f"c{start:g}", start, start + 2))  # fmt: skip

        def publish(n: int, start: float, end: float, result: dict | None, *, model: str = "claude-opus-5-5",
                    publishes: int = 1, aid: str = "") -> tuple:  # fmt: skip
            return (f"k-p{n}", aid or f"a-p{start:g}", f"publish:#{n}", "Publish", result,
                    lines(f"p{start:g}", start, end, model=model, publishes=publishes))  # fmt: skip

        major = [{"severity": "major", "problem": "p"}, {"severity": "minor", "problem": "q"}]
        Fixture.run(wf / "wf_a", [
            implement(31, 0),
            code(31, 9, major),
            ("k-g31", "a-g31", "review:godot-api:#31", review, {"findings": []},
             lines("g31", 9, 10, model=SONNET, effort="medium")),
            ("k-s31", "a-s31", "skeptic:#31", review, {"refuted": True, "reason": "handled", "evidence": "x.py:1"},
             lines("s31", 12, 13)),
            publish(31, 14, 16, None, aid="a-p-dead"),  # its first attempt died after one publish
            publish(31, 17, 30, new_pub(41, fixed=["a", "b"], not_fixed=["c"]), model=SONNET),
        ])  # fmt: skip
        Fixture.run(wf / "wf_b", [
            implement(32, 40),
            code(32, 49, [{"severity": "Blocker", "problem": "p"}]),
            publish(32, 52, 60, {"published": True, "green": True, "pr_url": f"{REPO}42"}),
        ])
        Fixture.run(wf / "wf_c", [
            implement(33, 62),
            code(33, 71, []),
            publish(33, 74, 80, {"published": False, "handoff_posted": True, "not_fixed": ["x"]}, publishes=0),
        ])
        Fixture.run(wf / "wf_d", [
            implement(34, 82),
            publish(34, 91, 100, new_pub(41, url="https://github.com/o/other/pull/41")),
        ])
        Fixture.run(wf / "wf_e", [implement(35, 102), code(35, 111, []), publish(35, 114, 120, new_pub(43))])
        Fixture.run(wf / "wf_f", [implement(31, 122), code(31, 131, []), publish(31, 134, 140, new_pub(41))])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def lines(tag: str, start: float, end: float, *, model: str = "claude-opus-5-5", effort: str = "high",
              publishes: int = 0) -> list[dict]:  # fmt: skip
        """An agent's transcript from start to end (minutes), with `publishes` publish calls run as bounded waits do."""
        out = [assistant(start, f"{tag}-1", usage(inp=1, write=1000, out=10), model=model, effort=effort)]
        for i in range(publishes):
            t = start + (end - start) * (i + 1) / (publishes + 2)
            cmd = f'tools/run.sh publish > a/publish-{i}.log 2>&1; echo "exit=$?" >> a/publish-{i}.log'
            out += [assistant(t, f"{tag}-p{i}", usage(inp=1, read=1000, out=10), model=model, effort=effort,
                              tool=bash(f"{tag}-t{i}", cmd)),
                    assistant(t + 0.1, f"{tag}-w{i}", usage(inp=1, read=1000, out=10), model=model, effort=effort,
                              tool=bash(f"{tag}-u{i}", f"tools/run.sh wait a/publish-{i}.log")),
                    tool_result(t + 0.2, f"{tag}-t{i}"), tool_result(t + 0.3, f"{tag}-u{i}")]  # fmt: skip
        out.append(assistant(end, f"{tag}-2", usage(inp=1, read=1000, out=10), model=model, effort=effort))
        return out

    def build(self, github: dict | None = None) -> tuple[list[str], dict, list[str]]:
        until = metrics.parse_time(UNTIL)
        data = metrics.collect([self.dir], {}, None, until)
        return metrics.build(data, [], None, None, until, github=github)

    def rows(self, github: dict | None = None) -> dict[str, dict]:
        return {q["wf"]: q for q in self.build(github)[1]["quality"]["tasks"]}

    def github(self) -> dict:
        return metrics.read_github(gh_stub(self.GITHUB))

    def test_quality_journal_signals_new_and_old_shapes(self) -> None:
        rows = self.rows()
        self.assertEqual(list(rows), ["wf_a", "wf_b", "wf_c", "wf_d", "wf_e", "wf_f"])
        a = rows["wf_a"]
        self.assertEqual((a["issue"], a["pr"], a["pr_url"]), (31, 41, f"{REPO}41"))
        self.assertEqual(a["findings"], {"major": 1, "minor": 1})
        self.assertEqual((a["serious"], a["checked"], a["refuted"], a["open"], a["clean"]), (1, 1, 1, 0, True))
        self.assertEqual((a["fixed"], a["not_fixed"], a["needs_engineer"]), (2, 1, 0))
        self.assertEqual((a["publish_runs"], a["fix_rounds"]), (2, 1), "both attempts of the retried publisher")
        self.assertEqual(a["settings"]["publisher"], {"model": SONNET, "effort": "high"})
        self.assertEqual(a["settings"]["godot-api-checker"], {"model": SONNET, "effort": "medium"})
        b = rows["wf_b"]
        self.assertEqual((b["pr"], b["serious"], b["open"], b["clean"]), (42, 1, 1, False), "pr from pr_url")
        self.assertEqual((b["checked"], b["refuted"]), (None, None), "no skeptic ran: unknown, not 0")
        self.assertEqual((b["fixed"], b["not_fixed"], b["needs_engineer"]), (None, None, None), "an older shape")
        c = rows["wf_c"]
        self.assertEqual((c["pr"], c["serious"], c["checked"], c["refuted"]), (None, 0, 0, 0))
        self.assertEqual((c["not_fixed"], c["publish_runs"], c["fix_rounds"]), (1, 0, 0))
        d = rows["wf_d"]
        self.assertEqual((d["serious"], d["open"], d["clean"]), (None, None, None), "no diff reviewer")
        # The first fixture's publisher result has only pr_number and ci_green: no list is read as 0.
        with tempfile.TemporaryDirectory() as tmp:
            fx = Fixture(Path(tmp))
            data = metrics.collect([fx.dir], {}, None, metrics.parse_time(UNTIL))
            done = next(r for r in data["runs"] if r["wf"] == "wf_done")
            q = metrics.quality_of(done)
        self.assertEqual((q["pr"], q["fixed"], q["not_fixed"], q["serious"]), (9, None, None, 1))

    def test_a_design_run_is_never_clean(self) -> None:
        # #315's publish_clean is false for a design task: issue-task.js says so in its implementer's prompt.
        prompt = {"type": "user", "timestamp": at(142),
                  "message": {"role": "user", "content": "Task: #36. This is a DESIGN task: documents only (...)."}}
        wf = self.dir / self.SID / "subagents" / "workflows" / "wf_g"
        Fixture.run(wf, [
            ("k-i36", "a-i36", "implement:#36", "Implement", {"verify_green": True},
             [prompt, *self.lines("i36", 142, 150)]),
            ("k-c36", "a-c36", "review:code:#36", "Review", {"findings": []}, self.lines("c36", 151, 152)),
            ("k-p36", "a-p36", "publish:#36", "Publish", new_pub(44), self.lines("p36", 153, 158, model=SONNET)),
        ])  # fmt: skip
        _md, record, _compact = self.build()
        rows = {q["wf"]: q for q in record["quality"]["tasks"]}
        g = rows["wf_g"]
        self.assertEqual((g["design"], g["open"], g["clean"]), (True, 0, False))
        self.assertEqual((rows["wf_e"]["design"], rows["wf_e"]["clean"]), (False, True))
        clean_sonnet = next(s for s in record["quality"]["settings"]
                            if s["role"] == "publisher (clean run)" and s["model"] == SONNET)
        self.assertEqual(clean_sonnet["runs"], 1, "wf_a's only: the design run's Sonnet publisher is not a clean run's")

    def test_a_pr_without_a_url_is_the_same_pr(self) -> None:
        # A relaunch of #31 whose publisher result has pr_number only: PR 41 of o/r still, counted once.
        wf = self.dir / self.SID / "subagents" / "workflows" / "wf_h"
        Fixture.run(wf, [
            ("k-i31", "a-i142", "implement:#31", "Implement", {"verify_green": True}, self.lines("i142", 142, 150)),
            ("k-p31", "a-p151", "publish:#31", "Publish", {"published": True, "pr_number": 41},
             self.lines("p151", 151, 158)),
        ])  # fmt: skip
        _md, record, _compact = self.build(self.github())
        rows = {q["wf"]: q for q in record["quality"]["tasks"]}
        self.assertEqual((rows["wf_h"]["pr"], rows["wf_h"]["repo"]), (41, "o/r"))
        self.assertEqual(rows["wf_d"]["repo"], "o/other")
        session = record["quality"]["sessions"][0]
        self.assertEqual((session["tasks"], session["prs"]), (7, 4), "41 (three runs), 42, 43 and o/other's 41")

    def test_quality_without_github_is_unknown_not_zero(self) -> None:
        md, record, compact = self.build()
        for wf, q in ((q["wf"], q) for q in record["quality"]["tasks"]):
            for key in ("merged", "ci_red_rounds", "ci_red_after_run", "green_first", "followups", "fixups"):
                with self.subTest(wf=wf, key=key):
                    self.assertIsNone(q[key])
        self.assertEqual(record["quality"]["github"], {"skipped": "not read"})
        self.assertIsNone(json.loads(json.dumps(record["quality"]))["tasks"][0]["ci_red_rounds"])
        text = "\n".join(md)
        section = text[text.index("## Quality per finished issue-task run (#314)"):]
        row = next(line for line in section.splitlines() if line.startswith("| 55555555 | #31 | 41 |"))
        self.assertEqual(row.split(" | ")[3], "?", "merged is unknown")
        self.assertIn("GitHub was not read", section)
        total = record["quality"]["all"]
        self.assertEqual((total["ci_red_rounds"]["known"], total["green_known"]), (0, 0))
        self.assertIsNone(total["usd_per_green_first"])
        line = next(x for x in compact if x.startswith("quality: "))
        self.assertIn("GitHub: not read", line)
        self.assertNotIn("per PR green", line)

    def test_quality_from_github(self) -> None:
        calls: list = []
        github = metrics.read_github(gh_stub(self.GITHUB, calls))
        self.assertEqual([c[:2] for c in calls], [["pr", "list"], ["run", "list"], ["issue", "list"]])
        self.assertIn("all", calls[0])
        self.assertEqual(calls[1][2:4], ["--workflow", "ci.yml"])
        rows = self.rows(github)
        a = rows["wf_a"]
        self.assertEqual((a["merged"], a["ci_runs"], a["ci_red_rounds"], a["ci_red_after_run"]), (True, 5, 2, 1),
                         "sha1 and sha3 red; the cancelled sha1 run adds nothing; the push to main is not the PR's")
        self.assertEqual((a["green_first"], a["ci_last"]), (False, "success"))
        self.assertEqual(a["followups"], [60])
        self.assertEqual(a["fixups"], [50, 54], "the revert names o/r#41; 40, 51, 52, 53, 55, 56, 57 are not fix-ups")
        b = rows["wf_b"]
        self.assertEqual((b["merged"], b["ci_red_rounds"], b["ci_red_after_run"]), (False, 1, 1))
        self.assertTrue(b["green_first"], "a cancelled round is skipped; a later red does not undo the first green")
        self.assertEqual((b["followups"], b["fixups"]), ([], []))
        e = rows["wf_e"]
        self.assertEqual((e["ci_red_rounds"], e["green_first"], e["ci_last"]), (0, None, "pending"))
        for wf in ("wf_c", "wf_d"):  # no PR; a PR of another repository
            for key in ("merged", "ci_red_rounds", "green_first", "followups", "fixups"):
                with self.subTest(wf=wf, key=key):
                    self.assertIsNone(rows[wf][key])

    def test_a_cut_list_or_a_failed_read_is_unknown(self) -> None:
        github = self.github()
        github["runs_from"] = metrics.parse_time(at(100))  # the run list was cut: it starts after PR 41 and 42
        rows = self.rows(github)
        self.assertEqual((rows["wf_a"]["ci_red_rounds"], rows["wf_a"]["merged"]), (None, True))
        self.assertEqual(rows["wf_e"]["ci_red_rounds"], 0)
        _md, record, compact = self.build({"error": "gh pr list failed: offline"})
        self.assertIsNone(record["quality"]["tasks"][0]["merged"])
        self.assertEqual(record["quality"]["github"], {"error": "gh pr list failed: offline"})
        self.assertIn("GitHub: not read (gh failed)", next(x for x in compact if x.startswith("quality: ")))

    def test_quality_medians_per_session_and_role_setting(self) -> None:
        md, record, _compact = self.build(self.github())
        quality = record["quality"]
        session = quality["sessions"][0]
        self.assertEqual((session["session"], session["tasks"]), ("55555555", 6))
        self.assertEqual(session["not_fixed"], {"median": 0, "known": 5, "of": 6}, "wf_b's older shape is unknown")
        self.assertEqual(session["serious"], {"median": 0, "known": 5, "of": 6})
        # Per PR, once each: 41 (two runs), 42, 43 and the other repository's 41; wf_c has no PR to count.
        self.assertEqual(session["ci_red_rounds"], {"median": 1, "known": 3, "of": 4})
        self.assertEqual((session["prs"], session["merged"], session["green_first"], session["green_known"]),
                         (4, 1, 1, 2))  # fmt: skip
        self.assertEqual((session["followups"], session["fixups"]), ([60], [50, 54]))
        spent = sum(q["usd"] for q in quality["tasks"])
        self.assertAlmostEqual(session["usd_per_green_first"], spent / 1)
        self.assertEqual(quality["all"]["tasks"], 6)
        settings = {(s["role"], s["model"], s["effort"]): s for s in quality["settings"]}
        self.assertEqual(settings[("publisher", SONNET, "high")]["agents"], 1)
        self.assertEqual(settings[("publisher", "claude-opus-5-5", "high")]["agents"], 6, "a-p-dead and 5 others")
        clean = settings[("publisher (clean run)", SONNET, "high")]
        self.assertEqual((clean["agents"], clean["runs"]), (1, 1), "only wf_a's Sonnet publisher")
        self.assertEqual(settings[("publisher (clean run)", "claude-opus-5-5", "high")]["agents"], 4,
                         "wf_a's dead attempt, wf_c, wf_e and wf_f: wf_b's blocker stood, wf_d's is unknown")
        godot = settings[("godot-api-checker", SONNET, "medium")]
        self.assertEqual((godot["agents"], godot["serious"]["median"]), (1, 1))
        text = "\n".join(md)
        self.assertIn("## Quality per finished issue-task run (#314)", text)
        self.assertLess(text.index("## Review findings by reviewer"), text.index("## Quality per finished"))
        self.assertIn("| 55555555 | 6 | 4 (1 merged) |", text)
        self.assertIn("| publisher (clean run) | claude-sonnet-5-5 | high | 1 | 1 |", text)

    def test_a_first_round_re_run_to_green_is_unknown(self) -> None:
        # `gh run list` shows a re-run's last attempt only: a first round re-run to green may have been red.
        github = self.github()
        for r in github["runs"]:
            if r["headSha"] in ("sha5", "sha1"):  # 42's first round (green), 41's first round (red)
                r["attempt"] = 2
        rows = self.rows(github)
        self.assertEqual((rows["wf_b"]["green_first"], rows["wf_b"]["ci_reruns"]), (None, 1))
        self.assertEqual((rows["wf_a"]["green_first"], rows["wf_a"]["ci_reruns"]), (False, 1), "red is red anyway")
        self.assertEqual((rows["wf_e"]["green_first"], rows["wf_e"]["ci_reruns"]), (None, 0))

    def test_none_green_on_the_first_round_is_not_unknown(self) -> None:
        github = self.github()
        github["runs"] = [r for r in github["runs"] if r["headSha"] not in ("sha5", "sha0")]  # 42's first round red
        _md, record, compact = self.build(github)
        total = record["quality"]["all"]
        self.assertEqual((total["green_first"], total["green_known"], total["usd_per_green_first"]), (0, 2, None))
        line = next(x for x in compact if x.startswith("quality: "))
        self.assertIn("none of 2 PRs green on their first CI round", line)

    def test_follow_ups_and_fix_ups_are_unknown_when_no_pr_is_found(self) -> None:
        _md, record, compact = self.build(metrics.read_github(EMPTY_GH))
        self.assertIsNone(record["quality"]["all"]["followups"])
        line = next(x for x in compact if x.startswith("quality: "))
        self.assertIn("Found-by follow-ups ?, fix-up PRs ?", line, "no PR in the list: unknown, not 0")

    def test_the_compact_quality_line(self) -> None:
        _md, _record, compact = self.build(self.github())
        line = next(x for x in compact if x.startswith("quality: "))
        self.assertEqual(compact.index(line), 3, "right after the task medians")
        self.assertIn("6 tasks, 4 PRs (1 merged)", line)
        self.assertIn("per PR green on its first CI round (1 of 2 known)", line)
        self.assertIn("Found-by follow-ups 1", line)
        self.assertIn("CI red rounds 3 in 3 of 4 PRs (2 after the run)", line, "of PRs: wf_c has none")
        # The most lines: tasks, three verify sources and CI. Ten, the CI line last.
        with tempfile.TemporaryDirectory() as tmp:
            fx = Fixture(Path(tmp))
            until = metrics.parse_time(UNTIL)
            history = [{"steps": {"lint": ("passed", 20.0)}, "total": 20.0, "status": "passed", "via": "history",
                        "t": until - 60, "wait": None, "over": False}]  # fmt: skip
            ci = {"runs": 3, "by_outcome": {"push success": 3}, "reruns": 0, "queue_s": 0.0, "green": 2,
                  "job_s": [360.0, 420.0], "steps": {"verify total": [380.0, 390.0]}}  # fmt: skip
            data = metrics.collect([fx.dir], {}, None, until)
            _md, _record, most = metrics.build(data, history, ci, None, until, github={"skipped": "--no-gh"})
        self.assertEqual(len(most), 10)
        self.assertTrue(most[3].startswith("quality: 1 tasks"))
        self.assertTrue(most[-1].startswith("CI: 3 runs"))
        self.assertIn("GitHub: not read (--no-gh)", most[3])

    def test_main_reads_github_and_degrades_on_failure(self) -> None:
        out = Path(self.tmp.name) / "out"

        def run(**kw: object) -> tuple[dict, str]:
            printed = io.StringIO()
            with redirect_stdout(printed):
                self.assertEqual(metrics.main(until=UNTIL, out=str(out), compact=True, dirs=[self.dir], history=[],
                                              **kw), 0)  # fmt: skip
            return json.loads((out / "metrics.json").read_text(encoding="utf-8"))["quality"], printed.getvalue()

        quality, _printed = run(gh=gh_stub(self.GITHUB))
        self.assertIn("read_at", quality["github"])
        self.assertEqual(quality["tasks"][0]["ci_red_rounds"], 2)

        def offline(args: list[str]) -> str:
            raise Failure("gh pr list failed: offline")

        for gh, error in ((offline, "gh pr list failed: offline"), (lambda args: "not json", "not JSON")):
            quality, printed = run(gh=gh)
            self.assertIn(error, quality["github"]["error"])
            self.assertIsNone(quality["tasks"][0]["ci_red_rounds"])
            self.assertLessEqual(len(printed.strip().splitlines()), 10)
            self.assertNotIn("warn", printed, "--compact prints only the summary")
        quality, _printed = run(gh=no_gh, no_gh=True)
        self.assertEqual(quality["github"], {"skipped": "--no-gh"})

    def test_the_no_gh_flag(self) -> None:
        self.assertTrue(cli.build_parser().parse_args(["metrics", "--no-gh"]).no_gh)
        self.assertFalse(cli.build_parser().parse_args(["metrics"]).no_gh)


class ProjectKeyTest(unittest.TestCase):
    def test_the_key_is_the_main_checkouts_from_any_worktree(self) -> None:
        self.assertEqual(metrics.project_key(Path("D:/prime-game")), metrics.project_key(Path("D:\\prime-game")))
        with tempfile.TemporaryDirectory() as tmp:
            main = Path(tmp).resolve() / "game"
            main.mkdir()
            git = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
            subprocess.run([*git, "init", "-q"], cwd=main, check=True)
            subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "x"], cwd=main, check=True)
            worktree = main / ".claude" / "worktrees" / "7"
            subprocess.run([*git, "worktree", "add", "-q", str(worktree)], cwd=main, check=True)
            self.assertEqual(metrics.main_checkout(worktree), main)
            self.assertEqual(metrics.main_checkout(main), main)


if __name__ == "__main__":
    unittest.main()
