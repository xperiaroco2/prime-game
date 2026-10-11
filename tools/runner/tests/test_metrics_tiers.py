"""`metrics` per review tier (#606): issue-task.js names a run's tier in its full publisher's prompt, and `metrics`
groups the finished issue-task runs by it (count, wall time, API list $) and names it on `--run`'s first line."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, at, usage

LIGHT = "Review tier (#606): light (no path under core/ server/ net/ voice/ tests/harness/ or client/ outside client/ui/): the light chain ran."
FULL = "Review tier (#606): full (the diff touches core/match/vote.gd)."


def prompt(minutes: float, text: str) -> dict:
    return {"type": "user", "timestamp": at(minutes), "message": {"role": "user", "content": text}}


def indented(text: str) -> str:
    """text as the harness hands a workflow's computed task to its agent (#761): every line indented by two spaces."""
    return "\n".join("  " + line if line else line for line in text.split("\n"))


def task(n: int, start: float, tier_line: str | None, usd_scale: int = 1, indent: bool = False) -> list[tuple]:
    """One finished issue-task run of issue n from minute start: an implementer, a code reviewer and a publisher whose
    prompt carries tier_line (none: a run before #606), indented as the harness indents it when indent."""
    text = f"Task: publish issue #{n}.\n\n{tier_line}\n\nThen, in this order:"
    pub_prompt = [prompt(start + 8, indented(text) if indent else text)] if tier_line else []
    return [
        ("k-i", f"a-i{n}", f"implement:#{n}", "Implement", {"verify_green": True}, [
            assistant(start, f"msg-i{n}", usage(inp=10, write=10000 * usd_scale, out=100)),
            assistant(start + 5, f"msg-i{n}b", usage(inp=1, read=10000 * usd_scale, out=50)),
        ]),
        ("k-c", f"a-c{n}", f"review:code:#{n}", "Review", {"findings": []}, [
            assistant(start + 6, f"msg-c{n}", usage(inp=2, write=5000, out=30)),
        ]),
        ("k-p", f"a-p{n}", f"publish:#{n}", "Publish", {"pr_number": 100 + n, "ci_green": True}, [
            *pub_prompt,
            assistant(start + 8, f"msg-p{n}", usage(inp=3, write=8000, out=40)),
            assistant(start + 10 + n, f"msg-p{n}b", usage(inp=3, read=8000, out=40)),
        ]),
    ]  # fmt: skip


class ReviewTierTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))  # its wf_done (#5) is a finished run before #606: no tier line
        self.wf = self.fx.dir / SESSION / "subagents" / "workflows"
        Fixture.run(self.wf / "wf_light1", task(11, 50, LIGHT))
        Fixture.run(self.wf / "wf_light2", task(12, 70, LIGHT, usd_scale=3))
        Fixture.run(self.wf / "wf_full", task(13, 90, FULL))
        # A line that only quotes the tier mid-line (a reviewer's digest, say) names none.
        Fixture.run(self.wf / "wf_quoted", task(14, 110, f"The publisher was told: {LIGHT}"))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict]:
        data = metrics.collect([self.fx.dir], {}, None, metrics.parse_time(UNTIL))
        md, record, _compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        return md, record

    def test_each_task_carries_the_tier_its_publisher_was_told(self) -> None:
        _md, record = self.build()
        tiers = {t["issue"]: t["tier"] for t in record["tasks"]}
        self.assertEqual(tiers, {5: "unknown", 11: "light", 12: "light", 13: "full", 14: "unknown"})

    def test_cost_and_wall_time_per_tier(self) -> None:
        md, record = self.build()
        rows = {r["tier"]: r for r in record["tiers"]}
        self.assertEqual([r["tier"] for r in record["tiers"]], ["light", "full", "unknown"])
        self.assertEqual({k: r["runs"] for k, r in rows.items()}, {"light": 2, "full": 1, "unknown": 2})
        tasks = {t["issue"]: t for t in record["tasks"]}
        light = [tasks[11], tasks[12]]
        self.assertAlmostEqual(rows["light"]["usd_sum"], sum(t["usd"] for t in light))
        self.assertAlmostEqual(rows["light"]["usd_max"], tasks[12]["usd"])
        self.assertGreater(tasks[12]["usd"], tasks[11]["usd"])
        self.assertAlmostEqual(rows["light"]["wall"], (tasks[11]["wall"] + tasks[12]["wall"]) / 2)
        self.assertEqual(rows["light"]["wall_max"], max(t["wall"] for t in light))
        self.assertAlmostEqual(rows["full"]["usd"], tasks[13]["usd"])
        text = "\n".join(md)
        self.assertIn("## Per review tier (#606): finished issue-task runs, medians in minutes", text)
        self.assertIn("| light | 2 |", text)
        self.assertIn("| full | 1 |", text)

    def test_run_names_the_tier_once_the_publisher_started(self) -> None:
        light = metrics.run_lines(metrics.run_spend(self.wf / "wf_light1", now=metrics.parse_time(UNTIL)))
        self.assertIn("; review tier light", light[0])
        before = metrics.run_lines(metrics.run_spend(self.wf / "wf_done", now=metrics.parse_time(UNTIL)))
        self.assertNotIn("review tier", before[0])

    def test_a_publisher_prompt_indented_by_the_harness_names_its_tier(self) -> None:
        Fixture.run(self.wf / "wf_ind_light", task(15, 130, LIGHT, indent=True))
        Fixture.run(self.wf / "wf_ind_full", task(16, 150, FULL, indent=True))
        _md, record = self.build()
        tiers = {t["issue"]: t["tier"] for t in record["tasks"]}
        self.assertEqual((tiers[15], tiers[16]), ("light", "full"))
        self.assertEqual(tiers[14], "unknown")  # a mid-line quote still names none


if __name__ == "__main__":
    unittest.main()
