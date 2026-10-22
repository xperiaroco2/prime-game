"""The saved workflows in .claude/workflows/: run each script under Node with stub agents and read the prompts.

The scripts are Claude Code workflow bodies (top-level await and return), so the harness wraps each one in an async
function and passes `args`, `agent`, `parallel`, `phase` and `log`. Node is not a project dependency: without it the
tests skip, except on GitHub Actions, where a missing Node fails `test_github_actions_runs_the_workflow_tests`.

Snapshots: other managers launch these scripts by name from their own copies and resume runs with the same args, and a
resume replays an agent only while its prompt and options are unchanged. `workflow_snapshots/<script>/<case>.txt`
pins every agent's prompt, label, phase, schema and options for representative arg sets, as launched: bounded waits
(#411: each agent that waits has the bounded-waits paragraph) and the lean agent types (#458: the implementing and
publishing agents' options end in an `agentType`) are always on. Until #883 an `unbounded/` folder held the same cases
with `bounded_waits: false` and `lean: false`, the text a resume of a run launched before #411 or #458 replayed; #883
removed both switches and that folder once no such run could resume (the engineer's approval on #876). Most cases pass
no v2 arg; `publish-clean-main` pins the publish_clean trial of #308 (`publish-clean-findings-main` the same launch
on a run with a major left open, whose publisher takes publish), `plan-review-main` #469's plan phase,
`checkpoint-main` #559's implementer handoffs (the default since #920; `checkpoint-off-main` its opt-out,
`checkpoint: false`), pr-rebase's `publish-sonnet-main` #835's Sonnet publisher, and `update-main` #856's update run.
#1147 removed `ab-review-main` (#535's A/B) and `publish-findings-main` (#835's issue-task trial): both options
ended on 2026-10-13 and now throw. A deliberate change of a default prompt rewrites them: run `selftest` once with
PRIME_WORKFLOW_SNAPSHOTS=update (the snapshot test then fails on purpose, naming the files it wrote), review the diff,
commit it with the change, and run `selftest` again without the variable. Such a change merges between waves, with no
issue-task run before its publisher, because a run that resumes after the merge replays its publisher fresh; the
scripts' header comments name each one (#339, #413, #456, #468, #470, #471, #605, #606, #815, #818, #834, #920, #1257;
issue-task.js also records #555's 180 s wait, #563's Cross-area line, #572's reading a log by search and #574's
`verify --fail-fast`).
Each snapshot ends with the run's return value, which a resume does not replay (#386 made it compact).
"""

import difflib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner import metrics, wait
from runner.common import ROOT, force_rmtree, node_bin

