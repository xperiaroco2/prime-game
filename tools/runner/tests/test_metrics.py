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


def assistant(minutes: float, mid: str, u: dict, *, model: str = "claude-opus-5-5", tool: dict | None = None) -> dict:
    content: list[dict] = [{"type": "text", "text": "working"}]
    if tool:
        content = [{"type": "tool_use", **tool}]
    return {
        "type": "assistant",
        "timestamp": at(minutes),
        "effort": "high",
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

    def test_the_compact_summary(self) -> None:
        ci = {"runs": 3, "by_outcome": {"push success": 3}, "reruns": 0, "queue_s": 0.0, "green": 2,
              "job_s": [360.0, 420.0], "steps": {"verify total": [380.0, 390.0]}}
        md, record, compact = self.build(ci=ci)
        self.assertLessEqual(len(compact), 10)
        self.assertTrue(compact[0].startswith("metrics, the first transcript to 2026-10-02T11:00:00Z: 1 finished"))
        self.assertIn("#5 18 min $", compact[1])
        self.assertTrue(any("% of a Max 20x week ($44 per 1%)" in line for line in compact))
        self.assertTrue(any(line.startswith("local verify (agents): 1 runs, 1 red, median 271 s") for line in compact))
        self.assertEqual(compact[-1], "CI: 3 runs in the window; last 2 green: job 6.5 min median, verify 385 s")
        self.assertIn("## CI (GitHub Actions)", md)

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
                [f"{SESSION[:4]}=M9"], until=UNTIL, out=str(out), compact=True, dirs=[self.fx.dir], history=[]
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
            self.assertEqual(metrics.main(until=UNTIL, out=str(out), dirs=[], history=[]), 0)
            self.assertEqual(metrics.main(["0000"], until=UNTIL, out=str(out), dirs=[self.fx.dir], history=[]), 0)
        self.assertIn("no Claude Code transcripts of this checkout", printed.getvalue())
        self.assertFalse(out.exists())
        with self.assertRaises(Failure):
            metrics.main(since=UNTIL, until=UNTIL, dirs=[], history=[])
        with self.assertRaises(Failure):
            metrics.main(until=UNTIL, ci=-1, dirs=[], history=[])

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
