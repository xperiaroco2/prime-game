"""The saved workflows in .claude/workflows/: run each script under Node with stub agents and read the prompts.

The scripts are Claude Code workflow bodies (top-level await and return), so the harness wraps each one in an async
function and passes `args`, `agent`, `parallel`, `phase` and `log`. Node is not a project dependency: without it the
tests skip.
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner.common import ROOT

WORKFLOWS = ROOT / ".claude" / "workflows"
NODE = shutil.which("node")

# Each stub agent returns a passing result shaped for its label, so the script runs to its end.
HARNESS = """
import fs from 'node:fs'
const [, , file, argsJson, pathsJson] = process.argv
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const paths = JSON.parse(pathsJson)
const calls = []
async function agent(prompt, opts) {
  calls.push({ label: opts.label, prompt })
  if (opts.label.startsWith('implement')) return { verify_green: true, complete: true, summary: 's', changed_paths: paths }
  if (opts.label.startsWith('rebase')) return { up_to_date: true, verify_green: true, published: true, changed_paths: paths }
  if (opts.label.startsWith('review')) return { reviewer: 'r', verdict: 'ok', findings: [] }
  return { published: true, handoff_posted: true }
}
const run = new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', src)
await run(JSON.parse(argsJson), agent, thunks => Promise.all(thunks.map(t => t())), () => {}, () => {})
process.stdout.write(JSON.stringify(calls))
"""

ARGS = {
    "n": 7,
    "pr": 8,
    "title": "t",
    "wt": "D:/prime-game/.claude/worktrees/7",
    "branch": "tooling/7-x",
    "notes": "n",
    "why": "w",
}
STASH_RULE = "Never use `git stash`"


def run_workflow(script: Path, base: str | None, paths: list[str]) -> list[dict[str, str]]:
    """The agent calls of one run: [{label, prompt}], in order."""
    args = dict(ARGS, **({"base": base} if base else {}))
    with tempfile.TemporaryDirectory() as tmp:
        harness = Path(tmp) / "harness.mjs"
        harness.write_bytes(HARNESS.encode("utf-8"))
        res = subprocess.run(
            [str(NODE), str(harness), str(script), json.dumps(args), json.dumps(paths)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=60,
        )
    if res.returncode != 0:
        raise AssertionError(f"{script.name} failed under node:\n{res.stderr[-2000:]}")
    return json.loads(res.stdout)


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class WorkflowTest(unittest.TestCase):
    def test_every_agent_gets_the_no_stash_rule(self) -> None:
        # Night run of #96: a publisher's `git stash drop "$ref"` asked; agents set work aside with commits instead.
        for name in ("issue-task.js", "pr-rebase.js"):
            calls = run_workflow(WORKFLOWS / name, "release/m3", ["core/x.gd"])
            for call in calls:
                if call["label"].startswith("review"):
                    continue  # reviewers are read-only
                with self.subTest(workflow=name, agent=call["label"]):
                    self.assertIn(STASH_RULE, call["prompt"])
                    self.assertIn("GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/release/m3", call["prompt"])
                    self.assertIn("$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash", call["prompt"])
                    self.assertIn("git reset --soft HEAD~1", call["prompt"])

    def test_a_release_base_reaches_publish_and_the_pr(self) -> None:
        # A release base is always passed, so publish never depends on the record start --base left (#113).
        for name in ("issue-task.js", "pr-rebase.js"):
            with self.subTest(workflow=name):
                prompts = "\n".join(c["prompt"] for c in run_workflow(WORKFLOWS / name, "release/m3", ["core/x.gd"]))
                self.assertIn("`tools\\run.cmd publish --base release/m3`", prompts)
        prompts = "\n".join(c["prompt"] for c in run_workflow(WORKFLOWS / "issue-task.js", "release/m3", ["core/x.gd"]))
        self.assertIn("gh pr create --base release/m3", prompts)
        self.assertIn("branch.tooling/7-x.primeBaseTip", prompts)

    def test_a_stacked_parent_base_is_left_to_publish(self) -> None:
        # Passing a parent's task branch would fail once the parent merges and its branch is deleted; without --base
        # publish follows the PR's live base, which GitHub retargets.
        for name in ("issue-task.js", "pr-rebase.js"):
            with self.subTest(workflow=name):
                calls = run_workflow(WORKFLOWS / name, "tooling/5-parent", ["core/x.gd"])
                prompts = "\n".join(c["prompt"] for c in calls)
                self.assertIn("`tools\\run.cmd publish`", prompts)
                self.assertNotIn("publish --base", prompts)

    def test_main_base_publishes_without_base(self) -> None:
        for name in ("issue-task.js", "pr-rebase.js"):
            with self.subTest(workflow=name):
                prompts = "\n".join(c["prompt"] for c in run_workflow(WORKFLOWS / name, None, ["core/x.gd"]))
                self.assertNotIn("publish --base", prompts)
                self.assertNotIn("primeBaseTip", prompts)

    def test_the_publisher_names_a_relayed_agreement(self) -> None:
        # #128: a change the engineer says was agreed with the designer gets the wording and the tag in its PR,
        # not only the MVP-provisional note, so the designer sees it later.
        calls = run_workflow(WORKFLOWS / "issue-task.js", None, ["content/roles/x.tres"])
        publish = [c["prompt"] for c in calls if c["label"].startswith("publish")]
        self.assertEqual(len(publish), 1, [c["label"] for c in calls])
        self.assertIn('"agreed with the designer, relayed by the engineer"', publish[0])
        self.assertIn("@SwiftySinister", publish[0])

    def test_the_leak_test_gets_a_netcode_review(self) -> None:
        # #115 touched only tests/ and tools/: no netcode review was routed, and one run by hand found a major.
        cases = (
            (["tests/harness/bots/leak_check.gd", "tools/runner/bots.py"], True),
            (["core/match/match.gd"], True),
            (["tools/runner/bots.py", "tests/unit/x_test.gd", "docs/x.md"], False),
        )
        for name in ("issue-task.js", "pr-rebase.js"):
            for paths, routed in cases:
                with self.subTest(workflow=name, paths=paths):
                    labels = [c["label"] for c in run_workflow(WORKFLOWS / name, "release/m3", paths)]
                    self.assertEqual(any(label.startswith("review:netcode") for label in labels), routed, labels)

    def test_a_client_change_gets_a_netcode_review(self) -> None:
        # The client renders public data, so a rendering leak is an information leak (#158): the M4 manager ran the
        # netcode review on PR #154 by hand twice, and both runs found real problems.
        cases = (
            (["client/player/first_person_camera.gd"], True),
            (["tools/runner/workflows.py"], False),
        )
        for name in ("issue-task.js", "pr-rebase.js"):
            for paths, routed in cases:
                with self.subTest(workflow=name, paths=paths):
                    labels = [c["label"] for c in run_workflow(WORKFLOWS / name, "release/m4", paths)]
                    self.assertEqual(any(label.startswith("review:netcode") for label in labels), routed, labels)


if __name__ == "__main__":
    unittest.main()