WORKFLOWS = ROOT / ".claude" / "workflows"
SNAPSHOTS = Path(__file__).resolve().parent / "workflow_snapshots"
NODE = node_bin()
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
# The two one-line rules of #326 (each prompt line that starts so is the whole rule).
HOOKS_RULE = "- Read the hooks path with `git rev-parse --git-path hooks`, never `git config --get core.hooksPath`"
SLEEP_RULE = "- Never poll with a foreground `sleep N; cat <log>`"
# #413's one-line rule: the writes outside the worktree and the scratchpad that a throwaway first command made.
# #468: how every agent reads code (outline or grep -n first, no re-read of unchanged content, batched reads).
READ_RULE = "- Reading (the docs-by-section rule of #339, extended to code by #468):"
# #815: the task's ADR, each section once per context (the repeats of PR #794's `metrics --adr-reads` table).
ADR_RULE = "- The task's ADR (each docs/decisions/ file the issue links):"
WRITE_RULE = "- Write no file outside your worktree and your scratchpad subfolder, not even an empty throwaway"
# #456's one-line rule: the one way to change or reword an earlier commit, with no editor.
REBASE_RULE = "- Change an earlier commit only with `git commit --fixup=<sha>`"
# The reword commit the rule names; RebaseRuleTest runs it through git.
REWORD_COMMIT = ("git", "commit", "--allow-empty", "-F")
# The agent types of the read-only reviewers, which get no RULES.
READ_ONLY_TYPES = ("code-reviewer", "netcode-security-reviewer", "godot-api-checker")
MAJOR = {"severity": "major", "file": "core/match/vote.gd", "line": 12, "problem": "p1", "fix": "f1"}
MINOR = {"severity": "minor", "file": "core/match/vote.gd", "line": 30, "problem": "p2", "fix": "f2"}
# What every agent that publishes returns for the engineer's own steps (#266), and how its prompt asks for it.
HUMAN_STEPS_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {"why": {"type": "string"}, "command": {"type": "string"}},
        "required": ["why", "command"],
    },
}
HUMAN_STEPS_ASK = "human_steps: each step only the engineer can take after you"
HUMAN_STEPS_ASK_TAIL = "The PR and your comment on the issue may carry the commands too.\n\nReturn the structured result."

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
        # #920: checkpoint: false, the opt-out of the default (a case with a v2 arg): no rule, no handoff key, and the
        # compact result without checkpoint and handoffs.
        ("checkpoint-off-main", {"branch": "tooling/7-x", "checkpoint": False}, {"paths": ["tools/runner/start.py", "docs/AGENT_WORKFLOW.md"]}),
        ("content-release", {"branch": "content/7-x", "base": "release/m5"}, {"paths": ["content/roles/x.tres", "levels/rooms/x.tscn"]}),
        ("design-main", {"branch": "docs/7-x", "design": True}, {"paths": ["docs/ARCHITECTURE.md", "docs/decisions/x.md"]}),
        ("no-paths-main", {"branch": "core/7-x"}, {"paths": []}),
        # #308's one-wave trial: a clean run's publisher with a cheaper model (a case with a v2 arg).
        ("publish-clean-main", {"branch": "core/7-x", "models": {"publish_clean": "sonnet"}}, {"paths": ["core/x.gd"], "findings": [MINOR]}),
        # The same launch on a run with a major left open: its publisher takes publish (#1147 ended #835's
        # publish_findings), so no model reaches it (a case with a v2 arg).
        (
            "publish-clean-findings-main",
            {"branch": "core/7-x", "models": {"publish_clean": "sonnet"}},
            {"paths": ["core/x.gd"], "findings": [MAJOR]},
        ),
        # #469's plan phase: the planner on the model the manager passes, a plan with a file map and its comment.
        (
            "plan-review-main",
            {"branch": "core/7-x", "plan_review": True, "models": {"plan": "sonnet", "publish_clean": "sonnet"}},
            {"paths": ["core/x.gd"], "queues": {"plan": [{
                "summary": "p", "criteria": ["c"], "files": ["core/x.gd: f"], "tests": ["t"],
                "file_map": {"base_sha": "0123456789abcdef0123456789abcdef01234567", "files": [{"path": "core/x.gd", "lines": "1-40", "facts": ["func f() -> int"]}]},
                "comment_url": "https://github.com/xperiaroco2/prime-game/issues/7#issuecomment-1",
            }]}},
        ),
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
        # #559's checkpoint, on by default since #920: three implementers that each hand over; the third may not, so all
        # three prompts are pinned.
        (
            "checkpoint-main",
            {"branch": "tooling/7-x"},
            {"paths": ["tools/runner/x.py"], "queues": {"implement": [
                {"verify_green": True, "complete": False, "summary": f"part {k}", "changed_paths": ["tools/runner/x.py"], "decisions": [f"d{k}"], "handoff": f"C:/scratchpad/a7/handoff-{k}.md"}
                for k in (1, 2, 3)
            ]}},
        ),
        # #856's update run: the reviewers read the delta since the published head; plan_review, test_review and the
        # skeptic passed are dropped (a case with an arg that is not v2's: a run without it is pinned by every other).
        (
            "update-main",
            {"branch": "core/7-x", "update": True, "plan_review": True, "test_review": True, "skeptic": True},
            {"paths": ["core/x.gd"], "findings": [MAJOR], "queues": {"implement": [{
                "verify_green": True, "complete": True, "summary": "s", "changed_paths": ["core/x.gd", "client/ui/x.gd", "docs/x.md"],
                "published_head": "89abcdef0123456789abcdef0123456789abcdef",
                "delta": [{"path": "client/ui/x.gd", "added": 3, "deleted": 1}, {"path": "docs/x.md", "added": 9, "deleted": 2}],
            }]}},
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
        # #835's trial: the rebase and fix agents on the model of models.publish (a case with a v2 arg).
        ("publish-sonnet-main", {"models": {"publish": "sonnet"}}, {"paths": ["core/x.gd"], "findings": [MAJOR]}),
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

    def test_every_agent_gets_the_hooks_path_and_no_foreground_sleep_rules(self) -> None:
        # #326, from #312: in the week of 2026-09-29 workflow agents made 9 of the 10 hooks-path reads the deny rule
        # `git config *hooksPath*` refused and 26 of the 28 foreground `sleep N; cat <log>` polls Claude Code blocked.
        # They read their workflow prompt, not docs/AGENT_WORKFLOW.md, so each rule is one line, the same in every
        # script. #818: 7 of the 12 refusals from 2026-10-07 to 11 were reviewers', whose prompts lacked both lines,
        # and 2 a PowerShell `Start-Sleep -Seconds N`; so every agent gets them, the read-only ones too.
        jobs = [
            ("issue-task.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS), {"paths": ["tools/x.py"]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("pr-rebase.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS), {"paths": ["tools/x.py"]}),
            ("quick-task.js", ARGS, {"findings": [MAJOR], "queues": {"publish": [quick(["core/x.gd"])], "fix": [{"fixed": ["f"], "open": 0, "ci_green": True}]}}),
        ]
        seen: dict[str, set[str]] = {HOOKS_RULE: set(), SLEEP_RULE: set()}
        labels: set[str] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                labels.add(f"{name}:{event['label'].rsplit(':#', 1)[0]}")
                # #1257: issue-task's and pr-rebase's reviewers have both lines from their agent files instead.
                carried = name != "quick-task.js" and options(event).get("agentType") in READ_ONLY_TYPES
                for rule, lines in seen.items():
                    with self.subTest(workflow=name, agent=event["label"], rule=rule):
                        found = [line for line in event["prompt"].splitlines() if line.startswith(rule)]
                        if carried:
                            self.assertEqual(found, [])
                            continue
                        self.assertEqual(len(found), 1, found)
                        lines.add(found[0])
        for rule, lines in seen.items():
            with self.subTest(rule=rule):
                self.assertEqual(len(lines), 1, f"the rule differs between agents or scripts: {sorted(lines)}")
        # Every read-only role is covered, not only the agents of the shared rules.
        self.assertLessEqual({f"issue-task.js:{r}" for r in ("review:plan", "review:code", "review:netcode", "review:godot-api",
                                                             "review:netcode-second", "skeptic")}
                             | {f"pr-rebase.js:{r}" for r in ("review:code", "review:netcode", "review:netcode-second", "skeptic")}
                             | {"quick-task.js:review:code", "quick-task.js:review:netcode", "quick-task.js:publish", "quick-task.js:fix"},
                             labels)  # fmt: skip
        self.assertIn("`git rev-parse --git-path hooks`", next(iter(seen[HOOKS_RULE])))
        sleep = next(iter(seen[SLEEP_RULE]))
        for way in ("`Start-Sleep N`", "blocks both", "`tools/run.sh wait <log>`", "run_in_background", "Monitor"):
            self.assertIn(way, sleep)
        for kind in READ_ONLY_TYPES:
            with self.subTest(agent_file=kind):
                text = (ROOT / ".claude" / "agents" / f"{kind}.md").read_text(encoding="utf-8")
                for part in ("`Start-Sleep N`", "blocks both", "`tools/run.sh wait <log>`", "`core.hooksPath`"):
                    self.assertIn(part, text)

    def test_every_agent_reads_each_section_of_the_tasks_adr_once_per_context(self) -> None:
        # #815: PR #794's `metrics --adr-reads` table (2026-10-08 to 11) counted 976 section reads of ADRs, about 960
        # of them repeats of the same task ADRs, by the implementer, the publisher and the two reviewers. Every role
        # of both scripts gets one line, the same text everywhere: issue-task's publisher too, whose PUB_RULES drop
        # the reading line (#696) but keep this one, and the read-only agents in their REVIEW_RULES. #834: the same
        # line covers docs/ARCHITECTURE.md (about $20 over 1471 reads since 2026-10-08T12:25Z, 51% the implementer's):
        # by section, each section once per context, again only after the file changed or a compaction.
        jobs = [
            ("issue-task.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS), {"paths": ["tools/x.py"]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("pr-rebase.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS), {"paths": ["tools/x.py"]}),
        ]
        lines: set[str] = set()
        labels: set[str] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                labels.add(f"{name}:{event['label'].rsplit(':#', 1)[0]}")
                with self.subTest(workflow=name, agent=event["label"]):
                    found = [line for line in event["prompt"].splitlines() if line.startswith(ADR_RULE)]
                    self.assertEqual(len(found), 1, found)
                    lines.update(found)
        self.assertEqual(len(lines), 1, f"the line differs between agents or scripts: {sorted(lines)}")
        self.assertLessEqual({f"issue-task.js:{r}" for r in ("plan", "review:plan", "implement", "review:code", "review:netcode",
                                                             "review:godot-api", "review:netcode-second", "test-review",
                                                             "skeptic", "publish")}
                             | {f"pr-rebase.js:{r}" for r in ("rebase", "review:code", "review:netcode", "review:netcode-second",
                                                              "skeptic", "fix")},
                             labels)  # fmt: skip
        rule = next(iter(lines))
        for part in ("docs/decisions/", "the issue links",
                     "read it, and ARCHITECTURE (`cd <your worktree> && tools/run.sh section docs/ARCHITECTURE.md`), each by section, never the whole file",
                     "each section you need once per context", "only after the file changed or your context was compacted"):
            self.assertIn(part, rule)

    def test_the_tasks_adr_line_names_the_section_reads(self) -> None:
        # #816: PR #794's `metrics --adr-reads` table (since 2026-10-08T12:25Z) counted 39 whole-file ADR reads of
        # 1043, $9.32 of $33, all of them the 2026-10-10 task ADRs (300 to 560 lines). The one task-ADR line (#815's)
        # tells the implementer, the publisher and the reviewers to read it by section: its outline, then
        # `section <adr> <§>`, never the whole file.
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS), {"paths": ["tools/x.py"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        roles: set[str] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                role = event["label"].rsplit(":#", 1)[0]
                if role not in ("implement", "publish", "rebase", "review:code", "review:netcode", "review:godot-api"):
                    continue
                roles.add(f"{name}:{role}")
                with self.subTest(workflow=name, agent=event["label"]):
                    found = [line for line in event["prompt"].splitlines() if line.startswith(ADR_RULE)]
                    self.assertEqual(len(found), 1, found)
                    for part in ("by section, never the whole file", "`tools/run.sh section <adr>`",
                                 "`tools/run.sh section <adr> <§>`"):
                        self.assertIn(part, found[0])
        self.assertLessEqual({f"issue-task.js:{r}" for r in ("implement", "publish", "review:code", "review:netcode",
                                                             "review:godot-api")}
                             | {f"pr-rebase.js:{r}" for r in ("rebase", "review:code", "review:netcode")},
                             roles)  # fmt: skip

    def test_every_agent_gets_the_no_write_outside_rule(self) -> None:
        # #413: from 2026-10-01 to 05 workflow agents opened Bash calls with 75 throwaway writes (`cat > <file>
        # 2>/dev/null;`), 64 of them into the system Temp folder ($TMP, $TEMP, $TMPDIR, /tmp), not the scratchpad.
        # On the night of 2026-10-04/05 one, `cat > ../../../../tmp_unused` from a worktree, asked and held #393's
        # rebase for two hours; two more left empty files in Temp. A Git Bash `/c/...` path given to `tools\run.cmd`
        # made D:\c\ (2026-10-02). The rule is one line of the shared RULES, the same in both scripts and in a lean run.
        jobs = [
            ("issue-task.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, lean=True), {"paths": ["tools/x.py"]}),
            ("pr-rebase.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, lean=True), {"paths": ["tools/x.py"]}),
        ]
        lines: set[str] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                if options(event).get("agentType") in READ_ONLY_TYPES:
                    continue  # reviewers are read-only
                with self.subTest(workflow=name, agent=event["label"]):
                    found = [line for line in event["prompt"].splitlines() if line.startswith(WRITE_RULE)]
                    self.assertEqual(len(found), 1, found)
                    lines.add(found[0])
        self.assertEqual(len(lines), 1, f"the rule differs between agents or scripts: {sorted(lines)}")
        rule = next(iter(lines))
        # The traps by name: a relative climb, a throwaway first write into Temp, a Git Bash path on the Windows side,
        # and where dropped output goes instead.
        for trap in ("`cat > ../../../../tmp_unused`", '`cat > "$TMP/x" 2>/dev/null;`', "`$TEMP`", "`$TMPDIR`",
                     "`/tmp`", "`/c/...`", "`tools\\run.cmd`", "`/dev/null` (Git Bash)", "`$null` (PowerShell)"):
            self.assertIn(trap, rule)

    def test_every_agent_gets_the_editor_free_rebase_rule(self) -> None:
        # #456: on the night of 2026-10-05/06 the fix agent of a pr-rebase run reworded a commit with its own sequence
        # editor (a Python script); the guard asked and the run waited 9 hours. Since #457 the guard lets that through in
        # the own worktree, but an editor that opens still hangs an agent. The one way to change or reword an
        # earlier commit is one line of the shared RULES, the same in both scripts and in a lean run, and the only
        # line of a prompt that names an autosquash (the stash line no longer repeats it).
        base = {"base": "release/m3"}
        jobs = [
            ("issue-task.js", dict(ARGS, **base), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **base, **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, **base, lean=True), {"paths": ["tools/x.py"]}),
            ("pr-rebase.js", dict(ARGS, **base), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, **base, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, **base, lean=True), {"paths": ["tools/x.py"], "findings": [MAJOR]}),
        ]
        lines: set[str] = set()
        seen: set[tuple[str, str]] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                if options(event).get("agentType") in READ_ONLY_TYPES:
                    continue  # reviewers are read-only
                seen.add((name, event["label"].split(":")[0]))
                with self.subTest(workflow=name, agent=event["label"]):
                    found = [line for line in event["prompt"].splitlines() if line.startswith(REBASE_RULE)]
                    self.assertEqual(len(found), 1, found)
                    lines.add(found[0])
                    autosquash = [line for line in event["prompt"].splitlines() if "--autosquash" in line]
                    self.assertEqual(autosquash, found)
        # Every agent that can commit: the plan agent, the implementer, the test reviewer, the publisher, the rebase
        # and fix agents.
        for want in (("issue-task.js", "plan"), ("issue-task.js", "implement"), ("issue-task.js", "test-review"),
                     ("issue-task.js", "publish"), ("pr-rebase.js", "rebase"), ("pr-rebase.js", "fix")):
            self.assertIn(want, seen)
        self.assertEqual(len(lines), 1, f"the rule differs between agents or scripts: {sorted(lines)}")
        rule = next(iter(lines))
        for text in (
            "`git commit --fixup=<sha>`, then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/release/m3`",
            "in PowerShell `$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/release/m3`",
            f"To reword one: `{' '.join(REWORD_COMMIT)} <file>` with the file's first line `amend! <that commit's subject>`",
            "then the same rebase",
            "or leave the message as it is",
            "The last commit alone: `git commit --amend --no-edit` or `--amend -F <file>`, never a bare `--amend`",
            "which opens the editor",
            "another sequence editor (a script, `sed`, `-c sequence.editor=...`)",
            "an interactive rebase without `GIT_SEQUENCE_EDITOR=:`",
            "`--fixup=reword:` or `--fixup=amend:` (both open the message editor)",
            "a `squash!` commit",
            "an editor that opens hangs the call until its timeout",
            "a `--fixup=reword:` keeps the old message without a word",
            "Since #457 the guard lets each of these through in your own worktree on your task branch",
            "9 hours",
            "it still asks for `git rebase --exec` and for any rebase in the main checkout or another worktree",
        ):
            self.assertIn(text, rule)
        # #457 (the guard) lets a sequence editor and every amend form through in the own worktree on its task branch:
        # the rule gives no reason that says the guard asks for them.
        self.assertNotIn("make the guard ask", rule)
        self.assertNotIn("until the human returns", rule)

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

    def test_the_publisher_lists_content_as_provisional_without_a_relay(self) -> None:
        # #563 (b), after #518 made the designer optional: a content-area change names the engineer's word and lists
        # its files as provisional; the relay phrase of #128 and the designer's tag are gone, and the approval line
        # that clears the gate is the manager's to add once the engineer approves.
        calls = run_workflow(WORKFLOWS / "issue-task.js", None, ["content/roles/x.tres"])
        publish = [c["prompt"] for c in calls if c["label"].startswith("publish")]
        self.assertEqual(len(publish), 1, [c["label"] for c in calls])
        self.assertIn("the content/ and levels/ files as provisional under the MVP content ADR", publish[0])
        self.assertIn('the "Approved by the engineer: <link>" line that lets the gate merge it is the manager\'s',
                      publish[0])  # fmt: skip
        self.assertIn(".claude/skills/new-mechanic/ and .claude/skills/new-level-piece/", publish[0])
        self.assertNotIn("relayed by the engineer", publish[0])
        self.assertNotIn("@SwiftySinister", publish[0])

    def test_every_publishing_agent_returns_human_steps_as_ready_commands(self) -> None:
        # #261 and #266: a publisher's human_steps read "run the cleanup command in the PR body", and the manager
        # relayed the pointer instead of the command. Each agent that publishes now returns {why, command} pairs,
        # each command one PowerShell line that starts with `cd` to its absolute folder, ready to paste.
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "tools/out/mutants/m1 is still listed"}
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        backslashes = {"wt": "D:\\prime-game\\.claude\\worktrees\\7"}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **backslashes), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("pr-rebase.js", dict(ARGS, **backslashes), core),
        ]
        publishing = ("publish", "rebase", "fix")
        seen, asks = [], set()
        for result in run_jobs(jobs):
            self.assertIsNone(result["error"])
            for event in agents(result):
                label, prompt = event["label"], event["prompt"]
                steps = options(event)["schema"]["properties"].get("human_steps")
                with self.subTest(agent=label):
                    if not label.startswith(publishing):
                        self.assertIsNone(steps)
                        self.assertNotIn(HUMAN_STEPS_ASK, prompt)
                        continue
                    seen.append(label.split(":")[0])
                    self.assertEqual(steps, HUMAN_STEPS_SCHEMA)
                    self.assertIn(HUMAN_STEPS_ASK, prompt)
                    self.assertIn("ONE PowerShell 5.1 line that starts with `cd <absolute folder>;`", prompt)
                    self.assertIn("`cd D:\\prime-game;` for the main checkout", prompt)
                    self.assertIn("`cd D:\\prime-game\\.claude\\worktrees\\7;` for your worktree", prompt)
                    self.assertIn("never `&&`", prompt)
                    self.assertIn('never a pointer such as "the command in the PR body"', prompt)
                    # A human step is one the agent must not take: it previews the command, runs only a read-only one.
                    self.assertIn("Preview it from that folder first", prompt)
                    self.assertIn("never one that does his step, changes `D:\\prime-game` or prompts", prompt)
                    self.assertNotIn("Run it yourself", prompt)
                    self.assertIn('A step without a command (a click in GitHub, a decision) has command ""', prompt)
                    # The ask is its own paragraph right before the result's, so every earlier line stays as it was.
                    paragraphs = prompt.split("\n\n")
                    self.assertTrue(paragraphs[-2].startswith(HUMAN_STEPS_ASK), paragraphs[-2][:200])
                    self.assertTrue(paragraphs[-1].startswith("Return the structured result."), paragraphs[-1][:200])
                    self.assertIn(HUMAN_STEPS_ASK_TAIL, prompt)
                    asks.add(paragraphs[-2])
        self.assertEqual(sorted(set(seen)), ["fix", "publish", "rebase"])
        self.assertEqual(seen.count("publish"), 2)  # the full publisher and the one that reports a mutants stop
        # The two workflows cannot share a module, so each carries its own copy of the ask: they must not drift apart.
        self.assertEqual(len(asks), 1, sorted(asks))

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

    def test_the_netcode_reviewers_always_read_the_leak_sections(self) -> None:
        # #339 (the instruction-diet ADR's N1 (a)): reviewers read ARCHITECTURE by section, but the netcode reviewers
        # (the second_review pass too, which audits the leak test) always read §5 (filtering), §4.2 (each event's
        # audience) and §4.6 (the leak test): a change that touches only §4.7 or §7.1 can still add a snapshot field
        # the leak test does not compare. One sentence, identical in both scripts, in every netcode review they route
        # (a design task's too) and in no other agent's prompt.
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True), {"paths": ["docs/ARCHITECTURE.md"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS), {"paths": ["client/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        sentences: set[str] = set()
        for (name, args, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            netcode = [e for e in agents(result) if e["label"].startswith("review:netcode")]
            self.assertEqual(len(netcode), 2 if args.get("second_review") else 1, [e["label"] for e in agents(result)])
            for event in agents(result):
                found = re.findall(r"Always read ARCHITECTURE §5[^\n]*?does not compare\.", event["prompt"])
                with self.subTest(workflow=name, agent=event["label"]):
                    self.assertEqual(len(found), 1 if event in netcode else 0, found)
                    sentences.update(found)
        self.assertEqual(len(sentences), 1, f"the sentence differs between scripts: {sorted(sentences)}")
        sentence = next(iter(sentences))
        for part in ("§5 (per-peer filtering)", "§4.2 (each event's audience)", "§4.6 (the client, the bots and the leak test)",
                     "`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6`"):
            self.assertIn(part, sentence)

    def test_reviewers_read_architecture_by_section_and_never_root_claude_md(self) -> None:
        # #339: the plan's critique and the reviews named docs/ARCHITECTURE.md (about 170k tokens) and root CLAUDE.md,
        # which every agent already has from its launch. Now they read the sections the change touches through
        # `section`, a design's reviewers the outline and every section the design could contradict, and no prompt
        # asks for root CLAUDE.md again ("Root CLAUDE.md applies in full" in the rules asks for no read).
        everything = dict(V2, test_review=False)
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **everything), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("issue-task.js", dict(ARGS, lean=True), {"paths": ["tools/x.py"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        outline = "`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh section docs/ARCHITECTURE.md` prints its outline"
        results = run_jobs(jobs)
        for (name, args, _), result in zip(jobs, results):
            self.assertIsNone(result["error"])
            for event in agents(result):
                label, prompt = event["label"], event["prompt"]
                with self.subTest(workflow=name, design=args.get("design", False), agent=label):
                    self.assertNotIn("root claude.md", prompt.lower().replace("root claude.md applies in full", ""))
                    if not label.startswith(("plan:", "review:")):
                        continue
                    # Every mention of the doc is a `section` call on it, never the whole file.
                    whole = re.findall(r"(?<!section )docs/ARCHITECTURE\.md", prompt)
                    self.assertEqual(whole, [], prompt[:300])
                    if name == "issue-task.js" and label.startswith(("review:code", "review:plan", "plan:")):
                        self.assertIn(outline, prompt)
                    if label.startswith("review:") and "tools/run.sh section" in prompt:
                        # The prompt allows `section` itself; the reviewer agent files allow it too since #433
                        # (test_agent_files.py).
                        self.assertIn("you may run it", prompt)
        design = {e["label"]: e["prompt"] for e in agents(results[1])}
        for label in ("review:code:#7", "review:netcode:#7"):
            self.assertIn("ARCHITECTURE by section: its outline first, then every section the design could contradict, "
                          "not only the ones it edits", design[label])
        self.assertIn("every section the plan could contradict", design["review:plan:#7"])
        code = {e["label"]: e["prompt"] for e in agents(results[0])}
        self.assertIn("the ARCHITECTURE sections the change touches, by section, never the whole doc", code["review:code:#7"])
        self.assertIn("the ARCHITECTURE sections the plan touches, by section", code["review:plan:#7"])

    def test_the_default_reading_list_leaves_area_files_to_load_by_path(self) -> None:
        # #339: the area CLAUDE.md files and .claude/rules/ load by path when the implementer Reads a file there (it
        # does before every Edit); read again by a tool they cost $17 in the ADR's window, mostly through `cat`. The
        # default list names neither and reads ARCHITECTURE by section; a manager's `reading` replaces it whole.
        jobs = [
            ("issue-task.js", dict(ARGS, plan_review=True), {"paths": ["tools/x.py"]}),
            ("issue-task.js", dict(ARGS, reading="r"), {"paths": ["tools/x.py"]}),
        ]
        default, given = run_jobs(jobs)
        for event in calls(default, "plan:") + calls(default, "implement:"):
            read = next(p for p in event["prompt"].split("\n\n") if p.startswith("Read: "))
            with self.subTest(agent=event["label"]):
                self.assertNotIn("CLAUDE.md", read)
                self.assertNotIn(".claude/rules/", read)
                self.assertIn("the ARCHITECTURE sections it names, by section, never the whole doc", read)
                self.assertIn("`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh section docs/ARCHITECTURE.md`", read)
        read = next(p for p in calls(given, "implement:")[0]["prompt"].split("\n\n") if p.startswith("Read: "))
        self.assertEqual(read, "Read: `gh issue view 7 --comments`; r.")

    def test_every_agent_call_matches_its_snapshot(self) -> None:
        # Compatibility first: another manager's launch or resume with today's args must get today's agents (every
        # case but publish-clean-main, publish-clean-findings-main, plan-review-main, checkpoint-off-main,
        # publish-sonnet-main and update-main passes no v2 arg). Each case runs as launched (`<case>.txt`), with
        # bounded waits (#411) and the lean agent types (#458) always on.
        jobs, files = [], []
        for name, cases in SNAPSHOT_CASES.items():
            for case, args, stub in cases:
                jobs.append((name, dict(ARGS, **args), stub))
                files.append(SNAPSHOTS.joinpath(name.removesuffix(".js"), f"{case}.txt"))
        results = run_jobs(jobs)
        if UPDATE:
            for path, result in zip(files, results):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(render(result).encode("utf-8"))
            self.fail(f"PRIME_WORKFLOW_SNAPSHOTS=update wrote {len(files)} snapshots; review the diff, then rerun without it")
        for path, result in zip(files, results):
            where = path.relative_to(SNAPSHOTS).as_posix()
            with self.subTest(snapshot=where):
                self.assertTrue(path.is_file(), f"missing snapshot {path}")
                want = path.read_bytes().decode("utf-8")
                got = render(result)
                if got != want:
                    old, new = want.splitlines(), got.splitlines()
                    diff = "\n".join(difflib.unified_diff(old, new, "snapshot", "now", n=1, lineterm=""))
                    k = next((i for i, (a, b) in enumerate(zip(old, new)) if a != b), min(len(old), len(new)))
                    first = new[k][:200] if k < len(new) else "(the run ends earlier)"
                    # selftest prints only a failure's last line, so the summary goes last.
                    self.fail(f"{diff[:4000]}\n{where} differs from line {k + 1}: {first!r}")


AVAILABLE = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))["availableModels"]
V2 = {"plan_review": True, "test_review": True, "second_review": True, "skeptic": True, "visual": ["spectate"]}
GODOT_LINE = "- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` (off-screen)."
PLAYCHECK_LINE = (
    "- No Godot windows: headless runs only; a screenshot only through `tools\\run.cmd shot` or "
    "`tools\\run.cmd playcheck` (both off-screen)."
)
# #455: how the test reviewer runs a mutants spec and the publisher a survived mutant again with bounded waits: in the
# background, a new log, `wait`; for ARGS.
MUTANTS_RUN = (
    "Run each spec in the background, never in the foreground (a foreground call dies at 600 s, and setup and the "
    "baseline come before the first mutant): `cd /d/prime-game/.claude/worktrees/7 && tools/run.sh mutants "
    '<spec.json> > <log> 2>&1; echo "exit=$?" >> <log>` in the Bash tool with run_in_background true and its timeout '
    "3600000, a NEW log under a7/ of your scratchpad for each run (mutants-1.log, mutants-2.log, ...), then "
    "`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh wait <log>` in separate calls until it finishes, as the "
    "bounded waits below say. A spec may hold several mutants (setup and the baseline then run once); one run at a "
    "time: another mutants run in the same checkout exits 1."
)
MUTANTS_RERUN = (
    "then run that mutant again in the background (a NEW log under a7/ of your scratchpad, then "
    "`tools/run.sh wait <log>`, as the bounded waits below say) to show it killed"
)
PNG = "D:/prime-game/.claude/worktrees/7/tools/out/playcheck/spectate/01.png"
SHOTS = {"available": True, "scenarios": ["spectate"], "exit_codes": [0], "pngs": [PNG]}
# lean (#332, docs/decisions/2026-10-04-lean-workflow-agent-types.md): the agent type each role's label prefix gets.
LEAN_WRITERS = ("task-implementer", "task-publisher")
LEAN_TYPES = {
    "plan": "task-implementer",
    "implement": "task-implementer",
    "test-review": "task-implementer",
    "publish": "task-publisher",
    "rebase": "task-publisher",
    "fix": "task-publisher",
}
# The lean snapshots pin a launch that passes `lean: true` (every launch of the week of N4 (a), 2026-10-06, before #458
# made it the default): since #883 a retired arg, which only logs.
LEAN_SNAPSHOT_CASES = {
    "issue-task.js": [("lean-main", {"branch": "core/7-x", "lean": True}, {"paths": ["core/x.gd"]})],
    "pr-rebase.js": [("lean-main", {"lean": True}, {"paths": ["core/x.gd"], "findings": [MAJOR]})],
}


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
        # b, the implementer's, is not sonnet: models.implement "sonnet" ended on 2026-10-13 (#1147).
        b = next(m for m in AVAILABLE if m != "sonnet")
        a = next(m for m in AVAILABLE if m != b)
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

    def test_the_code_role_is_the_code_reviewer_alone(self) -> None:
        # #535: efforts.review also moves the plan critique, the netcode reviews and the skeptics; efforts.code moves
        # only the diff's code reviewer, and falls back to review. models.code ended on 2026-10-13 (#1147:
        # EndedOptionsTest): models.review still moves the code reviewer with the others.
        a = AVAILABLE[0]
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", efforts={"code": "medium"}, **V2), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", models={"review": a}, efforts={"code": "medium", "review": "low"}, **V2), core),
        ]
        only_code, with_review = ({e["label"]: options(e) for e in agents(r)} for r in run_jobs(jobs))
        reviewers = ("review:plan:#7", "review:netcode:#7", "review:netcode-second:#7", "review:godot-api:#7", "skeptic:#7")
        self.assertEqual(only_code["review:code:#7"].get("effort"), "medium")
        for label in reviewers:
            self.assertNotIn("effort", only_code[label], label)
        self.assertNotIn("model", only_code["review:code:#7"])
        self.assertEqual((with_review["review:code:#7"]["model"], with_review["review:code:#7"]["effort"]), (a, "medium"))
        for label in set(reviewers) - {"review:godot-api:#7"}:
            self.assertEqual((with_review[label]["model"], with_review[label]["effort"]), (a, "low"), label)
        self.assertNotIn("model", with_review["review:godot-api:#7"])

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
        jobs += [("issue-task.js", dict(ARGS, **args), {}) for args in ({"checkpoint": "yes"}, {"checkpoint": 1})]  # #559
        # ab_review and models.code (#535) ended on 2026-10-13 and throw: EndedOptionsTest (#1147).
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

    def test_a_retired_arg_only_logs(self) -> None:
        # #883 removed the switches of bounded waits (#411) and the lean agent types (#458), whose only use was the
        # resume of a run launched before them (the engineer's approval on #876). A manager's launch with the old args
        # must not throw: each one only logs, as retired rather than unknown, and the run is the one without it.
        retired = (
            {"bounded_waits": True},
            {"bounded_waits": False},
            {"bounded_waits": None},
            {"lean": True},
            {"lean": None},
            {"lean": False, "lean_reason": "a resume of a run launched before #458"},
            {"lean_reason": "x"},
            {"bounded_waits": "yes", "lean": 1},
        )
        cases = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        jobs = [(name, dict(args, **extra), stub) for name, args, stub in cases for extra in ({}, *retired)]
        results = run_jobs(jobs)
        size = 1 + len(retired)
        for i, (name, _, _) in enumerate(cases):
            plain, *rest = results[size * i : size * (i + 1)]
            self.assertIsNone(plain["error"])
            self.assertFalse([e for e in plain["events"] if e["kind"] == "log" and "retired args" in e["message"]])
            for extra, result in zip(retired, rest):
                with self.subTest(workflow=name, args=extra):
                    self.assertIsNone(result["error"])
                    self.assertEqual(render(result), render(plain))
                    logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
                    said = [m for m in logs if "retired args ignored (#883" in m]
                    self.assertEqual(len(said), 1, logs)
                    for key in extra:
                        self.assertIn(key, said[0])
                    self.assertFalse([m for m in logs if "unknown args ignored" in m and any(k in m for k in extra)], logs)

    def test_every_agent_gets_the_reading_line(self) -> None:
        # #468: the token audit of 2026-10-06 found big code files read whole (metrics.py, guard.py, merge.py,
        # test_workflows.py), the same content read twice with nothing changed, and 88% of turns with one tool. The
        # reading line is one constant of both scripts, the same text for every agent, the read-only reviewers too,
        # but issue-task's publisher (#696) and, since #1257, its plan, implement and test-review agents: their
        # task-publisher and task-implementer agent types carry the line.
        jobs = [
            ("issue-task.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS), {"paths": ["tools/x.py"]}),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("pr-rebase.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS), {"paths": ["tools/x.py"]}),
        ]
        lines: set[str] = set()
        labels: set[str] = set()
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                labels.add(event["label"].rsplit(":#", 1)[0])
                with self.subTest(workflow=name, agent=event["label"]):
                    found = [line for line in event["prompt"].splitlines() if line.startswith(READ_RULE)]
                    if name == "issue-task.js" and options(event).get("agentType") in LEAN_WRITERS:
                        self.assertEqual(found, [])
                        continue
                    self.assertEqual(len(found), 1, found)
                    lines.add(found[0])
        self.assertEqual(len(lines), 1, f"the line differs between agents or scripts: {sorted(lines)}")
        # The reviewers, the plan critique and the skeptics are covered too, not only the agents of the shared rules.
        self.assertLessEqual({"plan", "review:plan", "implement", "review:code", "review:netcode", "review:godot-api",
                              "review:netcode-second", "test-review", "skeptic", "publish", "rebase", "fix"}, labels)
        rule = next(iter(lines))
        for part in ("over 400 lines", "`grep -n`", "`cd <your worktree> && tools/run.sh section <file>`",
                     "`tools/run.sh section <file> <symbol>`", "main's copy", "a base before #468",
                     "the rows of that outline do not each start with a kind", "`#` comments as headings or nothing after its first line",
                     "an edit, a rebase, a checkout, a failed Edit or a compaction", "parallel calls", "`sed -n`",
                     "only when you restructure it"):
            self.assertIn(part, rule)
        # The old-base test must not misfire on a base with #468: every outline row of the repository's own code,
        # the two workflow scripts (all const and let) included, starts with a kind the line names.
        named = re.search(r"start with a kind \(([^)]*)\)", rule)
        self.assertIsNotNone(named, rule)
        kinds = set(re.split(r", | or ", named.group(1)))
        from runner import symbols

        paths = [WORKFLOWS / "issue-task.js", WORKFLOWS / "pr-rebase.js"]
        paths += sorted((ROOT / "tools" / "runner").glob("*.py"))
        for area in ("core", "server", "net", "client", "voice"):
            paths += sorted((ROOT / area).rglob("*.gd"))
        for path in paths:
            rows = symbols.outline(path)[1:]
            with self.subTest(file=path.relative_to(ROOT).as_posix()):
                # An empty outline reads as an old base; that costs nothing only for a file too short to outline.
                if not rows:
                    self.assertLess(len(path.read_text(encoding="utf-8").splitlines()), 20)
                for row in rows:
                    self.assertIn(row.split()[0].rstrip("*"), kinds, row)

    def test_every_v2_agent_gets_the_rules_or_is_a_read_only_reviewer(self) -> None:
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", base="release/m5", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, base="release/m5", second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        # With lean (always on since #883) the implementing and publishing agents get a lean writer type (#332) and
        # still every rule.
        for result in run_jobs(jobs):
            for event in agents(result):
                with self.subTest(agent=event["label"]):
                    if options(event).get("agentType") in LEAN_WRITERS:
                        self.assertIn(STASH_RULE, event["prompt"])
                        self.assertIn("GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/release/m5", event["prompt"])
                    elif "agentType" in options(event):
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
        self.assertIn(f'{SHORT_PLAN} comment_url; its file_map', critique["prompt"])
        self.assertIn('): {"summary":"p"', critique["prompt"])
        self.assertIn(f"{SHORT_PLAN} comment_url, which `gh issue view 7 --comments` shows): " '{"summary":"p"', implement["prompt"])
        self.assertIn('The critique: {"reviewer":"r"', implement["prompt"])
        self.assertIn('under "Plan review"', calls(ok, "publish")[0]["prompt"])
        self.assertEqual(ok["returned"]["plan"], {"summary": "p", "critique": {}})
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
            (
                "issue-task.js",
                dict(ARGS, branch="core/7-x", test_review=True),
                dict(core, queues={"publish": [{"published": False, "handoff_posted": True, "stopped_by_mutants": True}]}),
            ),
        ]
        ok, absent, exit_2, skeptic, dead, design, tooling, pub_stuck = run_jobs(jobs)
        # The publisher's own mutants rerun exited 2: the result says so, like the test review's, with the way on.
        self.assertIn("stopped_by_mutants true", calls(pub_stuck, "publish")[0]["prompt"])
        self.assertIn("stopped_by_mutants", options(calls(pub_stuck, "publish")[0])["schema"]["properties"])
        self.assertIn("in a rerun by the publisher", pub_stuck["returned"]["stopped"])
        self.assertNotIn("stopped", ok["returned"])
        self.assertNotIn("stopped_by_mutants", options(calls(absent, "publish")[0])["schema"]["properties"])
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
        for text in ("`tools\\run.cmd mutants --help`", "exit_2 true"):
            self.assertIn(text, test_review)
        # #455: with bounded waits (always on) each spec runs in the background with a new log and `wait`, as verify
        # and publish do, before the bounded-waits paragraph that gives the commands, and so does the publisher's
        # rerun of a survived mutant; the foreground advice of before #411 is gone (#883).
        publish = calls(ok, "publish")[0]["prompt"]
        for prompt, text in ((test_review, MUTANTS_RUN), (publish, MUTANTS_RERUN)):
            self.assertEqual(prompt.count(text), 1)
            self.assertLess(prompt.index(text), prompt.index("Bounded waits (bounded_waits)"))
            for foreground in ("ONE mutant per", "one per call"):
                self.assertNotIn(foreground, prompt)
        # What `mutants` really does (#202): its exit codes, the spec rules it enforces, its per-test-run timeout,
        # and its `not run` result, which the schema's enum lacks.
        for text in (
            "1: an invalid spec or a run that could not start or finish (a dirty worktree, another mutants run in the "
            "same checkout, a failed import, a crash): fix the spec, else report the FAIL lines",
            "2: its scratch worktree could not be removed, or the task's `git status` changed during the run",
            "a mutant may not touch a `class_name` or `extends` line",
            "its `original` must start exactly once on its 1-based `line`",
            "`--seconds` (default 300)",
            "A mutant that a stopped run lists as `not run` is reported as error",
        ):
            self.assertIn(text, test_review)
        mutant = options(calls(ok, "test-review")[0])["schema"]["properties"]["mutants"]["items"]
        self.assertNotIn("not run", mutant["properties"]["result"]["enum"])
        # The publisher's stop on exit 2 is unchanged.
        self.assertIn("If a `tools\\run.cmd mutants` run exits 2 (its scratch worktree could not be removed), stop", calls(ok, "publish")[0]["prompt"])
        publish = calls(ok, "publish")[0]["prompt"]
        self.assertIn("a table of the mutants", publish)
        self.assertIn("If a `tools\\run.cmd mutants` run exits 2", publish)
        # The command is missing on the branch (P7 not merged): reported in the PR and the result, and the run goes on.
        self.assertIsNone(absent["error"])
        self.assertIn("`tools\\run.cmd mutants` is missing on this branch (P7, #184", calls(absent, "publish")[0]["prompt"])
        self.assertIn("no mutants command on the branch", calls(absent, "publish")[0]["prompt"])
        self.assertFalse(absent["returned"]["test_review"]["available"])
        self.assertTrue(absent["returned"]["published"])
        # mutants exited 2: the publisher only reports.
        publish = calls(exit_2, "publish")[0]["prompt"]
        self.assertIn("Task: report a stopped run of issue #7", publish)
        self.assertIn("publish nothing", publish)
        self.assertNotIn("gh pr create", publish)
        # metrics reads the tier from this prompt too (#606 review), so a stopped full run is not "unknown".
        self.assertEqual(metrics.REVIEW_TIER.search(publish).group(1), "full")
        self.assertIn("mutants exited 2 in the test review", exit_2["returned"]["stopped"])
        # A resume would replay the cached exit 2 and stop again, so the result names the way on.
        self.assertIn("relaunch issue-task (not a resume", exit_2["returned"]["stopped"])
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
        self.assertEqual(six["returned"]["skeptic"], {"refuted": 0, "stood": 6, "unchecked": 0})
        self.assertEqual(len(calls(four, "skeptic")), 4)
        self.assertEqual(four["returned"]["skeptic"], {"refuted": 0, "stood": 4, "unchecked": 0})
        self.assertFalse(any("skeptic limit" in e["message"] for r in (six, four) for e in r["events"] if e["kind"] == "log"))
        skeptics = calls(three, "skeptic")
        self.assertEqual(len(skeptics), 3)
        for event in skeptics:
            self.assertEqual(options(event)["agentType"], "code-reviewer")
            self.assertIn('"problem":"p1"', event["prompt"])
            self.assertIn("refuted true only with evidence", event["prompt"])
        self.assertEqual([e["label"] for e in agents(three)][-1], "publish:#7")
        self.assertEqual(three["returned"]["skeptic"], {"refuted": 1, "stood": 2, "unchecked": 0})
        publish = calls(three, "publish")[0]["prompt"]
        self.assertIn("vote.gd:12 already checks it", publish)
        self.assertIn("A refuted finding is not fixed unless you find the skeptic wrong", publish)
        # The limit: the rest go to the publisher unchecked, and the log says so.
        self.assertEqual(len(calls(two, "skeptic")), 2)
        self.assertEqual(two["returned"]["skeptic"], {"refuted": 0, "stood": 2, "unchecked": 1})
        self.assertTrue(any("over the skeptic limit of 2" in e["message"] for e in two["events"] if e["kind"] == "log"))
        self.assertFalse(calls(none, "skeptic"))
        self.assertNotIn("Skeptics tried to refute", calls(none, "publish")[0]["prompt"])
        self.assertIn("a skeptic returned nothing", dead["error"])
        # pr-rebase: a refuted finding is not sent to the fix agent; when none is left, no fix agent runs.
        self.assertFalse(calls(all_refuted, "fix"))
        self.assertIsNone(all_refuted["returned"]["fix"])
        self.assertIn("no fix agent ran", all_refuted["returned"]["note"])
        self.assertEqual(all_refuted["returned"]["skeptic"], {"refuted": 2, "stood": 0, "unchecked": 0})
        # The manager copies the refuted findings into the PR body, so they come back in full with their reasons.
        refuted_back = {"from": "code-reviewer", "severity": "major", "file": "core/match/vote.gd", "line": 12, "problem": "p1", "reason": "vote.gd:12 already checks it"}
        self.assertEqual(all_refuted["returned"]["refuted"], [refuted_back, dict(refuted_back, **{"from": "netcode-security-reviewer"})])
        self.assertNotIn("refuted", one_stands["returned"])
        fix = calls(one_stands, "fix")
        self.assertEqual(len(fix), 1)
        self.assertIn("Skeptics refuted these blocker or major findings", fix[0]["prompt"])
        self.assertIn("vote.gd:12 already checks it", fix[0]["prompt"])

    def test_publish_clean_applies_only_on_a_clean_run(self) -> None:
        # #308, a one-wave trial: the full publisher of a run that the reviews, the test review and the skeptics left
        # with no blocker or major open takes the role publish_clean (falling back to publish), so a launch can give it
        # a cheaper model. Nothing else changes: not its prompt, not another agent, not a design task's publisher.
        m, p = AVAILABLE[1], AVAILABLE[0]
        core = dict(ARGS, branch="core/7-x")  # three reviewers: code, netcode, godot
        clean = {"paths": ["core/x.gd"], "findings": [MINOR]}
        major = {"paths": ["core/x.gd"], "findings": [MAJOR, MINOR]}  # three majors
        blocker = {"paths": ["core/x.gd"], "findings": [dict(MAJOR, severity="blocker")]}
        refuted = {"refuted": True, "reason": "vote.gd:12 already checks it", "evidence": "vote.gd:12"}
        stands = {"refuted": False, "reason": "it stands"}
        survived = {"available": True, "exit_2": False, "findings": [MAJOR], "mutants": [{"file": "core/x.gd", "result": "survived"}]}
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "tools/out/mutants/m1 is still listed"}
        trial = {"models": {"publish_clean": m}}
        jobs = [
            ("issue-task.js", core, clean),  # 0: the same run without the arg
            ("issue-task.js", dict(core, **trial), clean),
            ("issue-task.js", dict(core, **trial), major),
            ("issue-task.js", dict(core, **trial), blocker),
            ("issue-task.js", dict(core, skeptic=True, **trial), dict(major, queues={"skeptic": [refuted] * 3})),
            ("issue-task.js", dict(core, skeptic=True, **trial), dict(major, queues={"skeptic": [refuted, stands, refuted]})),  # 5
            ("issue-task.js", dict(core, skeptic=1, **trial), dict(major, queues={"skeptic": [refuted]})),
            ("issue-task.js", dict(core, test_review=True, **trial), dict(clean, queues={"test-review": [survived]})),
            ("issue-task.js", dict(core, models={"publish": p, "publish_clean": m}), clean),
            ("issue-task.js", dict(core, models={"publish": p, "publish_clean": m}), major),
            ("issue-task.js", dict(core, models={"publish": p}), clean),  # 10
            ("issue-task.js", dict(core, models={"publish": p}), major),
            ("issue-task.js", dict(core, efforts={"publish_clean": "medium"}), clean),
            ("issue-task.js", dict(core, efforts={"publish_clean": "medium"}), major),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, **trial), {"paths": ["docs/x.md"]}),
            ("issue-task.js", dict(core, test_review=True, **trial), dict(clean, queues={"test-review": [stuck]})),  # 15
            ("pr-rebase.js", dict(ARGS, **trial), clean),
            ("issue-task.js", dict(ARGS, models={"publish_clean": ""}), {}),
            ("issue-task.js", dict(ARGS, efforts={"publish_clean": "extreme"}), {}),
        ]
        results = run_jobs(jobs)
        for k, result in enumerate(results[:16]):
            self.assertIsNone(result["error"], k)

        def publisher(result: dict) -> dict:
            (event,) = calls(result, "publish")
            return event

        def trial_of(result: dict) -> dict:
            return result["returned"]["publish_clean"]

        def logs(result: dict) -> list[str]:
            return [e["message"] for e in result["events"] if e["kind"] == "log" and "publish_clean" in e["message"]]

        base, on = results[0], results[1]
        # Clean: only the publisher's model changes; its prompt and every other option are today's.
        self.assertEqual(options(publisher(on))["model"], m)
        self.assertEqual(publisher(on)["prompt"], publisher(base)["prompt"])
        self.assertEqual({k: v for k, v in options(publisher(on)).items() if k != "model"}, options(publisher(base)))
        self.assertEqual([e["label"] for e in agents(on)], [e["label"] for e in agents(base)])
        for before, after in zip(agents(base), agents(on)):
            if not after["label"].startswith("publish"):
                self.assertEqual((after["opts"], after["prompt"]), (before["opts"], before["prompt"]), after["label"])
        self.assertNotIn("publish_clean", base["returned"])
        self.assertEqual(logs(base), [])
        want = {"applied": True, "why": "no blocker or major open", "open": 0, "model": m, "effort": "high"}
        self.assertEqual(trial_of(on), want)
        self.assertEqual(len(logs(on)), 1)
        self.assertIn("publish_clean applied", logs(on)[0])
        # A blocker or major still open keeps the publisher as it is today.
        for k, open_ in ((2, 3), (3, 3), (5, 1), (6, 2), (7, 1)):
            with self.subTest(case=k):
                self.assertNotIn("model", options(publisher(results[k])))
                self.assertEqual((trial_of(results[k])["applied"], trial_of(results[k])["open"]), (False, open_))
                self.assertIsNone(trial_of(results[k])["model"])
                self.assertIn(f"publish_clean not applied: {open_} blocker or major finding(s) open", logs(results[k])[0])
        # Every blocker or major refuted by a skeptic: closed, so the trial applies.
        self.assertEqual(options(publisher(results[4]))["model"], m)
        self.assertEqual((trial_of(results[4])["applied"], trial_of(results[4])["open"]), (True, 0))
        # publish_clean falls back to publish; publish alone gives the same model both ways and no result field.
        self.assertEqual(options(publisher(results[8]))["model"], m)
        self.assertEqual(options(publisher(results[9]))["model"], p)
        self.assertEqual(trial_of(results[9])["model"], p)
        for k in (10, 11):
            self.assertEqual(options(publisher(results[k]))["model"], p)
            self.assertNotIn("publish_clean", results[k]["returned"])
        # efforts.publish_clean: the effort in the options and in the prompt's Effort line.
        self.assertEqual(options(publisher(results[12]))["effort"], "medium")
        self.assertIn("Effort: medium.", publisher(results[12])["prompt"])
        self.assertEqual(options(publisher(results[13]))["effort"], "high")
        self.assertIn("Effort: high.", publisher(results[13])["prompt"])
        self.assertNotIn("model", options(publisher(results[12])))
        # A design task never switches.
        design = results[14]
        self.assertNotIn("model", options(publisher(design)))
        self.assertEqual((trial_of(design)["applied"], trial_of(design)["why"]), (False, "a design task"))
        self.assertIn("publish_clean not applied: a design task", logs(design)[0])
        # A mutants stop: the publisher that only reports it is not the trial's, and the result says so.
        stop = results[15]
        self.assertIn("Task: report a stopped run of issue #7", publisher(stop)["prompt"])
        self.assertNotIn("model", options(publisher(stop)))
        self.assertEqual((trial_of(stop)["applied"], trial_of(stop)["why"]), (False, "mutants exited 2"))
        self.assertIn("publish_clean not applied: mutants exited 2", logs(stop)[0])
        # pr-rebase has no publisher role; a wrong value names the role's values, not a missing role.
        self.assertIn("args.models.publish_clean: no such role", results[16]["error"])
        self.assertEqual(agents(results[16]), [])
        for result in results[17:]:
            self.assertIn("must be", result["error"])
            self.assertNotIn("no such role", result["error"])
            self.assertEqual(agents(result), [])

    def test_pr_rebase_publish_moves_its_rebase_and_fix_agents(self) -> None:
        # #835, a trial: pr-rebase's role publish is the fallback of rebase and fix, the two agents that publish; its
        # model can only be sonnet, while rebase and fix keep the values they had. The reviewers never move.
        s = "sonnet"
        other = next(m for m in AVAILABLE if m != s)
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        jobs = [
            ("pr-rebase.js", ARGS, core),  # 0: the same run without the arg
            ("pr-rebase.js", dict(ARGS, models={"publish": s}), core),
            ("pr-rebase.js", dict(ARGS, models={"publish": s, "fix": other}), core),
            ("pr-rebase.js", dict(ARGS, efforts={"publish": "medium"}), core),
            ("pr-rebase.js", dict(ARGS, models={"rebase": other}), core),
            ("pr-rebase.js", dict(ARGS, models={"publish": other}), core),  # 5
            ("pr-rebase.js", dict(ARGS, models={"publish_findings": s}), core),
        ]
        results = run_jobs(jobs)
        for k, result in enumerate(results[:5]):
            self.assertIsNone(result["error"], k)

        def got(result: dict, key: str) -> dict:
            return {e["label"]: options(e).get(key) for e in agents(result)}

        base, on = results[0], results[1]
        self.assertEqual({k: v for k, v in got(on, "model").items() if v}, {"rebase:#8": s, "fix:#8": s})
        self.assertEqual([e["prompt"] for e in agents(on)], [e["prompt"] for e in agents(base)])
        self.assertEqual({k: v for k, v in got(results[2], "model").items() if v}, {"rebase:#8": s, "fix:#8": other})
        self.assertEqual((got(results[3], "effort")["rebase:#8"], got(results[3], "effort")["fix:#8"]), ("medium", "medium"))
        self.assertEqual({k: v for k, v in got(results[4], "model").items() if v}, {"rebase:#8": other})
        self.assertIn("args.models.publish must be sonnet", results[5]["error"])
        self.assertIn("args.models.publish_findings: no such role", results[6]["error"])
        for result in results[5:]:
            self.assertEqual(agents(result), [])

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
        for event in calls(on, "implement"):
            self.assertIn(PLAYCHECK_LINE, event["prompt"])
            self.assertNotIn(GODOT_LINE, event["prompt"])
        # #696: the publisher of a run that is not visual has no Godot-windows line (it opens none); a visual run's
        # publisher keeps the playcheck one, since it may rerun a scenario.
        for event in calls(off, "publish"):
            self.assertNotIn(PLAYCHECK_LINE, event["prompt"])
            self.assertNotIn(GODOT_LINE, event["prompt"])
        for event in calls(on, "publish"):
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
        self.assertTrue(missing["returned"]["published"])
        self.assertIn("`spectate`", calls(unreported, "implement")[0]["prompt"])
        self.assertIn("the implementer reported no playcheck run", calls(unreported, "publish")[0]["prompt"])

    def test_each_agent_that_waits_gets_one_bounded_waits_paragraph(self) -> None:
        # #303: a tool call that blocks over 5 minutes (verify, publish, mutants, CI) costs the agent's whole context
        # again, so each agent that runs one gets one paragraph, after the steps it replaces; the others get none.
        # #411 made it the default and #883 removed its switch (bounded_waits false, the prompts of before #411). #455
        # changed one sentence more where mutants run: the test reviewer's run of a spec and the publisher's rerun of a
        # survived mutant.
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "tools/out/mutants/m1 is still listed"}
        design = {"paths": ["docs/x.md"], "findings": [MAJOR]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), core),
            ("pr-rebase.js", dict(ARGS), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True, skeptic=True), design),
        ]
        waiting, publishing = ("implement", "test-review", "publish", "rebase", "fix"), ("publish", "rebase", "fix")
        extra = {}
        for k, ((name, _, _), result) in enumerate(zip(jobs, run_jobs(jobs))):
            self.assertIsNone(result["error"])
            stopped = k == 2  # the publisher that only reports a mutants stop runs no long command
            for event in agents(result):
                label, prompt = event["label"], event["prompt"]
                with self.subTest(case=k, agent=label):
                    if not label.startswith(waiting) or (stopped and label.startswith("publish")):
                        self.assertNotIn("Bounded waits (bounded_waits)", prompt)
                        continue
                    # #455: the one other text bounded waits change is how mutants run, in the background with `wait`.
                    if label.startswith("test-review"):
                        self.assertIn(MUTANTS_RUN, prompt)
                    self.assertEqual(prompt.count("Bounded waits (bounded_waits)"), 1)
                    new = prompt.split("\n\n")
                    i = next(i for i, text in enumerate(new) if text.startswith("Bounded waits (bounded_waits): this replaces how"))
                    paragraph = new[i]
                    scratch = "r8" if name == "pr-rebase.js" else "a7"
                    for text in (
                        "every `verify`, `publish`, `mutants` and `gh pr checks --watch` step in this prompt",
                        "run_in_background",
                        f"under {scratch}/ of your scratchpad",
                        'cd /d/prime-game/.claude/worktrees/7 && tools/run.sh <command> > <log> 2>&1; echo "exit=$?" >> <log>',
                        "tools/run.sh wait <log>",
                        "`tools\\run.cmd wait <log>`",
                        "300000",
                        f"No tool call blocks longer than {wait.DEFAULT_MAX} s",
                        "never only with the tool's timeout",
                        "never start the job again",
                        f"timeout {wait.DEFAULT_MAX} gh pr checks <pr> --watch --interval 30; echo rc=$?` in the Bash "
                        "tool with the tool's timeout set to 300000",
                        "while rc is 124 or 8",
                        "no checks reported",
                        "`wait: no log`, `wait: cannot read` or `wait: --max` line is wait's own error",
                        "mutants: 0 the run completed, 1 a bad spec or a run that could not finish, 2 its scratch "
                        "worktree could not be removed",
                        "run them in the foreground as before",
                        "Read a log by search, never whole",  # #572: verify and publish point to their whole output
                        "`tools/out/logs/verify-output.log`",
                    ):
                        self.assertIn(text, paragraph)
                    # #555: the Bash tool's timeout outlasts the step plus the start-up before it, and every number of
                    # seconds the paragraph names is the step.
                    for ms in re.findall(r"timeout set to (\d+)", paragraph):
                        self.assertGreater(int(ms), (wait.DEFAULT_MAX + wait.AROUND_P95) * 1000)
                    self.assertEqual(set(re.findall(r"(\d+) s\b", paragraph)), {str(wait.DEFAULT_MAX)})
                    self.assertEqual(set(re.findall(r"timeout (\d+) gh", paragraph)), {str(wait.DEFAULT_MAX)})
                    # It comes after every step it replaces, so the last word on CI and verify is the bounded one.
                    for j, text in enumerate(new):
                        if j != i and ("gh pr checks" in text or "run.cmd verify" in text):
                            self.assertLess(j, i, text[:120])
                    kind = "publishing" if label.startswith(publishing) else "other"
                    kind = "implementing" if label.startswith("implement") else kind
                    # #574: only the implementer's inner loop may run verify --fail-fast; what it reports as
                    # verify_tail, publish's verify and every other agent's run each step.
                    fail_fast = "In your inner loop you may run `verify --fail-fast` (it stops at the first red step)"
                    if kind == "implementing":
                        self.assertIn(fail_fast, paragraph)
                        self.assertIn(
                            "the run you report as verify_tail, like publish's, is a whole `verify --changed`", paragraph
                        )
                    else:
                        self.assertNotIn("--fail-fast", paragraph)
                    if kind == "publishing":
                        # #471: publish verifies (or reuses a green verify of the identical tree) and pushes nothing
                        # on red, so a publisher runs no standalone verify before it.
                        self.assertIn("No standalone `verify` before `publish`", paragraph)
                        self.assertIn("run the tests they touch and `check`, then `publish`", paragraph)
                        self.assertIn("a red verify inside it pushes nothing", paragraph)
                        self.assertNotIn("wait --verified", paragraph)
                        self.assertTrue(new[-2].startswith(HUMAN_STEPS_ASK), new[-2][:80])
                    else:
                        self.assertNotIn("wait --verified", paragraph)
                    extra.setdefault((name, kind), set()).add(paragraph.replace(scratch + "/", "<s>/"))
        # One paragraph per kind, and the two scripts cannot share a module: their copies must not drift apart.
        self.assertEqual(len(extra[("issue-task.js", "publishing")]), 1)
        self.assertEqual(extra[("issue-task.js", "publishing")], extra[("pr-rebase.js", "publishing")])
        self.assertEqual(len(extra[("issue-task.js", "other")]), 1)
        self.assertEqual(len(extra[("issue-task.js", "implementing")]), 1)

    def test_meta_and_the_args_comment_name_each_v2_arg(self) -> None:
        # A manager states the agent count in its kickoff from these lines.
        for name, names in (
            (
                "issue-task.js",
                ("plan_review", "test_review", "second_review", "skeptic", "visual", "efforts", "models", "checkpoint", "tier", "update"),
            ),
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

    def test_the_writers_run_as_the_lean_types(self) -> None:
        # #332: lean appends an agentType to the implementing and publishing agents' options, last, so the efforts and
        # models a launch sets still reach them; a reviewer keeps its own type. #458 made it the default and #883
        # removed its switch (lean false, the general workflow agent): every agent of a launch has a type (#557).
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "n"}
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        tuned = {"efforts": {"implement": "medium", "publish": "low"}, "models": {"implement": AVAILABLE[0]}}
        bases = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **tuned, **V2), core),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True, efforts={"fix": "medium"}), core),
        ]
        results = run_jobs(bases)
        typed = set()
        for i, ((name, _, _), result) in enumerate(zip(bases, results)):
            with self.subTest(job=i, workflow=name):
                self.assertIsNone(result["error"])
                for event in agents(result):
                    label, opts = event["label"], options(event)
                    self.assertIn("agentType", opts, label)
                    want = LEAN_TYPES.get(label.split(":")[0])
                    if want is None:
                        self.assertNotIn(opts["agentType"], LEAN_WRITERS, label)
                        continue
                    typed.add(label.split(":")[0])
                    self.assertEqual(opts["agentType"], want, label)
                    self.assertEqual(list(opts)[-1], "agentType", label)  # appended last
        self.assertEqual(sorted(typed), sorted(LEAN_TYPES))
        # The tuned launch's effort and model still reach the lean implementer and publisher.
        lean = {e["label"]: options(e) for e in agents(results[0])}
        self.assertEqual((lean["implement:#7"]["effort"], lean["implement:#7"]["model"]), ("medium", AVAILABLE[0]))
        self.assertEqual(lean["publish:#7"]["effort"], "low")

    def test_lean_options_match_their_snapshots(self) -> None:
        # Like the main snapshots, each case runs as launched.
        jobs, files = [], []
        for name, cases in LEAN_SNAPSHOT_CASES.items():
            for case, args, stub in cases:
                jobs.append((name, dict(ARGS, **args), stub))
                files.append(SNAPSHOTS.joinpath(name.removesuffix(".js"), f"{case}.txt"))
        results = run_jobs(jobs)
        if UPDATE:
            for path, result in zip(files, results):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(render(result).encode("utf-8"))
            self.fail(f"PRIME_WORKFLOW_SNAPSHOTS=update wrote {len(files)} lean snapshots; review the diff, then rerun without it")
        for path, result in zip(files, results):
            with self.subTest(snapshot=path.relative_to(SNAPSHOTS).as_posix()):
                self.assertTrue(path.is_file(), f"missing snapshot {path}")
                self.assertEqual(render(result), path.read_bytes().decode("utf-8"))
                self.assertIn('"agentType":"task-', render(result))

    def test_every_agent_type_the_scripts_pass_has_an_agent_file(self) -> None:
        # A typo in an agentType makes agent() throw at launch; the file's name: is what Claude Code resolves.
        from runner import instructions

        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", lean=True, **V2), {"paths": ["core/x.gd", "client/x.tscn"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, lean=True, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        seen = {options(e).get("agentType") for result in run_jobs(jobs) for e in agents(result)} - {None}
        self.assertTrue(set(LEAN_WRITERS) <= seen, seen)
        for agent_type in sorted(seen):
            with self.subTest(agent_type=agent_type):
                path = ROOT / ".claude" / "agents" / f"{agent_type}.md"
                self.assertTrue(path.is_file(), f"no agent file for {agent_type}")
                self.assertEqual(instructions.parse(path.read_text(encoding="utf-8")).fields.get("name"), agent_type)


