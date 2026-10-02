"""The saved workflows in .claude/workflows/: run each script under Node with stub agents and read the prompts.

The scripts are Claude Code workflow bodies (top-level await and return), so the harness wraps each one in an async
function and passes `args`, `agent`, `parallel`, `phase` and `log`. Node is not a project dependency: without it the
tests skip, except on GitHub Actions, where a missing Node fails `test_github_actions_runs_the_workflow_tests`.

Snapshots: other managers launch these scripts by name from their own copies and resume runs with the same args, and a
resume replays an agent only while its prompt and options are unchanged. So with none of the optional pipeline-v2 args
(docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item 4) every agent's prompt, label, phase,
schema and options must stay byte-identical: `workflow_snapshots/<script>/<case>.txt` holds them for representative
arg sets, captured from the scripts on origin/main before v2 changed them. A deliberate change of a default prompt
rewrites them: run `selftest` once with PRIME_WORKFLOW_SNAPSHOTS=update (the snapshot test then fails on purpose,
naming the files it wrote), review the diff, commit it with the change, and run `selftest` again without the variable.
"""

import difflib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner.common import ROOT

WORKFLOWS = ROOT / ".claude" / "workflows"
SNAPSHOTS = Path(__file__).resolve().parent / "workflow_snapshots"
NODE = shutil.which("node")
UPDATE = os.environ.get("PRIME_WORKFLOW_SNAPSHOTS") == "update"

