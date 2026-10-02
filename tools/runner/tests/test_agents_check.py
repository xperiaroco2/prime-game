"""`agents-check`: expected model families from the caller's request, the agent files and the model guard."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import agents_check, metrics
from runner.agents_check import Transcript
from runner.common import Failure

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


if __name__ == "__main__":
    unittest.main()