EFFORTS = ("low", "medium", "high", "xhigh", "max")


class ReviewerEffortTest(unittest.TestCase):
    """The workflows pass an agentType reviewer no effort unless a launch's `efforts` names its role, so the agent file's
    own `effort` applies; without one the reviewer inherits the manager session's effort (xhigh before #308)."""

    def test_every_routed_reviewer_sets_its_own_effort(self) -> None:
        from runner.instructions import parse

        routed = set()
        for name in ("issue-task.js", "pr-rebase.js"):
            routed |= set(re.findall(r"agentType: '([a-z-]+)'", (WORKFLOWS / name).read_text(encoding="utf-8")))
        self.assertTrue(routed, "no agentType found in the workflows: the pattern no longer matches them")
        for agent in sorted(routed):
            fields = parse((ROOT / ".claude" / "agents" / f"{agent}.md").read_text(encoding="utf-8")).fields
            with self.subTest(agent=agent):
                self.assertIn(fields.get("effort"), EFFORTS, "no effort: the reviewer inherits the manager's")
                # Today's level for every reviewer (docs/decisions/2026-09-28-effort-and-workflow-bounds.md, amended
                # 2026-10-04 by #308).
                self.assertEqual(fields.get("effort"), "high")


# The compact result (#386): what a finished run hands the manager. Long texts as the agents of 2026-10-04 wrote them.
LONG = "First line of a long text that goes on well past one line of the manager's context. " * 4
SUMMARY = "#7 is done in 3 commits; verify passed at HEAD abc1234.\n\n" + "What changed: a paragraph. " * 250
BLOCKER = {"severity": "blocker", "file": "core/match/vote.gd", "line": 3, "problem": LONG, "fix": "Rewrite it: " + LONG * 3}
STEPS = [
    {"why": "After PR #9 merges, remove the task's worktree (previewed with `git worktree list`).", "command": "cd D:\\prime-game; tools\\run.cmd worktree-done 7"},
    {"why": "Decide whether #7 closes at 18 of 20 runs: (a) accept, (b) wait for #354. Recommended: (a). Answer on PR #9.", "command": ""},
]
NEEDS = [
    "1. Does #7 close at 18 of 20? (a) Accept it and close #7 when PR #9 merges. (b) Keep it open until #354 lands. Recommendation: (a).\nA second paragraph with the scenario.",
    "2. Approve the ADR amendment (recommended) or leave the ADR as history.",
]
FULL_IMPL = {
    "verify_green": True, "verify_tail": "verify summary\n" + "step ok\n" * 20, "changed_paths": ["core/match/vote.gd"],
    "commits": ["abc1234 feat(core): x"] * 3, "complete": False, "left": [LONG], "summary": SUMMARY, "decisions": [LONG] * 4,
    "needs_engineer": ["the implementer's own item, which the publisher carries into the PR"],
    "provisional_content": ["content/roles/x.tres"], "proposed_issues": [LONG],
}
FULL_PUB = {
    "published": True, "pr_number": 9, "pr_url": "https://github.com/xperiaroco2/prime-game/pull/9", "ci_green": True,
    "handoff_posted": True, "board_in_review": False, "closes_issue": False, "fixed": [LONG] * 5,
    "not_fixed": [LONG, "the second one\nwith a second line", "None"], "needs_engineer": NEEDS,
    "merge_notes": "Merge #8 first.\n" + LONG * 3, "human_steps": STEPS,
}


