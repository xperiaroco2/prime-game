"""`agents-check`: expected model families from the caller's request, the agent files and the model guard."""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import agents_check, metrics
from runner.agents_check import Transcript
from runner.common import ROOT, Failure, force_rmtree

AGENTS = {"code-reviewer": "opus", "test-runner": "haiku", "godot-api-checker": "sonnet"}
ALLOWED = ["opus", "sonnet", "haiku"]


def t(agent_type: str, served: set[str], requested: str | None = None) -> Transcript:
    return Transcript("s", "a1", agent_type, requested, served)


class JudgeTest(unittest.TestCase):
    def verdict(self, transcript: Transcript) -> str:
        return agents_check.judge(transcript, AGENTS, ALLOWED)[0]

    def test_family(self) -> None:
        self.assertEqual(agents_check.family("claude-opus-5-5"), "opus")
        self.assertEqual(agents_check.family("claude-haiku-4-5-20251001"), "haiku")
        self.assertEqual(agents_check.family("sonnet"), "sonnet")
        self.assertIsNone(agents_check.family("<synthetic>"))

    def test_project_agents_use_their_frontmatter_model(self) -> None:
        self.assertEqual(self.verdict(t("test-runner", {"claude-haiku-4-5-20251001"})), "ok")
        self.assertEqual(self.verdict(t("godot-api-checker", {"claude-sonnet-5"})), "ok")  # families, not IDs
        self.assertEqual(self.verdict(t("code-reviewer", {"claude-sonnet-5-5"})), "FAIL")
        self.assertEqual(self.verdict(t("code-reviewer", {"claude-opus-5-5", "claude-sonnet-5-5"})), "FAIL")

    def test_the_callers_request_wins(self) -> None:
        self.assertEqual(self.verdict(t("general-purpose", {"claude-sonnet-5-5"}, "sonnet")), "ok")
        self.assertEqual(self.verdict(t("general-purpose", {"claude-opus-5-5"}, "sonnet")), "FAIL")

    def test_full_ids_and_case(self) -> None:
        self.assertEqual(self.verdict(t("general-purpose", {"claude-sonnet-5-5"}, "claude-sonnet-5-5")), "ok")
        self.assertEqual(self.verdict(t("general-purpose", {"claude-sonnet-5-5"}, "Sonnet")), "ok")
        self.assertEqual(self.verdict(t("general-purpose", {"claude-opus-5-5"}, "claude-fable-5-1")), "ok")

    def test_model_guard(self) -> None:
        # fable is outside availableModels: the request must fall back, never be served.
        self.assertEqual(self.verdict(t("general-purpose", {"claude-opus-5-5"}, "fable")), "ok")
        self.assertEqual(self.verdict(t("general-purpose", {"claude-fable-5-1"}, "fable")), "FAIL")

    def test_inherited_and_empty_are_not_judged(self) -> None:
        self.assertEqual(self.verdict(t("general-purpose", {"claude-opus-5-5"})), "skip")
        self.assertEqual(self.verdict(t("test-runner", {"<synthetic>"})), "skip")


