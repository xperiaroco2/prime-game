"""`metrics`' Sonnet publisher trial (#835): the publisher of issue-task runs with a blocker or major left open on
Sonnet against the Opus ones since PUB_TRIAL_FROM, pr-rebase's runs by their rebase agent's model, the stop rules and
the tables, from synthetic runs written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import metrics
from runner.tests import test_metrics
from runner.tests.test_metrics import UNTIL, Fixture, gh_stub, new_pub

SONNET, OPUS = "claude-sonnet-5-5", "claude-opus-5-5"
FROM = metrics.parse_time(metrics.PUB_TRIAL_FROM)


def agent(role: str, result: dict | None, model: str | None = OPUS, usd: float = 0.0) -> dict:
    data = None if model is None else {"start": 1.0, "model": model, "tokens": {"usd_output": usd}}
    return {"role": role, "result": result, "data": data}


def member(issue: int | None, wf: str, model: str, *, open_: int = 2, not_fixed: int | None = 0, pr: int | None = None,
           later: tuple[int, int] | None = (0, 0), fix_rounds: int | None = 0, ci: int | None = 0, usd: float = 5.0,
           pub_usd: float = 1.0, design: bool | None = False, stopped: bool = False, start: float = FROM + 60) -> tuple:  # fmt: skip
    """A finished issue-task run (implementer, publisher) and its scorecard row."""
    run = {"issue": issue, "wf": wf, "start": start, "kind": "issue-task", "finished": True,
           "agents": [agent("implementer", {"verify_green": True}), agent("publisher", new_pub(pr or 0), model, pub_usd)]}  # fmt: skip
    row = {"design": design, "stopped_by_mutants": stopped, "open": open_, "not_fixed": not_fixed, "pr": pr,
           "followups": None if later is None else list(range(later[0] + 1)),  # one filed in the run
           "late_followups": None if later is None else list(range(later[0])),
           "fixups": None if later is None else list(range(later[1])),
           "fix_rounds": fix_rounds, "ci_red_rounds": ci, "usd": usd}  # fmt: skip
    return run, row


def rebase(pr: int, model: str, *, reb: dict | None = None, findings: int | None = 0, fix: dict | None = None,
           usd: float = 2.0, start: float = FROM + 60) -> dict:  # fmt: skip
    """A finished pr-rebase run: its rebase agent, the code review (findings majors; None: none ran) and a fix."""
    agents = [agent("pr-rebase", {"up_to_date": True, "verify_green": True, "published": True, "ci_green": True,
                                  **(reb or {})}, model, usd)]  # fmt: skip
    if findings is not None:
        agents.append(agent("code-reviewer", {"findings": [{"severity": "major"}] * findings + [{"severity": "minor"}]}))
    if fix is not None:
        agents.append(agent("pr-rebase fix", {"fixed": [], "verify_green": True, "published": True, "ci_green": True,
                                              **fix}, model))  # fmt: skip
    return {"issue": pr, "wf": f"wf_r{pr}", "start": start, "kind": "pr-rebase", "finished": True, "agents": agents}


def record(members: list[tuple], counted: list[dict] | None = None) -> dict:
    runs, rows = (list(x) for x in zip(*members)) if members else ([], [])
    return metrics.publisher_trial_record(runs, rows, list(runs) + (counted or []))


def means(n: int, **kw: float | None) -> dict:
    out: dict = {"n": n}
    for k in metrics.PUB_TRIAL_MEASURES:
        out[k] = kw.get(k, 0.0)
    return out


class PublisherTrialRecordTest(unittest.TestCase):
    MEMBERS = [
        # #70: a Sonnet publisher with findings left, then a relaunch with an Opus one on the same PR 80: one trial
        # task, PR 80's later findings (a follow-up) and red CI rounds counted once.
        member(70, "wf1", SONNET, open_=2, not_fixed=1, pr=80, later=(1, 0), fix_rounds=1, ci=1, usd=4.0, pub_usd=1.0),
        member(70, "wf2", OPUS, open_=1, not_fixed=0, pr=80, later=(1, 0), fix_rounds=0, ci=1, usd=6.0, pub_usd=3.0),
        # The baseline: #71. Not #72 (clean), #73 (a design task), #74 (before the window), #75 (stopped by mutants),
        # #76 (no publisher transcript).
        member(71, "wf3", OPUS, open_=1, not_fixed=0, pr=81, later=(0, 1), fix_rounds=2, ci=0, usd=8.0, pub_usd=4.0),
        member(72, "wf4", OPUS, open_=0, pr=82),
        member(73, "wf5", OPUS, pr=83, design=True),
        member(74, "wf6", OPUS, pr=84, start=FROM - 60),
        member(75, "wf7", OPUS, pr=85, stopped=True),
    ]  # fmt: skip

    def test_the_trial_tasks_and_the_baseline(self) -> None:
        nobody = member(76, "wf8", OPUS, pr=86)
        nobody[0]["agents"][1]["data"] = None
        got = record([*self.MEMBERS, nobody])
        (a,) = got["tasks"]
        self.assertEqual((a["issue"], a["models"], a["runs"], a["open"], a["not_fixed"]), (70, ["opus", "sonnet"], 2, 3, 1))
        self.assertEqual((a["later"], a["fix_rounds"], a["ci_fix_rounds"]), (1, 1, 1), "PR 80's signals count once")
        self.assertEqual((a["pub_usd"], a["usd"]), (4.0, 10.0))
        self.assertEqual([x["issue"] for x in got["baseline"]], [71])
        t, b = got["totals"]["trial"], got["totals"]["baseline"]
        self.assertEqual((t["n"], t["not_fixed"], t["later"], t["pub_usd"]), (1, 1.0, 1.0, 4.0))
        self.assertEqual((b["n"], b["not_fixed"], b["later"], b["fix_rounds"], b["pub_usd"]), (1, 0.0, 1.0, 2.0, 4.0))
        self.assertEqual(got["advice"], "continue: 1 of 10 trial tasks")
        self.assertEqual(got["from"], "2026-10-08T12:25:00Z")

    def test_unknown_signals_stay_unknown(self) -> None:
        # Without GitHub (--no-gh) the later findings and the CI rounds are unknown, never 0.
        got = record([member(70, "wf1", SONNET, pr=80, later=None, ci=None, not_fixed=None)])
        (a,) = got["tasks"]
        self.assertEqual((a["later"], a["ci_fix_rounds"], a["not_fixed"]), (None, None, None))
        self.assertIsNone(got["totals"]["trial"]["later"])

    def test_the_table(self) -> None:
        md = "\n".join(metrics.publisher_trial_section(record(self.MEMBERS)))
        self.assertIn("## Sonnet publisher trial (#835)", md)
        self.assertIn("| #70 | opus, sonnet | 2 | 3 | 1 | 1 | 1 | 1 | $4.00 | $10 |", md)
        self.assertIn("| Sonnet trial | 1 | 3.00 | 1.00 | 1.00 | 1.00 | 1.00 | $4.00 | $10 |", md)
        self.assertIn("| Opus baseline | 1 | 1.00 | 0.00 | 1.00 | 2.00 | 0.00 | $4.00 | $8.00 |", md)
        self.assertIn("since 2026-10-08 12:25Z", md)
        self.assertIn("Advice (publisher): continue: 1 of 10 trial tasks.", md)
        self.assertIn("| Sonnet | 0 | 0 | ? | ? | ? |", md)
        self.assertIn("Advice (pr-rebase): continue: 0 of 10 Sonnet pr-rebase runs.", md)
        only_opus = [m for m in self.MEMBERS if m[0]["issue"] != 70]
        self.assertEqual(metrics.publisher_trial_section(record(only_opus)), [], "no Sonnet run, no table")


class PublisherAdviceTest(unittest.TestCase):
    def test_without_a_baseline(self) -> None:
        self.assertEqual(metrics.pub_trial_advice(means(3), means(0)),
                         "continue: 3 of 10 trial tasks; no baseline in the window yet")  # fmt: skip
        self.assertTrue(metrics.pub_trial_advice(means(10), means(0)).startswith("no verdict: 10 trial tasks"))

    def test_the_early_stop_on_findings_not_fixed(self) -> None:
        base = means(5, not_fixed=0.5)
        self.assertEqual(metrics.pub_trial_advice(means(3, not_fixed=2.0), base), "continue: 3 of 10 trial tasks")
        self.assertEqual(metrics.pub_trial_advice(means(4, not_fixed=1.5), base),
                         "stop: drop Sonnet for the publisher of runs with findings (1.00 findings not fixed per task "
                         "over the baseline's)")  # fmt: skip
        self.assertEqual(metrics.pub_trial_advice(means(4, not_fixed=1.4), base), "continue: 4 of 10 trial tasks")

    def test_ten_tasks_decide(self) -> None:
        base = means(8, later=0.2, not_fixed=0.5, ci_fix_rounds=0.5, pub_usd=3.0)
        keep = metrics.pub_trial_advice(means(10, later=0.2, not_fixed=0.4, ci_fix_rounds=0.5, pub_usd=1.5), base)
        self.assertTrue(keep.startswith("keep Sonnet for the publisher of runs with findings"), keep)
        drop = metrics.pub_trial_advice(means(10, later=0.3, not_fixed=0.4, ci_fix_rounds=0.5, pub_usd=3.0), base)
        self.assertEqual(drop, "drop Sonnet for the publisher of runs with findings (worse: later findings, "
                               "publisher $ per task not lower)")  # fmt: skip

    def test_a_small_baseline_does_not_stop_the_trial_early(self) -> None:
        for size in (1, 2):
            self.assertEqual(metrics.pub_trial_advice(means(4, not_fixed=3.0), means(size, not_fixed=0.0)),
                             "continue: 4 of 10 trial tasks")  # fmt: skip
        self.assertTrue(metrics.pub_trial_advice(means(4, not_fixed=3.0), means(3, not_fixed=0.0)).startswith("stop:"))

    def test_a_measure_nobody_knows_is_no_verdict_not_worse(self) -> None:
        """A run without GitHub knows no later findings and CI rounds: it must not end the trial as a loss."""
        base = means(8, later=0.2, not_fixed=0.5, ci_fix_rounds=0.5, pub_usd=3.0)
        got = metrics.pub_trial_advice(means(10, later=None, not_fixed=0.4, ci_fix_rounds=None, pub_usd=1.5), base)
        self.assertEqual(got, "no verdict: unknown later findings, CI fix rounds (GitHub not read, or no run knows "
                              "it); report on #302, the engineer decides")  # fmt: skip
        worse = metrics.pub_trial_advice(means(10, later=None, not_fixed=0.9, ci_fix_rounds=0.5, pub_usd=1.5), base)
        self.assertEqual(worse, "drop Sonnet for the publisher of runs with findings (worse: findings not fixed)")


class RebaseTrialTest(unittest.TestCase):
    RUNS = [
        rebase(90, SONNET, findings=1, fix={"not_fixed": ["x"]}, usd=1.0),
        rebase(91, SONNET, reb={"verify_green": False, "published": False}, findings=None, usd=1.0),
        rebase(92, OPUS, findings=0, usd=3.0),
        rebase(93, OPUS, findings=2, fix={"ci_green": False, "not_fixed": []}, usd=5.0),
        rebase(94, OPUS, start=FROM - 60),  # before the window
    ]

    def test_the_runs_and_the_sides(self) -> None:
        got = record([], self.RUNS)["rebase"]
        self.assertEqual([(x["pr"], x["model"], x["red"], x["serious"], x["not_fixed"]) for x in got["runs"]],
                         [(90, "sonnet", False, 1, 1), (91, "sonnet", True, None, None), (92, "opus", False, 0, 0),
                          (93, "opus", True, 2, 0)])  # fmt: skip
        s, o = got["totals"]["sonnet"], got["totals"]["opus"]
        self.assertEqual((s["n"], s["red_runs"], s["red"], s["serious"], s["not_fixed"], s["usd"]), (2, 1, 0.5, 1.0, 1.0, 1.0))
        self.assertEqual((o["n"], o["red_runs"], o["red"], o["serious"], o["not_fixed"], o["usd"]), (2, 1, 0.5, 1.0, 0.0, 4.0))
        self.assertEqual(got["advice"], "continue: 2 of 10 Sonnet pr-rebase runs")
        md = "\n".join(metrics.publisher_trial_section(record([], self.RUNS)))
        self.assertIn("| Sonnet | 2 | 1 | 1.00 | 1.00 | $1.00 |", md)
        self.assertIn("| Opus | 2 | 1 | 1.00 | 0.00 | $4.00 |", md)

    def test_its_stop_rule(self) -> None:
        red = rebase(95, SONNET, reb={"ci_green": False})
        self.assertEqual(record([], [*self.RUNS, red])["rebase"]["advice"], "stop: drop Sonnet for pr-rebase (2 Sonnet runs red)")
        ten = [rebase(100 + k, SONNET, usd=1.0) for k in range(10)]
        keep = record([], [*ten, *self.RUNS[2:]])["rebase"]["advice"]
        self.assertTrue(keep.startswith("keep Sonnet for pr-rebase"), keep)
        dear = [rebase(100 + k, SONNET, usd=9.0) for k in range(10)]
        self.assertEqual(record([], [*dear, *self.RUNS[2:]])["rebase"]["advice"],
                         "drop Sonnet for pr-rebase (worse or unknown: $ per run not lower)")  # fmt: skip
        self.assertTrue(record([], ten)["rebase"]["advice"].startswith("no verdict"))


class PublisherTrialBuildTest(unittest.TestCase):
    """The table in the report and the record, from fixture journals: #70's publisher on Sonnet, #71's on Opus, both
    after a major finding."""

    def test_the_report_and_the_record(self) -> None:
        lines = test_metrics.QualityTest.lines
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(metrics, "PUB_TRIAL_FROM", "2026-10-01T00:00:00Z"):
            folder = Path(tmp) / "projects" / "D--prime-game"
            wf = folder / test_metrics.QualityTest.SID / "subagents" / "workflows"
            for n, start, model in ((70, 0, SONNET), (71, 30, OPUS)):
                Fixture.run(wf / f"wf_{n}", [
                    (f"k-i{n}", f"a-i{n}", f"implement:#{n}", "Implement", {"verify_green": True},
                     lines(f"i{n}", start, start + 8)),
                    (f"k-r{n}", f"a-r{n}", f"review:code:#{n}", "Review", {"findings": [{"severity": "major"}]},
                     lines(f"r{n}", start + 8, start + 9)),
                    (f"k-p{n}", f"a-p{n}", f"publish:#{n}", "Publish", new_pub(n + 10, not_fixed=["x"]),
                     lines(f"p{n}", start + 9, start + 15, model=model, publishes=1)),
                ])  # fmt: skip
            until = metrics.parse_time(UNTIL)
            data = metrics.collect([folder], {}, None, until)
            github = metrics.read_github(gh_stub({"prs": [], "runs": [], "issues": []}))
            md, rec, _compact = metrics.build(data, [], None, None, until, github=github)
        text = "\n".join(md)
        self.assertIn("## Sonnet publisher trial (#835)", text)
        self.assertIn("| #70 | sonnet | 1 | 1 | 1 |", text)
        trial = rec["publisher_trial"]
        self.assertEqual(([x["issue"] for x in trial["tasks"]], [x["issue"] for x in trial["baseline"]]), ([70], [71]))
        self.assertEqual(trial["advice"], "continue: 1 of 10 trial tasks")


if __name__ == "__main__":
    unittest.main()
