"""`metrics`' Sonnet implementer trial (#560): the issues' sizes, the trial tasks against the Opus-implemented Size S
baseline, the stop rule and the table, from synthetic runs written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests import test_metrics
from runner.tests.test_metrics import UNTIL, Fixture, gh_stub, new_pub

SONNET, OPUS = "claude-sonnet-5-5", "claude-opus-5-5"


def agent(role: str, result: dict | None, model: str = OPUS) -> dict:
    return {"role": role, "result": result, "data": {"start": 1.0, "model": model}}


def member(issue: int | None, wf: str, model: str, *, green: bool = True, pub: dict | None = None,
           verifies: tuple[int, int] = (1, 0), calls: int = 100, serious: int | None = 0, fix_rounds: int | None = 0,
           pr: int | None = None, ci: int | None = None, usd: float = 5.0, design: bool = False, start: float | None = None) -> tuple:  # fmt: skip
    """A finished run with its per_task record and its scorecard row."""
    agents = [agent("implementer", {"verify_green": green}, model)]
    if serious is not None:
        agents.append(agent("code-reviewer", {"findings": [{"severity": "major"}] * serious}))
    if pub is not None:
        agents.append(agent("publisher", pub, SONNET))
    run = {"session": "s", "issue": issue, "wf": wf, "agents": agents, "start": start}
    task = {"summaries": verifies[0], "summaries_failed": verifies[1], "calls": calls}
    row = {"pr": pr, "ci_red_rounds": ci, "serious": serious, "fix_rounds": fix_rounds, "design": design, "usd": usd}
    return run, task, row


def record(members: list[tuple], issues: list[dict] | None) -> dict:
    runs, tasks, rows = (list(x) for x in zip(*members))
    return metrics.trial_record(runs, tasks, rows, None if issues is None else {"issues": issues})


def issue(number: int, size: str) -> dict:
    return {"number": number, "title": "t", "body": f"## Goal\nx\n\nSize: {size}. Files: `a.py`.", "createdAt": "x"}


class IssueSizeTest(unittest.TestCase):
    def test_the_size_lines_the_issues_use(self) -> None:
        cases = {
            "Size: S. Files: `tools/runner/metrics.py`": "S",
            "## Scope\n- **Size:** M.\n": "M",
            "Size: S to M (about 40 calls)": "M",
            "Size: XS (about 25 calls)": "XS",
            "Size: M (design)": "M",
            "## Out of scope\nSize M or larger tasks": None,  # no colon: prose, not the Size line
            "- Sizes and offsets: 3": None,
            "": None,
        }
        for body, size in cases.items():
            self.assertEqual(metrics.issue_size(body), size, body)


class TrialRecordTest(unittest.TestCase):
    MEMBERS = [
        # #70: red on Sonnet, then green on Sonnet with PR 80 (one red CI round, counted once for both runs).
        member(70, "wf1", SONNET, green=False, verifies=(2, 2), calls=80, serious=None, fix_rounds=None, usd=3.0),
        member(70, "wf2", SONNET, pub=new_pub(80), verifies=(2, 1), calls=90, serious=1, fix_rounds=1, pr=80, ci=1,
               usd=4.0),
        # #71: red twice on Sonnet (published false, then CI red), then relaunched on Opus: one trial task.
        member(71, "wf3", SONNET, pub={"published": False}, usd=2.0),
        member(71, "wf4", SONNET, pub=new_pub(81, ci_green=False), pr=81, ci=2, usd=2.0),
        member(71, "wf5", OPUS, pub=new_pub(81), pr=81, ci=2, usd=6.0),
        # The baseline: #72 (Size S); not #73 (M), #74 (a design task), #75 (no Size line), #76 (no issue on GitHub).
        member(72, "wf6", OPUS, pub=new_pub(82), serious=2, fix_rounds=0, pr=82, ci=0, usd=8.0),
        member(73, "wf7", OPUS, pub=new_pub(83)),
        member(74, "wf8", OPUS, pub=new_pub(84), design=True),
        member(75, "wf9", OPUS, pub=new_pub(85)),
        member(76, "wf10", OPUS, pub=new_pub(86)),
        member(None, "wf11", OPUS, pub=new_pub(87)),  # no issue number: its own task, no size
    ]  # fmt: skip
    ISSUES = [issue(70, "S"), issue(71, "S"), issue(72, "S"), issue(73, "M"), issue(74, "S"),
              {"number": 75, "body": "no size here"}]  # fmt: skip

    def test_the_trial_tasks_and_the_baseline(self) -> None:
        got = record(self.MEMBERS, self.ISSUES)
        self.assertTrue(got["sizes_known"])
        a, b = got["tasks"]
        self.assertEqual((a["issue"], a["size"], a["models"], a["runs"], a["red_runs"]), (70, "S", ["sonnet"], 2, 1))
        self.assertEqual((a["verify_runs"], a["verify_red"], a["serious"], a["fix_rounds"]), (4, 3, 1, 1))
        self.assertEqual((a["ci_fix_rounds"], a["calls"], a["usd"]), (1, 170, 7.0))
        self.assertEqual((b["issue"], b["models"], b["runs"], b["red_runs"]), (71, ["opus", "sonnet"], 3, 2))
        self.assertEqual((b["ci_fix_rounds"], b["usd"]), (2, 10.0), "PR 81's rounds count once")
        self.assertEqual([x["issue"] for x in got["baseline"]], [72])
        t, base = got["totals"]["trial"], got["totals"]["baseline"]
        self.assertEqual((t["tasks"], t["red_twice"], t["red_runs"], t["usd"], t["usd_median"]), (2, 1, 1.5, 8.5, 8.5))
        self.assertEqual(t["serious"], 0.5, "#70: its red run, which no review saw, is left out of the sum")
        self.assertEqual((base["tasks"], base["serious"], base["ci_fix_rounds"], base["usd"]), (1, 2.0, 0.0, 8.0))
        self.assertEqual(got["advice"], f"continue: 2 of {metrics.TRIAL_TASKS} trial tasks")

    def test_without_github_there_is_no_baseline(self) -> None:
        got = record(self.MEMBERS, None)
        self.assertFalse(got["sizes_known"])
        self.assertEqual((len(got["tasks"]), got["baseline"]), (2, []))
        self.assertTrue(got["advice"].startswith("continue: 2 of 6 trial tasks; no baseline"), got["advice"])
        md = "\n".join(metrics.trial_section(got))
        self.assertIn("GitHub's issues were not read (--no-gh or a gh error)", md)
        self.assertIn("| Opus, Size S | 0 | 0 | ? | ? | ? | ? | ? | ? | ? | ? | ? |", md)

    def test_the_table(self) -> None:
        got = record(self.MEMBERS, self.ISSUES)
        md = "\n".join(metrics.trial_section(got))
        self.assertIn("## Sonnet implementer trial (#560)", md)
        self.assertIn("| #70 | S | sonnet | 2 (1) | 4 (3) | 1 | 1 | 1 | 170 | $7.00 |", md)
        self.assertIn("| #71 | S | opus, sonnet | 3 (2) | 3 (0) | 0 | 0 | 2 | 300 | $10 |", md)
        self.assertIn("| Sonnet trial | 2 | 1 | 1.50 | 3.50 | 1.50 | 0.50 | 0.50 | 1.50 | 235 | $8.50 | $8.50 |", md)
        self.assertIn("| Opus, Size S | 1 | 0 | 0.00 | 1.00 | 0.00 | 2.00 | 0.00 | 0.00 | 100 | $8.00 | $8.00 |", md)
        self.assertIn("The trial's own verdict: continue: 2 of 6 trial tasks.", md)
        self.assertIn("Advice: continue: 0 of 10 Sonnet-implemented tasks since 2026-10-10 18:06Z; no review counted yet.", md)
        only_opus = [m for m in self.MEMBERS if m[0]["issue"] not in (70, 71)]
        self.assertEqual(metrics.trial_section(record(only_opus, self.ISSUES)), [], "no trial task, no table")


def totals(tasks: int, **kw: float | None) -> dict:
    out: dict = {"tasks": tasks, "red_twice": 0, "usd_median": 5.0}
    return out | dict.fromkeys(metrics.TRIAL_MEASURES, 1.0) | kw


class TrialSeriousTest(unittest.TestCase):
    """One reviewer set on both sides: the A/B's control code reviewer replaces code-reviewer, no test review."""

    def test_one_code_reviewer_counts(self) -> None:
        def run(*agents: dict) -> dict:
            return {"agents": [agent("implementer", {"verify_green": True}), *agents]}

        def found(*severities: str) -> dict:
            return {"findings": [{"severity": s} for s in severities]}

        self.assertIsNone(metrics.trial_serious(run()), "no review ran")
        self.assertIsNone(metrics.trial_serious(run(agent("test-reviewer", found("major")))), "a test review alone")
        self.assertEqual(metrics.trial_serious(run(agent("code-reviewer", found("Major", "minor", "blocker")))), 2)
        both = run(agent("code-reviewer", found("major", "major"), SONNET), agent("code-reviewer-control", found("major")),
                   agent("godot-api-checker", found("blocker")), agent("test-reviewer", found("major")))  # fmt: skip
        self.assertEqual(metrics.trial_serious(both), 2, "the control's 1 in place of code-reviewer's 2, plus the checker's")


