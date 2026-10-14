"""`metrics`' tool calls per API call by agent role (#979: how often agents batch independent tool calls in one
message), from small synthetic transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import UNTIL, Fixture, assistant, bash, tool_result, usage, write_lines


def agent(role: str, tool_calls: int, api_calls: int, start: float | None = 0.0) -> dict:
    return {"role": role, "data": {"start": start, "tool_calls": tool_calls, "api_calls": api_calls}}


class BatchingTest(unittest.TestCase):
    def test_read_agent_counts_each_tool_use_block_and_each_message_id_once(self) -> None:
        # Claude Code writes a message's content blocks as one line each, with the same message id and usage: m0 made
        # two tool calls in one API call, m1 one, m2 none.
        lines = [
            assistant(0, "m0", usage(inp=1, write=100), tool=bash("t1", "git status")),
            assistant(0, "m0", usage(inp=1, write=100), tool=bash("t2", "git log --oneline -3")),
            tool_result(0.5, "t1"),
            tool_result(0.5, "t2"),
            assistant(1, "m1", usage(inp=1, read=100), tool=bash("t3", "gh issue view 1")),
            tool_result(1.5, "t3"),
            assistant(2, "m2", usage(inp=1, read=100)),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "agent.jsonl"
            write_lines(path, lines)
            data = metrics.read_agent(path)
        self.assertEqual((data["tool_calls"], data["api_calls"]), (3, 3))

    def test_the_record_sums_each_roles_agents_and_skips_those_that_never_started(self) -> None:
        counted = [
            {"agents": [agent("implementer", 30, 20), agent("publisher", 5, 5), {"role": "implementer", "data": None}]},
            {"agents": [agent("implementer", 15, 10), agent("planner", 0, 0), agent("publisher", 9, 9, start=None)]},
        ]
        rec = metrics.batching_record(counted)
        self.assertEqual(rec["implementer"], {"agents": 2, "tool_calls": 45, "api_calls": 30, "per_call": 1.5})
        self.assertEqual(rec["publisher"], {"agents": 1, "tool_calls": 5, "api_calls": 5, "per_call": 1.0})
        self.assertIsNone(rec["planner"]["per_call"], "no API call: no ratio, never 0")
        self.assertEqual(metrics.per_call_text(rec["implementer"]), "1.50")
        self.assertEqual(metrics.per_call_text(rec["planner"]), "-")
        self.assertEqual(metrics.per_call_text(None), "-")

    def test_the_per_role_table_and_the_json_record_from_a_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fx = Fixture(Path(tmp))
            data = metrics.collect([fx.dir], {}, None, metrics.parse_time(UNTIL))
            md, record, compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        # #5's implementer: a first attempt with 2 API calls and no tool call, then one with 4 API calls and 2 tool
        # calls (verify and publish); unfinished #6's with 1 API call counts too (its tokens were spent); #7's resumed
        # run has no implementer, #8's ends after --until.
        impl = record["tool_calls_per_api_call"]["implementer"]
        self.assertEqual((impl["agents"], impl["tool_calls"], impl["api_calls"]), (3, 2, 7))
        lines = [line for part in md for line in part.splitlines()]
        head = next(line for line in lines if line.startswith("| role | agents | wall min"))
        cells = [c.strip() for c in head.strip("|").split("|")]
        col = cells.index("tool calls per API call")
        self.assertEqual(cells[col - 1], "tool calls (median / max)")
        row = next(line for line in lines[lines.index(head):] if line.startswith("| implementer |"))
        self.assertEqual([c.strip() for c in row.strip("|").split("|")][col], "0.29")
        medians = next(line for line in compact if line.startswith("task medians"))
        pub = metrics.per_call_text(record["tool_calls_per_api_call"].get("publisher"))
        self.assertIn(f" tool calls (per API call: implementer 0.29, publisher {pub}, #979); ", medians)

    def test_the_compact_clause_keeps_the_line_count_and_needs_the_record(self) -> None:
        tasks = [{"issue": 1, "wall": 60.0, "usd": 1.0, "ctx": 10, "calls": 3}]
        week = {"percent": 1.0, "bracket": (0.9, 1.1)}
        batching = {"implementer": {"agents": 1, "tool_calls": 3, "api_calls": 2, "per_call": 1.5},
                    "planner": {"agents": 1, "tool_calls": 4, "api_calls": 4, "per_call": 1.0}}  # fmt: skip
        plain = metrics.compact_lines(tasks, [], {}, [], None, [], week, "w")
        lines = metrics.compact_lines(tasks, [], {}, [], None, [], week, "w", batching=batching)
        self.assertEqual(len(lines), len(plain))
        medians = next(line for line in lines if line.startswith("task medians"))
        self.assertIn("3 tool calls (per API call: implementer 1.50, #979); ", medians)
        self.assertNotIn("planner", medians, "only BATCHING_ROLES")
        self.assertNotIn("per API call", next(line for line in plain if line.startswith("task medians")))


if __name__ == "__main__":
    unittest.main()
