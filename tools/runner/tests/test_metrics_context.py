"""`metrics`' context per API call (#584), over a small synthetic run written here (never a real transcript): each
agent's average and peak (input, cache write and cache read of a call; output left out), per role, the heavy agents
at CONTEXT_HEAVY (average or peak) with their run and issue, the compact summary's clause on its first line (the line
count unchanged) and `--run`'s line."""

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from runner import cli, metrics
from runner.tests.test_metrics import assistant, usage, write_lines

CHECKOUT = Path("D:/prime-game")
SESSION = "11111111-2222-3333-4444-555555555555"
UNTIL = "2026-10-02T11:00:00Z"
HEAVY = "average 150k+ or peak 300k+ per call"

# implement:#9, heavy by its average: 100k, 200k, 300k (the 5k of output left out; the first message's streamed line
# repeats its usage, counted once): average 200k, peak 300k.
IMPLEMENTER = [
    assistant(0, "i0", usage(inp=1_000, write=99_000)),
    assistant(0.1, "i0", usage(inp=1_000, write=99_000)),
    assistant(1, "i1", usage(read=150_000, write=50_000)),
    assistant(2, "i2", usage(read=280_000, write=20_000, out=5_000)),
]
# review:code:#9, light: 40k and 60k.
REVIEWER = [assistant(3, "r0", usage(write=40_000)), assistant(4, "r1", usage(read=40_000, write=20_000))]
# publish:#9, heavy by its peak alone: 50k three times, then 330k: average 120k.
PUBLISHER = [
    assistant(5, "p0", usage(write=50_000)),
    assistant(6, "p1", usage(read=50_000)),
    assistant(7, "p2", usage(read=50_000)),
    assistant(8, "p3", usage(read=50_000, write=280_000)),
]


def agent(folder: Path, aid: str, label: str, kind: str, lines: list[dict]) -> None:
    write_lines(folder / f"agent-{aid}.jsonl", lines)
    meta = {"agentType": kind, "description": label, "workflowPhase": "P"}
    (folder / f"agent-{aid}.meta.json").write_text(json.dumps(meta), encoding="utf-8")


def context_run(folder: Path) -> None:
    agent(folder, "a-impl", "implement:#9", "task-implementer", IMPLEMENTER)
    agent(folder, "a-rev", "review:code:#9", "code-reviewer", REVIEWER)
    agent(folder, "a-pub", "publish:#9", "task-publisher", PUBLISHER)
    write_lines(folder / "journal.jsonl", [
        {"type": "started", "key": "k1", "agentId": "a-impl", "label": "implement:#9", "phase": "Implement"},
        {"type": "started", "key": "k2", "agentId": "a-rev", "label": "review:code:#9", "phase": "Review"},
        {"type": "started", "key": "k3", "agentId": "a-pub", "label": "publish:#9", "phase": "Publish"},
        {"type": "result", "key": "k1", "agentId": "a-impl", "result": {}},
        {"type": "result", "key": "k2", "agentId": "a-rev", "result": {"findings": []}},
        {"type": "result", "key": "k3", "agentId": "a-pub", "result": {}},
    ])  # fmt: skip


def fake(calls: int, ctx_sum: float, peak: int, role: str = "implementer") -> dict:
    return {"session": "s", "run": "wf", "issue": None, "label": "x", "role": role, "type": "?",
            "data": {"api_calls": calls, "ctx_sum": ctx_sum, "ctx_peak": peak}}  # fmt: skip


class ContextRecordTest(unittest.TestCase):
    def test_an_agent_is_heavy_at_either_threshold(self) -> None:
        agents = [fake(2, 300_000, 150_000), fake(2, 299_998, 299_999), fake(1, 10_000, 300_000)]
        self.assertEqual([a["heavy"] for a in metrics.context_record(agents)["agents"]], [True, False, True],
                         "average 150k exactly; 149,999 and a 299,999 peak; a 300k peak alone")  # fmt: skip

    def test_a_role_s_average_is_over_its_agents_calls(self) -> None:
        record = metrics.context_record([fake(1, 100_000, 100_000), fake(3, 300_000, 120_000)])
        self.assertEqual(record["roles"], [{"role": "implementer", "agents": 2, "calls": 4, "avg": 100_000.0,
                                            "peak": 120_000, "heavy": 0}])  # fmt: skip

    def test_no_call_says_so(self) -> None:
        record = metrics.context_record([])
        self.assertEqual(metrics.context_section(record), [
            "## Context per API call, per agent role and the heaviest agents (#584)", "",
            "workflow agents: no agent made an API call", ""])  # fmt: skip
        self.assertEqual(metrics.context_compact(record), "context per API call (#584): no API call")

    def test_millions(self) -> None:
        self.assertEqual([metrics.fmt_k(n) for n in (420_000, 999_499, 999_500, 5_750_000)],
                         ["420k", "999k", "1.00M", "5.75M"])  # fmt: skip


class ContextReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.dir = self.root / "projects" / "D--prime-game"
        context_run(self.dir / SESSION / "subagents" / "workflows" / "wf_ctx")
        write_lines(self.dir / f"{SESSION}.jsonl", [assistant(0, "own", usage(read=900_000))])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL))

    def test_read_agent_s_average_and_peak(self) -> None:
        data = metrics.read_agent(self.dir / SESSION / "subagents" / "workflows" / "wf_ctx" / "agent-a-impl.jsonl")
        self.assertEqual((data["api_calls"], data["ctx_sum"], data["ctx_peak"]), (3, 600_000, 300_000))

    def test_the_role_table_and_the_heavy_agents(self) -> None:
        md, record, _compact = self.build()
        text = "\n".join(md)
        self.assertIn(f"workflow agents: 3 agents, 9 API calls: average 131k, peak 330k per call; 2 heavy ({HEAVY})",
                      text, "the session's own 900k call is not a workflow agent's")  # fmt: skip
        self.assertIn("| role | agents | API calls | average per call | peak | heavy agents |\n"
                      "|---|---|---|---|---|---|\n"
                      "| implementer | 1 | 3 | 200k | 300k | 1 |\n| publisher | 1 | 4 | 120k | 330k | 1 |\n"
                      "| code-reviewer | 1 | 2 | 50k | 60k | 0 |", text, "by average, highest first")  # fmt: skip
        self.assertIn(f"Heavy agents ({HEAVY}), by the tokens over all their calls:", text)
        self.assertIn("| 11111111 | wf_ctx | #9 | implement:#9 | implementer | task-implementer | 3 | 200k | 300k | "
                      "0.60M |\n"
                      "| 11111111 | wf_ctx | #9 | publish:#9 | publisher | task-publisher | 4 | 120k | 330k | 0.48M |",
                      text)  # fmt: skip
        self.assertNotIn("| review:code:#9 | code-reviewer |", text, "a light agent has no heavy row")
        context = record["context_per_call"]
        self.assertEqual(context["thresholds"], {"avg": 150_000, "peak": 300_000})
        self.assertEqual([a["label"] for a in context["agents"]], ["implement:#9", "review:code:#9", "publish:#9"])

    def test_the_compact_clause_on_the_first_line(self) -> None:
        _md, _record, compact = self.build()
        self.assertTrue(compact[0].endswith(
            "; context per API call avg/peak (#584): implementer 200k/300k, publisher 120k/330k, code-reviewer "
            "50k/60k; 2 of 3 agents heavy (avg 150k+ or peak 300k+), most: implement:#9 200k/300k x3, publish:#9 "
            "120k/330k x4"),
            compact[0])  # fmt: skip
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        counted = [r for r in data["runs"] if r["counted"]]
        week = {"percent": 0.0, "bracket": [0.0, 0.0]}
        context = metrics.context_record(metrics.context_agents(counted))
        without = metrics.compact_lines([], counted, {}, [], None, [], week, "w")
        with_it = metrics.compact_lines([], counted, {}, [], None, [], week, "w", context=context)
        self.assertEqual(len(with_it), len(without), "the summary keeps its line count")
        self.assertEqual(with_it[1:], without[1:])

    def test_a_run_s_context_line(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf):
            metrics.runs_main(["wf_ctx"], checkout=CHECKOUT, base=self.root, now=0.0)
        lines = buf.getvalue().splitlines()
        self.assertEqual(lines[-1], f"context per API call avg/peak (#584; heavy: {HEAVY}): implement:#9 200k/300k x3 "
                                    "heavy, review:code:#9 50k/60k x2, publish:#9 120k/330k x4 heavy")  # fmt: skip
        self.assertEqual(len(lines), 4, "no re-write line: no gap of 5 minutes")

    def test_the_help_names_it(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf), self.assertRaises(SystemExit):
            cli.build_parser().parse_args(["metrics", "--help"])
        help_text = " ".join(buf.getvalue().split())
        self.assertIn("the average and peak context per API call per agent role and the heavy agents (#584)", help_text)
        self.assertIn("its first line ends with the context per API call per role and the heavy agents", help_text)


if __name__ == "__main__":
    unittest.main()