class ReadTest(unittest.TestCase):
    def test_reads_transcripts_of_this_checkout_and_its_worktrees(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = Path("D:/prime-game")
            name = "D--prime-game"
            for folder, session in ((name, "s1"), (f"{name}--claude-worktrees-12", "s2"), ("D--prime-game2", "s3")):
                sub = base / "projects" / folder / session / "subagents"
                sub.mkdir(parents=True)
                lines = [
                    {"type": "user", "message": {"role": "user"}},
                    {"type": "assistant", "message": {"model": "claude-haiku-4-5-20251001"}},
                ]
                (sub / "agent-a1.jsonl").write_text("\n".join(map(json.dumps, lines)) + "\n", encoding="utf-8")
                (sub / "agent-a1.meta.json").write_text(json.dumps({"agentType": "test-runner"}), encoding="utf-8")
            dirs = agents_check.project_dirs(root, base)
            self.assertEqual([d.name for d in dirs], [name, f"{name}--claude-worktrees-12"])
            found = agents_check.read(dirs[0], None)
            self.assertEqual([(x.session, x.agent_type, x.served) for x in found], [("s1", "test-runner", {"claude-haiku-4-5-20251001"})])
            self.assertEqual(agents_check.read(dirs[0], "other-session"), [])

    def test_nothing_to_judge_is_a_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(agents_check, "project_dirs", return_value=[]):
            with mock.patch.object(agents_check, "say"), self.assertRaises(Failure) as raised:
                agents_check.main(all_sessions=True, config=Path(tmp))
        self.assertIn("no subagent transcript", str(raised.exception))

    def test_repo_agent_models_are_read(self) -> None:
        models = agents_check.agent_models()
        self.assertEqual(models.get("test-runner"), "haiku")
        self.assertEqual(agents_check.allowed_models(), ALLOWED)

    def test_the_lean_reader_and_writer_are_judged_by_their_files_unless_the_call_names_a_model(self) -> None:
        # #466: a finder or gatherer launched with agentType lean-reader and no model must run on Sonnet; a skeptic
        # of that type passes model 'opus', recorded in its meta file, and is judged by it.
        models = agents_check.agent_models()
        self.assertEqual((models.get("lean-reader"), models.get("lean-writer")), ("sonnet", "opus"))
        cases = (
            (t("lean-reader", {"claude-sonnet-5-5"}), "ok"),
            (t("lean-reader", {"claude-opus-5-5"}), "FAIL"),
            (t("lean-reader", {"claude-opus-5-5"}, "opus"), "ok"),
            (t("lean-reader", {"claude-sonnet-5-5"}, "opus"), "FAIL"),
            (t("lean-writer", {"claude-opus-5-5"}), "ok"),
            (t("lean-writer", {"claude-sonnet-5-5"}, "sonnet"), "ok"),
            (t("lean-writer", {"claude-sonnet-5-5"}), "FAIL"),
        )
        for transcript, want in cases:
            with self.subTest(agent=transcript.agent_type, requested=transcript.requested, served=transcript.served):
                self.assertEqual(agents_check.judge(transcript, models, ALLOWED)[0], want)


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]


def transcript(folder: Path, agent_id: str, meta: dict, served: str) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    line = {"type": "assistant", "message": {"model": served}}
    (folder / f"agent-{agent_id}.jsonl").write_text(json.dumps(line) + "\n", encoding="utf-8")
    (folder / f"agent-{agent_id}.meta.json").write_text(json.dumps(meta), encoding="utf-8")


# Workflow agents' meta files as Claude Code writes them for a default launch (keys and values copied from the
# 2026-10-02 runs: a project reviewer and an implementer, which has no agent file and inherits the session's model).
def workflow_meta(agent_type: str, label: str, phase: str, **extra: str) -> dict:
    return {
        "agentType": agent_type,
        "description": label,
        "workflowPhase": phase,
        "spawnDepth": 1,
        "requestShape": "foreground",
        "requestNonInteractive": True,
        **extra,
    }