# One Node process runs a list of jobs ({file, args, stub}) read from stdin and prints one result per job: the phase
# and agent calls in order (each agent's options as JSON.stringify writes them, so key order counts), the value the
# script returned and the error it threw. Each stub agent returns a passing result shaped for its label, so the script
# runs to its end; stub.queues ({label prefix: [results]}) overrides that, one result per call in order (null: the
# agent died).
HARNESS = """
import fs from 'node:fs'
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const jobs = JSON.parse(fs.readFileSync(0, 'utf8'))
const out = []
for (const job of jobs) {
  const src = fs.readFileSync(job.file, 'utf8').replace(/^export const meta/m, 'const meta')
  const stub = job.stub || {}
  const queues = JSON.parse(JSON.stringify(stub.queues || {}))
  const paths = stub.paths || []
  const events = []
  const result = label => {
    for (const prefix of Object.keys(queues)) {
      if (label.startsWith(prefix) && queues[prefix].length) return queues[prefix].shift()
    }
    if (label.startsWith('implement')) return { verify_green: true, complete: true, summary: 's', changed_paths: paths }
    if (label.startsWith('rebase')) return { up_to_date: true, verify_green: true, published: true, changed_paths: paths }
    if (label.startsWith('plan')) return { summary: 'p', criteria: ['c'], files: ['f'], tests: ['t'] }
    if (label.startsWith('review')) return { reviewer: 'r', verdict: 'ok', findings: stub.findings || [] }
    if (label.startsWith('test-review')) return { available: true, exit_2: false, findings: [], mutants: [] }
    if (label.startsWith('skeptic')) return { refuted: false, reason: 'it stands' }
    if (label.startsWith('fix')) return { fixed: [], verify_green: true, published: true, ci_green: true }
    return { published: true, handoff_posted: true }
  }
  const agent = async (prompt, opts) => {
    events.push({ kind: 'agent', label: opts.label, opts: JSON.stringify(opts), prompt })
    return result(opts.label)
  }
  const phase = title => { events.push({ kind: 'phase', title }) }
  const log = message => { events.push({ kind: 'log', message }) }
  // As the Workflow tool's parallel(): a thunk that throws resolves to null.
  const parallel = thunks => Promise.all(thunks.map(t => t().catch(() => null)))
  let returned = null
  let error = null
  try {
    const run = new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', src)
    returned = await run(job.args, agent, parallel, phase, log)
  } catch (e) {
    error = String(e && e.message)
  }
  out.push({ events, returned: returned === undefined ? null : returned, error })
}
process.stdout.write(JSON.stringify(out))
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
MAJOR = {"severity": "major", "file": "core/match/vote.gd", "line": 12, "problem": "p1", "fix": "f1"}
MINOR = {"severity": "minor", "file": "core/match/vote.gd", "line": 30, "problem": "p2", "fix": "f2"}

# The representative arg sets of the snapshots: (case, args over ARGS, stub). A code task per area, a design task, a
# stacked base, a release base, every optional v1 arg, no changed paths, a red first agent and (pr-rebase) a fix round.
SNAPSHOT_CASES = {
    "issue-task.js": [
        ("core-release", {"branch": "core/7-x", "base": "release/m5"}, {"paths": ["core/match/vote.gd", "tests/unit/match/vote_test.gd"]}),
        ("net-main", {"branch": "net/7-x"}, {"paths": ["net/protocol/codec.gd"]}),
        ("server-release", {"branch": "server/7-x", "base": "release/m5"}, {"paths": ["server/host_session.gd"]}),
        ("client-release", {"branch": "client/7-x", "base": "release/m5"}, {"paths": ["client/hud/hud.gd", "client/hud/hud.tscn"]}),
        ("voice-stacked", {"branch": "voice/7-x", "base": "net/5-parent"}, {"paths": ["voice/mixer.gd"]}),
        ("tooling-main", {"branch": "tooling/7-x"}, {"paths": ["tools/runner/start.py", "docs/AGENT_WORKFLOW.md"]}),
        ("content-release", {"branch": "content/7-x", "base": "release/m5"}, {"paths": ["content/roles/x.tres", "levels/rooms/x.tscn"]}),
        ("design-main", {"branch": "docs/7-x", "design": True}, {"paths": ["docs/ARCHITECTURE.md", "docs/decisions/x.md"]}),
        ("no-paths-main", {"branch": "core/7-x"}, {"paths": []}),
        (
            "every-arg-release",
            {
                "branch": "core/7-x",
                "base": "release/m5",
                "wt": "D:\\prime-game\\.claude\\worktrees\\7",
                "notes": "Line one.\nLine two with `code` and §5.",
                "coord": "c",
                "decisions": "- d1\n- d2",
                "reading": "r",
                "testing": "t",
                "effort": "xhigh",
                "plan": 134,
                "manager": "the M5 manager session",
            },
            {"paths": ["core/match/vote.gd"], "findings": [MAJOR, MINOR]},
        ),
        (
            "red-main",
            {"branch": "core/7-x"},
            {"paths": ["core/x.gd"], "queues": {"implement": [{"verify_green": False, "complete": False, "summary": "s", "changed_paths": ["core/x.gd"]}]}},
        ),
    ],
    "pr-rebase.js": [
        ("core-main", {"branch": "core/7-x"}, {"paths": ["core/match/vote.gd"]}),
        ("tooling-release", {"base": "release/m5", "steps": "s1\ns2", "focus": "f"}, {"paths": ["tools/runner/start.py"]}),
        ("client-stacked", {"branch": "client/7-x", "base": "client/5-parent"}, {"paths": ["client/hud/hud.gd"]}),
        (
            "fix-release",
            {"branch": "net/7-x", "base": "release/m5", "plan": 134, "manager": "the M5 manager session"},
            {"paths": ["net/protocol/codec.gd"], "findings": [MAJOR, MINOR]},
        ),
        ("no-paths-main", {}, {"paths": []}),
        (
            "red-main",
            {},
            {"paths": ["core/x.gd"], "queues": {"rebase": [{"up_to_date": False, "verify_green": False, "published": False}]}},
        ),
    ],
}


def run_jobs(jobs: list[tuple[str, dict, dict]]) -> list[dict]:
    """Run (script name, args, stub) jobs in one Node process; each result is {events, returned, error}."""
    payload = [{"file": str(WORKFLOWS / name), "args": args, "stub": stub} for name, args, stub in jobs]
    with tempfile.TemporaryDirectory() as tmp:
        harness = Path(tmp) / "harness.mjs"
        harness.write_bytes(HARNESS.encode("utf-8"))
        res = subprocess.run(
            [str(NODE), str(harness)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
        )
    if res.returncode != 0:
        raise AssertionError(f"the workflow harness failed under node:\n{res.stderr[-2000:]}")
    return json.loads(res.stdout)


def run_one(name: str, args: dict, stub: dict | None = None) -> dict:
    return run_jobs([(name, dict(ARGS, **args), stub or {})])[0]


def agents(result: dict) -> list[dict]:
    return [e for e in result["events"] if e["kind"] == "agent"]


def run_workflow(script: Path, base: str | None, paths: list[str]) -> list[dict[str, str]]:
    """The agent calls of one run: [{label, prompt}], in order."""
    result = run_one(script.name, {"base": base} if base else {}, {"paths": paths})
    if result["error"]:
        raise AssertionError(f"{script.name} threw: {result['error']}")
    return [{"label": e["label"], "prompt": e["prompt"]} for e in agents(result)]


def render(result: dict) -> str:
    """A run as diffable text: each phase and agent call (label, options, prompt) in order, the return and the error."""
    lines = []
    for event in result["events"]:
        if event["kind"] == "phase":
            lines.append(f"### phase {event['title']}")
        elif event["kind"] == "agent":
            lines += [f"### agent {event['label']}", f"opts {event['opts']}", event["prompt"]]
    lines += ["### returned", json.dumps(result["returned"], indent=1, ensure_ascii=False)]
    lines.append(f"### error {json.dumps(result['error'], ensure_ascii=False)}")
    return "\n".join(lines) + "\n"


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

    def test_without_the_v2_args_every_agent_call_matches_its_snapshot(self) -> None:
        # Compatibility first: another manager's launch or resume with today's args must get today's agents.
        jobs, files = [], []
        for name, cases in SNAPSHOT_CASES.items():
            for case, args, stub in cases:
                jobs.append((name, dict(ARGS, **args), stub))
                files.append(SNAPSHOTS / name.removesuffix(".js") / f"{case}.txt")
        results = run_jobs(jobs)
        if UPDATE:
            for path, result in zip(files, results):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(render(result).encode("utf-8"))
            self.fail(f"PRIME_WORKFLOW_SNAPSHOTS=update wrote {len(files)} snapshots; review the diff, then rerun without it")
        for path, result in zip(files, results):
            with self.subTest(snapshot=f"{path.parent.name}/{path.name}"):
                self.assertTrue(path.is_file(), f"missing snapshot {path}")
                want = path.read_bytes().decode("utf-8")
                got = render(result)
                if got != want:
                    old, new = want.splitlines(), got.splitlines()
                    diff = "\n".join(difflib.unified_diff(old, new, "snapshot", "now", n=1, lineterm=""))
                    k = next((i for i, (a, b) in enumerate(zip(old, new)) if a != b), min(len(old), len(new)))
                    first = new[k][:200] if k < len(new) else "(the run ends earlier)"
                    # selftest prints only a failure's last line, so the summary goes last.
                    self.fail(f"{diff[:4000]}\n{path.parent.name}/{path.name} differs from line {k + 1}: {first!r}")


class NodeOnCiTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("GITHUB_ACTIONS") == "true", "only on GitHub Actions")
    def test_github_actions_runs_the_workflow_tests(self) -> None:
        # The ubuntu-24.04 image (20260927.320) lists Node.js 22. Without Node on PATH there, every test above would
        # skip silently and the snapshots would guard nothing on CI.
        self.assertIsNotNone(NODE, "Node is not on PATH on GitHub Actions: the workflow tests would skip")


if __name__ == "__main__":
    unittest.main()
