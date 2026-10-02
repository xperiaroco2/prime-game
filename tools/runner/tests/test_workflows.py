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


AVAILABLE = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))["availableModels"]
V2 = {"plan_review": True, "test_review": True, "second_review": True, "skeptic": True, "visual": ["spectate"]}
GODOT_LINE = "- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` (off-screen)."
PLAYCHECK_LINE = (
    "- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` or "
    "`tools\\run.cmd playcheck` (both off-screen)."
)
PNG = "D:/prime-game/.claude/worktrees/7/tools/out/playcheck/spectate/01.png"
SHOTS = {"available": True, "scenarios": ["spectate"], "exit_codes": [0], "pngs": [PNG]}


def implemented(paths: list[str], **extra) -> dict:
    return dict({"verify_green": True, "complete": True, "summary": "s", "changed_paths": paths}, **extra)


def calls(result: dict, prefix: str) -> list[dict]:
    return [e for e in agents(result) if e["label"].startswith(prefix)]


def options(event: dict) -> dict:
    return json.loads(event["opts"])


def schemas_of(schema: dict, where: str = "schema"):
    """Every object schema inside one, with its path."""
    if schema.get("type") == "object":
        yield where, schema
        for key, sub in schema.get("properties", {}).items():
            yield from schemas_of(sub, f"{where}.{key}")
    if schema.get("type") == "array" and isinstance(schema.get("items"), dict):
        yield from schemas_of(schema["items"], f"{where}[]")


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class PipelineV2Test(unittest.TestCase):
    """The optional args of pipeline v2: each stage's routing under the stub agents."""

    def test_no_model_name_outside_the_shared_list_is_in_the_scripts(self) -> None:
        # The model-guard ADR and its amendment A: a manager passes a model per launch through `models`; no script,
        # comment or default names one outside the shared availableModels.
        from runner.agents_check import FAMILIES

        outside = [f for f in FAMILIES if f not in AVAILABLE]
        self.assertTrue(outside, "the family table names no model outside availableModels: nothing to guard")
        for name in ("issue-task.js", "pr-rebase.js"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8").lower()
            with self.subTest(workflow=name):
                for family in outside:
                    self.assertNotRegex(text, rf"\b{family}\b")
                self.assertNotRegex(text, r"claude-[a-z]+-\d")
                self.assertNotRegex(text, r"\bmodel\s*:\s*['\"`]", "a model literal in the script is a default")

    def test_no_agent_gets_a_model_unless_models_names_its_role(self) -> None:
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, **V2), {"paths": ["docs/x.md"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        for result in run_jobs(jobs):
            self.assertIsNone(result["error"])
            for event in agents(result):
                with self.subTest(agent=event["label"]):
                    self.assertNotIn("model", options(event))

    def test_models_reach_the_roles_they_name_and_their_fallbacks(self) -> None:
        a, b = AVAILABLE[0], AVAILABLE[1]
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", models={"second_review": a}, **V2), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", models={"review": a, "implement": b}, **V2), core),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True, models={"second_review": a, "fix": b}), core),
        ]
        only_second, by_review, rebase = run_jobs(jobs)
        got = {e["label"]: options(e).get("model") for e in agents(only_second)}
        self.assertEqual({k: v for k, v in got.items() if v}, {"review:netcode-second:#7": a}, got)
        got = {e["label"]: options(e).get("model") for e in agents(by_review)}
        for label in ("review:plan:#7", "review:code:#7", "review:netcode:#7", "review:netcode-second:#7", "skeptic:#7"):
            self.assertEqual(got[label], a, label)
        for label in ("plan:#7", "implement:#7"):
            self.assertEqual(got[label], b, label)
        for label in ("review:godot-api:#7", "test-review:#7", "publish:#7"):
            self.assertIsNone(got[label], label)
        got = {e["label"]: options(e).get("model") for e in agents(rebase)}
        self.assertEqual({k: v for k, v in got.items() if v}, {"review:netcode-second:#8": a, "fix:#8": b}, got)

    def test_efforts_fall_back_per_role(self) -> None:
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", effort="medium", **V2), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", effort="medium", efforts={"implement": "max"}, **V2), core),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            (
                "issue-task.js",
                dict(ARGS, branch="core/7-x", efforts={"godot": "medium", "publish": "low", "plan": "xhigh", "test_review": "medium"}, **V2),
                core,
            ),
            ("issue-task.js", dict(ARGS, branch="core/7-x", efforts={"review": "low", "netcode": "medium"}, **V2), core),
            ("pr-rebase.js", dict(ARGS, efforts={"rebase": "xhigh", "fix": "medium", "review": "low"}, second_review=True, skeptic=True), core),
        ]
        default, effort, override, design, roles, review, rebase = (
            {e["label"]: (options(e).get("effort"), e["prompt"]) for e in agents(r)} for r in run_jobs(jobs)
        )
        reviewers = ("review:plan:#7", "review:code:#7", "review:netcode:#7", "review:godot-api:#7", "review:netcode-second:#7", "skeptic:#7")
        # Today's defaults; an agentType reviewer gets no effort (its agent file's applies) unless one is set.
        for label, want in (("plan:#7", "high"), ("implement:#7", "high"), ("test-review:#7", "high"), ("publish:#7", "high")):
            self.assertEqual(default[label][0], want, label)
        for label in reviewers:
            self.assertIsNone(default[label][0], label)
        # efforts.implement falls back to effort, which falls back to today's default; plan follows the implementer.
        self.assertEqual((effort["implement:#7"][0], effort["plan:#7"][0]), ("medium", "medium"))
        self.assertIn("Effort: medium.", effort["implement:#7"][1])
        self.assertEqual((override["implement:#7"][0], override["plan:#7"][0]), ("max", "max"))
        self.assertIn("Effort: max.", override["implement:#7"][1])
        self.assertEqual((design["implement:#7"][0], design["plan:#7"][0]), ("xhigh", "xhigh"))
        # Each role on its own.
        self.assertEqual(roles["review:godot-api:#7"][0], "medium")
        self.assertEqual((roles["publish:#7"][0], roles["plan:#7"][0], roles["test-review:#7"][0]), ("low", "xhigh", "medium"))
        self.assertIn("Effort: low.", roles["publish:#7"][1])
        self.assertEqual(roles["implement:#7"][0], "high")
        for label in set(reviewers) - {"review:godot-api:#7"}:
            self.assertIsNone(roles[label][0], label)
        # review covers every reviewer but the godot checker; netcode overrides it for both netcode reviews.
        want = {"review:plan:#7": "low", "review:code:#7": "low", "skeptic:#7": "low", "review:godot-api:#7": None}
        want |= {"review:netcode:#7": "medium", "review:netcode-second:#7": "medium"}
        self.assertEqual({k: review[k][0] for k in reviewers}, want)
        self.assertEqual(rebase["rebase:#8"][0], "xhigh")
        self.assertIn("Effort: xhigh.", rebase["rebase:#8"][1])
        self.assertEqual(rebase["fix:#8"][0], "medium")
        for label in ("review:code:#8", "review:netcode:#8", "review:netcode-second:#8", "skeptic:#8"):
            self.assertEqual(rebase[label][0], "low", label)

    def test_a_wrong_v2_arg_throws_before_any_agent_and_an_unknown_one_logs(self) -> None:
        bad = (
            {"efforts": {"reviewer": "high"}},
            {"efforts": {"review": "extreme"}},
            {"efforts": "high"},
            {"models": {"review": ""}},
            {"models": ["opus"]},
            {"skeptic": "yes"},
            {"skeptic": 0.5},
            {"second_review": "true"},
        )
        jobs = [(name, dict(ARGS, **args), {}) for name in ("issue-task.js", "pr-rebase.js") for args in bad]
        jobs += [("issue-task.js", dict(ARGS, **args), {}) for args in ({"plan_review": 1}, {"test_review": "no"}, {"visual": 5}, {"visual": [""]})]
        for (name, args, _), result in zip(jobs, run_jobs(jobs)):
            with self.subTest(workflow=name, args={k: v for k, v in args.items() if k not in ARGS}):
                self.assertIsNotNone(result["error"])
                self.assertIn("args.", result["error"])
                self.assertEqual(agents(result), [])
        jobs = [(name, dict(ARGS, second_reveiw=True), {"paths": ["core/x.gd"]}) for name in ("issue-task.js", "pr-rebase.js")]
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            with self.subTest(workflow=name):
                self.assertIsNone(result["error"])
                logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
                self.assertTrue(any("unknown args ignored" in m and "second_reveiw" in m for m in logs), logs)
                self.assertFalse(calls(result, "review:netcode-second"))

    def test_every_v2_agent_gets_the_rules_or_is_a_read_only_reviewer(self) -> None:
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", base="release/m5", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, base="release/m5", second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        for result in run_jobs(jobs):
            for event in agents(result):
                with self.subTest(agent=event["label"]):
                    if "agentType" in options(event):
                        self.assertIn(options(event)["agentType"], ("code-reviewer", "netcode-security-reviewer", "godot-api-checker"))
                        self.assertNotIn(STASH_RULE, event["prompt"])
                    else:
                        self.assertIn(STASH_RULE, event["prompt"])
                        self.assertIn("GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/release/m5", event["prompt"])

    def test_every_schema_is_one_the_workflow_tool_accepts(self) -> None:
        # agent() throws on a schema whose root is not an object or whose required names a missing property.
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        for result in run_jobs(jobs):
            for event in agents(result):
                schema = options(event)["schema"]
                self.assertEqual(schema["type"], "object", event["label"])
                for where, sub in schemas_of(schema):
                    with self.subTest(agent=event["label"], schema=where):
                        self.assertLessEqual(set(sub.get("required", [])), set(sub.get("properties", {})))

    def test_plan_review_plans_critiques_then_builds_with_both(self) -> None:
        core = {"paths": ["core/x.gd"]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", plan_review=True), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", plan_review=True), dict(core, queues={"plan": [None]})),
            ("issue-task.js", dict(ARGS, branch="core/7-x", plan_review=True), dict(core, queues={"review:plan": [None]})),
            (
                "issue-task.js",
                dict(ARGS, branch="core/7-x", plan_review=True),
                dict(core, queues={"implement": [implemented(["core/x.gd"], verify_green=False)]}),
            ),
        ]
        ok, no_plan, no_critique, red = run_jobs(jobs)
        events = [(e["kind"], e.get("title") or e.get("label")) for e in ok["events"] if e["kind"] != "log"]
        self.assertEqual(events[:4], [("phase", "Implement"), ("agent", "plan:#7"), ("agent", "review:plan:#7"), ("agent", "implement:#7")])
        plan, critique, implement = calls(ok, "plan")[0], calls(ok, "review:plan")[0], calls(ok, "implement")[0]
        self.assertIn("Plan only: create, edit or commit nothing", plan["prompt"])
        self.assertEqual(options(critique)["agentType"], "code-reviewer")
        self.assertIn('The plan: {"summary":"p"', critique["prompt"])
        self.assertIn('The plan: {"summary":"p"', implement["prompt"])
        self.assertIn('The critique: {"reviewer":"r"', implement["prompt"])
        self.assertIn('under "Plan review"', calls(ok, "publish")[0]["prompt"])
        self.assertEqual(ok["returned"]["plan"]["plan"]["summary"], "p")
        self.assertIn("the plan agent returned nothing", no_plan["error"])
        self.assertEqual([e["label"] for e in agents(no_plan)], ["plan:#7"])
        self.assertIn("the plan's reviewer returned nothing", no_critique["error"])
        self.assertFalse(calls(no_critique, "implement"))
        self.assertIn("stopped", red["returned"])
        self.assertIn("plan", red["returned"])

    def test_second_review_runs_wherever_the_netcode_review_does(self) -> None:
        jobs = []
        for name in ("issue-task.js", "pr-rebase.js"):
            for paths in (["core/x.gd"], ["tests/harness/bots/leak_check.gd"], ["client/hud/hud.gd"], ["tools/runner/bots.py"]):
                jobs.append((name, dict(ARGS, second_review=True), {"paths": paths}))
        jobs.append(("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, second_review=True), {"paths": ["docs/x.md"]}))
        for (name, _, stub), result in zip(jobs, run_jobs(jobs)):
            with self.subTest(workflow=name, paths=stub["paths"]):
                netcode = calls(result, "review:netcode:")
                second = calls(result, "review:netcode-second")
                self.assertEqual(len(second), len(netcode))
                if second:
                    self.assertEqual(options(second[0])["agentType"], "netcode-security-reviewer")
                    self.assertIn("second, independent netcode review", second[0]["prompt"])
                    self.assertIn("attacker", second[0]["prompt"])
                    self.assertNotIn("attacker", netcode[0]["prompt"])
                    self.assertEqual(len(result["returned"]["reviews"]), len(calls(result, "review:")))

    def test_test_review_runs_after_the_reviews_and_reports_a_missing_command(self) -> None:
        core = {"paths": ["core/x.gd"]}
        missing = {"available": False, "exit_2": False, "findings": [], "notes": "no mutants command on the branch"}
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "tools/out/mutants/m1 is still listed"}
        survived = {"available": True, "exit_2": False, "findings": [MAJOR], "mutants": [{"file": "core/x.gd", "result": "survived"}]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [missing]})),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True, skeptic=True), dict(core, queues={"test-review": [survived]})),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [None]})),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, test_review=True), {"paths": ["docs/x.md"]}),
            ("issue-task.js", dict(ARGS, test_review=True), {"paths": ["tools/runner/x.py", "content/roles/x.tres"]}),
        ]
        ok, absent, exit_2, skeptic, dead, design, tooling = run_jobs(jobs)
        # No production code in the diff: no mutant can go anywhere, so no agent runs; the PR and the result say so.
        self.assertIsNone(tooling["error"])
        self.assertFalse(calls(tooling, "test-review"))
        self.assertIn("The test review (test_review) was skipped: no changed path is production code", calls(tooling, "publish")[0]["prompt"])
        self.assertIn("no changed path is production code", tooling["returned"]["test_review"]["skipped"])
        self.assertTrue(any("test_review skipped" in e["message"] for e in tooling["events"] if e["kind"] == "log"))
        labels = [e["label"] for e in agents(ok)]
        self.assertEqual(labels[-2:], ["test-review:#7", "publish:#7"])
        self.assertTrue(all(label.startswith(("implement", "review:")) for label in labels[:-2]), labels)
        test_review = calls(ok, "test-review")[0]["prompt"]
        for text in ("`tools\\run.cmd mutants --help`", "ONE mutant per `tools\\run.cmd mutants <spec.json>` call", "600 s", "exit_2 true"):
            self.assertIn(text, test_review)
        publish = calls(ok, "publish")[0]["prompt"]
        self.assertIn("a table of the mutants", publish)
        self.assertIn("If a `tools\\run.cmd mutants` run exits 2", publish)
        # The command is missing on the branch (P7 not merged): reported in the PR and the result, and the run goes on.
        self.assertIsNone(absent["error"])
        self.assertIn("`tools\\run.cmd mutants` is missing on this branch (P7, #184", calls(absent, "publish")[0]["prompt"])
        self.assertIn("no mutants command on the branch", calls(absent, "publish")[0]["prompt"])
        self.assertFalse(absent["returned"]["test_review"]["available"])
        self.assertTrue(absent["returned"]["pub"]["published"])
        # mutants exited 2: the publisher only reports.
        publish = calls(exit_2, "publish")[0]["prompt"]
        self.assertIn("Task: report a stopped run of issue #7", publish)
        self.assertIn("publish nothing", publish)
        self.assertNotIn("gh pr create", publish)
        self.assertIn("mutants exited 2", exit_2["returned"]["stopped"])
        # A survived mutant is a finding like a reviewer's, so a skeptic checks it too.
        self.assertIn("from the test review", calls(skeptic, "skeptic")[0]["prompt"])
        self.assertIn("the test reviewer returned nothing", dead["error"])
        self.assertFalse(calls(dead, "publish"))
        self.assertFalse(calls(design, "test-review"))
        self.assertTrue(any("test_review skipped" in e["message"] for e in design["events"] if e["kind"] == "log"))

    def test_skeptics_check_each_blocker_or_major_up_to_the_limit(self) -> None:
        core = {"paths": ["core/x.gd"], "findings": [MAJOR, MINOR]}  # three reviewers: three majors
        refuted = {"refuted": True, "reason": "vote.gd:12 already checks it", "evidence": "vote.gd:12"}
        stands = {"refuted": False, "reason": "it stands"}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=True), dict(core, queues={"skeptic": [refuted, stands, stands]})),
            ("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=2), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=True), {"paths": ["core/x.gd"], "findings": [MINOR]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=True), dict(core, queues={"skeptic": [stands, None]})),
            ("pr-rebase.js", dict(ARGS, skeptic=True), dict(core, queues={"skeptic": [refuted, refuted]})),
            ("pr-rebase.js", dict(ARGS, skeptic=True), dict(core, queues={"skeptic": [refuted, stands]})),
            # true checks every blocker or major (the issue's criterion), however many there are.
            ("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR, MAJOR, MINOR]}),
            ("pr-rebase.js", dict(ARGS, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR, MAJOR, MINOR]}),
        ]
        three, two, none, dead, all_refuted, one_stands, six, four = run_jobs(jobs)
        self.assertEqual(len(calls(six, "skeptic")), 6)
        self.assertEqual(six["returned"]["skeptic"]["unchecked"], [])
        self.assertEqual(len(calls(four, "skeptic")), 4)
        self.assertEqual(four["returned"]["skeptic"]["unchecked"], [])
        self.assertFalse(any("skeptic limit" in e["message"] for r in (six, four) for e in r["events"] if e["kind"] == "log"))
        skeptics = calls(three, "skeptic")
        self.assertEqual(len(skeptics), 3)
        for event in skeptics:
            self.assertEqual(options(event)["agentType"], "code-reviewer")
            self.assertIn('"problem":"p1"', event["prompt"])
            self.assertIn("refuted true only with evidence", event["prompt"])
        self.assertEqual([e["label"] for e in agents(three)][-1], "publish:#7")
        self.assertEqual(len(three["returned"]["skeptic"]["refuted"]), 1)
        self.assertEqual(len(three["returned"]["skeptic"]["stood"]), 2)
        publish = calls(three, "publish")[0]["prompt"]
        self.assertIn("vote.gd:12 already checks it", publish)
        self.assertIn("A refuted finding is not fixed unless you find the skeptic wrong", publish)
        # The limit: the rest go to the publisher unchecked, and the log says so.
        self.assertEqual(len(calls(two, "skeptic")), 2)
        self.assertEqual(len(two["returned"]["skeptic"]["unchecked"]), 1)
        self.assertTrue(any("over the skeptic limit of 2" in e["message"] for e in two["events"] if e["kind"] == "log"))
        self.assertFalse(calls(none, "skeptic"))
        self.assertNotIn("Skeptics tried to refute", calls(none, "publish")[0]["prompt"])
        self.assertIn("a skeptic returned nothing", dead["error"])
        # pr-rebase: a refuted finding is not sent to the fix agent; when none is left, no fix agent runs.
        self.assertFalse(calls(all_refuted, "fix"))
        self.assertIsNone(all_refuted["returned"]["fix"])
        self.assertIn("no fix agent ran", all_refuted["returned"]["note"])
        fix = calls(one_stands, "fix")
        self.assertEqual(len(fix), 1)
        self.assertIn("Skeptics refuted these blocker or major findings", fix[0]["prompt"])
        self.assertIn("vote.gd:12 already checks it", fix[0]["prompt"])

    def test_visual_allows_playcheck_and_hands_the_pngs_to_the_code_reviewer(self) -> None:
        core = {"paths": ["client/hud/hud.gd"]}
        absent = {"available": False, "pngs": [], "notes": "no playcheck command on the branch"}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="client/7-x"), core),
            ("issue-task.js", dict(ARGS, branch="client/7-x", visual=["spectate", "esc_menu"]), dict(core, queues={"implement": [implemented(core["paths"], playcheck=SHOTS)]})),
            ("issue-task.js", dict(ARGS, branch="client/7-x", visual=True), dict(core, queues={"implement": [implemented(core["paths"], playcheck=absent)]})),
            ("issue-task.js", dict(ARGS, branch="client/7-x", visual="spectate"), core),
        ]
        off, on, missing, unreported = run_jobs(jobs)
        # Unset: the rules line is today's, word for word, and nothing mentions playcheck.
        for event in agents(off):
            self.assertNotIn("playcheck", event["prompt"])
            if "agentType" not in options(event):
                self.assertIn(GODOT_LINE, event["prompt"])
        for event in calls(on, "implement") + calls(on, "publish"):
            self.assertIn(PLAYCHECK_LINE, event["prompt"])
            self.assertNotIn(GODOT_LINE, event["prompt"])
        implement = calls(on, "implement")[0]
        self.assertIn("`tools\\run.cmd playcheck <scenario>`", implement["prompt"])
        self.assertIn("`spectate`, `esc_menu`", implement["prompt"])
        self.assertIn("playcheck", options(implement)["schema"]["required"])
        self.assertNotIn("playcheck", options(calls(off, "implement")[0])["schema"]["properties"])
        code = calls(on, "review:code")[0]["prompt"]
        self.assertIn(f"screenshots: {PNG}", code)
        self.assertIn("Read each PNG", code)
        self.assertNotIn("Read each PNG", calls(on, "review:netcode")[0]["prompt"])
        self.assertIn("In the PR's Screenshots section list each PNG's path", calls(on, "publish")[0]["prompt"])
        self.assertEqual(on["returned"]["visual"]["pngs"], [PNG])
        # true: the scenarios the notes name. Missing on the branch (P9 not merged): reported, and the run goes on.
        self.assertIn("the playcheck scenarios the task notes name", calls(missing, "implement")[0]["prompt"])
        self.assertIn("no playcheck screenshots (no playcheck command on the branch)", calls(missing, "review:code")[0]["prompt"])
        self.assertIn("Say so in the PR's Screenshots and verification sections", calls(missing, "publish")[0]["prompt"])
        self.assertTrue(missing["returned"]["pub"]["published"])
        self.assertIn("`spectate`", calls(unreported, "implement")[0]["prompt"])
        self.assertIn("the implementer reported no playcheck run", calls(unreported, "publish")[0]["prompt"])

    def test_meta_and_the_args_comment_name_each_v2_arg(self) -> None:
        # A manager states the agent count in its kickoff from these lines.
        for name, names in (
            ("issue-task.js", ("plan_review", "test_review", "second_review", "skeptic", "visual", "efforts", "models")),
            ("pr-rebase.js", ("second_review", "skeptic", "efforts", "models")),
        ):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            when = next(line for line in text.splitlines() if line.strip().startswith("whenToUse:"))
            comment = "\n".join(line for line in text.splitlines() if line.startswith("//"))
            with self.subTest(workflow=name):
                self.assertIn("Agents: ", when)
                for arg in names:
                    self.assertIn(f"{arg}?", when)
                    self.assertRegex(comment, rf"//   {arg} ")


class NodeOnCiTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("GITHUB_ACTIONS") == "true", "only on GitHub Actions")
    def test_github_actions_runs_the_workflow_tests(self) -> None:
        # The ubuntu-24.04 image (20260927.320) lists Node.js 22. Without Node on PATH there, every test above would
        # skip silently and the snapshots would guard nothing on CI.
        self.assertIsNotNone(NODE, "Node is not on PATH on GitHub Actions: the workflow tests would skip")


if __name__ == "__main__":
    unittest.main()