def size(value: object) -> int:
    return len(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class CompactResultTest(unittest.TestCase):
    def test_issue_task_keeps_every_field_the_manager_acts_on(self) -> None:
        # Orchestrate-stage §4 reads the PR, CI, published, stopped, needs_engineer, human_steps (their commands copied
        # as is), not_fixed, the reviews' counts and the v2 options' summaries; the long texts become a line or a count.
        reviews = {"review:code": [{"reviewer": "r", "verdict": LONG, "findings": [BLOCKER, MAJOR, MINOR, MINOR]}], "review:netcode": [{"reviewer": "r", "verdict": "ok", "findings": []}]}
        stub = {"paths": ["core/match/vote.gd"], "queues": dict(reviews, implement=[FULL_IMPL], publish=[FULL_PUB])}
        silent = {k: v for k, v in FULL_PUB.items() if k != "needs_engineer"}
        empty = dict(FULL_PUB, needs_engineer=["None"])
        jobs = [("issue-task.js", dict(ARGS, branch="core/7-x"), stub)] + [
            ("issue-task.js", dict(ARGS, branch="core/7-x"), dict(stub, queues=dict(stub["queues"], publish=[p]))) for p in (silent, empty)
        ]
        result, no_list, no_item = run_jobs(jobs)
        self.assertIsNone(result["error"])
        # A publisher that returns no needs_engineer list, or one with no item, leaves the implementer's.
        self.assertEqual(no_list["returned"]["needs_engineer"], FULL_IMPL["needs_engineer"])
        self.assertEqual(no_item["returned"]["needs_engineer"], FULL_IMPL["needs_engineer"])
        out = result["returned"]
        self.assertEqual(
            {k: out[k] for k in ("n", "pr", "pr_url", "published", "ci_green", "closes_issue", "board_in_review", "verify_green", "complete")},
            {"n": 7, "pr": 9, "pr_url": FULL_PUB["pr_url"], "published": True, "ci_green": True, "closes_issue": False, "board_in_review": False, "verify_green": True, "complete": False},
        )
        self.assertNotIn("handoff_posted", out)  # true is the usual: only a false one is the manager's to act on
        self.assertNotIn("stopped", out)
        self.assertEqual(out["human_steps"], STEPS)
        self.assertEqual(out["needs_engineer"], NEEDS)
        self.assertEqual(out["reviews"], [{"by": "code-reviewer", "blocker": 1, "major": 1, "minor": 2}, {"by": "netcode-security-reviewer"}, {"by": "godot-api-checker"}])
        self.assertEqual(out["fixed"], 5)
        self.assertEqual(len(out["not_fixed"]), 2, "a None entry says nothing")
        self.assertEqual(out["not_fixed"][1], "the second one …")
        for text, cut in ((SUMMARY, out["summary"]), (LONG, out["not_fixed"][0]), (FULL_PUB["merge_notes"], out["merge_notes"])):
            self.assertLessEqual(len(cut), 160)
            self.assertTrue(cut.endswith("…"), cut)
            self.assertTrue(text.startswith(cut.removesuffix("…").rstrip(" ")), cut)
        self.assertEqual(out["proposed_issues"], [LONG[:99].rstrip() + "…"])
        self.assertEqual(out["provisional_content"], ["content/roles/x.tres"])
        self.assertNotIn("left", out)  # after a publisher, the PR and not_fixed say what is left
        self.assertIn("journal.jsonl", out["full"])
        # The publisher's fix text and the implementer's decisions stay in the journal only.
        self.assertNotIn("Rewrite it", json.dumps(out))
        self.assertNotIn("decisions", out)
        self.assertLessEqual(size({k: v for k, v in out.items() if k not in ("needs_engineer", "human_steps")}), 1500)
        whole = size([FULL_IMPL, reviews["review:code"][0], FULL_PUB])
        self.assertGreater(whole, 10 * size(out), "the whole results, as the result before #386 carried them")

    def test_issue_task_stops_keep_the_failure_and_the_engineers_steps(self) -> None:
        # A red implementer: the relaunch's notes need its verify tail, what it left and its needs_engineer.
        red = dict(FULL_IMPL, verify_green=False, left=[LONG, "None", "the second one\nwith a second line"])
        stuck = {"available": True, "exit_2": True, "findings": [MAJOR], "notes": "tools/out/mutants/m1 is still listed\n" + LONG,
                 "mutants": [{"file": "core/x.gd", "result": "killed"}, {"file": "core/x.gd", "result": "survived"}, {"file": "core/x.gd", "result": "killed"}]}
        stop_pub = {"published": False, "handoff_posted": True, "stopped_by_mutants": True, "human_steps": STEPS[:1], "needs_engineer": NEEDS[:1]}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", plan_review=True), {"paths": ["core/x.gd"], "queues": {"implement": [red]}}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), {"paths": ["core/x.gd"], "queues": {"test-review": [stuck], "publish": [stop_pub]}}),
        ]
        red_run, mutants_run = run_jobs(jobs)
        out = red_run["returned"]
        self.assertIn("verify red after the implementer", out["stopped"])
        self.assertIn("relaunch issue-task (not a resume)", out["stopped"])
        self.assertEqual(out["verify_tail"], FULL_IMPL["verify_tail"])
        self.assertEqual(out["left"], [LONG, "the second one\nwith a second line"], "in full; a None entry says nothing")
        self.assertEqual(out["needs_engineer"], FULL_IMPL["needs_engineer"])
        self.assertEqual(out["plan"], {"summary": "p", "critique": {}})
        self.assertEqual(out["reviews"], [])
        self.assertNotIn("pr_url", out)
        out = mutants_run["returned"]
        self.assertIn("mutants exited 2 in the test review", out["stopped"])
        self.assertTrue(out["stopped_by_mutants"])
        self.assertFalse(out["published"])
        self.assertEqual(out["human_steps"], STEPS[:1])
        self.assertEqual(out["needs_engineer"], NEEDS[:1])
        self.assertEqual(out["test_review"], {"available": True, "exit_2": True, "mutants": {"killed": 2, "survived": 1}, "findings": {"major": 1}, "notes": "tools/out/mutants/m1 is still listed …"})

    def test_wave_reads_the_stop_of_a_compact_result(self) -> None:
        # `wave` reads only "stopped" from a run's notification (its <result> is cut at about 8 kB).
        from runner.wave import STOPPED

        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x"), {"paths": ["core/x.gd"], "queues": {"implement": [dict(FULL_IMPL, verify_green=False)]}}),
            ("issue-task.js", dict(ARGS, branch="core/7-x"), {"paths": ["core/x.gd"], "queues": {"implement": [FULL_IMPL], "publish": [FULL_PUB]}}),
            ("pr-rebase.js", ARGS, {"paths": ["core/x.gd"], "queues": {"rebase": [{"up_to_date": False, "verify_green": False, "published": False}]}}),
        ]
        red, ok, red_rebase = run_jobs(jobs)
        for result in (red, red_rebase):
            m = STOPPED.search(json.dumps(result["returned"], ensure_ascii=False))
            self.assertIsNotNone(m)
            self.assertEqual(m.group(1), result["returned"]["stopped"])
        self.assertIsNone(STOPPED.search(json.dumps(ok["returned"], ensure_ascii=False)))

    def test_pr_rebase_keeps_every_field_the_manager_acts_on(self) -> None:
        step_fix = {"why": "Re-run the trial merge after #8.", "command": "cd D:\\prime-game; tools\\run.cmd merge-check --base main"}
        rebased = {"up_to_date": True, "verify_green": True, "published": True, "ci_green": True, "old_tip": "a" * 40, "new_tip": "b" * 40,
                   "changed_paths": ["core/x.gd"], "conflicts": [LONG, LONG], "fixes": [LONG], "problems": [], "human_steps": STEPS[:1]}
        fixed = {"fixed": [LONG, LONG], "not_fixed": [LONG], "verify_green": True, "published": True, "ci_green": False, "human_steps": [step_fix]}
        problems = ["verify red: test_x fails\n" + LONG, "publish refused: behind origin/main"]
        jobs = [
            ("pr-rebase.js", ARGS, {"paths": ["core/x.gd"], "findings": [BLOCKER, MINOR], "queues": {"rebase": [rebased], "fix": [fixed]}}),
            ("pr-rebase.js", ARGS, {"paths": ["core/x.gd"], "queues": {"rebase": [{"up_to_date": False, "verify_green": False, "published": False, "problems": problems, "human_steps": STEPS}]}}),
        ]
        ok, red = run_jobs(jobs)
        out = ok["returned"]
        self.assertIsNone(ok["error"])
        self.assertEqual(
            {k: out[k] for k in ("pr", "n", "published", "ci_green", "verify_green", "up_to_date", "conflicts", "fixes", "fix")},
            {"pr": 8, "n": 7, "published": True, "ci_green": False, "verify_green": True, "up_to_date": True, "conflicts": 2, "fixes": 1, "fix": {"fixed": 2}},
        )
        self.assertEqual(out["human_steps"], STEPS[:1] + [step_fix])
        self.assertEqual(out["reviews"], [{"by": "code-reviewer", "blocker": 1, "minor": 1}, {"by": "netcode-security-reviewer", "blocker": 1, "minor": 1}])
        self.assertEqual(out["not_fixed"], [LONG[:159].rstrip() + "…"])
        self.assertNotIn("stopped", out)
        self.assertIn("journal.jsonl", out["full"])
        self.assertLessEqual(size(out), 1500)
        out = red["returned"]
        self.assertIn("rebase red or unpublished", out["stopped"])
        self.assertEqual(out["problems"], problems, "the relaunch's steps need the problems in full")
        self.assertEqual(out["human_steps"], STEPS)
        self.assertEqual((out["published"], out["verify_green"], out["fix"], out["reviews"]), (False, False, None, []))

    def test_both_scripts_share_the_compact_helpers(self) -> None:
        # One reducer's helpers in two scripts (a workflow script imports nothing): the same text, from the comment that
        # opens them to the blank line that ends them.
        blocks = []
        for name in ("issue-task.js", "pr-rebase.js"):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            start = text.index("// The compact result (#386)")
            blocks.append(text[start : text.index("\n\n", start)])
        self.assertEqual(blocks[0], blocks[1])
        self.assertIn("const FULL = ", blocks[0])


# #470: what the later agents get of the implementer's report and the plan (the token audit of 2026-10-06).
REPORT = (
    "The implementer's report, as a digest (its summary, whether it is complete and what it left, the changed "
    "paths, the content it marked provisional, and each decision and item for the engineer cut to a line; the diff "
    "is the change): "
)
PLAN_MARKS = {"criteria": ["CRITERION-MARK"], "files": ["FILE-MARK"], "tests": ["TEST-MARK"], "steps": ["STEP-MARK"]}