class TrialAdviceTest(unittest.TestCase):
    def test_the_stop_rule(self) -> None:
        advice, base = metrics.trial_advice, totals(5, usd=6.0)
        # Two tasks red twice: stop, whatever the rest (even with no baseline).
        self.assertTrue(advice(totals(2, red_twice=2), totals(0)).startswith("stop: drop Sonnet"))
        self.assertTrue(advice(totals(1, red_twice=1), totals(0)).startswith("continue: 1 of 6 trial tasks; no baseline"))
        # Six trial tasks and still no baseline: no verdict, never an endless "continue".
        self.assertTrue(advice(totals(6), totals(0)).startswith("no verdict: 6 trial tasks but no baseline"))
        # One blocker or major per task over the baseline: stop from the fourth task on, not before.
        self.assertTrue(advice(totals(4, serious=2.0), base).startswith("stop: drop Sonnet for the implementer (1.00 blockers"))
        self.assertEqual(advice(totals(3, serious=2.0), base), "continue: 3 of 6 trial tasks")
        self.assertEqual(advice(totals(5, serious=1.9), base), "continue: 5 of 6 trial tasks")
        self.assertEqual(advice(totals(4, serious=None), base), "continue: 4 of 6 trial tasks")
        # After six: keep when no worse and cheaper.
        keep = "keep Sonnet for qualifying tasks (the engineer decides; a habit only by a further amendment)"
        self.assertEqual(advice(totals(6, usd=4.0), base), keep)
        self.assertEqual(advice(totals(6, usd=4.0, verify_runs=9.0, calls=500.0), base), keep, "not in the keep rule")
        self.assertEqual(advice(totals(6, usd=6.0), base), "drop Sonnet for the implementer (worse or unknown: $ per task not lower)")
        self.assertEqual(advice(totals(6, usd=4.0, fix_rounds=1.5, ci_fix_rounds=None), base),
                         "drop Sonnet for the implementer (worse or unknown: publisher fix rounds, CI fix rounds)")  # fmt: skip
        self.assertTrue(advice(totals(6, red_runs=1.2, verify_red=1.1), base).endswith("red runs, verify reds)"))


