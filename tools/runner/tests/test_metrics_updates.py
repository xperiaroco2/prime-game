"""`metrics` per path (#875): issue-task.js (#856) opens an update run's prompts with "Update run (update, #856):",
and `metrics` groups the finished issue-task runs into first runs, light update runs and full update runs."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, usage
from runner.tests.test_metrics_tiers import FULL, LIGHT, indented, prompt, task

UPDATE = "Update run (update, #856): this run continues the published PR of core/7-x; the change is in the task notes."
UPDATE_PUBLISHER = "Update run (update, #856): the update path: the reviewers read only the delta since the PR's head."


def update_task(n: int, start: float, tier_line: str | None, indent: bool = False, usd_scale: int = 1) -> list[tuple]:
    """task(), with the update line in its implementer's prompt (and its publisher's, when the publisher got one)."""
    agents = task(n, start, tier_line, usd_scale=usd_scale, indent=indent)
    text = f"Task: update the PR of issue #{n}.\n\n{UPDATE}\n\nThen:"
    agents[0][5].insert(0, prompt(start, indented(text) if indent else text))
    return agents


class UpdateRunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))  # its wf_done (#5): a finished run with no line, a first run
        self.wf = self.fx.dir / SESSION / "subagents" / "workflows"
        Fixture.run(self.wf / "wf_first", task(11, 50, FULL))
        Fixture.run(self.wf / "wf_light", update_task(12, 70, LIGHT))
        Fixture.run(self.wf / "wf_full", update_task(13, 90, FULL, usd_scale=3))
        Fixture.run(self.wf / "wf_ind", update_task(14, 110, LIGHT, indent=True))
        # A line that only quotes the update line mid-line names none: a first run.
        Fixture.run(self.wf / "wf_quoted", task(15, 130, f"The publisher was told: {UPDATE_PUBLISHER}"))
        # An update run stopped before its publisher: no tier.
        stopped = update_task(16, 150, None)
        Fixture.run(self.wf / "wf_stopped", stopped[:2])

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.fx.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL))

    def test_each_run_lands_in_its_path(self) -> None:
        _md, record, _compact = self.build()
        paths = {t["issue"]: t["path"] for t in record["tasks"]}
        self.assertEqual(paths[5], "first")  # no line at all
        self.assertEqual(paths[11], "first")
        self.assertEqual(paths[12], "update-light")
        self.assertEqual(paths[13], "update-full")
        self.assertEqual(paths[14], "update-light")  # the harness indents the line (#761)
        self.assertEqual(paths[15], "first")

    def test_rows_count_cost_and_agents(self) -> None:
        _md, record, _compact = self.build()
        rows = {r["path"]: r for r in record["update_runs"]}
        order = ["first", "update-light", "update-full", "update-unknown"]
        self.assertEqual([r["path"] for r in record["update_runs"]], order)
        counts = {k: r["runs"] for k, r in rows.items()}
        self.assertEqual(counts, {"first": 3, "update-light": 2, "update-full": 1, "update-unknown": 1})
        tasks = {t["issue"]: t for t in record["tasks"]}
        light = [tasks[12], tasks[14]]
        self.assertAlmostEqual(rows["update-light"]["usd"], sum(t["usd"] for t in light) / 2)
        self.assertAlmostEqual(rows["update-light"]["usd_mean"], sum(t["usd"] for t in light) / 2)
        self.assertAlmostEqual(rows["update-full"]["usd"], tasks[13]["usd"])
        self.assertEqual(rows["update-full"]["agents"], 3)
        self.assertEqual(rows["update-full"]["serious"], 0)

    def test_the_table_states_the_baseline_and_the_advice(self) -> None:
        md, record, compact = self.build()
        text = "\n".join(md)
        self.assertIn("## Update runs (#856)", text)
        self.assertIn("| update run (light delta) | 2 |", text)
        self.assertIn("| update run (full delta) | 1 |", text)
        self.assertIn("$7.60 to $14", text)
        self.assertEqual(sum(r["runs"] for r in record["update_runs"] if r["path"].startswith("update")), 4)
        self.assertIn("4 update runs: compare", text)
        self.assertNotIn("wait", next(line for line in compact if line.startswith("per task ")))

    def test_fewer_than_three_update_runs_wait(self) -> None:
        for wf in ("wf_full", "wf_ind"):
            for f in (self.wf / wf).rglob("*"):
                if f.is_file():
                    f.unlink()
        md, _record, compact = self.build()
        self.assertIn("fewer runs than 3: wait (2 update runs)", "\n".join(md))
        line = next(line for line in compact if line.startswith("per task "))
        self.assertIn(" | update runs (#856): first run 3 runs", line)
        self.assertIn("update run (light delta) 1 runs", line)
        self.assertIn("baseline $7.60 to $14", line)
        self.assertIn("fewer runs than 3: wait", line)


if __name__ == "__main__":
    unittest.main()
