"""`metrics`' cache re-writes after an idle gap (#558), over small synthetic transcripts written here (never real ones):
one gap per cause (the runner's `wait`, a background `verify`, a shell `sleep`, another shell command, Monitor, a Read,
an API wait), the half-the-gap rule and the background tasks' order, the per-run and per-agent tables, the totals line
and the compact summary's clause, `--track` over another checkout's agents (hand-run ones too, never the session's own
lines) and `--run`'s fourth line."""

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from runner import cli, metrics
from runner.tests.test_metrics import assistant, at, bash, tool_result, usage, write_lines

CHECKOUT = Path("D:/prime-game")
SESSION = "11111111-2222-3333-4444-555555555555"
UNTIL = "2026-10-02T11:00:00Z"
REWRITE = usage(write=100_000)  # $0.50 of cache write on Opus 5.5: the whole context written again
READ = usage(read=100_000)


def background(tool_id: str, command: str) -> dict:
    return {"id": tool_id, "name": "Bash", "input": {"command": command, "run_in_background": True}}


def notification(minutes: float, tool_id: str) -> dict:
    """A background task's end, as Claude Code queues it."""
    content = (f"<task-notification>\n<task-id>x{tool_id}</task-id>\n<tool-use-id>{tool_id}</tool-use-id>\n"
               "<status>completed</status>\n</task-notification>")  # fmt: skip
    return {"type": "queue-operation", "operation": "enqueue", "timestamp": at(minutes), "content": content}


# One implementer: a gap of 5 minutes or more per cause, each followed by a call that writes its context again (but the
# last, which reads it), in minutes from 08:00.
ONE_OF_EACH = [
    assistant(0, "c0", READ, tool=bash("w", "cd /d/wt && tools/run.sh wait a558/verify-1.log")),
    tool_result(4.5, "w"),
    # wait: 4.5 of the 5.5 minutes
    assistant(5.5, "c1", REWRITE, tool=background("v", "tools/run.sh verify > a558/verify-1.log 2>&1")),
    tool_result(5.6, "v", "Command running in background"),
    assistant(6, "c2", READ),  # ends its turn
    notification(12, "v"),
    # verify: no tool call, the background verify still running when the gap began
    assistant(12.5, "c3", REWRITE, tool=bash("s", "until grep -q done x.log; do sleep 10; done")),
    tool_result(18, "s"),
    # sleep: 5.5 of 6 minutes
    assistant(18.5, "c4", REWRITE, tool=bash("b", "blender --background scene.blend --render")),
    tool_result(24.5, "b"),
    # shell: 6 of 6.5 minutes
    assistant(25, "c5", REWRITE,
              tool={"id": "m", "name": "Monitor", "input": {"command": "tail -f x.log", "timeout_ms": 600_000}}),
    tool_result(25.1, "m", "Monitor started"),
    assistant(25.5, "c6", READ),  # ends its turn; the Monitor is armed until 35
    # Monitor: no tool call, the Monitor armed
    assistant(32, "c7", REWRITE, tool={"id": "r", "name": "Read", "input": {"file_path": "D:/raw/sheet.png"}}),
    tool_result(38, "r"),
    # tool: the Read took 6 of 6.5 minutes
    assistant(38.5, "c8", REWRITE, tool=bash("l", "ls")),
    tool_result(38.6, "l"),
    # API: `ls` took 6 seconds of 6.5 minutes
    assistant(45, "c9", REWRITE),
    assistant(46, "c10", READ),  # ends its turn; nothing runs (the verify ended at 12, the Monitor at 35)
    # API: no tool call and nothing running
    assistant(53, "c11", REWRITE),
    # API again, and this call read its cache (a gap, not most of the context written again)
    assistant(60, "c12", READ),
]
CAUSES = ["wait", "verify", "sleep", "shell", "Monitor", "tool", "API", "API", "API"]


def agent(folder: Path, aid: str, label: str, kind: str, lines: list[dict]) -> None:
    write_lines(folder / f"agent-{aid}.jsonl", lines)
    meta = {"agentType": kind, "description": label, "workflowPhase": "Implement"}
    (folder / f"agent-{aid}.meta.json").write_text(json.dumps(meta), encoding="utf-8")