def report_of(prompt: str) -> dict:
    """The digest a reviewer's prompt carries, parsed."""
    start = prompt.index(REPORT) + len(REPORT)
    return json.loads(prompt[start : prompt.index("\n\n", start)])


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class DigestTest(unittest.TestCase):
    def test_reviewers_get_a_digest_of_the_implementers_report(self) -> None:
        # Every reviewer and the test reviewer: the summary, complete, the changed paths, the provisional content, the
        # decisions, needs_engineer and left (each cut to a line), and nothing else of the report (no verify tail,
        # commits or proposed issues). A reviewer must see what was left on purpose, or it reports each deferred
        # acceptance criterion as a blocker.
        args = dict(ARGS, branch="core/7-x", second_review=True, test_review=True)
        stub = {"paths": FULL_IMPL["changed_paths"], "queues": {"implement": [FULL_IMPL]}}
        bare = {"paths": ["core/x.gd"], "queues": {"implement": [implemented(["core/x.gd"], needs_engineer=["None"])]}}
        result, plain = run_jobs([("issue-task.js", args, stub), ("issue-task.js", args, bare)])
        readers = calls(result, "review:") + calls(result, "test-review")
        self.assertEqual(len(readers), 5)
        for event in readers:
            with self.subTest(agent=event["label"]):
                prompt = event["prompt"]
                self.assertNotIn("The implementer reported", prompt)
                self.assertEqual(prompt.count(REPORT), 1)
                digest = report_of(prompt)
                self.assertEqual(
                    list(digest),
                    ["summary", "complete", "changed_paths", "provisional_content", "decisions", "needs_engineer", "left"],
                )
                self.assertIs(digest["complete"], False)
                self.assertEqual(digest["provisional_content"], FULL_IMPL["provisional_content"])
                self.assertEqual(len(digest["left"]), 1)
                self.assertTrue(len(digest["left"][0]) <= 160 and digest["left"][0].endswith("…"), digest["left"])
                self.assertLessEqual(len(digest["summary"]), 1200)
                self.assertTrue(FULL_IMPL["summary"].startswith(digest["summary"].removesuffix("…")))
                self.assertEqual(digest["changed_paths"], FULL_IMPL["changed_paths"])
                self.assertEqual(len(digest["decisions"]), 4)
                self.assertTrue(all(len(d) <= 160 and d.endswith("…") for d in digest["decisions"]), digest["decisions"])
                self.assertEqual(digest["needs_engineer"], FULL_IMPL["needs_engineer"])
                self.assertLessEqual(size(digest), 2500)
                for text in ("step ok", "abc1234 feat(core)", "verify_tail", "proposed_issues"):
                    self.assertNotIn(text, prompt)
        # Lists with nothing in them stay out; the summary, complete and the paths are always there.
        for event in calls(plain, "review:") + calls(plain, "test-review"):
            self.assertEqual(report_of(event["prompt"]), {"summary": "s", "complete": True, "changed_paths": ["core/x.gd"]})
        # The publisher gets its own copy (PublisherCopyTest), not the reviewers' digest.
        self.assertNotIn(REPORT, calls(result, "publish")[0]["prompt"])

    def test_the_implementers_summary_is_capped(self) -> None:
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="client/7-x", visual="spectate"), {"paths": ["client/hud/hud.gd"]}),
        ]
        for result in run_jobs(jobs):
            implement = calls(result, "implement")[0]
            self.assertEqual(options(implement)["schema"]["properties"]["summary"], {"type": "string", "maxLength": 1200})
            self.assertIn("summary: at most 1200 characters, a few lines on what changed and why", implement["prompt"])
            self.assertIn("the why of each choice goes in decisions", implement["prompt"])

    def test_the_publisher_gets_the_plans_summary_and_the_critique(self) -> None:
        plan = dict({"summary": "the plan in a line"}, **PLAN_MARKS)
        critique = {"reviewer": "r", "verdict": "ok", "findings": [MAJOR]}
        stub = {"paths": ["core/x.gd"], "queues": {"plan": [plan], "review:plan": [critique]}}
        result = run_one("issue-task.js", {"branch": "core/7-x", "plan_review": True}, stub)
        publish = calls(result, "publish")[0]["prompt"]
        given = json.dumps({"plan_summary": plan["summary"], "critique": critique}, separators=(",", ":"))
        self.assertIn(
            "The plan's summary and its critique (plan_review; the whole plan is the plan agent's comment on the issue, "
            f"plan_comment, and stays in the run's journal): {given}",
            publish,
        )
        self.assertIn('under "Plan review": the plan in a few lines (from its summary) with a link to its comment', publish)
        # The implementer builds from the whole plan; the publisher needs only what the PR says about it.
        implement = calls(result, "implement")[0]["prompt"]
        for marks in PLAN_MARKS.values():
            self.assertIn(marks[0], implement)
            self.assertNotIn(marks[0], publish)

    def test_the_publisher_carries_finish_tasks_steps_inline(self) -> None:
        # The publisher read finish-task/SKILL.md (7.3k characters) for steps its prompt lists itself; the docs,
        # intervention and credits steps, the one part it lacked, are inline now, and no agent is pointed at the skill.
        jobs = [
            ("issue-task.js", dict(ARGS, **args), stub)
            for args, stub in (
                ({"branch": "core/7-x"}, {"paths": ["core/x.gd"]}),
                ({"branch": "core/7-x", "base": "release/m5", **V2}, {"paths": ["core/x.gd"], "findings": [MAJOR]}),
                ({"branch": "docs/7-x", "design": True}, {"paths": ["docs/x.md"]}),
            )
        ]
        for result in run_jobs(jobs):
            for event in agents(result):
                self.assertNotIn("finish-task", event["prompt"], event["label"])
            publish = calls(result, "publish")[0]["prompt"]
            steps = publish[publish.index("Then, in this order (the definition of done; the reviews above were its review step):") :]
            for text in (
                "- Docs: durable knowledge that the change or your fixes alter goes into the doc that owns it",
                "a docs/interventions/ entry by .claude/skills/log-intervention/SKILL.md (read it only then)",
                "A third-party asset: docs/credits/<asset>.md, then `tools\\run.cmd credits`. Commit these too.",
                "the other owner's paths (.github/CODEOWNERS) also get `--reviewer <their handle>`",
                "already finds a PR for the branch, update its body with `gh pr edit <pr> --body-file <file>` instead of creating a second one",
                'or with "cannot confirm that the parent … was merged", push nothing by hand',
            ):
                self.assertIn(text, steps)
            # In the definition of done's order: docs, publish, the PR, CI, the handoff, the board.
            marks = ["- Docs:", "- `tools\\run.cmd publish", "- PR: `gh pr create", "- `gh pr checks", "- The handoff comment", "- `tools\\run.cmd board move"]
            self.assertEqual([steps.index(m) for m in marks], sorted(steps.index(m) for m in marks))


# #696: the publisher's own copies of the report and the reviews, and the three preamble lines it goes without.
PUB_REPORT = (
    "The implementer reported (its commits, changed paths and verify tail left out: `git log`, `git diff --name-only` "
    "and your `publish` give them): "
)
PUB_REVIEWS = "Fresh reviewers found (each finding's fix only on a blocker or major): "
GAME_RULE = "- A game rule that no ADR, ARCHITECTURE section or issue comment settles: do not invent it."
NIT = {"severity": "nit", "file": "docs/x.md", "problem": "p3", "fix": "f3"}


def json_after(prompt: str, marker: str) -> object:
    """The JSON a prompt carries after marker, up to the paragraph's end, parsed."""
    start = prompt.index(marker) + len(marker)
    return json.loads(prompt[start : prompt.index("\n\n", start)])


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class PublisherCopyTest(unittest.TestCase):
    def test_the_publisher_gets_the_report_without_what_git_and_publish_give(self) -> None:
        # The implementer's rationale reaches the PR whole (summary, decisions, left, needs_engineer, proposed issues,
        # provisional content, playcheck); its commits, changed paths and verify tail do not (about 1.7k characters at
        # the median, #470's table).
        shots = {"available": True, "pngs": ["D:/x/01.png"]}
        stub = {"paths": FULL_IMPL["changed_paths"], "queues": {"implement": [dict(FULL_IMPL, playcheck=shots)]}}
        result = run_one("issue-task.js", {"branch": "client/7-x", "visual": "spectate"}, stub)
        publish = calls(result, "publish")[0]["prompt"]
        drops = ("commits", "changed_paths", "verify_tail")
        want = {k: v for k, v in dict(FULL_IMPL, playcheck=shots).items() if k not in drops}
        got = json_after(publish, PUB_REPORT)
        self.assertEqual(got, want)
        self.assertEqual(list(got), list(want))  # whole, in the report's order: nothing cut to a line
        for text in ("step ok", "abc1234 feat(core)", '"verify_tail"', '"changed_paths"'):
            self.assertNotIn(text, publish)
        self.assertNotIn("The implementer reported: ", publish)
        # Where the PR's verify tail comes from now.
        self.assertIn(
            'the verification commands and the verify tail (from your `publish`; when it skipped verify on an identical '
            'tree, the "verify summary" block at the end of tools/out/logs/verify-output.log)',
            publish,
        )
        self.assertIn("the summary and the why, from the implementer's summary and decisions (not rebuilt from `git log`)", publish)

    def test_the_publisher_gets_each_findings_fix_only_on_a_blocker_or_major(self) -> None:
        # The reviewers' verdicts and the fix text of a minor or nit stay with the reviewers (1.5k to 2k characters).
        reviews = {
            "review:code": [{"reviewer": "code-reviewer", "verdict": LONG, "findings": [BLOCKER, MINOR, NIT]}],
            "review:netcode": [{"reviewer": "netcode-security-reviewer", "verdict": "ok", "findings": [MAJOR]}],
        }
        stub = {"paths": ["core/match/vote.gd"], "queues": reviews}
        result = run_one("issue-task.js", {"branch": "core/7-x", "test_review": True}, stub)
        publish = calls(result, "publish")[0]["prompt"]
        bare = lambda f: {k: v for k, v in f.items() if k != "fix"}  # noqa: E731
        self.assertEqual(
            json_after(publish, PUB_REVIEWS),
            [
                {"reviewer": "code-reviewer", "findings": [BLOCKER, bare(MINOR), bare(NIT)]},
                {"reviewer": "netcode-security-reviewer", "findings": [MAJOR]},
                {"reviewer": "r", "findings": []},  # the godot-api-checker, a .gd path
            ],
        )
        self.assertNotIn('"verdict"', publish)
        self.assertNotIn("Fresh reviewers found: ", publish)
        # The test reviewer still reads the reviews whole.
        test_review = calls(result, "test-review")[0]["prompt"]
        self.assertIn(f"Fresh reviewers found: {json.dumps(reviews['review:code'] + reviews['review:netcode'] + [{'reviewer': 'r', 'verdict': 'ok', 'findings': []}], separators=(',', ':'))}", test_review)

    def test_the_publishers_preamble_leaves_out_its_unused_lines(self) -> None:
        # The Godot-windows line (the reading rule for code left the shared rules in #1257: both agent types carry it)
        # (unless the run is visual: its publisher may rerun playcheck) and the game-rule line: every other line of
        # the shared rules stays, in order, for both publishers (the full one and the one a mutants exit 2 stops).
        stopped = {"available": True, "exit_2": True, "findings": [], "mutants": []}
        jobs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="client/7-x", visual="spectate"), {"paths": ["client/hud/hud.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), {"paths": ["core/x.gd"], "queues": {"test-review": [stopped]}}),
        ]
        dropped = [
            (GODOT_LINE, GAME_RULE),
            (GAME_RULE,),  # visual: the playcheck line stays
            (GODOT_LINE, GAME_RULE),
        ]
        for result, gone in zip(run_jobs(jobs), dropped):
            self.assertIsNone(result["error"])
            rules = calls(result, "implement")[0]["prompt"].split("\n\n")[0].splitlines()
            publish = calls(result, "publish")
            self.assertEqual(len(publish), 1)
            with self.subTest(publisher=publish[0]["prompt"].split("\n\n")[1][:40], dropped=len(gone)):
                got = publish[0]["prompt"].split("\n\n")[0].splitlines()
                self.assertEqual(got, [line for line in rules if not any(line.startswith(d) for d in gone)])
                self.assertEqual(len(rules) - len(got), len(gone), rules)
        self.assertIn("Task: report a stopped run of issue #7", calls(result, "publish")[0]["prompt"])


SHA ="0123456789abcdef0123456789abcdef01234567"
SHORT_PLAN = "The plan, in short (the whole plan is the plan agent's comment on the issue,"
COMMENT = "https://github.com/xperiaroco2/prime-game/issues/7#issuecomment-1"
MAPPED = {
    "base_sha": SHA,
    "files": [
        {"path": "core/match/vote.gd", "lines": "10-60", "facts": ["func cast(voter: int, target: int) -> void"]},
        {"path": "tests/unit/match/vote_test.gd", "lines": "1-30", "facts": ["helper _match(seed)"]},
    ],
}


def mapped_plan(**extra) -> dict:
    return dict({"summary": "p", "criteria": ["c"], "files": ["f"], "tests": ["t"], "file_map": MAPPED, "comment_url": COMMENT}, **extra)


def plan_in(prompt: str) -> dict:
    """The plan JSON a critique's or an implementer's prompt carries, parsed."""
    start = prompt.index("): ", prompt.index(SHORT_PLAN)) + 3
    return json.loads(prompt[start : prompt.index("\n\n", start)])


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class PlanPhaseTest(unittest.TestCase):
    """#469: the plan's comment on the issue, its short and capped result, and the file map the implementer trusts."""

    def run_plan(self, plan: dict | None, **args) -> dict:
        queues = {"plan": [plan]} if plan is not None else {}
        result = run_one("issue-task.js", dict({"branch": "core/7-x", "plan_review": True}, **args), {"paths": ["core/x.gd"], "queues": queues})
        self.assertIsNone(result["error"])
        return result

    def test_the_plan_schema_asks_for_a_file_map_and_caps_the_summary(self) -> None:
        schema = options(calls(self.run_plan(None), "plan:")[0])["schema"]
        props = schema["properties"]
        self.assertEqual(props["summary"], {"type": "string", "maxLength": 1500})
        self.assertIn("file_map", schema["required"])
        self.assertEqual(props["file_map"]["required"], ["base_sha", "files"])
        self.assertEqual(props["file_map"]["properties"]["files"]["items"]["required"], ["path", "facts"])
        self.assertEqual(props["comment_url"], {"type": "string"})
        # Every field the plan had before #469 is still there.
        for key in ("criteria", "files", "interfaces", "tests", "docs", "risks", "questions", "steps"):
            self.assertEqual(props[key], {"type": "array", "items": {"type": "string"}}, key)

    def test_the_planner_posts_the_whole_plan_and_returns_its_short_form(self) -> None:
        prompt = calls(self.run_plan(None), "plan:")[0]["prompt"]
        for text in (
            "The whole plan goes in ONE comment on the issue; the structured result is its short form",
            "to a7/plan.md in your scratchpad, its first line `Plan of #7 (issue-task plan_review, branch core/7-x)`",
            "`gh issue comment 7 --body-file <that file>`",
            "first list your own comments on the issue in the Bash tool",
            """`gh issue view 7 --json comments --jq '.comments[] | select(.author.login == "<your login>") | .url + " " + """
            """(.body | split("\\n") | .[0])'`""",
            "If the last of them starts with that first line, replace it with "
            "`gh issue comment 7 --edit-last --body-file <that file>`",
            "if only an earlier one does, post a new comment whose second line is `Supersedes <that comment's URL>`",
            "Never `gh api -X PATCH` (it asks, and nobody answers).",
            "Return its URL in comment_url.",
            "at most about 8000 characters of JSON in all: summary at most 1500 characters",
            "base_sha: `git rev-parse HEAD` in the worktree",
            "Only what you read in that file; a fact you inferred is not in the map.",
            "Plan only: create, edit or commit nothing",
        ):
            self.assertIn(text, prompt)

    def test_the_implementer_trusts_the_map_for_files_unchanged_since_its_sha(self) -> None:
        result = self.run_plan(mapped_plan())
        implement = calls(result, "implement")[0]["prompt"]
        self.assertIn(
            f"the plan agent read these files at {SHA}. Trust it while a file is unchanged since that sha: first run in the Bash tool "
            f"`cd /d/prime-game/.claude/worktrees/7 && git diff --name-only {SHA} -- 'core/match/vote.gd' "
            "'tests/unit/match/vote_test.gd'` once (again after a rebase)",
            implement,
        )
        self.assertIn("A path it lists changed since the plan: read it as usual.", implement)
        self.assertIn("A file whose facts the critique disputes: read it as usual too.", implement)
        self.assertIn("If the command fails (the sha unknown), the map does not hold", implement)
        self.assertEqual(plan_in(implement)["file_map"], MAPPED)
        critique = calls(result, "review:plan")[0]["prompt"]
        self.assertIn("a file_map fact that the file at base_sha does not bear out (the implementer trusts it)", critique)
        self.assertEqual(plan_in(critique), mapped_plan())
        # A quote in a path stays one word of the shell command.
        quoted = mapped_plan(file_map={"base_sha": SHA, "files": [{"path": "levels/it's.tscn", "facts": ["f"]}]})
        implement = calls(self.run_plan(quoted), "implement")[0]["prompt"]
        self.assertIn(f"git diff --name-only {SHA} -- 'levels/it'\\''s.tscn'` once", implement)
        # No map, an empty one or a sha that is not one: the implementer reads as usual.
        for plan in ({"summary": "p", "criteria": [], "files": [], "tests": []}, mapped_plan(file_map={"base_sha": SHA, "files": []}),
                     mapped_plan(file_map=dict(MAPPED, base_sha="HEAD; rm -rf x"))):
            implement = calls(self.run_plan(plan), "implement")[0]["prompt"]
            self.assertIn("The plan has no usable file map (file_map): read the files as usual.", implement)
            self.assertNotIn("Trust it while a file is unchanged", implement)

    def test_a_plan_over_the_cap_is_cut_before_the_critique_and_the_implementer(self) -> None:
        long = "x" * 900
        big = mapped_plan(summary="s" * 1500, criteria=[long] * 10, files=[long] * 10, steps=[f"{long}\nsecond line"] * 10)
        big["file_map"] = {"base_sha": SHA, "files": [{"path": f"core/f{i}.gd", "lines": "1-9", "facts": [long] * 3} for i in range(5)]}
        self.assertGreater(size(big), 30000)
        result = self.run_plan(big)
        logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
        self.assertTrue(any(m.startswith(f"#7: the plan's result was {size(big)} characters of JSON; cut to ") for m in logs), logs)
        for label in ("review:plan", "implement"):
            short = plan_in(calls(result, label)[0]["prompt"])
            with self.subTest(agent=label):
                self.assertLessEqual(size(short), 8000)
                self.assertEqual(short["clipped"], f"cut from {size(big)} characters of JSON; the whole plan: {COMMENT}")
                self.assertEqual(short["comment_url"], COMMENT)
                self.assertEqual(short["file_map"]["base_sha"], SHA)
                self.assertTrue(all(len(x) <= 240 for k in ("criteria", "files", "steps") for x in short[k]))
                self.assertTrue(all(x.endswith("…") for x in short["criteria"]))
                # The plan's lists are cut before the file map loses an entry.
                self.assertLess(sum(len(short[k]) for k in ("criteria", "files", "steps")), 30)
                self.assertEqual([f["path"] for f in short["file_map"]["files"]], [f"core/f{i}.gd" for i in range(5)])
        self.assertIs(result["returned"]["plan"]["clipped"], True)
        # A map too big on its own loses its last entries once no plan list is left.
        huge = mapped_plan(criteria=[], files=[], tests=[])
        huge["file_map"] = {"base_sha": SHA, "files": [{"path": f"core/f{i}.gd", "facts": [long] * 3} for i in range(40)]}
        short = plan_in(calls(self.run_plan(huge), "implement")[0]["prompt"])
        self.assertLessEqual(size(short), 8000)
        kept = [f["path"] for f in short["file_map"]["files"]]
        self.assertTrue(kept, short)
        self.assertEqual(kept, [f"core/f{i}.gd" for i in range(len(kept))])
        self.assertLess(len(kept), 40)
        # A plan under the cap reaches them as the agent sent it, with no clipped field.
        small = self.run_plan(mapped_plan())
        self.assertNotIn("clipped", plan_in(calls(small, "implement")[0]["prompt"]))
        self.assertFalse([e for e in small["events"] if e["kind"] == "log" and "cut to" in e["message"]])

    def test_the_result_and_the_publisher_carry_the_plans_comment_and_model(self) -> None:
        model = AVAILABLE[1]
        result = self.run_plan(mapped_plan(), models={"plan": model})
        self.assertEqual(result["returned"]["plan"], {"summary": "p", "critique": {}, "comment": COMMENT, "model": model})
        got = {e["label"]: options(e).get("model") for e in agents(result)}
        self.assertEqual({k: v for k, v in got.items() if v}, {"plan:#7": model}, got)
        publish = calls(result, "publish")[0]["prompt"]
        self.assertIn('{"plan_summary":"p","plan_comment":"' + COMMENT + '","critique":', publish)
        # models.implement still reaches the planner when models.plan is unset (the fallback), and the result says so;
        # not with "sonnet", which ended on 2026-10-13 for the implementer (#1147).
        model = next(m for m in AVAILABLE if m != "sonnet")
        result = self.run_plan(mapped_plan(), models={"implement": model})
        self.assertEqual(options(calls(result, "plan:")[0])["model"], model)
        self.assertEqual(result["returned"]["plan"]["model"], model)


class EndedOptionsTest(unittest.TestCase):
    """#1147 (the engineer's answer 3A on #302, comment 6291039723): issue-task.js refuses the options the engineer
    ended on 2026-10-13 (#302 comment 6145513919, 3A to 5A), which managers still passed after the stop: an error
    naming the option, the date and that comment, before any agent runs. A launch with today's habits still passes."""

    # (the option the error names, the args over a core task's).
    REFUSED = (
        ("ab_review", {"ab_review": True}),
        ("ab_review", {"ab_review": "yes"}),
        ("ab_review", {"ab_review": 1}),
        ("ab_review", {"ab_review": True, "models": {"code": "sonnet", "publish_clean": "sonnet"}}),
        ("ab_review", {"ab_review": True, "design": True}),
        ("models.code", {"models": {"code": "sonnet"}}),
        ("models.code", {"models": {"code": "opus", "publish_clean": "sonnet"}}),
        ("models.code", {"models": {"code": ""}}),
        ('models.implement "sonnet"', {"models": {"implement": "sonnet"}}),
        ('models.implement "sonnet"', {"models": {"implement": "Sonnet"}}),
        ('models.implement "sonnet"', {"models": {"implement": "claude-sonnet-5-5"}}),
        ('models.implement "sonnet"', {"plan_review": True, "models": {"implement": "sonnet", "plan": "sonnet"}}),
        ("models.publish_findings", {"models": {"publish_findings": "sonnet"}}),
        ("models.publish_findings", {"models": {"publish_clean": "sonnet", "publish_findings": "opus"}}),
        ("efforts.publish_findings", {"efforts": {"publish_findings": "medium"}}),
        ("efforts.publish_findings", {"efforts": {"implement": "medium", "publish_findings": "high"}}),
    )

    def test_each_ended_option_throws_naming_it_before_any_agent(self) -> None:
        stub = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        jobs = [("issue-task.js", dict(ARGS, branch="core/7-x", **args), stub) for _, args in self.REFUSED]
        for (option, args), result in zip(self.REFUSED, run_jobs(jobs)):
            with self.subTest(args=args):
                self.assertIsNotNone(result["error"])
                self.assertIn(f"issue-task: args.{option} ended on 2026-10-13 (#302 comment 6145513919)", result["error"])
                self.assertIn("Launch without it", result["error"])
                self.assertEqual(agents(result), [])

    def test_a_launch_with_todays_habits_still_runs(self) -> None:
        # launch-args.md: publish_clean "sonnet" on every non-design launch, plan "sonnet" with plan_review, another
        # model of models.implement (a stage design or a task red twice), efforts.code and efforts.implement; and
        # ab_review false or null, which change nothing.
        other = next(m for m in AVAILABLE if m != "sonnet")
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        plain = dict(ARGS, branch="core/7-x", models={"publish_clean": "sonnet"})
        normal = (
            plain,
            dict(ARGS, branch="core/7-x", plan_review=True, test_review=True, models={"plan": "sonnet", "publish_clean": "sonnet"}),
            dict(ARGS, branch="core/7-x", models={"implement": other, "publish_clean": "sonnet"}),
            dict(ARGS, branch="core/7-x", efforts={"code": "medium", "implement": "medium"}, models={"publish_clean": "sonnet"}),
            dict(ARGS, branch="docs/7-x", design=True, skeptic=2),
            dict(plain, ab_review=False),
            dict(plain, ab_review=None),
        )
        jobs = [("issue-task.js", args, {"paths": ["docs/x.md"]} if args.get("design") else core) for args in normal]
        results = run_jobs(jobs)
        for args, result in zip(normal, results):
            with self.subTest(args={k: v for k, v in args.items() if k not in ARGS}):
                self.assertIsNone(result["error"])
                self.assertTrue(result["returned"]["published"])
                self.assertFalse([e for e in result["events"] if e["kind"] == "log" and "ended" in e["message"]])
                labels = [e["label"] for e in agents(result)]
                self.assertFalse([x for x in labels if "control" in x or "judge" in x], labels)
                self.assertNotIn("ab_review", result["returned"])
                self.assertNotIn("publish_findings", result["returned"])
        self.assertEqual(options(calls(results[2], "implement:")[0])["model"], other)
        # A run with a major left open: its publisher takes publish, so publish_clean's model does not reach it.
        self.assertNotIn("model", options(calls(results[0], "publish:")[0]))
        self.assertFalse(results[0]["returned"]["publish_clean"]["applied"])
        # ab_review false or null is the launch without it.
        for k in (5, 6):
            self.assertEqual(render(results[k]), render(results[0]))


class NodeOnCiTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("GITHUB_ACTIONS") == "true", "only on GitHub Actions")
    def test_github_actions_runs_the_workflow_tests(self) -> None:
        # The ubuntu-24.04 image (20260927.320) lists Node.js 22. Without Node on PATH there, every test above would
        # skip silently and the snapshots would guard nothing on CI.
        self.assertIsNotNone(NODE, "Node is not on PATH on GitHub Actions: the workflow tests would skip")


