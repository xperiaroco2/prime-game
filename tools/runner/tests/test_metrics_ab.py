"""`metrics`' A/B of the code reviewer's model (#535): per run with a control code reviewer (issue-task's ab_review),
each side's findings as the blind judge ruled them, the totals per pair of models and the stop rule, from synthetic
runs written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import metrics
from runner.tests import test_metrics
from runner.tests.test_metrics import UNTIL, Fixture, gh_stub, new_pub

SONNET, OPUS = "claude-sonnet-5-5", "claude-opus-5-5"
MAJOR = {"severity": "major", "problem": "p"}
MINOR = {"severity": "minor", "problem": "p"}


def agent(role: str, usd: float, result: dict | None, model: str = OPUS) -> dict:
    tokens = {"usd_input": usd, "usd_cache_write": 0.0, "usd_cache_read": 0.0, "usd_output": 0.0}
    return {"role": role, "result": result, "data": {"start": 1.0, "tokens": tokens, "model": model}}


def verdict(reviewer: int, index: int, ruled: str, severity: str) -> dict:
    return {"reviewer": reviewer, "index": index, "verdict": ruled, "severity": severity, "reason": "r"}


def run(issue: int, trial: list, control: list, judge: dict | None, *, judged: bool = True) -> dict:
    agents = [
        agent("implementer", 5.0, {"verify_green": True}),
        agent("code-reviewer", 0.4, {"findings": trial}, SONNET),
        agent("code-reviewer-control", 0.9, {"findings": control}),
    ]
    if judged:
        agents.append(agent("ab-judge", 1.2, judge))
    return {"session": "s", "issue": issue, "wf": f"wf{issue}", "agents": agents}


# The trial raised a major (valid, the control's too) and a minor the judge held invalid; the control also raised a
# valid major the trial missed, and a nit with no verdict (unsure).
FULL = {
    "verdicts": [
        verdict(1, 0, "valid", "major"), verdict(1, 1, "invalid", "minor"),
        verdict(2, 0, "valid", "major"), verdict(2, 1, "valid", "blocker"),
        verdict(2, 0, "invalid", "nit"),  # a second verdict on one finding: the first stands
        verdict(3, 0, "valid", "major"),  # no such reviewer
    ],
    "matches": [{"first": 0, "second": 0}, {"first": 1, "second": 0}, {"first": 5, "second": 2}],  # one already paired, one out of range
}  # fmt: skip


class AbRowsTest(unittest.TestCase):
    def test_the_labels_name_the_roles_and_the_control_counts_as_a_reviewer(self) -> None:
        self.assertEqual(metrics.role_of("review:code-control:#7"), "code-reviewer-control")
        self.assertEqual(metrics.role_of("ab-judge:#7"), "ab-judge")
        self.assertEqual(metrics.role_of("review:code:#7"), "code-reviewer")
        # issue-task.js counts the control's blockers and majors as open like any reviewer's (publish_clean).
        self.assertIn("code-reviewer-control", metrics.SERIOUS_FROM)
        self.assertIn("code-reviewer-control", metrics.FINDERS)

    def test_a_judged_run_per_side(self) -> None:
        rows = metrics.ab_rows([
            run(7, [MAJOR, MINOR], [MAJOR, MAJOR, dict(MINOR, severity="nit")], FULL),
            {"session": "s", "issue": 8, "wf": "wf8", "agents": [agent("code-reviewer", 1.0, {"findings": [MAJOR]})]},
        ])  # fmt: skip
        self.assertEqual(len(rows), 1, "a run without a control is no A/B run")
        x = rows[0]
        self.assertEqual((x["issue"], x["trial_model"], x["control_model"], x["judged"], x["pairs"]), (7, SONNET, OPUS, True, 1))
        self.assertEqual(
            x["trial"],
            {"findings": 2, "valid": 1, "serious": 1, "invalid": 1, "unsure": 0, "unique": 0, "unique_serious": 0},
        )
        self.assertEqual(
            x["control"],
            {"findings": 3, "valid": 2, "serious": 2, "invalid": 0, "unsure": 1, "unique": 1, "unique_serious": 1},
        )
        self.assertEqual((x["trial_usd"], x["control_usd"], x["judge_usd"]), (0.4, 0.9, 1.2))

    def test_nothing_to_judge_and_a_judge_that_died(self) -> None:
        empty, died = metrics.ab_rows([run(7, [], [], None, judged=False), run(8, [MAJOR], [], None)])
        self.assertTrue(empty["judged"])
        self.assertEqual(empty["trial"]["findings"] + empty["control"]["findings"], 0)
        self.assertFalse(died["judged"])
        self.assertEqual((died["trial"], died["control"]), ({"findings": 1}, {"findings": 0}))
        totals = metrics.ab_totals([empty, died])
        self.assertEqual((totals[0]["runs"], totals[0]["judged"]), (2, 1))
        md = "\n".join(metrics.ab_section({"rows": [empty, died], "totals": totals}))
        self.assertIn("| #8 | claude-sonnet-5-5 | claude-opus-5-5 | no (the judge returned nothing) | 1 / ? | 0 / ? | ? | ? |", md)
        self.assertEqual(metrics.ab_section({"rows": [], "totals": []}), [])


def side(**kw) -> dict:
    out = {"findings": 0, "valid": 0, "serious": 0, "invalid": 0, "unsure": 0, "unique": 0, "unique_serious": 0,
           "missed": 0, "missed_serious": 0}
    return out | kw


def row(issue: int, trial: dict, control: dict) -> dict:
    return {"session": "s", "issue": issue, "wf": "w", "trial_model": SONNET, "control_model": OPUS, "judged": True,
            "pairs": 0, "trial": trial, "control": control, "trial_usd": 0.4, "control_usd": 0.9, "judge_usd": 1.0}  # fmt: skip


class AbVerdictTest(unittest.TestCase):
    def test_the_totals_count_what_each_side_missed(self) -> None:
        rows = [row(1, side(findings=2, valid=2), side(findings=3, valid=3, serious=1, unique=1, unique_serious=1)),
                row(2, side(findings=1, valid=1, unique=1), side(findings=1, invalid=1))]  # fmt: skip
        (t,) = metrics.ab_totals(rows)
        self.assertEqual((t["trial"]["missed"], t["trial"]["missed_serious"]), (1, 1))
        self.assertEqual((t["control"]["missed"], t["control"]["missed_serious"]), (1, 0))
        self.assertEqual((t["trial"]["valid"], t["control"]["valid"], t["control"]["invalid"]), (3, 3, 1))
        self.assertEqual(t["verdict"], f"continue: 2 of {metrics.AB_RUNS} judged runs")
        md = "\n".join(metrics.ab_section({"rows": rows, "totals": [t]}))
        self.assertIn("## The code reviewer's A/B (#535)", md)
        self.assertIn("| claude-sonnet-5-5 | claude-opus-5-5 | 2 of 2 | 3 (0) | 3 (1) | 1 (1) | 1 (0) | 0 of 3 | 1 of 4 |", md)

    def test_the_stop_rule(self) -> None:
        n = metrics.AB_RUNS
        missed_two = side(findings=4, valid=4, unique=2, unique_serious=2)  # the control's: the trial missed these
        stop = metrics.ab_verdict(3, side(findings=1, valid=1, missed_serious=2), side(missed_serious=0))
        self.assertTrue(stop.startswith("stop: drop the trial model"), stop)
        self.assertTrue(metrics.ab_verdict(3, side(missed_serious=3), side(missed_serious=1)).startswith("stop"))
        self.assertTrue(metrics.ab_verdict(3, side(missed_serious=1), side(missed_serious=0)).startswith("continue"))
        good = side(findings=10, valid=8, invalid=2, missed_serious=1)
        self.assertEqual(metrics.ab_verdict(n, good, side(findings=10, valid=10, invalid=1, missed_serious=0)),
                         "keep the trial model (the engineer decides)")  # fmt: skip
        # Too few of the control's valid findings, or too many invalid ones: drop.
        self.assertEqual(metrics.ab_verdict(n, good, side(findings=12, valid=11, missed_serious=0)), "drop the trial model")
        noisy = side(findings=10, valid=8, invalid=4, missed_serious=0)
        self.assertEqual(metrics.ab_verdict(n, noisy, side(findings=10, valid=8, invalid=1)), "drop the trial model")
        # The totals' missed_serious comes from the other side's unique ones.
        rows = [row(i, side(), missed_two if i == 0 else side()) for i in range(2)]
        self.assertTrue(metrics.ab_totals(rows)[0]["verdict"].startswith("stop"))


class EndedOptionsJournalTest(unittest.TestCase):
    """#1147: issue-task.js refuses ab_review, models.code, models.implement "sonnet" and publish_findings since they
    ended on 2026-10-13, and runs no control reviewer or judge any more; `metrics` still reads the journals of the runs
    launched with them, beside a run of today, from fixture journals."""

    def test_an_old_run_with_the_ended_options_beside_a_run_of_today(self) -> None:
        lines = test_metrics.QualityTest.lines
        judged = {"verdicts": [verdict(1, 0, "valid", "major"), verdict(2, 0, "valid", "major")], "matches": [{"first": 0, "second": 0}]}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(metrics, "PUB_TRIAL_FROM", "2026-10-01T00:00:00Z"):
            folder = Path(tmp) / "projects" / "D--prime-game"
            wf = folder / test_metrics.QualityTest.SID / "subagents" / "workflows"
            # #70, launched with ab_review, models.code, models.implement and models.publish_findings, all "sonnet":
            # the control code reviewer and the judge on Opus, a major left open for the Sonnet publisher.
            Fixture.run(wf / "wf_70", [
                ("k-i70", "a-i70", "implement:#70", "Implement", {"verify_green": True}, lines("i70", 0, 8, model=SONNET)),
                ("k-r70", "a-r70", "review:code:#70", "Review", {"findings": [MAJOR]}, lines("r70", 8, 9, model=SONNET)),
                ("k-c70", "a-c70", "review:code-control:#70", "Review", {"findings": [MAJOR]}, lines("c70", 8, 9)),
                ("k-j70", "a-j70", "ab-judge:#70", "Review", judged, lines("j70", 9, 10)),
                ("k-p70", "a-p70", "publish:#70", "Publish", new_pub(80, not_fixed=["x"]),
                 lines("p70", 10, 15, model=SONNET, publishes=1)),
            ])  # fmt: skip
            # #71, a run of today: no control, no judge, the publisher on the session's model.
            Fixture.run(wf / "wf_71", [
                ("k-i71", "a-i71", "implement:#71", "Implement", {"verify_green": True}, lines("i71", 30, 38)),
                ("k-r71", "a-r71", "review:code:#71", "Review", {"findings": [MAJOR]}, lines("r71", 38, 39)),
                ("k-p71", "a-p71", "publish:#71", "Publish", new_pub(81), lines("p71", 39, 45, publishes=1)),
            ])  # fmt: skip
            until = metrics.parse_time(UNTIL)
            data = metrics.collect([folder], {}, None, until)
            github = metrics.read_github(gh_stub({"prs": [], "runs": [], "issues": []}))
            md, rec, _compact = metrics.build(data, [], None, None, until, github=github)
        text = "\n".join(md)
        self.assertEqual(sorted(r["issue"] for r in data["runs"]), [70, 71])
        # The old run's A/B row, as before #1147; today's run has none.
        self.assertIn("## The code reviewer's A/B (#535)", text)
        (ab,) = rec["ab_review"]["rows"]
        self.assertEqual((ab["issue"], ab["trial_model"], ab["control_model"], ab["judged"]), (70, SONNET, OPUS, True))
        # Its Sonnet publisher with a major left open is still a task of #835's trial, today's Opus one the baseline.
        trial = rec["publisher_trial"]
        self.assertEqual(([x["issue"] for x in trial["tasks"]], [x["issue"] for x in trial["baseline"]]), ([70], [71]))


if __name__ == "__main__":
    unittest.main()