class WorkflowReadTest(unittest.TestCase):
    """#206: workflow agents (<session>/subagents/workflows/wf_*/agent-*.jsonl) are read beside hand-run ones."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        transcript(self.folder / "s1" / "subagents", "h1", {"agentType": "test-runner"}, "claude-haiku-4-5-20251001")
        run = self.folder / "s1" / "subagents" / "workflows" / "wf_0407695f-d88"
        transcript(run, "w1", workflow_meta("code-reviewer", "review:code:#188", "Review"), "claude-opus-5-5")
        transcript(run, "w2", workflow_meta("workflow-subagent", "implement:#188", "Implement"), "claude-opus-5-5")
        # A launch that passes `models` (issue-task's agent({model})): recorded as `model`, like the Agent tool's.
        transcript(
            run, "w3", workflow_meta("netcode-security-reviewer", "review:netcode-2:#188", "Review", model="sonnet"),
            "claude-sonnet-5-5",
        )
        (run / "journal.jsonl").write_text('{"type":"launched"}\n', encoding="utf-8")
        other = self.folder / "s2" / "subagents" / "workflows" / "wf_1a525aa7-7c9"
        transcript(other, "w4", workflow_meta("code-reviewer", "review:code:#181", "Review"), "claude-opus-5-5")

    def test_reads_hand_run_and_workflow_agents(self) -> None:
        found = {x.agent_id: x for x in agents_check.read(self.folder, None)}
        self.assertEqual(sorted(found), ["h1", "w1", "w2", "w3", "w4"])
        h1, w1, w3, w4 = found["h1"], found["w1"], found["w3"], found["w4"]
        self.assertEqual((h1.session, h1.run, h1.label), ("s1", None, ""))
        self.assertEqual((w1.session, w1.run, w1.label), ("s1", "wf_0407695f-d88", "review:code:#188"))
        self.assertEqual((w1.agent_type, w1.requested, w1.served), ("code-reviewer", None, {"claude-opus-5-5"}))
        self.assertEqual((w3.requested, w3.served), ("sonnet", {"claude-sonnet-5-5"}))
        self.assertEqual((w4.session, w4.run), ("s2", "wf_1a525aa7-7c9"))
        self.assertEqual([x.unread_keys for x in found.values()], [()] * 5)

    def test_a_session_filter_keeps_that_sessions_workflow_agents(self) -> None:
        self.assertEqual(sorted(x.agent_id for x in agents_check.read(self.folder, "s2")), ["w4"])
        self.assertEqual(sorted(x.agent_id for x in agents_check.read(self.folder, "s1")), ["h1", "w1", "w2", "w3"])

    def test_default_launches_are_judged_by_their_agent_file_or_inherit(self) -> None:
        found = {x.agent_id: x for x in agents_check.read(self.folder, None)}
        self.assertEqual(agents_check.judge(found["w1"], AGENTS, ALLOWED)[0], "ok")
        self.assertEqual(agents_check.judge(found["w2"], AGENTS, ALLOWED)[0], "skip")  # workflow-subagent inherits
        verdict, why = agents_check.judge(found["w3"], AGENTS, ALLOWED)
        self.assertEqual((verdict, why.split(",")[0]), ("ok", "requested sonnet"))  # the request beats the file's opus

    def test_a_meta_key_that_may_name_a_model_under_another_name_fails(self) -> None:
        run = self.folder / "s1" / "subagents" / "workflows" / "wf_0407695f-d88"
        meta = workflow_meta("code-reviewer", "review:code:#188", "Review", requestedModel="sonnet")
        transcript(run, "w5", meta, "claude-opus-5-5")
        w5 = next(x for x in agents_check.read(self.folder, "s1") if x.agent_id == "w5")
        self.assertEqual(w5.unread_keys, ("requestedModel",))
        verdict, why = agents_check.judge(w5, AGENTS, ALLOWED)
        self.assertEqual(verdict, "FAIL")
        self.assertIn("requestedModel", why)

    def test_a_nested_meta_key_that_may_name_a_model_fails(self) -> None:
        run = self.folder / "s1" / "subagents" / "workflows" / "wf_0407695f-d88"
        meta = workflow_meta("workflow-subagent", "implement:#188", "Implement")
        meta["request"] = {"model": "sonnet", "tools": [{"name": "x", "defaultModel": "haiku"}]}
        transcript(run, "w5", meta, "claude-opus-5-5")
        w5 = next(x for x in agents_check.read(self.folder, "s1") if x.agent_id == "w5")
        self.assertEqual(w5.unread_keys, ("request.model", "request.tools.0.defaultModel"))
        verdict, why = agents_check.judge(w5, AGENTS, ALLOWED)
        self.assertEqual(verdict, "FAIL")
        self.assertIn("request.model", why)

    def test_odd_lines_and_a_broken_meta_file_are_skipped(self) -> None:
        run = self.folder / "s3" / "subagents" / "workflows" / "wf_x"
        run.mkdir(parents=True)
        lines = ['["assistant"]', '"assistant"', "{not json, assistant", json.dumps(
            {"type": "assistant", "message": {"model": "claude-haiku-4-5-20251001"}}
        )]
        (run / "agent-w6.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
        (run / "agent-w6.meta.json").write_text("{", encoding="utf-8")
        (w6,) = agents_check.read(self.folder, "s3")
        self.assertEqual((w6.agent_type, w6.requested, w6.served), ("?", None, {"claude-haiku-4-5-20251001"}))


class MainTest(unittest.TestCase):
    """main() end to end on a temporary repository with a worktree and a temporary Claude config folder."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.main = Path(tmp.name).resolve() / "game"
        (self.main / ".claude").mkdir(parents=True)
        (self.main / ".claude" / "settings.json").write_text(json.dumps({"availableModels": ALLOWED}), encoding="utf-8")
        (self.main / ".claude" / "agents").mkdir()
        (self.main / ".claude" / "agents" / "code-reviewer.md").write_text(
            "---\nname: code-reviewer\ndescription: x\nmodel: opus\n---\nReview.\n", encoding="utf-8"
        )
        subprocess.run([*GIT, "init", "-q"], cwd=self.main, check=True)
        subprocess.run([*GIT, "add", "."], cwd=self.main, check=True)
        subprocess.run([*GIT, "commit", "-q", "-m", "x"], cwd=self.main, check=True)
        self.worktree = self.main / ".claude" / "worktrees" / "7"
        subprocess.run([*GIT, "worktree", "add", "-q", str(self.worktree)], cwd=self.main, check=True)
        self.config = Path(tmp.name).resolve() / "config"
        # Workflow and hand-run agents of a session started in the main checkout log under its key.
        self.subagents = self.config / "projects" / metrics.project_key(self.main) / "s1" / "subagents"
        transcript(self.subagents, "a1", {"agentType": "general-purpose", "model": "sonnet"}, "claude-sonnet-5-5")
        for name in ("say", "ok", "bad", "skip"):
            patcher = mock.patch.object(agents_check, name)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_from_a_worktree_it_reads_the_main_checkouts_transcripts(self) -> None:
        self.assertEqual(agents_check.main(all_sessions=True, root=self.worktree, config=self.config), 0)
        self.assertEqual(agents_check.main(all_sessions=True, root=self.main, config=self.config), 0)

    def test_a_user_scope_model_passes_only_while_the_user_list_holds_it(self) -> None:
        transcript(self.subagents, "a2", {"agentType": "general-purpose", "model": OUTSIDE}, f"claude-{OUTSIDE}-5-1")
        user_settings = self.config / "settings.json"
        user_settings.write_text(json.dumps({"availableModels": [OUTSIDE]}), encoding="utf-8")
        self.assertEqual(agents_check.main(all_sessions=True, root=self.worktree, config=self.config), 0)
        user_settings.unlink()
        self.assertEqual(agents_check.main(all_sessions=True, root=self.worktree, config=self.config), 1)

    def verdicts(self) -> dict[str, str]:
        """{agent id: ok | FAIL | skip} of the last main() run, from its printed lines."""
        found = {}
        for verdict, printer in (("ok", agents_check.ok), ("FAIL", agents_check.bad), ("skip", agents_check.skip)):
            for call in printer.call_args_list:
                found[re.search(r"agent (\w+)", call.args[0]).group(1)] = verdict
        return found

    def test_workflow_agents_get_the_same_verdicts(self) -> None:
        """#206: shared list, user-scope list, fell back and neither list, for agents of a workflow run."""
        run = self.subagents / "workflows" / "wf_1"
        served_outside = f"claude-{OUTSIDE}-5-1"
        cases = {
            "w1": (workflow_meta("code-reviewer", "review:code:#7", "Review"), "claude-opus-5-5", "ok"),
            "w2": (workflow_meta("code-reviewer", "review:code:#8", "Review"), "claude-sonnet-5-5", "FAIL"),
            "w3": (workflow_meta("workflow-subagent", "implement:#7", "Implement"), "claude-opus-5-5", "skip"),
            "w4": (workflow_meta("code-reviewer", "review:2:#7", "Review", model="sonnet"), "claude-sonnet-5-5", "ok"),
            "w5": (workflow_meta("code-reviewer", "review:2:#8", "Review", model=OUTSIDE), served_outside, "ok"),
            "w6": (workflow_meta("code-reviewer", "review:2:#9", "Review", model=OUTSIDE), "claude-opus-5-5", "skip"),
        }
        for agent_id, (meta, served, _) in cases.items():
            transcript(run, agent_id, meta, served)
        (self.config / "settings.json").write_text(json.dumps({"availableModels": [OUTSIDE]}), encoding="utf-8")
        self.assertEqual(agents_check.main(all_sessions=True, root=self.worktree, config=self.config), 1)
        got = self.verdicts()
        self.assertEqual({k: got[k] for k in cases}, {k: v[2] for k, v in cases.items()})
        self.assertEqual(got["a1"], "ok")  # the hand-run agent is still read
        printed = " ".join(c.args[0] for c in agents_check.bad.call_args_list)
        self.assertIn("review:code:#8", printed)
        self.assertIn("workflow wf_1", printed)
        summary = agents_check.say.call_args_list[-1].args[0]
        self.assertIn("5 checked, 4 of them in workflows; 1 wrong", summary)

    def test_a_workflow_agent_served_by_a_model_in_neither_list_fails(self) -> None:
        run = self.subagents / "workflows" / "wf_2"
        meta = workflow_meta("code-reviewer", "review:2:#7", "Review", model=OUTSIDE)
        transcript(run, "w1", meta, f"claude-{OUTSIDE}-5-1")
        self.assertEqual(agents_check.main(all_sessions=True, root=self.worktree, config=self.config), 1)
        self.assertEqual(self.verdicts()["w1"], "FAIL")
        self.assertIn("the model guard failed", agents_check.bad.call_args.args[0])


