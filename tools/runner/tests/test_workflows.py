"""The saved workflows in .claude/workflows/: run each script under Node with stub agents and read the prompts.

The scripts are Claude Code workflow bodies (top-level await and return), so the harness wraps each one in an async
function and passes `args`, `agent`, `parallel`, `phase` and `log`. Node is not a project dependency: without it the
tests skip, except on GitHub Actions, where a missing Node fails `test_github_actions_runs_the_workflow_tests`.

Snapshots: other managers launch these scripts by name from their own copies and resume runs with the same args, and a
resume replays an agent only while its prompt and options are unchanged. So with none of the optional pipeline-v2 args
(docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item 4) and `bounded_waits: false` every
agent's prompt, label, phase, schema and options must stay byte-identical: `workflow_snapshots/<script>/unbounded/`
holds them for representative arg sets, captured from the scripts on origin/main before v2 changed them. The one
exception is `publish-clean-main`: it passes a v2 arg and pins the publish_clean trial of #308, so the byte-identical
rule covers every other case. `workflow_snapshots/<script>/<case>.txt` holds the same cases as launched, with
`bounded_waits` on by default since #411 (their one deliberate change: each agent that waits gained the bounded-waits
paragraph). A deliberate change of a default prompt rewrites them: run `selftest` once with
PRIME_WORKFLOW_SNAPSHOTS=update (the snapshot test then fails on purpose, naming the files it wrote), review the diff,
commit it with the change, and run `selftest` again without the variable. Such changes rewrote unbounded/ too: #413's
and #456's lines of the shared rules, and #339's section reads (the reviewers' and the plan critique's ARCHITECTURE sections, no
root CLAUDE.md, the netcode reviewers' §5, §4.2 and §4.6, the default reading list); they landed between waves, when
no run could resume. Each snapshot ends with the run's return value, which the rule does not cover (a resume replays
agents, not the return): #386 made it compact and changed only that part of every snapshot.
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
        ("content-release", {"branch": "content/7-x", "base": "release/m5"}, {"paths": ["content/roles/x.tres", "levels/rooms/x.tscn"]}),
        ("design-main", {"branch": "docs/7-x", "design": True}, {"paths": ["docs/ARCHITECTURE.md", "docs/decisions/x.md"]}),
        ("no-paths-main", {"branch": "core/7-x"}, {"paths": []}),
        # #308's one-wave trial: a clean run's publisher with a cheaper model (the only case with a v2 arg).
        ("publish-clean-main", {"branch": "core/7-x", "models": {"publish_clean": "sonnet"}}, {"paths": ["core/x.gd"], "findings": [MINOR]}),
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

    def test_every_agent_gets_the_hooks_path_and_no_foreground_sleep_rules(self) -> None:
        # #326, from #312: in the week of 2026-09-29 workflow agents made 9 of the 10 hooks-path reads the deny rule
        # `git config *hooksPath*` refused and 26 of the 28 foreground `sleep N; cat <log>` polls Claude Code blocked.
        # They read their workflow prompt, not docs/AGENT_WORKFLOW.md, so each rule is one line of the shared RULES,
        # the same in both scripts.
        jobs = [
            ("issue-task.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", **V2), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
            ("pr-rebase.js", dict(ARGS, base="release/m3"), {"paths": ["core/x.gd"]}),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True), {"paths": ["core/x.gd"], "findings": [MAJOR]}),
        ]
        seen: dict[str, set[str]] = {HOOKS_RULE: set(), SLEEP_RULE: set()}
        for (name, _, _), result in zip(jobs, run_jobs(jobs)):
            self.assertIsNone(result["error"])
            for event in agents(result):
                if options(event).get("agentType") in READ_ONLY_TYPES:
                    continue  # reviewers are read-only
                for rule, lines in seen.items():
                    with self.subTest(workflow=name, agent=event["label"], rule=rule):
                        found = [line for line in event["prompt"].splitlines() if line.startswith(rule)]
                        self.assertEqual(len(found), 1, found)
                        lines.add(found[0])
        for rule, lines in seen.items():
            with self.subTest(rule=rule):
                self.assertEqual(len(lines), 1, f"the rule differs between agents or scripts: {sorted(lines)}")
        self.assertIn("`git rev-parse --git-path hooks`", next(iter(seen[HOOKS_RULE])))
        sleep = next(iter(seen[SLEEP_RULE]))
        for way in ("`tools/run.sh wait <log>`", "run_in_background", "Monitor"):
            self.assertIn(way, sleep)

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
            ("issue-task.js", dict(ARGS, **base, bounded_waits=False), {"paths": ["core/x.gd"]}),
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

    def test_the_publisher_names_a_relayed_agreement(self) -> None:
        # #128: a change the engineer says was agreed with the designer gets the wording and the tag in its PR,
        # not only the MVP-provisional note, so the designer sees it later.
        calls = run_workflow(WORKFLOWS / "issue-task.js", None, ["content/roles/x.tres"])
        publish = [c["prompt"] for c in calls if c["label"].startswith("publish")]
        self.assertEqual(len(publish), 1, [c["label"] for c in calls])
        self.assertIn('"agreed with the designer, relayed by the engineer"', publish[0])
        self.assertIn("@SwiftySinister", publish[0])

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
        # case but publish-clean-main passes no v2 arg besides the bounded_waits false of its unbounded/ run). Each
        # case runs twice: as launched (`<case>.txt`, bounded waits on by default since #411) and with bounded_waits
        # false (`unbounded/<case>.txt`, the text before #411).
        jobs, files = [], []
        for name, cases in SNAPSHOT_CASES.items():
            for case, args, stub in cases:
                for extra, folder in (({}, ()), ({"bounded_waits": False}, ("unbounded",))):
                    jobs.append((name, dict(ARGS, **args, **extra), stub))
                    files.append(SNAPSHOTS.joinpath(name.removesuffix(".js"), *folder, f"{case}.txt"))
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
# #455: how the test reviewer runs a mutants spec and the publisher a survived mutant again, with bounded waits (the
# default: in the background, a new log, `wait`) and without (the foreground text of before #411), for ARGS.
MUTANTS_RUN = {
    True: (
        "Run each spec in the background, never in the foreground (a foreground call dies at 600 s, and setup and the "
        "baseline come before the first mutant): `cd /d/prime-game/.claude/worktrees/7 && tools/run.sh mutants "
        '<spec.json> > <log> 2>&1; echo "exit=$?" >> <log>` in the Bash tool with run_in_background true and its timeout '
        "3600000, a NEW log under a7/ of your scratchpad for each run (mutants-1.log, mutants-2.log, ...), then "
        "`cd /d/prime-game/.claude/worktrees/7 && tools/run.sh wait <log>` in separate calls until it finishes, as the "
        "bounded waits below say. A spec may hold several mutants (setup and the baseline then run once); one run at a "
        "time: another mutants run in the same checkout exits 1."
    ),
    False: (
        "Run ONE mutant per `tools\\run.cmd mutants <spec.json>` call (a foreground call dies at 600 s), or start it in "
        "the background and wait for it."
    ),
}
MUTANTS_RERUN = {
    True: (
        "then run that mutant again in the background (a NEW log under a7/ of your scratchpad, then "
        "`tools/run.sh wait <log>`, as the bounded waits below say) to show it killed"
    ),
    False: "then run that mutant again (one per call, or in the background: a foreground call dies at 600 s) to show it killed",
}
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
# The lean snapshots pin the options lean adds. They sit beside the pre-v2 snapshots but are not part of that guard:
# every other case runs without a v2 arg.
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
            {"bounded_waits": "yes"},
            {"lean": "yes"},
            {"lean": 1},
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
        # With lean the implementing and publishing agents get a lean writer type (#332) and still every rule.
        jobs += [(name, dict(args, lean=True), stub) for name, args, stub in jobs]
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
        self.assertIn('The plan: {"summary":"p"', critique["prompt"])
        self.assertIn('The plan: {"summary":"p"', implement["prompt"])
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
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True, bounded_waits=False), core),
        ]
        ok, absent, exit_2, skeptic, dead, design, tooling, pub_stuck, unbounded = run_jobs(jobs)
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
        # #455: with bounded waits (the default) each spec runs in the background with a new log and `wait`, as
        # verify and publish do, before the bounded-waits paragraph that gives the commands; the foreground advice of
        # before #411 is left only to bounded_waits false, and so is the publisher's rerun of a survived mutant.
        publish = calls(ok, "publish")[0]["prompt"]
        for prompt, text in ((test_review, MUTANTS_RUN), (publish, MUTANTS_RERUN)):
            self.assertEqual(prompt.count(text[True]), 1)
            self.assertNotIn(text[False], prompt)
            self.assertLess(prompt.index(text[True]), prompt.index("Bounded waits (bounded_waits)"))
            for foreground in ("ONE mutant per", "one per call"):
                self.assertNotIn(foreground, prompt)
        old_review, old_publish = calls(unbounded, "test-review")[0]["prompt"], calls(unbounded, "publish")[0]["prompt"]
        for prompt, text in ((old_review, MUTANTS_RUN), (old_publish, MUTANTS_RERUN)):
            self.assertEqual(prompt.count(text[False]), 1)
            self.assertNotIn(text[True], prompt)
            self.assertNotIn("Bounded waits (bounded_waits)", prompt)
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
        self.assertTrue(missing["returned"]["published"])
        self.assertIn("`spectate`", calls(unreported, "implement")[0]["prompt"])
        self.assertIn("the implementer reported no playcheck run", calls(unreported, "publish")[0]["prompt"])

    def test_bounded_waits_adds_one_paragraph_to_each_agent_that_waits(self) -> None:
        # #303: a tool call that blocks over 5 minutes (verify, publish, mutants, CI) costs the agent's whole context
        # again. With the arg, each agent that runs one gets one paragraph more, after the steps it replaces. #411 made
        # it the default (a missing or null arg); with bounded_waits false every prompt is the one before (the
        # unbounded/ snapshots), so a resume of an earlier run with false added is unchanged. #455 changed one sentence
        # more where mutants run: the test reviewer's run of a spec and the publisher's rerun of a survived mutant.
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "tools/out/mutants/m1 is still listed"}
        design = {"paths": ["docs/x.md"], "findings": [MAJOR]}
        pairs = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), core),
            ("pr-rebase.js", dict(ARGS), core),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True, skeptic=True), design),
        ]
        jobs = []
        for name, args, stub in pairs:
            jobs += [(name, args, stub), (name, dict(args, bounded_waits=True), stub)]
            jobs += [(name, dict(args, bounded_waits=None), stub), (name, dict(args, bounded_waits=False), stub)]
        results = run_jobs(jobs)
        waiting, publishing = ("implement", "test-review", "publish", "rebase", "fix"), ("publish", "rebase", "fix")
        extra = {}
        for k, (name, _, _) in enumerate(pairs):
            default, on, null, off = results[4 * k : 4 * k + 4]
            for result in (default, on, null, off):
                self.assertIsNone(result["error"])
            self.assertEqual(render(default), render(on), "bounded_waits true is the default")
            self.assertEqual(render(null), render(on), "a null bounded_waits is the default")
            self.assertEqual([e["label"] for e in agents(on)], [e["label"] for e in agents(off)])
            stopped = k == 2  # the publisher that only reports a mutants stop runs no long command
            for before, after in zip(agents(off), agents(on)):
                label = before["label"]
                with self.subTest(case=k, agent=label):
                    self.assertEqual(after["opts"], before["opts"])
                    if not label.startswith(waiting) or (stopped and label.startswith("publish")):
                        self.assertEqual(after["prompt"], before["prompt"])
                        continue
                    # #455: the one other text bounded waits change is how mutants run, in the background with `wait`.
                    prompt = after["prompt"]
                    if label.startswith("test-review"):
                        self.assertIn(MUTANTS_RUN[True], prompt)
                    for text in (MUTANTS_RUN, MUTANTS_RERUN):
                        if text[True] in prompt:
                            self.assertEqual(before["prompt"].count(text[False]), 1)
                            prompt = prompt.replace(text[True], text[False])
                    old, new = before["prompt"].split("\n\n"), prompt.split("\n\n")
                    self.assertEqual(len(new), len(old) + 1)
                    i = next(i for i, (a, b) in enumerate(zip(old + [None], new)) if a != b)
                    paragraph = new[i]
                    self.assertEqual(new[:i] + new[i + 1 :], old, "removing the paragraph gives today's prompt")
                    self.assertTrue(paragraph.startswith("Bounded waits (bounded_waits): this replaces how"), paragraph[:120])
                    scratch = "r8" if name == "pr-rebase.js" else "a7"
                    for text in (
                        "every `verify`, `publish`, `mutants` and `gh pr checks --watch` step in this prompt",
                        "run_in_background",
                        f"under {scratch}/ of your scratchpad",
                        'cd /d/prime-game/.claude/worktrees/7 && tools/run.sh <command> > <log> 2>&1; echo "exit=$?" >> <log>',
                        "tools/run.sh wait <log>",
                        "`tools\\run.cmd wait <log>`",
                        "300000",
                        "No tool call blocks longer than 240 s",
                        "never only with the tool's timeout",
                        "never start the job again",
                        "timeout 240 gh pr checks <pr> --watch --interval 30; echo rc=$?` in the Bash tool with the "
                        "tool's timeout set to 300000",
                        "while rc is 124 or 8",
                        "no checks reported",
                        "`wait: no log`, `wait: cannot read` or `wait: --max` line is wait's own error",
                        "mutants: 0 the run completed, 1 a bad spec or a run that could not finish, 2 its scratch "
                        "worktree could not be removed",
                        "run them in the foreground as before",
                    ):
                        self.assertIn(text, paragraph)
                    # It comes after every step it replaces, so the last word on CI and verify is the bounded one.
                    for j, text in enumerate(new):
                        if j != i and ("gh pr checks" in text or "run.cmd verify" in text):
                            self.assertLess(j, i, text[:120])
                    kind = "publishing" if label.startswith(publishing) else "other"
                    if kind == "publishing":
                        self.assertIn("`tools/run.sh wait --verified`", paragraph)
                        self.assertIn("`publish` runs `verify` itself", paragraph)
                        self.assertTrue(new[-2].startswith(HUMAN_STEPS_ASK), new[-2][:80])
                    else:
                        self.assertNotIn("wait --verified", paragraph)
                    extra.setdefault((name, kind), set()).add(paragraph.replace(scratch + "/", "<s>/"))
        # One paragraph per kind, and the two scripts cannot share a module: their copies must not drift apart.
        self.assertEqual(len(extra[("issue-task.js", "publishing")]), 1)
        self.assertEqual(extra[("issue-task.js", "publishing")], extra[("pr-rebase.js", "publishing")])
        self.assertEqual(len(extra[("issue-task.js", "other")]), 1)

    def test_meta_and_the_args_comment_name_each_v2_arg(self) -> None:
        # A manager states the agent count in its kickoff from these lines.
        for name, names in (
            (
                "issue-task.js",
                ("plan_review", "test_review", "second_review", "skeptic", "visual", "bounded_waits", "efforts", "models", "lean"),
            ),
            ("pr-rebase.js", ("second_review", "skeptic", "bounded_waits", "efforts", "models", "lean")),
        ):
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            when = next(line for line in text.splitlines() if line.strip().startswith("whenToUse:"))
            comment = "\n".join(line for line in text.splitlines() if line.startswith("//"))
            with self.subTest(workflow=name):
                self.assertIn("Agents: ", when)
                for arg in names:
                    self.assertIn(f"{arg}?", when)
                    self.assertRegex(comment, rf"//   {arg} ")

    def test_lean_adds_only_the_agent_type(self) -> None:
        # #332: lean must change nothing but an agentType appended to the implementing and publishing agents' options,
        # so the efforts and models a launch sets still reach them, and a run without lean stays as it was.
        stuck = {"available": True, "exit_2": True, "findings": [], "notes": "n"}
        core = {"paths": ["core/x.gd"], "findings": [MAJOR]}
        tuned = {"bounded_waits": True, "efforts": {"implement": "medium", "publish": "low"}, "models": {"implement": AVAILABLE[0]}}
        bases = [
            ("issue-task.js", dict(ARGS, branch="core/7-x", **tuned, **V2), core),
            ("issue-task.js", dict(ARGS, branch="docs/7-x", design=True, plan_review=True), {"paths": ["docs/x.md"]}),
            ("issue-task.js", dict(ARGS, branch="core/7-x", test_review=True), dict(core, queues={"test-review": [stuck]})),
            ("pr-rebase.js", dict(ARGS, second_review=True, skeptic=True, efforts={"fix": "medium"}), core),
        ]
        jobs = [(name, dict(args, **extra), stub) for name, args, stub in bases for extra in ({}, {"lean": False}, {"lean": True})]
        results = run_jobs(jobs)
        typed = set()
        for i, (name, _, _) in enumerate(bases):
            plain, off, lean = results[3 * i : 3 * i + 3]
            with self.subTest(job=i, workflow=name):
                for result in (plain, off, lean):
                    self.assertIsNone(result["error"])
                self.assertEqual(render(off), render(plain))
                before, after = agents(plain), agents(lean)
                self.assertEqual([e["label"] for e in after], [e["label"] for e in before])
                for old, new in zip(before, after):
                    self.assertEqual(new["prompt"], old["prompt"], old["label"])
                    want = LEAN_TYPES.get(old["label"].split(":")[0])
                    if want is None:
                        self.assertEqual(new["opts"], old["opts"], old["label"])
                        continue
                    typed.add(old["label"].split(":")[0])
                    self.assertNotIn("agentType", options(old))
                    self.assertEqual(options(new), dict(options(old), agentType=want), old["label"])
                    self.assertEqual(list(options(new))[-1], "agentType", old["label"])  # appended last
        self.assertEqual(sorted(typed), sorted(LEAN_TYPES))
        # The tuned launch's effort and model still reach the lean implementer and publisher.
        lean = {e["label"]: options(e) for e in agents(results[2])}
        self.assertEqual((lean["implement:#7"]["effort"], lean["implement:#7"]["model"]), ("medium", AVAILABLE[0]))
        self.assertEqual(lean["publish:#7"]["effort"], "low")

    def test_lean_options_match_their_snapshots(self) -> None:
        # Like the main snapshots, each case runs as launched and with bounded_waits false (`unbounded/`): a resume of
        # a lean run launched before #411 passes false and must replay its old prompts byte for byte.
        jobs, files = [], []
        for name, cases in LEAN_SNAPSHOT_CASES.items():
            for case, args, stub in cases:
                for extra, folder in (({}, ()), ({"bounded_waits": False}, ("unbounded",))):
                    jobs.append((name, dict(ARGS, **args, **extra), stub))
                    files.append(SNAPSHOTS.joinpath(name.removesuffix(".js"), *folder, f"{case}.txt"))
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


if __name__ == "__main__":
    unittest.main()