class RevertRuleTest(unittest.TestCase):
    """The keep's revert rule (the model-guard ADR, 2026-10-10): blockers and majors a task over the first 10 Sonnet
    tasks started on or after the keep date."""

    KEEP = metrics.parse_time(metrics.KEEP_FROM)

    def rows(self, serious: list[int | None], *, before: int = 0) -> list[dict]:
        """`before` older trial tasks (3 blockers or majors each), then one task a day per entry of `serious`."""
        old = [{"start": self.KEEP - 86400 * (i + 1), "serious": 3} for i in range(before)]
        return old + [{"start": self.KEEP + 86400 * i, "serious": n} for i, n in enumerate(serious)]

    def advice(self, serious: list[int | None], **kw: int) -> str:
        return metrics.revert_advice(self.rows(serious, **kw))[1]

    def test_before_ten_tasks_it_continues(self) -> None:
        self.assertEqual(self.advice([]), "continue: 0 of 10 Sonnet-implemented tasks since 2026-10-10 18:06Z; no review counted yet")
        self.assertEqual(self.advice([None, None]), "continue: 2 of 10 Sonnet-implemented tasks since 2026-10-10 18:06Z; no review counted yet")
        self.assertEqual(self.advice([1, 0, 0], before=6),
                         "continue: 3 of 10 Sonnet-implemented tasks since 2026-10-10 18:06Z; 0.33 blockers and majors a task (revert above 0.3)")  # fmt: skip

    def test_ten_tasks_decide_by_the_mean(self) -> None:
        keep = self.advice([1, 1, 1] + [0] * 7)  # 0.30 exactly: within the rule, "pass 0.3" is a strict excess
        self.assertTrue(keep.startswith("keep Sonnet for qualifying tasks (10 of 10"), keep)
        self.assertTrue(self.advice([1, 1, 1, 1] + [0] * 6, before=6).startswith("revert: drop Sonnet for the implementer (10 of 10"))
        # Only the first ten count: a bad eleventh task changes nothing; tasks before the keep date never count.
        self.assertTrue(self.advice([0] * 10 + [9], before=6).startswith("keep Sonnet"))

    def test_unreviewed_tasks_are_named_in_the_advice(self) -> None:
        got = metrics.revert_advice(self.rows([1, None, 0, 0, None, 0, 0, 0, 0, 0]))[0]
        self.assertEqual((got["tasks"], got["reviewed"], got["serious"]), (10, 8, 0.125))
        self.assertEqual(got["advice"], "keep Sonnet for qualifying tasks (10 of 10 Sonnet-implemented tasks since "
                                        "2026-10-10 18:06Z, 8 reviewed; 0.12 blockers and majors a task, within 0.3)")  # fmt: skip
        self.assertNotIn("reviewed", self.advice([0] * 10), "all reviewed: no count")

    def test_the_trials_tasks_of_the_keep_day_never_count(self) -> None:
        # #750 and #760 ran on 2026-10-10 hours before the keep (18:06:44Z): the trial judged them, the rule does not.
        self.assertEqual(metrics.KEEP_FROM, "2026-10-10T18:06:44Z")
        same_day = [{"start": self.KEEP - 3600 * h, "serious": 5} for h in (1, 6)]
        got = metrics.revert_advice(same_day + self.rows([0, 0]))[0]
        self.assertEqual((got["tasks"], got["serious"]), (2, 0.0))
        self.assertIn("since 2026-10-10 18:06Z", got["advice"])

    def test_the_record_carries_it(self) -> None:
        got = record([member(70, "wf1", SONNET, serious=2, start=RevertRuleTest.KEEP + 5)], [issue(70, "S")])
        self.assertEqual((got["revert"]["tasks"], got["revert"]["serious"]), (1, 2.0))
        self.assertTrue(got["revert"]["advice"].startswith("continue: 1 of 10"), got["revert"]["advice"])
        md = "\n".join(metrics.trial_section(got))
        self.assertIn(f"Advice: {got['revert']['advice']}.", md)
        self.assertIn("Revert rule since 2026-10-10", md)