def idle_run(folder: Path) -> None:
    """wf_idle: the implementer above and a code reviewer with no gap ($0.50 of cache write)."""
    agent(folder, "a-one", "implement:#9", "task-implementer", ONE_OF_EACH)
    agent(folder, "a-two", "review:code:#9", "code-reviewer", [assistant(61, "r0", REWRITE), assistant(62, "r1", READ)])
    write_lines(folder / "journal.jsonl", [
        {"type": "started", "key": "k1", "agentId": "a-one", "label": "implement:#9", "phase": "Implement"},
        {"type": "started", "key": "k2", "agentId": "a-two", "label": "review:code:#9", "phase": "Review"},
        {"type": "result", "key": "k1", "agentId": "a-one", "result": {}},
        {"type": "result", "key": "k2", "agentId": "a-two", "result": {"findings": []}},
    ])


def use(name: str, **inp: object) -> dict:
    return metrics.idle_use("t", "m", name, inp)


def call(cause: str, t0: float, t1: float | None, *, bg: bool = False, limit: float = 1800.0, tid: str = "t") -> dict:
    return {"id": tid, "mid": "m", "background": bg, "limit": limit, "cause": cause, "t0": t0, "t1": t1}


class IdleCauseTest(unittest.TestCase):
    def test_a_tool_calls_cause(self) -> None:
        cases = [
            (use("Bash", command="cd /d/wt && tools/run.sh wait a558/verify-1.log"), "wait", False),
            (use("PowerShell", command="tools\\run.cmd wait a558\\verify-1.log"), "wait", False),
            (use("Bash", command="tools/run.sh verify > v.log 2>&1", run_in_background=True), "verify", True),
            (use("Bash", command="tools/run.sh mutants spec.json"), "verify", False),
            (use("PowerShell", command='& "D:\\prime-game\\tools\\run.cmd" publish'), "verify", False),
            (use("PowerShell", command="Start-Sleep -Seconds 60"), "sleep", False),
            (use("Bash", command="for i in $(seq 1 99); do grep -q ok x.log && break; sleep 5; done"), "sleep", False),
            (use("Bash", command="gh pr checks 9 --watch"), "shell", False),
            (use("Monitor", command="tail -f x.log"), "Monitor", True),
            (use("Read", file_path="D:/x.png"), "tool", False),
            (use("Agent", prompt="x"), "tool", False),
        ]
        for got, cause, bg in cases:
            with self.subTest(cause=cause, got=got):
                self.assertEqual((got["cause"], got["background"]), (cause, bg))

    def test_how_long_a_background_task_runs_at_most(self) -> None:
        self.assertEqual(use("Bash", command="sleep 30", run_in_background=True, timeout=60_000)["limit"], 60)
        self.assertEqual(use("Bash", command="x", run_in_background=True)["limit"], metrics.BACKGROUND_TIMEOUT)
        self.assertEqual(use("Monitor", command="x")["limit"], 300, "Monitor's default timeout_ms")
        self.assertEqual(use("Monitor", command="x", timeout_ms=7_200_000)["limit"], 3600, "at most 1 hour")

    def test_the_longest_foreground_tool_counts_when_it_ran_half_the_gap(self) -> None:
        began, ended = 0.0, 400.0
        made = [call("tool", 0, 10), call("wait", 0, 200), call("verify", 0, 1, bg=True)]
        self.assertEqual(metrics.idle_cause(made, made, began, ended, {}), "wait", "200 s of 400: half")
        made = [call("wait", 0, 199)]
        self.assertEqual(metrics.idle_cause(made, made, began, ended, {}), "API", "the model took the rest")
        made = [call("shell", 0, None)]
        self.assertEqual(metrics.idle_cause(made, made, began, ended, {}), "shell", "no result yet: up to the call")
        made = [call("verify", 0, 1, bg=True)]
        self.assertEqual(metrics.idle_cause(made, made, began, ended, {}), "API", "a background call returns at once")

    def test_after_a_turn_the_background_tasks_running_in_order(self) -> None:
        began, ended = 100.0, 500.0
        monitor = call("Monitor", 50, 51, bg=True, limit=300, tid="m")
        verify = call("verify", 60, 61, bg=True, tid="v")
        self.assertEqual(metrics.idle_cause([], [monitor, verify], began, ended, {}), "verify", "IDLE_WAKERS' order")
        self.assertEqual(metrics.idle_cause([], [monitor, verify], began, ended, {"v": 90.0}), "Monitor",
                         "the verify ended before the gap")  # fmt: skip
        later = call("verify", 200, 201, bg=True, tid="later")
        self.assertEqual(metrics.idle_cause([], [later], began, ended, {}), "API", "started after the gap began")
        expired = call("Monitor", 0, 1, bg=True, limit=60, tid="old")
        self.assertEqual(metrics.idle_cause([], [expired], began, ended, {}), "API", "past its timeout")


class IdleReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.dir = self.root / "projects" / "D--prime-game"
        idle_run(self.dir / SESSION / "subagents" / "workflows" / "wf_idle")
        write_lines(self.dir / f"{SESSION}.jsonl", [assistant(0, "own1", READ), assistant(30, "own2", REWRITE)])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL))

    def test_one_gap_per_cause(self) -> None:
        data = metrics.read_agent(self.dir / SESSION / "subagents" / "workflows" / "wf_idle" / "agent-a-one.jsonl")
        self.assertEqual([e["cause"] for e in data["idle"]], CAUSES)
        self.assertEqual([e["gap"] / 60 for e in data["idle"]], [5.5, 6.5, 6, 6.5, 6.5, 6.5, 6.5, 7, 7])
        self.assertEqual([round(e["usd"], 2) for e in data["idle"]], [0.5] * 8 + [0.0])
        self.assertEqual(data["max_gap"], 420.0)

    def test_the_tables_and_the_totals_line(self) -> None:
        md, record, _compact = self.build()
        totals = record["idle"]["totals"]
        self.assertEqual((totals["rewrites"], totals["most"], totals["agents"], totals["agents_rewriting"]), (9, 8, 2, 1))
        self.assertAlmostEqual(totals["usd"], 4.0)
        self.assertAlmostEqual(totals["share"], 4.0 / 4.5, msg="the reviewer's $0.50 of cache write counts too")
        self.assertEqual(totals["causes"]["API"], {"rewrites": 3, "usd": 1.0})
        text = "\n".join(md)
        self.assertIn(
            "workflow agents: 9 API calls after an idle gap of 5 min or more (8 wrote most of the context to the cache again) "
            "in 1 of 2 agents, $4.00 list = 89% of their cache-write $; gap median 6.5 min, max 7 min; by cause: wait 1 "
            "($0.50), verify 1 ($0.50), sleep 1 ($0.50), shell 1 ($0.50), Monitor 1 ($0.50), tool 1 ($0.50), API wait 3 "
            "($1.00)", text)  # fmt: skip
        causes = "1 ($0.50) | 1 ($0.50) | 1 ($0.50) | 1 ($0.50) | 1 ($0.50) | 1 ($0.50) | 3 ($1.00)"
        self.assertIn(f"| 11111111 | wf_idle | 1 of 2 | 15 | 9 | $4.00 | {causes} | 7 |", text, "per run")
        self.assertIn(f"| 11111111 | wf_idle | implement:#9 | task-implementer | 13 | 9 | $4.00 | {causes} | 7 | 0.10M |",
                      text, "per agent: its type, API calls, longest gap and final context")  # fmt: skip
        self.assertNotIn("review:code:#9 |", text, "an agent with no re-write has no row")
        self.assertEqual([a["type"] for a in record["idle"]["agents"]], ["task-implementer", "code-reviewer"])
        self.assertEqual(record["idle"]["agents"][1]["max_gap"], 60.0)

    def test_the_session_s_own_gap_is_not_a_subagent_re_write(self) -> None:
        _md, record, _compact = self.build()
        self.assertEqual(record["idle"]["totals"]["rewrites"], 9, "the manager's 30-minute gap is #305's table")

    def test_the_compact_summary_keeps_its_lines(self) -> None:
        _md, _record, compact = self.build()
        total = next(line for line in compact if line.startswith("total API list $"))
        self.assertTrue(total.endswith("; API calls after 5+ min idle (its table): 9, 8 of them re-wrote most of the "
                                       "context, $4.00 (89% of the agents' cache-write $)"), total)  # fmt: skip
        self.assertLessEqual(len(compact), 10)
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        counted = [r for r in data["runs"] if r["counted"]]
        week = {"percent": 0.0, "bracket": [0.0, 0.0]}
        without = metrics.compact_lines([], counted, {}, [], None, [], week, "w")
        self.assertEqual(len(metrics.compact_lines([], counted, {}, [], None, [], week, "w",
                                                   idle={"rewrites": 0, "most": 0, "usd": 0.0, "share": 0.0})), len(without))

    def test_no_gap_says_so(self) -> None:
        record = metrics.idle_record([])
        self.assertEqual(metrics.idle_section(record), [
            "## Cache re-writes after an idle gap of 5 minutes or more, per run and per agent (#558)", "",
            "workflow agents: no API call after an idle gap of 5 min or more in 0 agents", ""])

    def test_a_run_s_fourth_line(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf):
            metrics.runs_main(["wf_idle"], checkout=CHECKOUT, base=self.root, now=0.0)
        lines = buf.getvalue().splitlines()
        self.assertEqual(len(lines), 4)
        self.assertTrue(lines[3].startswith("9 API calls after an idle gap of 5 min or more (8 wrote most"))
        self.assertTrue(lines[3].endswith("; most: implement:#9 9 ($4.00)"), lines[3])

    def test_the_help_names_the_table(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf), self.assertRaises(SystemExit):
            cli.build_parser().parse_args(["metrics", "--help"])
        help_text = " ".join(buf.getvalue().split())
        self.assertIn("cache re-writes after an idle gap of 5 min or more per run and per agent", help_text)
        self.assertIn("its total line ends with the re-write table's count and $", help_text)


