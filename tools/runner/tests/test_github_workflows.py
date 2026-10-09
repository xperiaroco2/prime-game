"""The GitHub Actions files (docs/AGENT_WORKFLOW.md §11 CI and §15 Night jobs), parsed and checked before GitHub
runs them: a new scheduled workflow cannot be tried on a task branch (workflow_dispatch needs the file on the default
branch, docs.github.com "Events that trigger workflows"), so its first run is the night after the merge; once it is
there, `gh workflow run <file> --ref <branch>` runs the branch's version. The bash of nightly.yml's own logic runs
here under Git Bash (or bash), with stubs for gh and the runner.

PyYAML comes with the pinned gdtoolkit (its dependency), so it is there wherever `verify` runs; without it the tests
skip.
"""

import argparse
import contextlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, gdunit
from runner.common import git_bash

try:
    import yaml
except ImportError:  # pragma: no cover - only without gdtoolkit's dependencies
    yaml = None

ROOT = Path(__file__).resolve().parents[3]
GITHUB = ROOT / ".github"
SETUP = "./.github/actions/setup-toolchain"
# The actions CI used when the night jobs came (#189). Another one from the marketplace is a new dependency: the
# engineer's call (root CLAUDE.md, "Stop and ask before").
# actions/setup-node came with the signalling Worker's tests (#368; the M6 ADR D23).
KNOWN_ACTIONS = {
    "actions/checkout@v7",
    "actions/setup-python@v7",
    "actions/cache@v6",
    "actions/upload-artifact@v7",
    "actions/setup-node@v7",
}


