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
from runner.common import ROOT, Failure

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
        with mock.patch.object(agents_check, "project_dirs", return_value=[]), mock.patch.object(agents_check, "say"):
            with self.assertRaises(Failure):
                agents_check.main(all_sessions=True)

    def test_repo_agent_models_are_read(self) -> None:
        models = agents_check.agent_models()
        self.assertEqual(models.get("test-runner"), "haiku")
        self.assertEqual(agents_check.allowed_models(), ALLOWED)


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]


def transcript(folder: Path, agent_id: str, meta: dict, served: str) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    line = {"type": "assistant", "message": {"model": served}}
    (folder / f"agent-{agent_id}.jsonl").write_text(json.dumps(line) + "\n", encoding="utf-8")
    (folder / f"agent-{agent_id}.meta.json").write_text(json.dumps(meta), encoding="utf-8")


class MainTest(unittest.TestCase):
    """main() end to end on a temporary repository with a worktree and a temporary Claude config folder."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.main = Path(tmp.name).resolve() / "game"
        (self.main / ".claude").mkdir(parents=True)
        (self.main / ".claude" / "settings.json").write_text(json.dumps({"availableModels": ALLOWED}), encoding="utf-8")
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


if __name__ == "__main__":
    unittest.main()