class TrialBuildTest(unittest.TestCase):
    """The table in the report and the record, from fixture journals: #70 on Sonnet, #71 on Opus (Size S)."""

    def test_the_report_and_the_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "projects" / "D--prime-game"
            wf = folder / test_metrics.QualityTest.SID / "subagents" / "workflows"
            for n, start, model in ((70, 0, SONNET), (71, 30, OPUS)):
                Fixture.run(wf / f"wf_{n}", [
                    (f"k-i{n}", f"a-i{n}", f"implement:#{n}", "Implement", {"verify_green": True},
                     test_metrics.QualityTest.lines(f"i{n}", start, start + 8, model=model)),
                    (f"k-p{n}", f"a-p{n}", f"publish:#{n}", "Publish", new_pub(n + 10),
                     test_metrics.QualityTest.lines(f"p{n}", start + 9, start + 15, model=SONNET, publishes=1)),
                ])  # fmt: skip
            until = metrics.parse_time(UNTIL)
            data = metrics.collect([folder], {}, None, until)
            github = metrics.read_github(gh_stub({"prs": [], "runs": [], "issues": [issue(70, "S"), issue(71, "S")]}))
            md, rec, _compact = metrics.build(data, [], None, None, until, github=github)
        text = "\n".join(md)
        self.assertIn("## Sonnet implementer trial (#560)", text)
        self.assertIn("| #70 | S | sonnet | 1 (0) | 0 (0) | ? | 0 | ? |", text)
        trial = rec["sonnet_trial"]
        self.assertEqual(([x["issue"] for x in trial["tasks"]], [x["issue"] for x in trial["baseline"]]), ([70], [71]))
        self.assertEqual(trial["advice"], "continue: 1 of 6 trial tasks")


if __name__ == "__main__":
    unittest.main()