def load(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if True in data:  # YAML 1.1 reads a bare `on:` key as the boolean true
        data["on"] = data.pop(True)
    return data


def steps_of(data: dict) -> list[dict]:
    if "runs" in data:
        return data["runs"].get("steps", [])
    return [step for job in data.get("jobs", {}).values() for step in job.get("steps", [])]


class CiPushTriggerTest(unittest.TestCase):
    """Without PyYAML (the test below it is skipped then): CI's push trigger is read as text."""

    def test_ci_runs_on_pushes_to_main_and_to_release_branches(self) -> None:
        # #622: `merge --base release/<x>` (and --sync-main) rely on CI instead of a local verify of the merged tree,
        # so a push to a release branch must run it.
        text = (GITHUB / "workflows" / "ci.yml").read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^  push:\n(?:    #.*\n)*    branches: \[main, release/\*\*\]$")


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

    def test_the_setup_action_installs_the_pinned_node_without_a_package_cache(self) -> None:
        steps = load(ROOT / SETUP / "action.yml")["runs"]["steps"]
        pins = next(i for i, step in enumerate(steps) if step.get("name") == "Read pins")
        self.assertIn("node=$(tools/run.sh pins --get node)", steps[pins]["run"])
        self.assertIn('echo "NODE_PIN=$node"', steps[pins]["run"])
        node = [i for i, step in enumerate(steps) if step.get("uses") == "actions/setup-node@v7"]
        self.assertEqual(len(node), 1)
        self.assertLess(pins, node[0])
        settings = {"node-version": "${{ env.NODE_PIN }}", "package-manager-cache": False}
        self.assertEqual(steps[node[0]]["with"], settings)

    def test_ci_keeps_its_triggers_and_runs_verify_after_the_shared_setup(self) -> None:
        data = load(GITHUB / "workflows" / "ci.yml")
        # release/** (#622): `merge --base release/<x>` relies on CI, so a release branch's tree is tested on push.
        push = {"branches": ["main", "release/**"]}
        self.assertEqual(data["on"], {"pull_request": None, "push": push, "workflow_dispatch": None})
        steps = data["jobs"]["verify"]["steps"]
        uses = [step.get("uses", "") for step in steps]
        self.assertEqual(uses[:2], ["actions/checkout@v7", SETUP])
        self.assertIn("GODOT_BIN=$HOME/godot/godot tools/run.sh verify --full", [step.get("run") for step in steps])

    def test_every_workflow_verify_runs_the_full_suite(self) -> None:
        # #605: a plain `verify` runs only doctor, lint and check; CI is where every test runs, so each workflow's
        # verify call is `verify --full`, and the parser reads it as such.
        calls = []
        for path in sorted((GITHUB / "workflows").glob("*.yml")):
            for job in load(path)["jobs"].values():
                for step in job.get("steps", []):
                    run = step.get("run", "")
                    if "tools/run.sh verify" in run:
                        calls.append((path.name, run))
                        argv = run.split("tools/run.sh ", 1)[1].split()
                        args = cli.build_parser().parse_args(argv)
                        self.assertEqual((args.command, args.full, args.fail_fast), ("verify", True, False), run)
        self.assertIn("ci.yml", [name for name, _run in calls])

    def test_ci_runs_the_runner_on_the_pinned_minimum_python(self) -> None:
        # #349: the verify job's Python is 3.12, the runner's stated minimum 3.11 (pins.PYTHON_MIN).
        steps = load(GITHUB / "workflows" / "ci.yml")["jobs"]["python-min"]["steps"]
        runs = [step.get("run", "") for step in steps]
        setup = [step for step in steps if step.get("uses") == "actions/setup-python@v7"]
        self.assertEqual(len(setup), 1)
        self.assertEqual(setup[0]["with"]["python-version"], "${{ steps.pins.outputs.python }}")
        pins = next(i for i, step in enumerate(steps) if step.get("id") == "pins")
        self.assertIn("tools/run.sh pins --get python_min", runs[pins])
        self.assertLess(pins, steps.index(setup[0]))
        order = [runs.index("python -m compileall -q tools"), runs.index("tools/run.sh selftest --group python")]
        self.assertEqual(order, sorted(order))
        self.assertLess(steps.index(setup[0]), order[0])
        self.assertIn("tools/run.sh pins --get gdtoolkit", runs[pins])
        # A failing `pins --get` must stop the step, not write an empty version (setup-python would then take 3.12).
        self.assertNotIn("$(tools/run.sh", "".join(line for line in runs[pins].splitlines() if "echo" in line))
        # After setup-python, the job checks the interpreter it runs is the pin's, and hands it to tools/run.sh.
        guard = next(i for i, run in enumerate(runs) if "sys.version_info" in run)
        self.assertLess(steps.index(setup[0]), guard)
        self.assertLess(guard, order[0])
        self.assertIn("${{ steps.pins.outputs.python }}", runs[guard])
        self.assertIn('PYTHON_BIN=$(command -v python)" >> "$GITHUB_ENV"', runs[guard])
        self.assertNotIn(SETUP, [step.get("uses") for step in steps], "the shared setup pins Python 3.12")

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
        self.assertLess(cache[0], runs.index("GODOT_BIN=$HOME/godot/godot tools/run.sh verify --full"))

    def test_nightly_runs_on_a_schedule_and_by_hand_with_the_least_permissions(self) -> None:
        data = load(GITHUB / "workflows" / "nightly.yml")
        self.assertEqual(set(data["on"]), {"schedule", "workflow_dispatch"})
        self.assertEqual(len(data["on"]["schedule"]), 1)
        minute, hour, *rest = data["on"]["schedule"][0]["cron"].split()
        self.assertEqual(rest, ["*", "*", "*"], "once a night")
        self.assertTrue(0 <= int(hour) <= 5 and minute != "0", "a night hour UTC, off the hour")
        self.assertEqual(data["permissions"], {"contents": "read"})
        # #272: by hand, optionally one ref alone.
        ref = data["on"]["workflow_dispatch"]["inputs"]["ref"]
        self.assertEqual((ref["type"], ref["required"], ref["default"]), ("string", False, ""))

    def test_the_refs_job_picks_the_runs_ref_and_the_newest_release_branch(self) -> None:
        # #272: the schedule runs main's file, so the release ref is found at run time and checked out by each job.
        jobs = load(GITHUB / "workflows" / "nightly.yml")["jobs"]
        refs = jobs["refs"]
        self.assertNotIn("permissions", refs, "the workflow's contents: read is enough")
        self.assertNotIn("needs", refs)
        self.assertEqual(set(refs["outputs"]), {"matrix", "list"})
        self.assertEqual(refs["env"]["INPUT_REF"], "${{ inputs.ref }}")
        script = "".join(step.get("run", "") for step in refs["steps"])
        self.assertIn("matching-refs/heads/release/", script)
        self.assertIn("sort -V", script)
        for name in ("$INPUT_REF", "$GITHUB_REF_NAME", "$GITHUB_SHA", "$GITHUB_OUTPUT", "::error::"):
            self.assertIn(name, script)

    def test_every_night_job_sets_up_like_ci_and_the_report_job_waits_for_all_of_them(self) -> None:
        jobs = load(GITHUB / "workflows" / "nightly.yml")["jobs"]
        self.assertIn("flaky", jobs)
        night = [name for name in jobs if name not in ("refs", "report")]
        artifacts = []
        for name in night:
            job = jobs[name]
            self.assertIn("timeout-minutes", job, name)
            self.assertNotIn("permissions", job, f"{name}: the workflow's contents: read is enough")
            uses = [step.get("uses", "") for step in job["steps"]]
            self.assertEqual(uses[:2], ["actions/checkout@v7", SETUP], name)
            self.assertIn("actions/upload-artifact@v7", uses, f"{name}: uploads its reports")
            # #272: once per ref of the night, each ref's own commit, its artifacts named with the ref.
            self.assertEqual(job["needs"], "refs", name)
            self.assertEqual(job["strategy"]["matrix"], "${{ fromJSON(needs.refs.outputs.matrix) }}", name)
            self.assertIs(job["strategy"]["fail-fast"], False, f"{name}: one ref's failure keeps the other's run")
            self.assertIn("${{ matrix.ref }}", job["name"], name)
            self.assertEqual(job["steps"][0]["with"]["ref"], "${{ matrix.sha }}", name)
            upload = next(step for step in job["steps"] if step.get("uses") == "actions/upload-artifact@v7")
            self.assertTrue(upload["with"]["name"].endswith("-${{ matrix.slug }}"), name)
            artifacts.append(upload["with"]["name"])
            # The ref's runner is asked for the job's options before anything runs on it.
            names = [step.get("name", "") for step in job["steps"]]
            check = names.index("The ref's runner has the job's options")
            self.assertIn("--help", job["steps"][check]["run"], name)
            self.assertLess(check, names.index("doctor"), name)
            command, *options = job["steps"][check]["env"]["CALLS"].split()
            later = "".join(step.get("run", "") for step in job["steps"][check + 1 :])
            self.assertIn(f"tools/run.sh {command} ", later, name)
            for option in options:
                self.assertIn(option, later, f"{name}: checks {option}, which it calls")
        self.assertEqual(len(set(artifacts)), len(artifacts), "one artifact name per job")
        runs = [step.get("run", "") for step in jobs["flaky"]["steps"]]
        self.assertTrue(any("tools/run.sh test --repeat 3" in run for run in runs))
        self.assertIn("perf", jobs)
        chaos = [step.get("run", "") for step in jobs["chaos"]["steps"]]
        self.assertTrue(any("tools/run.sh bots --chaos --long --runs" in run for run in chaos))
        self.assertTrue(any("tools/run.sh bots --chaos --long --enet" in run for run in chaos))
        report = jobs["report"]
        self.assertEqual(sorted(report["needs"]), sorted(night + ["refs"]))
        # actions: read lists the run's jobs, whose names hold their refs (#272).
        self.assertEqual(report["permissions"], {"actions": "read", "contents": "read", "issues": "write"})
        self.assertIn("failure", report["if"])
        script = "".join(step.get("run", "") for step in report["steps"])
        for command in ("gh issue list", "gh issue create", "gh issue comment", "/actions/runs/$GITHUB_RUN_ID/jobs"):
            self.assertIn(command, script)
        self.assertEqual(report["env"]["TITLE"], "Night jobs")
        self.assertEqual(report["env"]["REFS"], "${{ needs.refs.outputs.list }}")

    def test_perf_compares_with_the_last_nights_report_kept_in_the_cache(self) -> None:
        steps = load(GITHUB / "workflows" / "nightly.yml")["jobs"]["perf"]["steps"]
        names = [step.get("name", step.get("uses", "")) for step in steps]
        cache = next(step for step in steps if step.get("uses") == "actions/cache@v6")["with"]
        # A new key every run, so each successful night saves its report; the prefix restores the newest of the same
        # ref (#272), ended by ":", which no ref name holds.
        self.assertIn("${{ github.run_id }}", cache["key"])
        self.assertTrue(cache["key"].startswith(cache["restore-keys"]))
        self.assertTrue(cache["restore-keys"].endswith(":${{ matrix.ref }}:"))
        last = cache["path"] + "/last.json"
        run = next(step["run"] for step in steps if "tools/run.sh perf" in step.get("run", ""))
        self.assertIn(f"--baseline {last}", run)
        self.assertNotIn("verify", run)
        keep = next(step["run"] for step in steps if step.get("name") == "Keep this report for the next night")
        self.assertIn(last, keep)
        self.assertLess(names.index("The last night's report"), names.index("perf"))
        self.assertLess(names.index("perf"), names.index("Keep this report for the next night"))

    def test_ci_tests_the_frame_bound_suites_at_fixed_fps_and_the_nightly_flaky_job_in_real_time(self) -> None:
        # #341, the engineer's option (b) on PR #323. CI runs `verify --full` (test_ci_keeps_its_triggers_...), whose
        # test step takes gdunit.FIXED_FPS_SUITES at fixed fps (test_gdunit_shards, the verify pin). The flaky job's
        # `test --repeat` stays real-time, the run that still meets the #222 class (several physics steps a frame).
        ci = [step.get("run", "") for step in load(GITHUB / "workflows" / "ci.yml")["jobs"]["verify"]["steps"]]
        self.assertFalse([run for run in ci if "--real-time" in run or "tools/run.sh test" in run], ci)
        steps = load(GITHUB / "workflows" / "nightly.yml")["jobs"]["flaky"]["steps"]
        runs = [step["run"] for step in steps if "tools/run.sh test" in step.get("run", "")]
        self.assertEqual(len(runs), 1, runs)
        argv = runs[0].split("tools/run.sh ", 1)[1].split()
        args = cli.build_parser().parse_args(argv)
        self.assertEqual((args.command, args.paths), ("test", []))
        self.assertIsNotNone(args.repeat)
        self.assertIn(args.fixed_fps, (None, False), "the nightly flaky job must stay real-time (#341)")
        with mock.patch.object(gdunit, "repeat", return_value=0) as repeat:
            self.assertEqual(cli.main(argv), 0)
        self.assertIn(repeat.call_args.kwargs.get("fixed_fps"), (None, False))


# A stub of gh for the `refs` step: canned output instead of GitHub's API (and of gh's --jq, which it skips). Each
# call goes to $GH_CALLS.
FAKE_GH = """gh() {
  echo "$*" >> "$GH_CALLS"
  [ -z "$FAKE_FAIL" ] || return 1
  case "$*" in
    *git/matching-refs/heads/release/*) printf '%s' "$FAKE_RELEASES" ;;
    *repos/o/r/commits/*) printf '%s\\n' "$FAKE_SHA" ;;
    *) echo "unexpected: gh $*" >&2; return 2 ;;
  esac
}
"""
MAIN_SHA = "a" * 40


@unittest.skipIf(yaml is None, "PyYAML is missing (it comes with gdtoolkit)")
class NightlyScriptsTest(unittest.TestCase):
    """The bash of nightly.yml's steps, run as GitHub runs a `run:` (bash --noprofile --norc -eo pipefail)."""

    def script(self, job: str, name: str) -> str:
        steps = load(GITHUB / "workflows" / "nightly.yml")["jobs"][job]["steps"]
        return next(step["run"] for step in steps if step.get("name") == name)

    def bash(self, text: str, cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        bash = git_bash()
        self.assertIsNotNone(bash, "Git Bash (or bash) is needed to run the workflow's scripts")
        path = cwd / "step.sh"
        path.write_bytes(text.encode("utf-8"))
        return subprocess.run(
            [str(bash), "--noprofile", "--norc", "-eo", "pipefail", path.as_posix()],
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env={**os.environ, **env},
            timeout=60,
        )

    def refs(self, input_ref: str = "", releases: str = "", sha: str = "", fail: bool = False) -> dict:
        """Runs the `refs` step; returns its exit code, outputs, stdout and gh calls."""
        with tempfile.TemporaryDirectory() as tmp:
            where = Path(tmp)
            output, summary, calls = where / "output", where / "summary", where / "calls"
            for path in (output, summary, calls):
                path.write_bytes(b"")
            env = {
                "GITHUB_REPOSITORY": "o/r",
                "GITHUB_REF_NAME": "main",
                "GITHUB_SHA": MAIN_SHA,
                "GITHUB_OUTPUT": output.as_posix(),
                "GITHUB_STEP_SUMMARY": summary.as_posix(),
                "GH_CALLS": calls.as_posix(),
                "INPUT_REF": input_ref,
                "FAKE_RELEASES": releases,
                "FAKE_SHA": sha,
                "FAKE_FAIL": "1" if fail else "",
            }
            res = self.bash(FAKE_GH + self.script("refs", "The run's ref and the newest release branch"), where, env)
            outputs = dict(line.split("=", 1) for line in output.read_text(encoding="utf-8").splitlines() if line)
            return {
                "code": res.returncode,
                "stdout": res.stdout,
                "outputs": outputs,
                "matrix": json.loads(outputs["matrix"])["include"] if "matrix" in outputs else None,
                "calls": calls.read_text(encoding="utf-8"),
            }

    def test_without_a_release_branch_the_runs_ref_runs_alone(self) -> None:
        got = self.refs()
        self.assertEqual(got["code"], 0, got["stdout"])
        self.assertEqual(got["matrix"], [{"ref": "main", "sha": MAIN_SHA, "slug": "main"}])
        self.assertEqual(got["outputs"]["list"], "`main` at aaaaaaa")

    def test_the_newest_release_branch_by_version_joins_the_runs_ref(self) -> None:
        releases = "".join(f"release/{name} {name[1:] * 20}\n" for name in ("m9", "m10", "m5"))
        got = self.refs(releases=releases)
        self.assertEqual(got["code"], 0, got["stdout"])
        self.assertEqual(
            got["matrix"],
            [
                {"ref": "main", "sha": MAIN_SHA, "slug": "main"},
                {"ref": "release/m10", "sha": "10" * 20, "slug": "release-m10"},
            ],
        )
        self.assertEqual(got["outputs"]["list"], "`main` at aaaaaaa, `release/m10` at 1010101")

    def test_a_release_branch_at_the_runs_commit_runs_once(self) -> None:
        got = self.refs(releases=f"release/m5 {'5' * 40}\nrelease/m6 {MAIN_SHA}\n")
        self.assertEqual(got["code"], 0, got["stdout"])
        self.assertEqual(got["matrix"], [{"ref": "main", "sha": MAIN_SHA, "slug": "main"}])

    def test_a_dispatch_ref_runs_alone_at_its_commit(self) -> None:
        got = self.refs(input_ref="release/m5", releases=f"release/m6 {'6' * 40}\n", sha="b" * 40)
        self.assertEqual(got["code"], 0, got["stdout"])
        self.assertEqual(got["matrix"], [{"ref": "release/m5", "sha": "b" * 40, "slug": "release-m5"}])
        self.assertIn("repos/o/r/commits/release%2Fm5", got["calls"])
        self.assertNotIn("matching-refs", got["calls"])

    def test_a_ref_with_another_character_or_a_failed_api_call_fails_clearly(self) -> None:
        for case in ({"input_ref": 'x";y'}, {"fail": True}, {"input_ref": "release/m5", "fail": True}):
            got = self.refs(**case)
            self.assertNotEqual(got["code"], 0, case)
            self.assertIn("::error::", got["stdout"], case)
            self.assertIsNone(got["matrix"], case)

    def check_options(self, calls: str, helps: dict[str, str]) -> subprocess.CompletedProcess[str]:
        """Runs a night job's options check against a runner stub that prints the given --help texts."""
        with tempfile.TemporaryDirectory() as tmp:
            where = Path(tmp)
            (where / "tools").mkdir()
            for command, text in helps.items():
                (where / "tools" / f"help-{command}.txt").write_bytes(text.encode("utf-8"))
            run = where / "tools" / "run.sh"
            run.write_bytes(b'#!/usr/bin/env bash\n[ "$2" = --help ] && cat "$(dirname "$0")/help-$1.txt"\n')
            run.chmod(0o755)
            return self.bash(self.script(calls[0], calls[1]), where, {"CALLS": calls[2], "REF": "release/m0"})

    def real_help(self, command: str) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(SystemExit):
            cli.build_parser().parse_args([command, "--help"])
        return out.getvalue()

    def jobs_calls(self) -> list[tuple[str, str, str]]:
        jobs = load(GITHUB / "workflows" / "nightly.yml")["jobs"]
        check = "The ref's runner has the job's options"
        return [
            (name, check, step["env"]["CALLS"])
            for name, job in jobs.items()
            for step in job.get("steps", [])
            if step.get("name") == check
        ]

    def test_the_options_check_passes_on_this_runner(self) -> None:
        calls = self.jobs_calls()
        self.assertEqual({name for name, _, _ in calls}, {"flaky", "perf", "chaos"})
        for call in calls:
            command = call[2].split()[0]
            res = self.check_options(call, {command: self.real_help(command)})
            self.assertEqual(res.returncode, 0, f"{call}: {res.stdout}{res.stderr}")

    def test_the_options_check_fails_on_a_runner_that_names_an_option_only_in_help_text(self) -> None:
        # An older runner's `bots`: no --chaos, but its other options' help texts begin with "--chaos:".
        old = argparse.ArgumentParser(prog="run bots")
        for option in ("--seed", "--runs"):
            old.add_argument(option, help="--chaos: a number")
        for option in ("--long", "--enet"):
            old.add_argument(option, action="store_true", help="--chaos: a switch")
        chaos = next(call for call in self.jobs_calls() if call[0] == "chaos")
        res = self.check_options(chaos, {"bots": old.format_help()})
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("::error::The runner of release/m0 has no 'bots --chaos'", res.stdout)


if __name__ == "__main__":
    unittest.main()
