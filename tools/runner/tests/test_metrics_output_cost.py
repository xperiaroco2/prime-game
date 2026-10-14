"""`metrics`' output API list $ by agent role, review tier and effort (#982: measure what medium effort saves on
docs-only light-tier runs), from small synthetic transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, usage
from runner.tests.test_metrics_tiers import FULL, LIGHT, prompt

OUT_USD = 20.0 / 1e6  # Opus 5.5's output list $ per token (PRICES)


def task(n: int, start: float, tier_line: str, effort: str, out: int) -> list[tuple]:
    """One finished issue-task run of issue n: an implementer at effort with out output tokens over two API calls, and a
    publisher at high whose prompt names the tier."""
    return [
        ("k-i", f"a-i{n}", f"implement:#{n}", "Implement", {"verify_green": True}, [
            assistant(start, f"msg-i{n}", usage(inp=10, write=1000, out=out // 2), effort=effort),
            assistant(start + 2, f"msg-i{n}b", usage(inp=1, read=1000, out=out - out // 2), effort=effort),
        ]),
        ("k-p", f"a-p{n}", f"publish:#{n}", "Publish", {"pr_number": 100 + n, "ci_green": True}, [
            prompt(start + 4, f"Task: publish issue #{n}.\n\n{tier_line}\n\nThen, in this order:"),
            assistant(start + 4, f"msg-p{n}", usage(inp=3, write=800, out=200)),
        ]),
    ]  # fmt: skip


def cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip("|").split("|")]


class OutputCostTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        wf = self.fx.dir / SESSION / "subagents" / "workflows"
        Fixture.run(wf / "wf_docs1", task(21, 50, LIGHT, "medium", 1000))
        Fixture.run(wf / "wf_docs2", task(22, 60, LIGHT, "medium", 3000))
        Fixture.run(wf / "wf_tool", task(23, 70, LIGHT, "high", 8000))
        Fixture.run(wf / "wf_core", task(24, 80, FULL, "high", 6000))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict]:
        data = metrics.collect([self.fx.dir], {}, None, metrics.parse_time(UNTIL))
        md, record, _compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        return [line for part in md for line in part.splitlines()], record

    def test_the_record_splits_each_roles_output_by_tier_and_effort(self) -> None:
        _lines, record = self.build()
        rows = {(r["role"], r["tier"], r["effort"]): r for r in record["output_by_role"]}
        medium = rows[("implementer", "light", "medium")]
        self.assertEqual((medium["agents"], medium["output_tokens"]), (2, 2000))
        self.assertAlmostEqual(medium["output_usd"], 2000 * OUT_USD)
        self.assertAlmostEqual(medium["output_usd_sum"], 4000 * OUT_USD)
        high = rows[("implementer", "light", "high")]
        self.assertEqual((high["agents"], high["output_tokens"]), (1, 8000))
        self.assertAlmostEqual(high["output_usd"], 8000 * OUT_USD)
        self.assertEqual(rows[("implementer", "full", "high")]["output_tokens"], 6000)
        pub = rows[("publisher", "light", "high")]
        self.assertEqual((pub["agents"], pub["output_tokens"]), (3, 200))
        # The share of their whole $: output $ over input, cache write, cache read and output $ of the same agents.
        whole = 2 * (10 * 4.0 + 1000 * 5.0 + 1 * 4.0 + 1000 * 0.20) / 1e6 + 4000 * OUT_USD
        self.assertAlmostEqual(medium["share"], 4000 * OUT_USD / whole)
        # The base fixture's run before #606 lands in the unknown tier; a resumed or pr-rebase run would carry its kind.
        self.assertIn("unknown", {r["tier"] for r in record["output_by_role"]})
        sums = [r["output_usd_sum"] for r in record["output_by_role"]]
        self.assertEqual(sums, sorted(sums, reverse=True), "largest output $ first")

    def test_the_table_and_the_per_role_column(self) -> None:
        lines, record = self.build()
        title = "## Output API list $ per agent role, review tier and effort (#982, every run in the window)"
        self.assertIn(title, lines)
        head = lines[lines.index(title) + 1]  # an empty part splits into no line
        self.assertEqual(cells(head), ["role", "tier", "effort", "agents", "output tokens (median)",
                                       "output $ (median)", "output $ total", "of their $"])  # fmt: skip
        body = lines[lines.index(title) + 3:]
        row = next(line for line in body if line.startswith("| implementer | light | medium |"))
        self.assertEqual(cells(row)[3:7], ["2", "2k", metrics.fmt_usd(2000 * OUT_USD), metrics.fmt_usd(4000 * OUT_USD)])
        # The per-role table's column: the role's output $ and its share of the role's $.
        role_head = next(line for line in lines if line.startswith("| role | agents | wall min"))
        col = cells(role_head).index("output $ (of its $)")
        self.assertEqual(cells(role_head)[col - 1], "API list $")
        impl = next(line for line in lines[lines.index(role_head):] if line.startswith("| implementer |"))
        out = sum(r["output_usd_sum"] for r in record["output_by_role"] if r["role"] == "implementer")
        self.assertTrue(cells(impl)[col].startswith(metrics.fmt_usd(out) + " ("), cells(impl)[col])

    def test_no_table_without_a_run_and_the_compact_summary_keeps_its_lines(self) -> None:
        self.assertEqual(metrics.output_section(metrics.output_rows([])), [])
        _lines, record = self.build()
        self.assertFalse(any("#982" in line for line in record["compact"]), "the compact summary does not change")


if __name__ == "__main__":
    unittest.main()
