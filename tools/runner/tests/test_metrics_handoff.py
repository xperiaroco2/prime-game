"""`metrics`' implementer context (#559, issue-task's checkpoint): each API call's context with the tool calls before
it, the calls over 200k and their $, the `<total_tokens>` reminder check, the handoffs of a run (its `implement:#N#k`
continuations) and the section, from small synthetic transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import Fixture, assistant, at, bash, tool_result, usage, write_lines

BUDGET = 15_000_000


def reminder(minutes: float, left: int) -> dict:
    """The harness's context reminder after a tool result, as the transcript logs it."""
    text = f"<total_tokens>{left} tokens left</total_tokens>"
    return {"type": "attachment", "timestamp": at(minutes), "attachment": {"type": "total_tokens_reminder", "text": text}}


def calls_with(contexts: list[int], tools: list[int], *, reminders: bool = True, prefix: str = "m") -> list[dict]:
    """One API call per context (all cache read but 1 input token, 10 output), each making tools[i] tool calls, each
    tool result followed by a reminder of the budget less that call's whole context (output included)."""
    lines: list[dict] = []
    for i, (ctx, n) in enumerate(zip(contexts, tools)):
        u = usage(inp=1, read=ctx - 1, out=10)
        if not n:
            lines.append(assistant(i, f"{prefix}{i}", u))
        for j in range(n):
            tid = f"{prefix}{i}-t{j}"
            lines.append(assistant(i, f"{prefix}{i}", u, tool=bash(tid, "ls")))
            lines.append(tool_result(i + 0.5, tid))
            if reminders:
                lines.append(reminder(i + 0.5, BUDGET - ctx - 10))
    return lines


class ReadAgentContextTest(unittest.TestCase):
    def read(self, lines: list[dict]) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "agent.jsonl"
            write_lines(path, lines)
            return metrics.read_agent(path)

    def test_each_call_has_its_context_and_the_tool_calls_before_it(self) -> None:
        d = self.read(calls_with([100_000, 210_000, 250_000], [2, 1, 0]))
        self.assertEqual(d["ctx_series"], [(0, 100_000), (2, 210_000), (3, 250_000)])

    def test_calls_above_200k_and_their_usd(self) -> None:
        d = self.read(calls_with([100_000, 210_000, 250_000, 200_000], [1, 1, 1, 0]))
        self.assertEqual(d["high_ctx"]["calls"], 2, "over 200k only: 200,000 itself is not")
        model = "claude-opus-5-5"
        want = sum(metrics.usd(metrics.usd_of({**usage(inp=1, read=c - 1, out=10), "cache_write_1h": 0, "model": model}))
                   for c in (210_000, 250_000))  # fmt: skip
        self.assertAlmostEqual(d["high_ctx"]["usd"], want)
        self.assertGreater(want, 0)

    def test_the_reminder_check(self) -> None:
        d = self.read(calls_with([30_000, 40_000, 50_000], [1, 1, 1]))
        self.assertEqual(d["reminders"], {"n": 3, "exact": 3, "budget": BUDGET})
        wrong = calls_with([30_000, 40_000, 50_000], [1, 1, 1])
        wrong[-1] = reminder(2.5, BUDGET - 50_000)  # leaves out the call's output: not exact
        self.assertEqual(self.read(wrong)["reminders"], {"n": 3, "exact": 2, "budget": BUDGET})
        none = self.read(calls_with([30_000, 40_000], [1, 1], reminders=False))
        self.assertEqual(none["reminders"], {"n": 0, "exact": 0, "budget": None})
        self.assertEqual(none["high_ctx"], {"calls": 0, "usd": 0})


class HandoffTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        wf = self.fx.dir / "11111111-2222-3333-4444-555555555555" / "subagents" / "workflows"
        # #21: an implementer hands over twice; the second continuation died once and was retried (one handoff).
        Fixture.run(wf / "wf_handoff", [
            ("k1", "a-i1", "implement:#21", "Implement", {"verify_green": False, "handoff": "a21/handoff-2.md"},
             calls_with([50_000, 160_000, 210_000], [40, 25, 0], prefix="x")),
            ("k2", "a-i2-dead", "implement:#21#2", "Implement", None, calls_with([20_000], [0], prefix="y")),
            ("k2", "a-i2", "implement:#21#2", "Implement", {"verify_green": False, "handoff": "a21/handoff-3.md"},
             calls_with([30_000, 230_000], [1, 0], prefix="z")),
            ("k3", "a-i3", "implement:#21#3", "Implement", {"verify_green": True},
             calls_with([30_000, 90_000], [1, 0], prefix="w")),
            ("k4", "a-c", "review:code:#21", "Review", {"findings": []}, [assistant(5, "c1", usage(inp=1, write=100))]),
            ("k5", "a-p", "publish:#21", "Publish", {"pr_number": 30}, [assistant(6, "p1", usage(inp=1, write=100))]),
        ])  # fmt: skip

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.fx.dir], {}, None, metrics.parse_time("2026-10-02T11:00:00Z"))
        return metrics.build(data, [], None, None, metrics.parse_time("2026-10-02T11:00:00Z"))

    def test_continuation_labels_are_the_implementer_role(self) -> None:
        for label in ("implement:#7#2", "implement:#7#3", "implement:#559#2"):
            with self.subTest(label=label):
                self.assertEqual(metrics.role_of(label), "implementer")
        self.assertEqual(metrics.role_of("implement:#7:2"), "other", "the reason continuations take #k, never :k")

    def test_per_task_handoffs_and_calls_over_200k(self) -> None:
        _md, record, _compact = self.build()
        task = next(t for t in record["tasks"] if t["issue"] == 21)
        self.assertEqual(task["handoffs"], 2, "two continuations; the retried one counts once")
        self.assertEqual(task["impl_calls"], 3 + 1 + 2 + 2)
        self.assertEqual(task["over200_calls"], 2)
        self.assertGreater(task["over200_usd"], 0)
        plain = next(t for t in record["tasks"] if t["issue"] == 5)
        self.assertEqual((plain["handoffs"], plain["over200_calls"]), (0, 0))

    def test_the_section_the_proxy_and_the_compact_line(self) -> None:
        md, record, compact = self.build()
        text = "\n".join(md)
        self.assertIn("## Implementer context and checkpoint handoffs (#559)", text)
        self.assertIn("| #21 | 4 | 2 | 8 | 2 (25%) |", text)
        rec = record["handoffs"]
        by_k = {p["calls"]: p for p in rec["proxy"]}
        # Only #21's first implementer made 40 or more tool calls: its next call after 40 was the 160k one.
        self.assertEqual((by_k[40]["agents"], by_k[40]["median_ctx"], by_k[40]["over"]), (1, 160_000, 1))
        self.assertEqual((by_k[60]["agents"], by_k[60]["median_ctx"], by_k[60]["over"]), (1, 210_000, 1))
        self.assertEqual((by_k[80]["agents"], by_k[80]["median_ctx"]), (0, None))
        self.assertIn("| 80 | 0 | - | - |", text)
        # Crossing 150k: #21's first at tool call 40, its second continuation at 1.
        self.assertEqual({k: rec["crossed"][k] for k in ("agents", "median", "min", "max")},
                         {"agents": 2, "median": 20.5, "min": 1, "max": 40})  # fmt: skip
        self.assertEqual(rec["reminders"]["budgets"], [BUDGET])
        self.assertEqual(rec["reminders"]["n"], rec["reminders"]["exact"])
        self.assertIn(f"readings equal the budget less the context of the API call before them (budget {BUDGET})", text)
        medians = next(line for line in compact if line.startswith("task medians"))
        self.assertIn("implementer calls over 200k:", medians)
        self.assertIn("2 handoffs (#559)", medians)
        self.assertLessEqual(len(compact), 11)

    def test_no_section_without_an_implementer(self) -> None:
        self.assertEqual(metrics.handoff_section(metrics.handoff_record([])), [])


if __name__ == "__main__":
    unittest.main()
