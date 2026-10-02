"""The GitHub Actions files (docs/AGENT_WORKFLOW.md §11 CI and §15 Night jobs), parsed and checked before GitHub
runs them: a scheduled workflow cannot be tried on a task branch (workflow_dispatch needs the file on the default
branch, docs.github.com "Events that trigger workflows"), so its first run is the night after the merge.

PyYAML comes with the pinned gdtoolkit (its dependency), so it is there wherever `verify` runs; without it the tests
skip.
"""

import unittest
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - only without gdtoolkit's dependencies
    yaml = None

ROOT = Path(__file__).resolve().parents[3]
GITHUB = ROOT / ".github"
SETUP = "./.github/actions/setup-toolchain"
# The actions CI used when the night jobs came (#189). Another one from the marketplace is a new dependency: the
# engineer's call (root CLAUDE.md, "Stop and ask before").
KNOWN_ACTIONS = {"actions/checkout@v7", "actions/setup-python@v7", "actions/cache@v6", "actions/upload-artifact@v7"}


def load(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if True in data:  # YAML 1.1 reads a bare `on:` key as the boolean true
        data["on"] = data.pop(True)
    return data


def steps_of(data: dict) -> list[dict]:
    if "runs" in data:
        return data["runs"].get("steps", [])
    return [step for job in data.get("jobs", {}).values() for step in job.get("steps", [])]


@unittest.skipIf(yaml is None, "PyYAML is missing (it comes with gdtoolkit)")
class GithubWorkflowsTest(unittest.TestCase):
    def files(self) -> list[Path]:
        return sorted(GITHUB.glob("workflows/*.yml")) + sorted(GITHUB.glob("actions/*/action.yml"))

    def test_every_file_parses_and_uses_only_local_or_known_actions(self) -> None:
        self.assertTrue(self.files())
        for path in self.files():
            for step in steps_of(load(path)):
                used = step.get("uses")
                if used and not used.startswith("./"):
                    self.assertIn(used, KNOWN_ACTIONS, f"{path.relative_to(ROOT).as_posix()}: a new action")
                if used and used.startswith("./"):
                    self.assertTrue((ROOT / used / "action.yml").is_file(), f"{used} has no action.yml")

    def test_the_setup_action_is_composite_and_every_run_step_names_its_shell(self) -> None:
        data = load(ROOT / SETUP / "action.yml")
        self.assertEqual(data["runs"]["using"], "composite")
        for step in data["runs"]["steps"]:
            if "run" in step:
                self.assertEqual(step.get("shell"), "bash", step.get("name"))

    def test_ci_keeps_its_triggers_and_runs_verify_after_the_shared_setup(self) -> None:
        data = load(GITHUB / "workflows" / "ci.yml")
        self.assertEqual(data["on"], {"pull_request": None, "push": {"branches": ["main"]}, "workflow_dispatch": None})
        steps = data["jobs"]["verify"]["steps"]
        uses = [step.get("uses", "") for step in steps]
        self.assertEqual(uses[:2], ["actions/checkout@v7", SETUP])
        self.assertIn("GODOT_BIN=$HOME/godot/godot tools/run.sh verify", [step.get("run") for step in steps])

    def test_ci_restores_the_last_gdunit_times_before_verify(self) -> None:
        # `test` balances its shards by them (#182); a fresh CI checkout has none of its own.
        steps = load(GITHUB / "workflows" / "ci.yml")["jobs"]["verify"]["steps"]
        runs = [step.get("run") for step in steps]
        cache = [i for i, step in enumerate(steps) if step.get("uses") == "actions/cache@v6"]
        self.assertEqual(len(cache), 1)
        settings = steps[cache[0]]["with"]
        self.assertEqual(settings["path"], "tools/out/logs/gdunit-times.json")
        self.assertEqual(settings["restore-keys"], "gdunit-times-")
        self.assertIn("${{ github.run_id }}", settings["key"])
        self.assertLess(cache[0], runs.index("GODOT_BIN=$HOME/godot/godot tools/run.sh verify"))

    def test_nightly_runs_on_a_schedule_and_by_hand_with_the_least_permissions(self) -> None:
        data = load(GITHUB / "workflows" / "nightly.yml")
        self.assertEqual(set(data["on"]), {"schedule", "workflow_dispatch"})
        self.assertEqual(len(data["on"]["schedule"]), 1)
        minute, hour, *rest = data["on"]["schedule"][0]["cron"].split()
        self.assertEqual(rest, ["*", "*", "*"], "once a night")
        self.assertTrue(0 <= int(hour) <= 5 and minute != "0", "a night hour UTC, off the hour")
        self.assertEqual(data["permissions"], {"contents": "read"})

    def test_every_night_job_sets_up_like_ci_and_the_report_job_waits_for_all_of_them(self) -> None:
        jobs = load(GITHUB / "workflows" / "nightly.yml")["jobs"]
        self.assertIn("flaky", jobs)
        night = [name for name in jobs if name != "report"]
        for name in night:
            job = jobs[name]
            self.assertIn("timeout-minutes", job, name)
            self.assertNotIn("permissions", job, f"{name}: the workflow's contents: read is enough")
            uses = [step.get("uses", "") for step in job["steps"]]
            self.assertEqual(uses[:2], ["actions/checkout@v7", SETUP], name)
            self.assertIn("actions/upload-artifact@v7", uses, f"{name}: uploads its reports")
        runs = [step.get("run", "") for step in jobs["flaky"]["steps"]]
        self.assertTrue(any("tools/run.sh test --repeat 3" in run for run in runs))
        report = jobs["report"]
        self.assertEqual(sorted(report["needs"]), sorted(night))
        self.assertEqual(report["permissions"], {"contents": "read", "issues": "write"})
        self.assertIn("failure", report["if"])
        script = "".join(step.get("run", "") for step in report["steps"])
        for command in ("gh issue list", "gh issue create", "gh issue comment"):
            self.assertIn(command, script)
        self.assertEqual(report["env"]["TITLE"], "Night jobs")


if __name__ == "__main__":
    unittest.main()