@unittest.skipUnless(shutil.which("git"), "needs git on PATH")
class RebaseRuleTest(unittest.TestCase):
    """#456's rule run through git with every editor failing: its fixup and its reword need none, and the two
    commands it rules out for a reword do (git refuses -F with --fixup=reword:, so that one opens the editor)."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="rebase-rule-"))
        self.addCleanup(force_rmtree, str(self.tmp))
        self.repo = self.tmp / "repo"  # the message files stay outside it
        self.repo.mkdir()
        # An editor that runs fails the command, and the environment and the user's config cannot change that.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_EDITOR="false", GIT_SEQUENCE_EDITOR="false", GIT_TERMINAL_PROMPT="0")
        self.git("init", "-q", "-b", "main")
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            self.git("config", key, value)
        for subject, line in (("chore: base", "a"), ("feat: tow", "b"), ("feat: three", "c")):
            with open(self.repo / "f.txt", "a", encoding="utf-8", newline="") as f:
                f.write(line + "\n")
            self.git("add", "f.txt")
            self.git("commit", "-q", "-m", subject)
        self.base = self.git("rev-parse", "HEAD~2")

    def run_git(self, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args], cwd=self.repo, capture_output=True, text=True, encoding="utf-8", timeout=60,
            env={**self.env, **env},
        )  # fmt: skip

    def git(self, *args: str, **env: str) -> str:
        res = self.run_git(*args, **env)
        if res.returncode != 0:
            raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
        return res.stdout.strip()

    def test_the_fixup_and_the_reword_need_no_editor(self) -> None:
        typo = self.git("rev-parse", "HEAD~1")
        # A fix folded into the last commit, and a reword of the one before it, as the rule says.
        with open(self.repo / "f.txt", "a", encoding="utf-8", newline="") as f:
            f.write("d\n")
        self.git("add", "f.txt")
        self.git("commit", "-q", "--fixup=HEAD")
        message = self.tmp / "msg.txt"
        message.write_bytes(b"amend! feat: tow\n\nfeat: two\n\nThe new body.\n")
        self.git(*REWORD_COMMIT[1:], str(message))
        self.git("rebase", "-q", "-i", "--autosquash", self.base, GIT_SEQUENCE_EDITOR=":")
        self.assertEqual(self.git("log", "--format=%s", f"{self.base}..").splitlines(), ["feat: three", "feat: two"])
        self.assertEqual(self.git("log", "-1", "--format=%B", "HEAD~1"), "feat: two\n\nThe new body.")
        self.assertEqual(self.git("show", "HEAD:f.txt").splitlines(), ["a", "b", "c", "d"])
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertNotEqual(self.git("rev-parse", "HEAD~1"), typo)

    def test_amending_the_last_commit_needs_an_editor_only_when_bare(self) -> None:
        # The rule's clause for the last commit: --no-edit and -F need no editor, a bare --amend opens it.
        message = self.tmp / "msg.txt"
        message.write_bytes(b"feat: three, reworded\n")
        self.assertNotEqual(self.run_git("commit", "--amend").returncode, 0)
        self.assertEqual(self.git("log", "-1", "--format=%s"), "feat: three")
        self.git("commit", "-q", "--amend", "--allow-empty", "--no-edit")
        self.git("commit", "-q", "--amend", "--allow-empty", "-F", str(message))
        self.assertEqual(self.git("log", "-1", "--format=%s"), "feat: three, reworded")

    def test_the_reword_commands_the_rule_rules_out_open_the_editor(self) -> None:
        typo = self.git("rev-parse", "HEAD~1")
        message = self.tmp / "msg.txt"
        message.write_bytes(b"feat: two\n")
        for args in ((f"--fixup=reword:{typo}", "-F", str(message)), (f"--fixup=amend:{typo}", "-F", str(message))):
            with self.subTest(args=args[0].split(":")[0]):
                self.assertNotEqual(self.run_git("commit", *args).returncode, 0)
        for prefix in ("reword", "amend"):
            with self.subTest(prefix=prefix):
                res = self.run_git("commit", f"--fixup={prefix}:{typo}")
                self.assertNotEqual(res.returncode, 0)
                self.assertIn("editor", res.stderr)
        # An interactive rebase without GIT_SEQUENCE_EDITOR=: runs the todo editor (here one that fails).
        res = self.run_git("rebase", "-q", "-i", self.base)
        self.assertNotEqual(res.returncode, 0)
        self.run_git("rebase", "--abort")
        self.assertEqual(self.git("log", "--format=%s", f"{self.base}..").splitlines(), ["feat: three", "feat: tow"])

    def test_a_reword_fixup_under_an_editor_that_exits_at_once_keeps_the_old_message(self) -> None:
        # The rule's reason since #457: Claude Code's tools set GIT_EDITOR=true, so `--fixup=reword:` hangs nothing
        # there, but the editor changes nothing either, and the autosquash keeps the old subject without a word.
        typo = self.git("rev-parse", "HEAD~1")
        self.git("commit", "-q", f"--fixup=reword:{typo}", GIT_EDITOR="true")
        self.git("rebase", "-q", "-i", "--autosquash", self.base, GIT_SEQUENCE_EDITOR=":")
        self.assertEqual(self.git("log", "--format=%s", f"{self.base}..").splitlines(), ["feat: three", "feat: tow"])
        self.assertEqual(self.git("status", "--porcelain"), "")


# checkpoint (#559): an implementer past 150k context hands over to a fresh one, at most twice.
RULE_HEAD = "Checkpoint (checkpoint, #559): keep your context under 150,000 tokens."
NOTE = "C:/scratchpad/a7/handoff-1.md"
# #983: the last implementer's stop rule, the follow-up it files, and the publisher's line about it.
STOP_HEAD = "Checkpoint stop (checkpoint, #983):"
FOLLOWUP = "https://github.com/xperiaroco2/prime-game/issues/99"
FOLLOWUP_LINE = "Follow-up (checkpoint, #983):"


def handing_over(note: str = NOTE, **extra) -> dict:
    return implemented(["tools/runner/x.py"], **dict({"complete": False, "verify_green": False, "handoff": note}, **extra))


def without_rule(prompt: str) -> str:
    """The prompt with its checkpoint paragraph (one paragraph of the '\\n\\n'-joined prompt) cut out."""
    return "\n\n".join(p for p in prompt.split("\n\n") if not p.startswith(RULE_HEAD))


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class CheckpointTest(unittest.TestCase):
    PATHS = {"paths": ["tools/runner/x.py"]}

    def test_checkpoint_false_ignores_a_handoff(self) -> None:
        # #920: checkpoint: false turns the default off: a handoff in the result is not followed, the agents are those
        # of a launch with checkpoint: false and no handoff, and the prompts carry no rule.
        off = {"checkpoint": False}
        stub = dict(self.PATHS, queues={"implement": [implemented(["tools/runner/x.py"], handoff=NOTE)]})
        base, other = run_jobs([("issue-task.js", dict(ARGS, **off), self.PATHS), ("issue-task.js", dict(ARGS, **off), stub)])
        want = [(e["label"], e["opts"], e["prompt"]) for e in agents(base)]
        got = [(e["label"], e["opts"], e["prompt"]) for e in agents(other)]
        # The publisher embeds the implementer's whole result, so the stub's own handoff key shows there only.
        self.assertEqual([g[0] for g in got], [w[0] for w in want])
        self.assertEqual(got[:-1], want[:-1])
        for result in (base, other):
            self.assertIsNone(result["error"])
            self.assertNotIn("handoffs", result["returned"])
            self.assertNotIn("checkpoint", result["returned"])  # #597: no key, so a launch or resume without it shows
            self.assertFalse([e for e in result["events"] if e["kind"] == "log" and "handoff" in e["message"]])
        self.assertNotIn(RULE_HEAD, json.dumps(want))
        self.assertFalse([e for e in agents(base) if "handoff" in options(e)["schema"]["properties"]])

    def test_checkpoint_is_on_by_default(self) -> None:
        # #920 (the engineer's answer 6A on #302): a launch without the arg, or with null, is a launch with true.
        on, *others = run_jobs([("issue-task.js", dict(ARGS, **extra), self.PATHS) for extra in ({"checkpoint": True}, {}, {"checkpoint": None})])
        want = [(e["label"], e["opts"], e["prompt"]) for e in agents(on)]
        self.assertIn(RULE_HEAD, calls(on, "implement")[0]["prompt"])
        for result in others:
            self.assertIsNone(result["error"])
            self.assertEqual([(e["label"], e["opts"], e["prompt"]) for e in agents(result)], want)
            self.assertEqual((result["returned"]["checkpoint"], result["returned"]["handoffs"]), (True, 0))

    def test_checkpoint_adds_only_the_rule_and_the_schema_key(self) -> None:
        for extra in ({}, {"visual": True}):
            off, on = run_jobs([("issue-task.js", dict(ARGS, checkpoint=False, **extra), self.PATHS), ("issue-task.js", dict(ARGS, **extra), self.PATHS)])
            with self.subTest(**{k: str(v) for k, v in extra.items()}):
                self.assertEqual([e["label"] for e in agents(on)], [e["label"] for e in agents(off)])
                # #597: the compact result shows checkpoint: true, and with it the handoffs, 0 too.
                self.assertEqual((on["returned"]["checkpoint"], on["returned"]["handoffs"]), (True, 0))
                self.assertFalse({"checkpoint", "handoffs"} & set(off["returned"]))
                for a, b in zip(agents(off), agents(on)):
                    if not a["label"].startswith("implement"):
                        self.assertEqual((a["opts"], a["prompt"]), (b["opts"], b["prompt"]), a["label"])
                        continue
                    rule = [p for p in b["prompt"].split("\n\n") if p.startswith(RULE_HEAD)]
                    self.assertEqual(len(rule), 1)
                    self.assertEqual(without_rule(b["prompt"]), a["prompt"])
                    self.assertTrue(b["prompt"].index(RULE_HEAD) < b["prompt"].index("Do NOT publish"))
                    # #597: measured by a runner command, never by arithmetic on the harness's reminder; the backstop
                    # holds whatever ctx printed, and past 200k "only the final verify left" no longer lets it finish.
                    for words in ("`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh ctx --at 150000 --hard 200000`", "every ~15 tool calls and after each verify", "When it prints HANDOFF NOW",
                                  "or after 60 tool calls in any case (whatever ctx printed, also when it found no transcript)",
                                  "If only the final verify and the return are left, finish instead, unless ctx printed past 200,000.",
                                  "a7/handoff-1.md", "done (", "left (", "decisions (", "gotchas (", "verify state (",
                                  "leave no background job", "handoff: the note's absolute path"):  # fmt: skip
                        self.assertIn(words, rule[0])
                    self.assertNotIn("total_tokens", rule[0])
                    self.assertEqual("visual" in extra, "playcheck {available: false" in rule[0])
                    o_off, o_on = options(a), options(b)
                    self.assertEqual(o_on["schema"]["properties"].pop("handoff"), {"type": "string"})
                    self.assertNotIn("handoff", o_on["schema"]["required"])
                    self.assertEqual(json.dumps(o_on), json.dumps(o_off), "the same options in the same order otherwise")

    def test_a_handoff_launches_a_fresh_implementer_with_the_note(self) -> None:
        first = handing_over(decisions=["d1"], needs_engineer=["n1"], commits=["c1"], left=["the rest"], summary="first part")
        last = implemented(["tools/runner/x.py", "docs/x.md"], decisions=["d2", "d1"], commits=["c2"], summary="the whole branch")
        result = run_one("issue-task.js", {}, dict(self.PATHS, queues={"implement": [first, last]}))
        self.assertIsNone(result["error"])
        one, two = calls(result, "implement")
        self.assertEqual([one["label"], two["label"]], ["implement:#7", "implement:#7#2"])
        self.assertIn(f"Continuation 1 of 2 (checkpoint, #559): an earlier implementer of this task reached its context limit and handed over. Its note is {NOTE}:", two["prompt"])
        self.assertIn("Your result covers the whole branch since origin/main", two["prompt"])
        self.assertIn(STASH_RULE, two["prompt"])
        self.assertIn(RULE_HEAD, two["prompt"], "the second may hand over too")
        self.assertIn("a7/handoff-2.md", two["prompt"])
        self.assertNotIn("You are the last one", two["prompt"])
        o1, o2 = options(one), options(two)
        self.assertEqual(o2.pop("label"), "implement:#7#2")
        o1.pop("label")
        self.assertEqual(o1, o2, "the same agent type, effort, model and schema")
        self.assertEqual(o2["agentType"], "task-implementer")
        logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
        self.assertTrue(any(f"handoff 1 of 2: the implementer stopped at its context limit (verify red); a fresh one continues from {NOTE}" in m for m in logs), logs)
        # The handoff's red verify did not stop the run: the reviewers and the publisher read the joined result.
        report = calls(result, "review:code")[0]["prompt"]
        self.assertIn('"summary":"the whole branch"', report)
        self.assertIn('"decisions":["d1","d2"]', report)
        self.assertIn('"needs_engineer":["n1"]', report)
        pub = calls(result, "publish")[0]["prompt"]
        self.assertIn(f'"handoffs":["{NOTE}"]', pub)
        self.assertIn('"decisions":["d1","d2"]', pub)
        # #696: the joined commits stay in the journal; the publisher reads them from `git log`.
        self.assertNotIn('"commits":', pub)
        self.assertNotIn('"handoff":', pub)
        out = result["returned"]
        self.assertEqual((out["handoffs"], out["verify_green"], out["summary"]), (1, True, "the whole branch"))
        self.assertIs(out["checkpoint"], True)
        self.assertNotIn("stopped", out)

    def test_at_most_two_handoffs(self) -> None:
        notes = [f"C:/scratchpad/a7/handoff-{k}.md" for k in (1, 2, 3)]
        result = run_one("issue-task.js", {"checkpoint": True}, dict(self.PATHS, queues={"implement": [handing_over(n, verify_green=True) for n in notes]}))
        self.assertIsNone(result["error"])
        impls = calls(result, "implement")
        self.assertEqual([e["label"] for e in impls], ["implement:#7", "implement:#7#2", "implement:#7#3"])
        third = impls[2]
        self.assertIn("Continuation 2 of 2 (checkpoint, #559)", third["prompt"])
        self.assertIn(f"Its note is {notes[1]}:", third["prompt"])
        self.assertIn("You are the last one: do not hand over", third["prompt"])
        self.assertNotIn(RULE_HEAD, third["prompt"])
        self.assertNotIn("handoff", options(third)["schema"]["properties"])
        # #983: the last one stops and files the rest instead; the first two may not (they hand over).
        self.assertIn(STOP_HEAD, third["prompt"])
        self.assertFalse([e for e in impls[:2] if STOP_HEAD in e["prompt"] or "followup" in options(e)["schema"]["properties"]])
        logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
        self.assertTrue(any("handoff 2 of 2" in m for m in logs), logs)
        self.assertTrue(any("handoff ignored: the last implementer may not hand over" in m for m in logs), logs)
        self.assertTrue(calls(result, "review:code"))
        self.assertEqual(result["returned"]["handoffs"], 2)
        self.assertIn(f'"handoffs":["{notes[0]}","{notes[1]}"]', calls(result, "publish")[0]["prompt"])
        # No follow-up returned: no key, no publisher line.
        self.assertNotIn("followup", result["returned"])
        self.assertNotIn(FOLLOWUP_LINE, calls(result, "publish")[0]["prompt"])

    def test_the_last_implementer_stops_at_green_and_files_the_rest(self) -> None:
        # #983: past the threshold the last implementer stops at its last green commit, files the rest as a follow-up
        # issue and returns its URL; the reviewers and the publisher run on what is green.
        notes = [f"C:/scratchpad/a7/handoff-{k}.md" for k in (1, 2)]
        last = implemented(["tools/runner/x.py"], complete=False, left=["the rest, in #99"], summary="the green part", followup=f" {FOLLOWUP} ")
        result = run_one("issue-task.js", {}, dict(self.PATHS, queues={"implement": [*(handing_over(n, verify_green=True) for n in notes), last]}))
        self.assertIsNone(result["error"])
        third = calls(result, "implement")[2]
        (rule,) = [p for p in third["prompt"].split("\n\n") if p.startswith(STOP_HEAD)]
        self.assertTrue(third["prompt"].index(STOP_HEAD) < third["prompt"].index("Do NOT publish"))
        for words in ("`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh ctx --at 150000 --hard 200000` every ~15 tool calls and after each verify",
                      "When it prints `HANDOFF NOW: past 200,000` (a plain HANDOFF NOW does not stop you), or when it found no transcript and you have made 150 tool calls, stop at your last green commit",
                      "a whole `verify --changed` passed on", "leave no background job", "a WIP commit first, so all of it has a sha",
                      "(1) keep the work after that commit", "`git update-ref refs/dropped/7-<HEAD's short sha> HEAD`",
                      "(2) file the rest as a follow-up issue: `gh issue create --title", "each dropped commit's sha",
                      "`git diff --stat <that commit> <the ref>` (the whole diff too", "(3) only then `git reset --hard <that commit>`", "--label <area> --body-file <file under a7/>`", "area:* label",
                      "`--milestone \"<its title>\"` when #7 has one", "`gh issue view 7 --json labels,milestone`", '"Part of #7"',
                      "done (", "decisions (", "gotchas (", "the verify state (", "Never close, reopen or edit #7.",
                      "complete false, verify_green true", "followup: the follow-up issue's URL",
                      "If only the final verify and the return are left, finish instead.", "No commit since origin/main was ever green: file nothing"):  # fmt: skip
            self.assertIn(words, rule)
        self.assertNotIn("playcheck", rule)
        # The hard threshold, not the handoff's 150k mark or its 60-call backstop (#983's review).
        self.assertNotIn("after 60 tool calls", rule)
        self.assertNotIn("unless ctx printed past", rule)
        # The dropped work is kept in a ref and filed before the reset (#983's review: the branch's reflog dies with it).
        self.assertTrue(rule.index("git update-ref") < rule.index("gh issue create") < rule.index("git reset --hard"))
        schema = options(third)["schema"]
        self.assertEqual(schema["properties"]["followup"], {"type": "string"})
        self.assertNotIn("followup", schema["required"])
        logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
        self.assertTrue(any(f"the last implementer stopped at its context limit and filed the rest as {FOLLOWUP}" in m for m in logs), logs)
        self.assertTrue(calls(result, "review:code"))
        pub = calls(result, "publish")[0]["prompt"]
        self.assertIn(f"{FOLLOWUP_LINE} the last implementer stopped at its context limit, at its last green commit, and filed the rest as {FOLLOWUP}. The PR says `Part of #7`", pub)
        out = result["returned"]
        self.assertEqual((out["followup"], out["handoffs"], out["complete"], out["verify_green"]), (FOLLOWUP, 2, False, True))
        self.assertNotIn("stopped", out)

    def test_a_followup_only_from_the_last_implementer(self) -> None:
        # Only the third implementer's schema has the key: an earlier one's (or any with checkpoint: false) is not read.
        # A red last one still stops the run, and the result names the issue it filed.
        stray = {"queues": {"implement": [implemented(["tools/runner/x.py"], followup=FOLLOWUP)]}}
        red_last = [handing_over(verify_green=True), handing_over(verify_green=True), implemented(["tools/runner/x.py"], verify_green=False, verify_tail="FAILED", followup=FOLLOWUP)]
        first, off, red = run_jobs([
            ("issue-task.js", dict(ARGS), dict(self.PATHS, **stray)),
            ("issue-task.js", dict(ARGS, checkpoint=False), dict(self.PATHS, **stray)),
            ("issue-task.js", dict(ARGS), dict(self.PATHS, queues={"implement": red_last})),
        ])  # fmt: skip
        for result in (first, off):
            self.assertIsNone(result["error"])
            self.assertNotIn("followup", result["returned"])
            self.assertNotIn(FOLLOWUP_LINE, calls(result, "publish")[0]["prompt"])
            self.assertFalse([e for e in agents(result) if STOP_HEAD in e["prompt"]])
        self.assertIn("verify red after the implementer", red["returned"]["stopped"])
        self.assertTrue(red["returned"]["stopped"].endswith(f"with the failure in notes, and that the rest of #7 is {FOLLOWUP}'s (the last implementer filed it): build only up to it"))
        self.assertEqual(red["returned"]["followup"], FOLLOWUP)
        self.assertFalse(calls(red, "publish"))

    def test_the_stop_rule_with_visual(self) -> None:
        notes = [f"C:/scratchpad/a7/handoff-{k}.md" for k in (1, 2)]
        result = run_one("issue-task.js", {"visual": True}, dict(self.PATHS, queues={"implement": [handing_over(n, verify_green=True) for n in notes]}))
        third = calls(result, "implement")[2]
        self.assertIn('followup: the follow-up issue\'s URL, and playcheck {available: false, pngs: [], notes: "stopped at the context limit"}', third["prompt"])

    def test_a_dead_or_red_continuation(self) -> None:
        dead, red = run_jobs([
            ("issue-task.js", dict(ARGS, checkpoint=True), dict(self.PATHS, queues={"implement": [handing_over(), None]})),
            ("issue-task.js", dict(ARGS, checkpoint=True), dict(self.PATHS, queues={"implement": [handing_over(verify_green=True), implemented(["tools/runner/x.py"], verify_green=False, verify_tail="FAILED")]})),
        ])  # fmt: skip
        self.assertIn("the implementer returned nothing", dead["error"])
        self.assertIn("resume this run with the same args", dead["error"])
        self.assertIn("verify red after the implementer", red["returned"]["stopped"])
        self.assertEqual((red["returned"]["handoffs"], red["returned"]["verify_tail"]), (1, "FAILED"))
        self.assertFalse(calls(red, "review"))
        self.assertFalse(calls(red, "publish"))


# #606: issue-task's review tier by the change's risk. Each light path alone is light; each full path, alone or with
# light ones, makes the run full.
# A path no rule lists is light (the manager's notes for #606: "otherwise light"; the issue's table said full for
# "anything else", the ADR amendment says which and why): project.godot and CI's workflow pin that default.
# client/ui/ is light, the rest of client/ full (the engineer's answer 2b on #302, comment 6085059719): a folder or a
# file whose name only starts with "ui" is not client/ui/.
LIGHT_PATHS = ["docs/AGENT_WORKFLOW.md", "content/roles/x.tres", "levels/rooms/x.tscn", "tools/runner/start.py",
               "tests/unit/match/vote_test.gd", "addons/x/plugin.cfg", ".claude/workflows/issue-task.js",
               "project.godot", ".github/workflows/ci.yml", "tests/integration/net/x_test.gd",
               "client/ui/hud_text.gd", "client/ui/theme/game_theme.tres", "tests/unit/client/ui/screens_test.gd"]  # fmt: skip
FULL_PATHS = ["core/match/vote.gd", "server/host_session.gd", "net/protocol/codec.gd", "client/hud/hud.gd",
              "voice/mixer.gd", "tests/harness/bots/leak_check.gd", "client/player/first_person_camera.gd",
              "client/physics_layers.gd", "client/ui_kit/x.gd", "client/ui.gd"]  # fmt: skip
# Every option the light tier drops, passed at once, with a major finding for the skeptic to check.
ALL_OPTIONS = {"plan_review": True, "test_review": True, "second_review": True, "skeptic": True}
TIER_LINE = "Review tier (#606): "


def tier_of(result: dict) -> str:
    """The tier the publisher's prompt names (the line metrics.REVIEW_TIER reads), checked against the result's."""
    (pub,) = calls(result, "publish")
    line = next(x for x in pub["prompt"].split("\n\n") if x.startswith(TIER_LINE))
    tier = line[len(TIER_LINE):].split(" ")[0]
    assert tier == result["returned"]["tier"], (line, result["returned"]["tier"])
    return tier


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class ReviewTierTest(unittest.TestCase):
    """issue-task.js (#606): the full chain only where a mistake becomes a cheat, a desync or a leak."""

    def test_the_diff_chooses_the_tier_and_the_worst_path_wins(self) -> None:
        cases = [({}, [p], "light") for p in LIGHT_PATHS]
        cases += [({}, [p], "full") for p in FULL_PATHS]
        cases += [({}, LIGHT_PATHS + [p], "full") for p in FULL_PATHS]  # one full path among light ones: full
        cases += [({}, LIGHT_PATHS, "light"), ({}, [], "full")]  # no changed paths returned: unknown, so full
        cases += [({"branch": "docs/7-x", "design": True}, ["docs/x.md"], "full")]
        cases += [({"tier": "full"}, LIGHT_PATHS, "full"), ({"tier": None}, ["docs/x.md"], "light")]
        results = run_jobs([("issue-task.js", dict(ARGS, **args), {"paths": paths}) for args, paths, _ in cases])
        for (args, paths, want), result in zip(cases, results):
            with self.subTest(args=args, paths=paths):
                self.assertIsNone(result["error"])
                self.assertEqual(tier_of(result), want)
                self.assertTrue(any(f"review tier {want} (" in e["message"] for e in result["events"] if e["kind"] == "log"))
        forced = results[-2]
        self.assertIn("Review tier (#606): full (forced by the launch (tier: full))", calls(forced, "publish")[0]["prompt"])

    def test_the_light_tier_drops_the_optional_agents_even_when_passed(self) -> None:
        light, godot, full = run_jobs([
            ("issue-task.js", dict(ARGS, **ALL_OPTIONS), {"paths": ["docs/x.md", "tools/runner/x.py"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, **ALL_OPTIONS), {"paths": ["content/roles/x.tres"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **ALL_OPTIONS), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ])  # fmt: skip
        for result in (light, godot, full):
            self.assertIsNone(result["error"])
        self.assertEqual([e["label"] for e in agents(light)], ["implement:#7", "review:code:#7", "publish:#7"])
        self.assertEqual([e["label"] for e in agents(godot)], ["implement:#7", "review:code:#7", "review:godot-api:#7", "publish:#7"])
        for result in (light, godot):
            out = result["returned"]
            self.assertEqual((out["tier"], out["tier_skipped"]), ("light", ["plan_review", "test_review", "second_review", "skeptic"]))
            self.assertNotIn("skeptic", out)
            # The publisher fixes the major unchecked, and the prompt says what the light chain dropped.
            pub = calls(result, "publish")[0]["prompt"]
            self.assertIn("the light chain ran, code-reviewer", pub)
            self.assertIn("dropped although the launch passed them: plan_review, test_review, second_review, skeptic", pub)
            self.assertNotIn("Skeptics tried to refute", pub)
            self.assertTrue(any("plan_review skipped: the branch's area tooling" in e["message"] for e in result["events"] if e["kind"] == "log"))
        # The full tier keeps today's chain: every option passed runs.
        labels = [e["label"] for e in agents(full)]
        for want in ("plan:#7", "review:plan:#7", "review:netcode:#7", "review:netcode-second:#7", "test-review:#7", "skeptic:#7"):
            self.assertIn(want, labels)
        self.assertEqual(full["returned"]["tier"], "full")
        self.assertNotIn("tier_skipped", full["returned"])
        self.assertIn("skeptic", full["returned"])

    def test_a_client_ui_diff_is_light_and_drops_the_netcode_and_test_reviews(self) -> None:
        # Before 2b every client/ path routed the netcode review (#158) and was production code for test_review; in the
        # light tier client/ui/ gets neither, and the rest of client/ keeps both.
        ui, mixed = run_jobs([
            ("issue-task.js", dict(ARGS, branch="client/7-x", **ALL_OPTIONS), {"paths": ["client/ui/hud.gd", "docs/x.md"], "findings": [MAJOR]}),
            ("issue-task.js", dict(ARGS, branch="client/7-x", **ALL_OPTIONS), {"paths": ["client/ui/hud.gd", "client/player/p.gd"], "findings": [MAJOR]}),
        ])  # fmt: skip
        for result in (ui, mixed):
            self.assertIsNone(result["error"])
        self.assertEqual([e["label"] for e in agents(ui)], ["plan:#7", "review:plan:#7", "implement:#7", "review:code:#7", "review:godot-api:#7", "publish:#7"])
        # The netcode review the paths route (§4.2) is listed as dropped, so the result and the PR body say it did not run.
        self.assertEqual((ui["returned"]["tier"], ui["returned"]["tier_skipped"]), ("light", ["netcode_review", "test_review", "second_review", "skeptic"]))
        self.assertIn("; the netcode review its paths route (AGENT_WORKFLOW §4.2) did not run: its only client/ paths are under client/ui/; dropped although the launch passed them: test_review, second_review, skeptic.", calls(ui, "publish")[0]["prompt"])
        why = "the light review tier (#606): the diff's only production code is under client/ui/"
        self.assertEqual(ui["returned"]["test_review"], {"skipped": why})
        pub = calls(ui, "publish")[0]["prompt"]
        self.assertIn("Review tier (#606): light (no path under core/ server/ net/ voice/ tests/harness/ or client/ outside client/ui/)", pub)
        self.assertIn(f"The test review (test_review) was skipped: {why}.", pub)
        self.assertEqual(mixed["returned"]["tier"], "full")
        self.assertIn("Review tier (#606): full (the diff touches client/player/p.gd)", calls(mixed, "publish")[0]["prompt"])
        labels = [e["label"] for e in agents(mixed)]
        for want in ("review:netcode:#7", "review:netcode-second:#7", "test-review:#7", "skeptic:#7"):
            self.assertIn(want, labels)

    def test_a_voice_diff_routes_the_netcode_review(self) -> None:
        # #921: voice/ was full-tier but missed NETCODE_PATH, so a voice/-only diff ran no leak review (AGENT_WORKFLOW §4.2).
        (voice,) = run_jobs([("issue-task.js", dict(ARGS, branch="voice/7-x", **ALL_OPTIONS), {"paths": ["voice/x.gd"]})])
        self.assertIsNone(voice["error"])
        self.assertEqual(voice["returned"]["tier"], "full")
        labels = [e["label"] for e in agents(voice)]
        for want in ("review:netcode:#7", "review:netcode-second:#7"):
            self.assertIn(want, labels)

    def test_plan_review_follows_the_branch_area_before_the_diff_exists(self) -> None:
        cases = [
            ("core/7-x", {}, ["docs/x.md"], True, "light", ["skeptic"]),  # a full area plans; the light diff drops the skeptic
            ("tooling/7-x", {}, ["core/x.gd"], False, "full", ["plan_review"]),  # a light area skips; the diff is full
            ("content/7-x", {}, ["content/x.tres"], False, "light", ["plan_review", "skeptic"]),
            ("level/7-x", {}, ["levels/x.tscn"], False, "light", ["plan_review", "skeptic"]),
            ("tooling/7-x", {"tier": "full"}, ["docs/x.md"], True, "full", None),  # forced: plans and keeps the skeptic
            ("docs/7-x", {"design": True}, ["docs/x.md"], True, "full", None),
        ]
        jobs = [("issue-task.js", dict(ARGS, branch=b, plan_review=True, skeptic=True, **a), {"paths": p, "findings": [MAJOR]})
                for b, a, p, *_ in cases]  # fmt: skip
        for (branch, args, paths, plans, tier, skipped), result in zip(cases, run_jobs(jobs)):
            with self.subTest(branch=branch, args=args, paths=paths):
                self.assertIsNone(result["error"])
                self.assertEqual(bool(calls(result, "plan:")), plans)
                self.assertEqual(bool(calls(result, "review:plan:")), plans)
                self.assertEqual(bool(calls(result, "skeptic:")), tier == "full")
                self.assertEqual(result["returned"]["tier"], tier)
                self.assertEqual(result["returned"].get("tier_skipped"), skipped)

    def test_a_red_implementer_still_reports_its_tier(self) -> None:
        (result,) = run_jobs([("issue-task.js", ARGS, {"queues": {"implement": [implemented(["docs/x.md"], verify_green=False)]}})])
        self.assertIsNone(result["error"])
        self.assertIn("stopped", result["returned"])
        self.assertEqual(result["returned"]["tier"], "light")

    def test_only_the_full_tier_can_be_forced(self) -> None:
        bad = [{"tier": "light"}, {"tier": "auto"}, {"tier": True}, {"tier": ""}, {"tier": "Full"}]
        for args, result in zip(bad, run_jobs([("issue-task.js", dict(ARGS, **a), {}) for a in bad])):
            with self.subTest(args=args):
                self.assertIn("issue-task: args.tier must be 'full'", result["error"] or "")
                self.assertFalse(agents(result))

    def test_issue_task_uses_quick_tasks_netcode_rule(self) -> None:
        # One rule for the netcode review in both scripts (a workflow script imports nothing, so the regex is copied):
        # issue-task's full tier is quick-task's netcode review; quick-task also reviews client/ui/, with code-reviewer.
        def rule(name: str, const: str) -> str:
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            return next(line for line in text.splitlines() if line.startswith(f"const {const} = ")).split(" = ", 1)[1]

        self.assertEqual(rule("issue-task.js", "REVIEWED"), rule("quick-task.js", "NETCODE"))
        self.assertEqual(rule("quick-task.js", "REVIEWED"), r"/^(core|server|net|client|voice|tests\/harness)\//")


# #856: an update run of a published PR. The implementer returns the published head and the delta since it.
HEAD = "89abcdef0123456789abcdef0123456789abcdef"
UPDATE_LINE = "Update run (update, #856): "


def updated(delta: list[tuple[str, int, int]], head: str = HEAD, **extra) -> dict:
    """An update run's implementer: the whole PR's changed paths and the delta's numstat rows."""
    rows = [{"path": p, "added": a, "deleted": d} for p, a, d in delta]
    return implemented(["core/x.gd", "docs/x.md"] + [p for p, _, _ in delta], published_head=head, delta=rows, **extra)


def run_update(cases: list[tuple[dict, dict]]) -> list[dict]:
    """issue-task with update true and each (args, implementer result), a major finding for a skeptic to check."""
    jobs = [("issue-task.js", dict(ARGS, update=True, **args), {"queues": {"implement": [impl]}, "findings": [MAJOR]}) for args, impl in cases]
    return run_jobs(jobs)


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class UpdateRunTest(unittest.TestCase):
    """issue-task.js (#856): a relaunch for a published PR reviews the delta since its published head."""

    def test_update_is_validated_and_absent_by_default(self) -> None:
        bad = [{"update": "yes"}, {"update": 1}, {"update": "true"}, {"update": []}]
        for args, result in zip(bad, run_jobs([("issue-task.js", dict(ARGS, **a), {}) for a in bad])):
            with self.subTest(args=args):
                self.assertIn("issue-task: args.update must be true or false", result["error"] or "")
                self.assertFalse(agents(result))
        # false and null are today's run, byte for byte (the snapshots pin the run without the arg).
        stub = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        runs = run_jobs([("issue-task.js", dict(ARGS, branch="core/7-x", skeptic=True, **a), stub) for a in ({}, {"update": False}, {"update": None})])
        self.assertEqual(render(runs[1]), render(runs[0]))
        self.assertEqual(render(runs[2]), render(runs[0]))
        self.assertNotIn("update", runs[0]["returned"])
        self.assertFalse(any("Update run" in e["prompt"] or "published_head" in e["opts"] for e in agents(runs[0])))

    def test_the_update_path_drops_the_planner_the_test_review_and_the_skeptic(self) -> None:
        # A core PR whose delta is outside the full tier's paths (client/ui/ is light): the delta's paths route the
        # reviewers (the engineer's answer 2A on PR #862), so client/ui/ still gets the netcode review on a full PR.
        (result,) = run_update([(dict(ALL_OPTIONS, branch="core/7-x"), updated([("client/ui/x.gd", 3, 1), ("docs/y.md", 20, 5)]))])
        self.assertIsNone(result["error"])
        labels = [e["label"] for e in agents(result)]
        self.assertEqual(labels, ["implement:#7", "review:code:#7", "review:netcode:#7", "review:godot-api:#7", "review:netcode-second:#7", "publish:#7"])
        out = result["returned"]
        self.assertEqual(
            out["update"],
            {"path": "update", "head": HEAD, "files": 2, "lines": 29, "skipped": ["plan_review", "test_review", "skeptic"]},
        )
        self.assertEqual(out["test_review"]["skipped"][:30], "an update run (update, #856): ")
        self.assertNotIn("skeptic", out)
        self.assertEqual(out["tier"], "full")
        logs = [e["message"] for e in result["events"] if e["kind"] == "log"]
        self.assertTrue(any("plan_review skipped: an update run" in m for m in logs), logs)
        # The implementer records the head first and returns it with the delta.
        (impl,) = calls(result, "implement")
        self.assertIn("Update run (update, #856): this run continues the published PR of core/7-x", impl["prompt"])
        self.assertIn("rev-parse origin/core/7-x`: the PR's published head", impl["prompt"])
        self.assertIn("diff --numstat --no-renames <published head>..HEAD`", impl["prompt"])
        schema = options(impl)["schema"]
        self.assertEqual(schema["required"][-2:], ["published_head", "delta"])
        self.assertEqual(schema["properties"]["delta"]["items"]["required"], ["path", "added", "deleted"])
        # Each reviewer reads the delta and names the published head; the whole PR is context only.
        for review in calls(result, "review:"):
            with self.subTest(reviewer=review["label"]):
                self.assertIn(f"diff {HEAD}..HEAD`, 29 changed lines in 2 files since the PR's published head {HEAD}", review["prompt"])
                self.assertIn("only as context", review["prompt"])
                self.assertNotIn(": `git -C /d/prime-game/.claude/worktrees/7 diff origin/main...HEAD` and the files", review["prompt"])
        pub = calls(result, "publish")[0]["prompt"]
        line = next(x for x in pub.split("\n\n") if x.startswith(UPDATE_LINE))
        self.assertIn(f"the update path: the reviewers read only the delta since the PR's published head {HEAD}, 29 changed lines in 2 files, none under core/", line)
        self.assertIn("skipped although the launch passed them: plan_review, test_review, skeptic", line)
        self.assertNotIn("Skeptics tried to refute", pub)

    def test_a_delta_touching_a_full_tier_path_takes_the_full_chain(self) -> None:
        # The engineer's answer 1C on PR #862: any path of the full tier, whatever the delta's size (one line here).
        roots = ["core/x.gd", "server/x.gd", "net/x.gd", "client/hud/x.gd", "voice/x.gd", "tests/harness/x.gd"]
        cases = [({"branch": "core/7-x"}, updated([("docs/y.md", 500, 0), (p, 1, 0)])) for p in roots]
        cases += [({"branch": "core/7-x"}, updated([("core/x.png", -1, -1)]))]  # a binary file there
        # git quotes a path with non-ASCII bytes (core.quotePath): the quote must not hide it from the full tier.
        cases += [({"branch": "core/7-x"}, updated([('"core/\\303\\251.gd"', 1, 0)]))]
        cases += [({"branch": "core/7-x"}, updated([("core/a.gd", 1, 0), ("net/b.gd", 0, 1), ("voice/c.gd", 1, 1), ("server/d.gd", 2, 0)]))]
        results = run_update([(dict(ALL_OPTIONS, **a), impl) for a, impl in cases])
        for (args, impl), result in zip(cases, results):
            with self.subTest(delta=impl["delta"]):
                self.assertIsNone(result["error"])
                out = result["returned"]["update"]
                self.assertEqual(out["path"], "full")
                self.assertEqual(out["skipped"], ["plan_review"])
                labels = [e["label"] for e in agents(result)]
                for want in ("review:netcode:#7", "test-review:#7", "skeptic:#7"):
                    self.assertIn(want, labels)
                self.assertNotIn("plan:#7", labels)
                for review in calls(result, "review:"):
                    self.assertIn(": `git -C /d/prime-game/.claude/worktrees/7 diff origin/main...HEAD` and the files", review["prompt"])
                    self.assertNotIn(HEAD, review["prompt"])
                pub = calls(result, "publish")[0]["prompt"]
                self.assertIn(f"{UPDATE_LINE}the full chain ({out['why']}): the reviewers read the whole PR diff", pub)
        whys = [r["returned"]["update"]["why"] for r in results]
        self.assertEqual(whys[:len(roots)], [f"the delta touches the full tier's paths ({p})" for p in roots])
        self.assertEqual(whys[-3], "the delta touches the full tier's paths (core/x.png)")
        self.assertEqual(whys[-2], 'the delta touches the full tier\'s paths ("core/\\303\\251.gd")')
        self.assertEqual(whys[-1], "the delta touches the full tier's paths (core/a.gd, net/b.gd, voice/c.gd, 1 more)")
        # A delta of any size outside those paths (client/ui/ and tests/ but tests/harness/ included): the update path.
        cases = [
            ({}, updated([("tools/x.py", 400, 0), ("docs/x.md", 900, 300)])),
            ({}, updated([("client/ui/x.gd", 300, 40), ("tests/unit/x_test.gd", 90, 0)])),
            ({}, updated([("docs/x.png", -1, -1)])),
        ]
        for (_, impl), result in zip(cases, run_update(cases)):
            with self.subTest(delta=impl["delta"]):
                self.assertIsNone(result["error"])
                self.assertEqual(result["returned"]["update"]["path"], "update")

    def test_no_published_head_takes_the_full_chain_and_says_why(self) -> None:
        cases = [
            ({}, updated([("docs/x.md", 1, 0)], head="", update_note="origin/core/7-x is not an ancestor of HEAD: rebased")),
            ({}, updated([("docs/x.md", 1, 0)], head="")),
            ({}, updated([("docs/x.md", 1, 0)], head="not a sha")),
            ({}, implemented(["core/x.gd"])),  # the implementer returned neither key
            ({}, implemented(["core/x.gd"], published_head=HEAD)),  # a head but no delta
            ({"tier": "full"}, updated([("docs/x.md", 1, 0)])),
        ]
        whys = [
            "no published head returned: origin/core/7-x is not an ancestor of HEAD: rebased",
            "no published head returned",
            "no published head returned",
            "no published head returned",
            "no delta returned",
            "forced by the launch (tier: full)",
        ]
        results = run_update([(dict(a, branch="core/7-x", skeptic=True), impl) for a, impl in cases])
        for why, result in zip(whys, results):
            with self.subTest(why=why):
                self.assertIsNone(result["error"])
                self.assertEqual(result["returned"]["update"], {"path": "full", "why": why})
                self.assertTrue(calls(result, "skeptic"))
                self.assertIn(f"{UPDATE_LINE}the full chain ({why})", calls(result, "publish")[0]["prompt"])

    def test_the_delta_routes_the_reviewers(self) -> None:
        cases = [
            ({"branch": "core/7-x"}, updated([("docs/x.md", 4, 0)])),  # a core PR, a docs delta: the code reviewer
            ({"branch": "core/7-x"}, updated([])),  # an empty delta is known: no reviewer for unknown paths
            ({"branch": "core/7-x"}, updated([("client/ui/x.gd", 4, 0)])),  # a core PR: the delta's client/ path routes the netcode review
            ({"branch": "docs/7-x", "design": True}, updated([("docs/x.md", 4, 0)])),  # a design task keeps its netcode review
            ({"branch": "client/7-x"}, dict(updated([("client/ui/x.gd", 4, 0)]), changed_paths=["client/ui/x.gd"])),  # light
        ]
        want = [
            ["review:code:#7"],
            ["review:code:#7"],
            ["review:code:#7", "review:netcode:#7", "review:godot-api:#7"],
            ["review:code:#7", "review:netcode:#7"],
            ["review:code:#7", "review:godot-api:#7"],
        ]
        for labels, result in zip(want, run_update(cases)):
            with self.subTest(labels=labels):
                self.assertIsNone(result["error"])
                self.assertEqual([e["label"] for e in calls(result, "review:")], labels)
                self.assertEqual(result["returned"]["update"]["path"], "update")
                self.assertNotIn("skipped", result["returned"]["update"])

    def test_a_light_update_run_names_each_dropped_agent_once(self) -> None:
        # The light tier already dropped test_review and skeptic: the update does not list them a second time.
        light = dict(updated([("docs/x.md", 4, 0)]), changed_paths=["docs/x.md"])
        (result,) = run_update([(dict(ALL_OPTIONS, branch="docs/7-x"), light)])
        self.assertIsNone(result["error"])
        out = result["returned"]
        self.assertEqual(out["tier"], "light")
        self.assertEqual(out["update"]["skipped"], ["plan_review"])  # test_review and skeptic are tier_skipped
        self.assertNotIn("update run", out.get("test_review", {}).get("skipped", ""))
        pub = calls(result, "publish")[0]["prompt"]
        line = next(x for x in pub.split("\n\n") if x.startswith(UPDATE_LINE))
        self.assertIn("skipped although the launch passed them: plan_review. Say", line)

    def test_the_publisher_gets_no_delta_rows(self) -> None:
        # The line of the update path carries the head, the file count and the line count; the rows would only add tokens.
        (result,) = run_update([({"branch": "core/7-x"}, dict(updated([("client/ui/rows_marker.gd", 3, 1)]), changed_paths=["core/x.gd"]))])
        pub = calls(result, "publish")[0]["prompt"]
        self.assertIn(f"published head {HEAD}", pub)
        self.assertNotIn("rows_marker", pub)
        self.assertNotIn('"published_head"', pub)

    def test_a_red_update_run_still_reports_its_path(self) -> None:
        (result,) = run_update([({}, updated([("docs/x.md", 1, 0)], verify_green=False))])
        self.assertIsNone(result["error"])
        self.assertIn("stopped", result["returned"])
        self.assertEqual(result["returned"]["update"]["path"], "update")


def quick(paths: list[str], **extra) -> dict:
    """The quick agent's result (#608): a PR with CI green unless extra says otherwise."""
    pr = {"pr_url": "https://github.com/o/r/pull/9", "pr_number": 9, "ci_green": True, "changed_paths": paths, "summary": "s"}
    return dict(pr, **extra)


QUICK_FIELDS = {"n", "pr_url", "ci_green", "reviewed", "ready_to_merge", "needs_engineer", "summary"}


@unittest.skipUnless(NODE, "needs Node on PATH to run the workflow scripts")
class QuickTaskTest(unittest.TestCase):
    """quick-task.js (#608): one agent to a PR, reviewers only for a diff under core/ server/ net/ client/ voice/ tests/harness/."""

    def run_quick(self, *cases: tuple[dict, dict]) -> list[dict]:
        return run_jobs([("quick-task.js", dict(ARGS, **args), stub) for args, stub in cases])

    def test_a_light_diff_gets_no_reviewer_and_is_ready(self) -> None:
        light = ["docs/AGENT_WORKFLOW.md", "tools/runner/start.py", "content/roles/x.tres", "tests/unit/x_test.gd", "levels/r.tscn"]
        (result,) = self.run_quick(({}, {"queues": {"publish": [quick(light)]}}))
        self.assertIsNone(result["error"])
        self.assertEqual([e["label"] for e in agents(result)], ["publish:#7"])
        out = result["returned"]
        self.assertLessEqual(QUICK_FIELDS, set(out))
        self.assertEqual(out["reviewed"]["done"], False)
        self.assertIn("CI is the gate", out["reviewed"]["why"])
        self.assertTrue(out["ready_to_merge"])
        self.assertEqual((out["pr_url"], out["pr"], out["ci_green"], out["needs_engineer"]), ("https://github.com/o/r/pull/9", 9, True, []))

    def test_a_core_or_netcode_diff_gets_both_reviewers(self) -> None:
        cases = [({}, {"queues": {"publish": [quick([p])]}}) for p in ("core/match/vote.gd", "server/h.gd", "net/c.gd", "client/hud/hud.gd", "client/ui_kit/k.gd", "voice/m.gd", "tests/harness/bots/b.gd")]
        cases.append(({}, {"queues": {"publish": [quick([])]}}))  # no paths returned: unknown, so reviewed
        for result in self.run_quick(*cases):
            with self.subTest(why=result["returned"]["reviewed"]["why"]):
                self.assertIsNone(result["error"])
                reviewers = [(e["label"], options(e)["agentType"]) for e in agents(result)[1:]]
                self.assertEqual(reviewers, [("review:code:#7", "code-reviewer"), ("review:netcode:#7", "netcode-security-reviewer")])
                self.assertTrue(result["returned"]["reviewed"]["done"])
                self.assertTrue(result["returned"]["ready_to_merge"])

    def test_a_client_ui_diff_gets_the_code_reviewer_alone(self) -> None:
        # #606: the engineer's answer 2b (#302, comment 6085059719) made client/ui/ light in issue-task, where light keeps
        # code-reviewer; quick-task gives the screens the same one reviewer, never none. A path outside client/ui/ under
        # client/ (client/ui_kit/ only starts with "ui") brings the netcode review back.
        ui, mixed, kit = self.run_quick(
            ({}, {"findings": [MAJOR], "queues": {"publish": [quick(["client/ui/hud.gd", "docs/x.md"])], "fix": [{"fixed": ["f"], "open": 0, "ci_green": True}]}}),
            ({}, {"queues": {"publish": [quick(["client/ui/hud.gd", "client/player/p.gd"])]}}),
            ({}, {"queues": {"publish": [quick(["client/ui_kit/k.gd"])]}}),
        )  # fmt: skip
        self.assertIsNone(ui["error"])
        self.assertEqual([(e["label"], options(e)["agentType"]) for e in agents(ui)[1:2]], [("review:code:#7", "code-reviewer")])
        self.assertFalse(calls(ui, "review:netcode"))
        self.assertEqual(ui["returned"]["reviews"], [{"by": "code-reviewer", "findings": 1, "serious": 1}])
        self.assertIn("code-reviewer alone, no netcode review (#606)", ui["returned"]["reviewed"]["why"])
        self.assertEqual(len(calls(ui, "fix")), 1)  # a major from the one reviewer still gets the fix agent
        self.assertTrue(ui["returned"]["ready_to_merge"])
        for result in (mixed, kit):
            self.assertIsNone(result["error"])
            self.assertTrue(calls(result, "review:netcode"))
            self.assertNotIn("code-reviewer alone", result["returned"]["reviewed"]["why"])

    def test_a_blocker_or_major_gets_one_fix_agent_and_gates_the_merge(self) -> None:
        core = quick(["core/match/vote.gd"])
        fixed, left, red = self.run_quick(
            ({}, {"findings": [MAJOR], "queues": {"publish": [core], "fix": [{"fixed": ["f"], "open": 0, "ci_green": True}]}}),
            ({}, {"findings": [MAJOR], "queues": {"publish": [core], "fix": [{"fixed": [], "open": 1, "ci_green": True}]}}),
            ({}, {"findings": [MAJOR], "queues": {"publish": [core], "fix": [{"fixed": ["f"], "open": 0, "ci_green": False}]}}),
        )
        fix = calls(fixed, "fix")
        self.assertEqual(len(fix), 1)
        self.assertEqual(options(fix[0])["agentType"], "task-publisher")
        self.assertIn('"problem":"p1"', fix[0]["prompt"])
        self.assertTrue(fixed["returned"]["ready_to_merge"])
        self.assertFalse(left["returned"]["ready_to_merge"])
        self.assertFalse(red["returned"]["ready_to_merge"])
        self.assertFalse(red["returned"]["ci_green"])
        (minor,) = self.run_quick(({}, {"findings": [MINOR], "queues": {"publish": [core]}}))
        self.assertFalse(calls(minor, "fix"))
        self.assertTrue(minor["returned"]["ready_to_merge"])

    def test_a_dead_reviewer_or_fix_agent_blocks_the_merge(self) -> None:
        core = quick(["core/match/vote.gd"])
        clean, fixed, no_fix = self.run_quick(
            ({}, {"queues": {"publish": [core], "review:netcode": [None]}}),
            ({}, {"findings": [MAJOR], "queues": {"publish": [core], "review:netcode": [None], "fix": [{"fixed": ["f"], "open": 0, "ci_green": True}]}}),
            ({}, {"findings": [MAJOR], "queues": {"publish": [core], "fix": [None]}}),
        )
        for result in (clean, fixed):
            self.assertFalse(result["returned"]["ready_to_merge"])
            self.assertIn("1 reviewer(s) returned nothing", result["returned"]["needs_engineer"][0])
        self.assertFalse(no_fix["returned"]["ready_to_merge"])
        self.assertEqual(no_fix["returned"]["open_serious"], 2)  # the stub gives both reviewers the major
        self.assertIn("the fix agent returned nothing", no_fix["returned"]["needs_engineer"][0])

    def test_red_ci_no_pr_or_a_dead_agent_is_not_ready(self) -> None:
        red, none, dead, asks = self.run_quick(
            ({}, {"queues": {"publish": [quick(["docs/x.md"], ci_green=False)]}}),
            ({}, {"queues": {"publish": [quick([], pr_url="", needs_engineer=["bigger than a quick task"])]}}),
            ({}, {"queues": {"publish": [None]}}),
            ({}, {"queues": {"publish": [quick(["docs/x.md"], needs_engineer=["approve the text"])]}}),
        )
        for result in (red, none, dead, asks):
            self.assertLessEqual(QUICK_FIELDS, set(result["returned"]))
            self.assertFalse(result["returned"]["ready_to_merge"])
        self.assertEqual(none["returned"]["needs_engineer"], ["bigger than a quick task"])
        self.assertEqual([e["label"] for e in agents(none)], ["publish:#7"])
        self.assertIn("returned nothing", dead["returned"]["stopped"])

    def test_the_quick_agent_is_one_lean_bounded_agent(self) -> None:
        default, opus = self.run_quick(
            ({"base": "release/m5"}, {"queues": {"publish": [quick(["docs/x.md"])]}}),
            ({"models": {"quick": "opus"}}, {"queues": {"publish": [quick(["docs/x.md"])]}}),
        )
        event = agents(default)[0]
        o = options(event)
        self.assertEqual((o["agentType"], o["model"]), ("task-publisher", "sonnet"))
        self.assertEqual(options(agents(opus)[0])["model"], "opus")
        prompt = event["prompt"]
        for want in ("at most 60 tool calls", "tools/run.sh lint", "tools/run.sh check", "git push -u origin tooling/7-x",
                     "gh pr create --base release/m5", "Closes #7", "timeout 180 gh pr checks", "At most two fix rounds",
                     "the attribution line your system reminder gives for commits", STASH_RULE.replace("Never use ", "No "),
                     "Read a log by search, never whole"):  # #572
            self.assertIn(want, prompt)
        self.assertNotIn("tools/run.sh verify", prompt)
        self.assertNotIn("publish`", prompt)
        for where, sub in schemas_of(o["schema"]):
            self.assertLessEqual(set(sub.get("required", [])), set(sub.get("properties", {})), where)

    def test_wrong_args_throw_before_any_agent(self) -> None:
        bad = [{"n": ""}, {"notes": ""}, {"models": "opus"}, {"models": {"implement": "opus"}}, {"models": {"quick": ""}}]
        for result in self.run_quick(*[(args, {}) for args in bad]):
            self.assertIn("quick-task: args.", result["error"] or "")
            self.assertFalse(agents(result))


if __name__ == "__main__":
    unittest.main()
