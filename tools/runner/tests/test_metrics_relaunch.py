"""`metrics`' issues launched 2 or more times (#833): the rows (runs, $ after the first, unfinished runs, handoff
continuations, back-to-back starts), the section and its place in the JSON record, from synthetic runs written here."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import Fixture, assistant, usage

UNIT = {"usd_input": 1.0, "usd_cache_write": 0.0, "usd_cache_read": 0.0, "usd_output": 0.0}


def agent(role: str, dollars: float, label: str | None = None, result: dict | None = None) -> dict:
    tokens = {**UNIT, "usd_input": dollars}
    return {"role": role, "label": label or f"{role}:#1", "data": {"tokens": tokens}, "result": result}


def run(wf: str, issue: int | None, start: float, end: float, *, finished: bool = True, kind: str = "issue-task",
        agents: list[dict] | None = None) -> dict:  # fmt: skip
    return {"wf": wf, "issue": issue, "start": start, "end": end, "finished": finished, "kind": kind,
            "agents": agents or [agent("implementer", 1.0)]}  # fmt: skip


class RelaunchRowsTest(unittest.TestCase):
    def test_only_issues_with_two_runs_and_the_dearest_first(self) -> None:
        runs = [
            run("a1", 1, 0, 100, agents=[agent("implementer", 2.0)]),
            run("a2", 1, 10_000, 10_100, agents=[agent("implementer", 3.0)]),
            run("b1", 2, 0, 100, agents=[agent("implementer", 40.0)]),  # one run: not listed
            run("c1", 3, 0, 100, agents=[agent("implementer", 5.0)]),
            run("c2", 3, 50_000, 50_100, agents=[agent("implementer", 6.0)]),
            run("n1", None, 0, 100),  # no issue named: not listed
            run("n2", None, 200, 300),
        ]
        rows = metrics.relaunch_rows(runs)
        self.assertEqual([x["issue"] for x in rows], [3, 1])
        self.assertEqual((rows[1]["runs"], rows[1]["usd"], rows[1]["later_usd"]), (2, 5.0, 3.0))
        self.assertEqual(rows[1]["wfs"], ["a1", "a2"])
        self.assertAlmostEqual(rows[1]["span_s"], 10_100)

    def test_runs_are_taken_in_start_order_whatever_the_input_order(self) -> None:
        runs = [run("late", 7, 5_000, 5_100, agents=[agent("implementer", 9.0)]),
                run("early", 7, 0, 100, agents=[agent("implementer", 1.0)])]  # fmt: skip
        row = metrics.relaunch_rows(runs)[0]
        self.assertEqual((row["wfs"], row["later_usd"]), (["early", "late"], 9.0))

    def test_unfinished_runs_and_their_dollars(self) -> None:
        runs = [run("a1", 4, 0, 100, finished=False, agents=[agent("implementer", 8.0)]),
                run("a2", 4, 200, 900, agents=[agent("implementer", 6.0)])]  # fmt: skip
        row = metrics.relaunch_rows(runs)[0]
        self.assertEqual((row["unfinished"], row["unfinished_usd"]), (1, 8.0))

    def test_back_to_back_is_a_start_soon_after_the_previous_end(self) -> None:
        soon = metrics.RELAUNCH_BACK_TO_BACK - 1
        runs = [run("a1", 5, 0, 1_000), run("a2", 5, 1_000 + soon, 2_000),
                run("a3", 5, 2_000 + metrics.RELAUNCH_BACK_TO_BACK, 3_000)]  # fmt: skip
        self.assertEqual(metrics.relaunch_rows(runs)[0]["back_to_back"], 1, "the gap of exactly the limit is not")

    def test_other_runs_are_left_out(self) -> None:
        # A wave's agents name several issues; the most common #N is not a relaunch of that issue.
        runs = [run("a1", 5, 0, 1_000), run("w1", 5, 5_000, 6_000, kind="other")]
        self.assertEqual(metrics.relaunch_rows(runs), [])

    def test_a_run_that_overlaps_the_previous_one_is_not_back_to_back(self) -> None:
        runs = [run("a1", 5, 0, 1_000), run("a2", 5, 500, 2_000, kind="issue-task (resumed)")]
        self.assertEqual(metrics.relaunch_rows(runs)[0]["back_to_back"], 0)

    def test_handoff_continuations_are_counted_apart(self) -> None:
        runs = [
            run("a1", 6, 0, 100, agents=[agent("implementer", 4.0, "implement:#6"),
                                         agent("implementer", 1.5, "implement:#6#2"),
                                         agent("implementer", 0.5, "implement:#6#3")]),
            run("a2", 6, 5_000, 5_100, agents=[agent("implementer", 2.0, "implement:#6")]),
        ]  # fmt: skip
        row = metrics.relaunch_rows(runs)[0]
        self.assertEqual((row["handoffs"], row["handoff_usd"]), (2, 2.0))

    def test_a_pr_rebase_labelled_with_its_pr_counts_under_the_issue_that_published_the_pr(self) -> None:
        # pr-rebase.js labels its agents rebase:#PR, review:code:#PR, fix:#PR, so read_run gives it the PR's number.
        task = run("a1", 8, 0, 100, agents=[agent("implementer", 1.0, "implement:#8"),
                                            agent("publisher", 1.0, "publish:#8", {"pr_number": 9})])
        rebase = run("a2", 9, 5_000, 5_100, kind="pr-rebase",
                     agents=[agent("pr-rebase", 2.0, "rebase:#9"), agent("code-reviewer", 1.0, "review:code:#9")])
        rows = metrics.relaunch_rows([task, rebase])
        self.assertEqual([(x["issue"], x["pr"], x["runs"]) for x in rows], [(8, None, 2)])
        self.assertEqual(rows[0]["kinds"], {"issue-task": 1, "pr-rebase": 1})

    def test_the_pr_is_found_from_a_run_outside_the_counted_ones_or_from_pr_url(self) -> None:
        earlier = run("a0", 8, -9_000, -8_900, agents=[
            agent("publisher", 1.0, "publish:#8", {"pr_url": "https://github.com/o/r/pull/9"})])  # fmt: skip
        rebases = [run(w, 9, t, t + 100, kind="pr-rebase", agents=[agent("pr-rebase", 1.0, "rebase:#9")])
                   for w, t in (("r1", 0), ("r2", 5_000))]  # fmt: skip
        row = metrics.relaunch_rows(rebases, [earlier, *rebases])[0]
        self.assertEqual((row["issue"], row["pr"], row["runs"]), (8, None, 2))

    def test_a_pr_rebase_with_no_known_publisher_is_listed_under_its_pr(self) -> None:
        rebases = [run(w, 9, t, t + 100, kind="pr-rebase", agents=[agent("pr-rebase", 1.0, "rebase:#9")])
                   for w, t in (("r1", 0), ("r2", 5_000))]  # fmt: skip
        rows = metrics.relaunch_rows(rebases)
        self.assertEqual([(x["issue"], x["pr"]) for x in rows], [(None, 9)])
        self.assertIn("| PR #9 | 2 |", "\n".join(metrics.relaunch_section(rows)))


class RelaunchSectionTest(unittest.TestCase):
    def test_no_section_without_a_relaunch(self) -> None:
        self.assertEqual(metrics.relaunch_section(metrics.relaunch_rows([run("a1", 1, 0, 100)])), [])

    def test_the_section_lists_the_issue_and_the_totals(self) -> None:
        runs = [run("a1", 12, 0, 100, agents=[agent("implementer", 2.0)]),
                run("a2", 12, 7_200, 7_300, agents=[agent("implementer", 3.0)])]  # fmt: skip
        text = "\n".join(metrics.relaunch_section(metrics.relaunch_rows(runs)))
        self.assertIn("## Issues launched 2 or more times (#833)", text)
        self.assertIn("| #12 | 2 | 2 issue-task | $5.00 | $3.00 | 0 ($0.00) | 0 ($0.00) | 0 | 2.0 |", text)
        self.assertIn("1 issues, $5.00; after the first run $3.00.", text)


class RelaunchBuildTest(unittest.TestCase):
    def test_build_puts_the_rows_in_the_record_and_the_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fx = Fixture(Path(tmp))
            wf = fx.dir / "11111111-2222-3333-4444-555555555555" / "subagents" / "workflows"
            for name, minute in (("wf_one", 1), ("wf_two", 40)):
                Fixture.run(wf / name, [
                    ("k1", f"a-{name}", "implement:#33", "Implement", {"verify_green": True},
                     [assistant(minute, f"m-{name}", usage(inp=1, write=100))]),
                    ("k2", f"p-{name}", "publish:#33", "Publish", {"pr_number": 9},
                     [assistant(minute + 1, f"q-{name}", usage(inp=1, write=100))]),
                ])  # fmt: skip
            data = metrics.collect([fx.dir], {}, None, metrics.parse_time("2026-10-02T11:00:00Z"))
            md, record, _ = metrics.build(data, [], None, None, metrics.parse_time("2026-10-02T11:00:00Z"))
        self.assertEqual([(x["issue"], x["runs"]) for x in record["relaunches"]], [(33, 2)])
        self.assertIn("## Issues launched 2 or more times (#833)", "\n".join(md))


if __name__ == "__main__":
    unittest.main()