# The example of a model outside the shared list, taken from the family table so no test adds its name.
OUTSIDE = next(f for f in agents_check.FAMILIES if f not in ALLOWED)


class UserScopeJudgeTest(unittest.TestCase):
    """Amendment A of the model-guard ADR: the user-scope availableModels may hold a model the shared list does not."""

    def judge(self, served: set[str], requested: str, user: list[str]) -> tuple[str, str]:
        return agents_check.judge(t("general-purpose", served, requested), AGENTS, ALLOWED, user=user)

    def test_a_user_scope_model_that_served_is_ok(self) -> None:
        for user in ([OUTSIDE], [OUTSIDE.capitalize()], [f"claude-{OUTSIDE}-5-1"]):
            with self.subTest(user=user):
                verdict, why = self.judge({f"claude-{OUTSIDE}-5-1"}, OUTSIDE, user)
                self.assertEqual(verdict, "ok")
                self.assertIn("user-scope", why)

    def test_a_model_in_neither_list_that_served_stays_a_fail(self) -> None:
        for user in ([], ["sonnet"], ["claude-opus-5-5"]):
            with self.subTest(user=user):
                verdict, why = self.judge({f"claude-{OUTSIDE}-5-1"}, OUTSIDE, user)
                self.assertEqual(verdict, "FAIL")
                self.assertIn("the model guard failed", why)

    def test_a_user_scope_model_that_fell_back_is_listed_not_judged(self) -> None:
        # Not a FAIL: transcripts from before the user list held it (the 2026-09-28 guard check) would keep --all red.
        verdict, why = self.judge({"claude-opus-5-5"}, OUTSIDE, [OUTSIDE])
        self.assertEqual(verdict, "skip")
        self.assertIn("fell back", why)

    def test_an_inherited_model_in_neither_list_that_served_fails(self) -> None:
        # A workflow-subagent (no agent file) overridden by `models` with no key in its meta file: still guarded.
        inherited = t("workflow-subagent", {f"claude-{OUTSIDE}-5-1"})
        for user in ([], ["sonnet"]):
            with self.subTest(user=user):
                verdict, why = agents_check.judge(inherited, AGENTS, ALLOWED, user=user)
                self.assertEqual(verdict, "FAIL")
                self.assertIn("the model guard failed", why)
        self.assertEqual(agents_check.judge(inherited, AGENTS, ALLOWED, user=[OUTSIDE])[0], "skip")
        self.assertEqual(agents_check.judge(t("workflow-subagent", {"claude-opus-5-5"}), AGENTS, ALLOWED)[0], "skip")
        self.assertEqual(agents_check.judge(inherited, AGENTS, [])[0], "skip")  # no availableModels: no guard

    def test_the_user_list_changes_nothing_for_shared_models(self) -> None:
        self.assertEqual(self.judge({"claude-opus-5-5"}, "sonnet", ["sonnet", OUTSIDE])[0], "FAIL")
        self.assertEqual(self.judge({"claude-sonnet-5-5"}, "sonnet", [OUTSIDE])[0], "ok")
        self.assertEqual(self.judge({"claude-opus-5-5"}, OUTSIDE, ["sonnet"]), self.judge({"claude-opus-5-5"}, OUTSIDE, []))


class UserModelsTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.config = Path(tmp.name)
        self.settings = self.config / "settings.json"

    def test_reads_the_list(self) -> None:
        self.settings.write_text(json.dumps({"env": {}, "availableModels": ["x", "y"]}), encoding="utf-8")
        self.assertEqual(agents_check.user_models(self.config), ["x", "y"])
        self.settings.write_text(json.dumps({"availableModels": ["z"]}), encoding="utf-8-sig")  # PowerShell's BOM
        self.assertEqual(agents_check.user_models(self.config), ["z"])

    def test_no_file_or_no_key_is_an_empty_list(self) -> None:
        self.assertEqual(agents_check.user_models(self.config), [])
        self.settings.write_text("{}", encoding="utf-8")
        self.assertEqual(agents_check.user_models(self.config), [])

    def test_a_broken_file_is_a_failure_that_names_it(self) -> None:
        for text in ("{", "[]", '{"availableModels": "x"}', '{"availableModels": [1]}'):
            with self.subTest(text=text):
                self.settings.write_text(text, encoding="utf-8")
                with self.assertRaises(Failure) as caught:
                    agents_check.user_models(self.config)
                self.assertIn(str(self.settings), str(caught.exception))

    def test_claude_config_dir_is_honoured(self) -> None:
        self.settings.write_text(json.dumps({"availableModels": ["x"]}), encoding="utf-8")
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(self.config)}):
            self.assertEqual(agents_check.user_models(), ["x"])