class IdleTrackTest(unittest.TestCase):
    """--track: the art checkout's workflow agent above, a hand-run subagent (a 10-minute `sleep 600`) and the session's
    own lines (a gap of 10 minutes, $0.50 of cache write): only the subagents' gaps count, as a share of the track's
    cache-write $ ($4.00 + $0.50 + $0.50)."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        art = self.root / "projects" / "D--prime-game-art"
        idle_run(art / "s-art" / "subagents" / "workflows" / "wf_art")
        (art / "s-art" / "subagents" / "workflows" / "wf_art" / "agent-a-two.jsonl").write_text("", encoding="utf-8")
        write_lines(art / "s-art" / "subagents" / "agent-h.jsonl", [
            assistant(0, "h0", READ, tool=bash("z", "sleep 600")), tool_result(10, "z"),
            assistant(10.5, "h1", REWRITE),
        ])
        write_lines(art / "s-art.jsonl", [assistant(0, "s0", REWRITE), assistant(10, "s1", READ)])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_main(self, compact: bool) -> str:
        buf = io.StringIO()
        with redirect_stdout(buf):
            metrics.tracks_main([], ["art"], [], at(-1), UNTIL, str(self.root / "out"), compact, checkout=CHECKOUT,
                                base=self.root)  # fmt: skip
        return buf.getvalue()

    def test_the_tracks_line_and_tables(self) -> None:
        out = self.run_main(False)
        self.assertIn("art: 10 API calls after an idle gap of 5 min or more (9 wrote most of the context to the cache again) "
                      "in 2 of 2 agents, $4.50 list = 90% of the track's cache-write $", out)  # fmt: skip
        self.assertIn("| s-art | wf_art | implement:#9 | task-implementer | 13 | 9 | $4.00 |", out)
        self.assertIn("| s-art | hand-run |  | ? | 2 | 1 | $0.50 |  |  | 1 ($0.50) |", out, "no .meta.json: '?'")
        record = json.loads((self.root / "out" / "tracks.json").read_text(encoding="utf-8"))
        self.assertEqual(record["idle"]["art"]["totals"]["rewrites"], 10)
        self.assertAlmostEqual(record["tracks"]["art"]["write_usd"], 5.0)

    def test_the_compact_budget_lines_are_unchanged(self) -> None:
        out = self.run_main(True)
        self.assertNotIn("re-write", out)
        self.assertEqual(len(out.splitlines()), 3, "the window, art, every session")



if __name__ == "__main__":
    unittest.main()