def names_outside(text: str, outside: list[str]) -> list[str]:
    """The families of `outside` that the text names as a word; the model-guard ADR's file name (a link to it holds
    one) is not a name, any other path that holds one is."""
    text = re.sub(r"2026-09-28-model-guard-no-\w+-in-shared-config\.md", " ", text.lower())
    return [f for f in outside if re.search(rf"\b{f}\b", text)]


class SharedFilesTest(unittest.TestCase):
    """Amendment A of the model-guard ADR: a model beyond the shared availableModels is passed per launch and named
    in ADRs, issues and PRs, never in .claude/ (settings, agents, workflows, skills, rules), .github/ or a CLAUDE.md."""

    def test_the_scan_sees_a_named_model_and_passes_a_link_to_the_adr(self) -> None:
        self.assertEqual(names_outside(f"the second review runs on {OUTSIDE.capitalize()}.", [OUTSIDE]), [OUTSIDE])
        link = f"[ADR](../../../docs/decisions/2026-09-28-model-guard-no-{OUTSIDE}-in-shared-config.md)"
        self.assertEqual(names_outside(f"the guard ({link})", [OUTSIDE]), [])

    def test_a_link_to_another_file_named_after_the_model_is_still_a_name(self) -> None:
        for path in (f".claude/agents/{OUTSIDE}-reviewer.md", f"docs/{OUTSIDE}.md"):
            with self.subTest(path=path):
                self.assertEqual(names_outside(f"see [the agent]({path})", [OUTSIDE]), [OUTSIDE])

    def test_no_shared_instruction_file_names_a_model_outside_the_shared_list(self) -> None:
        shared = {agents_check.family(m) for m in agents_check.allowed_models()}
        outside = [f for f in agents_check.FAMILIES if f not in shared]
        self.assertTrue(outside, "the family table names no model outside availableModels: nothing to guard")
        listed = subprocess.run(
            ["git", "ls-files", "-z", "--", ".claude", ".github", "CLAUDE.md", "*/CLAUDE.md"],
            cwd=ROOT, capture_output=True, check=True,
        ).stdout.decode("utf-8")
        files = [f for f in listed.split("\0") if f and not f.startswith("docs/history/")]
        self.assertIn(".claude/settings.json", files)
        for name in files:
            text = (ROOT / name).read_bytes().decode("utf-8", errors="replace")
            with self.subTest(file=name):
                self.assertEqual(names_outside(text, outside), [], f"{name} names a model beyond the shared list")


def git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout.strip()


class LaunchTest(unittest.TestCase):
    """#557: `agents-check --launch`, which the manager runs before each issue-task or pr-rebase launch. The Workflow
    tool runs the scripts and resolves their agent types from the manager's checkout, and a script cannot read a file:
    a checkout without the lean agent files, or with scripts older than origin/main's, launched general agents."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="launch-"))
        self.addCleanup(force_rmtree, str(self.tmp))
        git(self.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        self.work = self.clone("work")
        for name in agents_check.LAUNCH_AGENTS:
            self.write(f".claude/agents/{name}.md", (ROOT / ".claude" / "agents" / f"{name}.md").read_text(encoding="utf-8"))
        for name in agents_check.LAUNCH_SCRIPTS:
            self.write(f".claude/workflows/{name}", "export const meta = { name: 'x', description: 'x' }\n")
        # The paths the lean bodies name, which instructions.agent_problems checks.
        self.write("docs/workflow-scripts.md", "x\n")
        self.write("docs/decisions/2026-10-04-lean-workflow-agent-types.md", "x\n")
        self.commit("c1")

    def clone(self, name: str) -> Path:
        git(self.tmp, "clone", "-q", str(self.tmp / "remote.git"), name)
        work = self.tmp / name
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            git(work, "config", key, value)
        return work

    def write(self, rel: str, text: str, work: Path | None = None) -> None:
        path = (work or self.work) / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))

    def commit(self, message: str, work: Path | None = None) -> None:
        work = work or self.work
        git(work, "add", "-A")
        git(work, "commit", "-q", "-m", message)
        git(work, "push", "-q", "origin", "HEAD:main")

    def other_pushes(self, rel: str) -> None:
        other = self.clone("other")
        self.write(rel, "newer\n", other)
        self.commit("newer", other)

    def test_a_current_checkout_passes(self) -> None:
        self.assertEqual(agents_check.launch_problems(self.work), ([], []))
        with mock.patch.object(agents_check, "say") as said:
            self.assertEqual(agents_check.main(launch=True, root=self.work), 0)
        self.assertIn("agents-check --launch: ready", " ".join(str(c.args[0]) for c in said.call_args_list))

    def test_a_missing_or_broken_lean_agent_file_fails(self) -> None:
        (self.work / ".claude" / "agents" / "task-publisher.md").unlink()
        implementer = self.work / ".claude" / "agents" / "task-implementer.md"
        implementer.write_bytes(implementer.read_bytes().replace(b"\n---\n", b"\nskills: x\n---\n", 1))
        problems, _ = agents_check.launch_problems(self.work, fetch=False)
        joined = " | ".join(problems)
        self.assertIn(".claude/agents/task-publisher.md: missing", joined)
        self.assertIn(".claude/agents/task-implementer.md: skills: a lean type preloads no skill", joined)
        with mock.patch.object(agents_check, "bad"), mock.patch.object(agents_check, "say"):
            self.assertEqual(agents_check.main(launch=True, root=self.work), 1)

    def test_a_missing_script_fails(self) -> None:
        (self.work / ".claude" / "workflows" / "pr-rebase.js").unlink()
        problems, _ = agents_check.launch_problems(self.work, fetch=False)
        # Deleted in the working tree, so it also differs from origin/main.
        self.assertEqual(problems[0], ".claude/workflows/pr-rebase.js: missing")
        self.assertEqual(len(problems), 2, problems)

    def test_scripts_or_agent_files_behind_origin_main_fail_after_a_fetch(self) -> None:
        self.other_pushes(".claude/workflows/issue-task.js")
        # Without a fetch this checkout cannot know; launch_problems fetches first.
        self.assertEqual(agents_check.launch_problems(self.work, fetch=False), ([], []))
        problems, _ = agents_check.launch_problems(self.work)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("differ from origin/main", problems[0])
        self.assertIn(".claude/workflows/issue-task.js", problems[0])

    def test_a_newer_origin_main_elsewhere_passes(self) -> None:
        self.other_pushes("docs/other.md")
        self.assertEqual(agents_check.launch_problems(self.work), ([], []))

    def test_an_uncommitted_edit_fails(self) -> None:
        # The Workflow tool reads the working tree, so an edit not on origin/main would run.
        self.write(".claude/agents/task-implementer.md", (self.work / ".claude/agents/task-implementer.md").read_text(encoding="utf-8") + "x\n")
        problems, _ = agents_check.launch_problems(self.work, fetch=False)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn(".claude/agents/task-implementer.md", problems[0])

    def test_a_failed_fetch_warns_and_compares_with_the_last_fetch(self) -> None:
        git(self.work, "remote", "set-url", "origin", str(self.tmp / "gone.git"))
        problems, notes = agents_check.launch_problems(self.work)
        self.assertEqual(problems, [])
        self.assertEqual(len(notes), 1, notes)
        self.assertIn("could not fetch origin main", notes[0])

    def test_launch_is_its_own_mode(self) -> None:
        from runner import cli

        for argv in (["agents-check", "--launch", "--all"], ["agents-check", "--launch", "--session", "s"]):
            with self.subTest(argv=argv), self.assertRaises(SystemExit), mock.patch("sys.stderr"):
                cli.build_parser().parse_args(argv)
        self.assertTrue(cli.build_parser().parse_args(["agents-check", "--launch"]).launch)


if __name__ == "__main__":
    unittest.main()
