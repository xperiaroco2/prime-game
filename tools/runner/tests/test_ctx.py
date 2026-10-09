"""`ctx` (#597): the calling agent's context from its own transcript, for issue-task's checkpoint (#559)."""

import io
import json
import os
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

from runner import cli, ctx

WT = Path("D:/prime-game/.claude/worktrees/597")


def call(context: int, model: str = "claude-opus-5-5") -> dict:
    """An assistant line whose API call had `context` tokens: cache reads, a cache write, input and output."""
    usage = {"input_tokens": 2, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": context - 1100, "output_tokens": 98}
    return {"type": "assistant", "message": {"model": model, "role": "assistant", "usage": usage, "content": []}}


def transcript(path: Path, prompt: str, contexts: list[int], mtime: float | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [{"type": "user", "message": {"role": "user", "content": prompt}}]
    for n in contexts:
        lines.append(call(n))
        lines.append({"type": "attachment", "attachment": {"type": "total_tokens_reminder", "text": f"<total_tokens>{15000000 - n} tokens left</total_tokens>"}})
    path.write_text("\n".join(json.dumps(line) for line in lines) + "\n", encoding="utf-8")
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


class CtxTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def run_ctx(self, *args: str) -> tuple[int, str]:
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = cli.main(["ctx", *args])
        return rc, buf.getvalue()

    def test_below_the_threshold_it_says_go_on(self) -> None:
        path = transcript(self.dir / "agent-a.jsonl", "work in D:/prime-game/.claude/worktrees/597", [40000, 120500])
        rc, out = self.run_ctx("--transcript", str(path))
        self.assertEqual(rc, 0)
        self.assertIn("ctx: 120,500 tokens of context (hand over at 150,000)", out)
        self.assertNotIn("HANDOFF NOW", out)

    def test_at_or_past_the_threshold_it_says_handoff_now(self) -> None:
        for last, hard in ((150000, False), (185321, False), (269000, True)):
            with self.subTest(last=last):
                path = transcript(self.dir / f"agent-{last}.jsonl", "p", [60000, last])
                rc, out = self.run_ctx("--transcript", str(path))
                self.assertEqual(rc, 0)
                self.assertIn(f"ctx: {last:,} tokens of context", out)
                self.assertIn("HANDOFF NOW", out)
                self.assertEqual(hard, "past 200,000, even when only the final verify is left" in out)

    def test_the_thresholds_come_from_the_arguments(self) -> None:
        path = transcript(self.dir / "agent-a.jsonl", "p", [90000])
        self.assertIn("HANDOFF NOW: past 80,000", self.run_ctx("--transcript", str(path), "--at", "50000", "--hard", "80000")[1])

    def test_no_api_call_or_no_file_is_exit_2(self) -> None:
        empty = transcript(self.dir / "agent-a.jsonl", "p", [])
        synthetic = self.dir / "agent-s.jsonl"
        synthetic.write_text(json.dumps(call(500000, model="<synthetic>")) + "\n", encoding="utf-8")
        for path in (empty, synthetic, self.dir / "missing.jsonl"):
            with self.subTest(path=path.name):
                rc, out = self.run_ctx("--transcript", str(path))
                self.assertEqual(rc, ctx.MISSING)
                self.assertIn("ctx: no transcript with an API call found", out)

    def test_the_folder_matches_every_spelling_and_no_longer_name(self) -> None:
        pattern = ctx.folder_pattern(WT)
        for text in ("D:/prime-game/.claude/worktrees/597", "cd /d/prime-game/.claude/worktrees/597 && x",
                     json.dumps("D:\\prime-game\\.claude\\worktrees\\597\\tools"), "d:/Prime-Game/.claude/worktrees/597."):  # fmt: skip
            self.assertTrue(pattern.search(text), text)
        for text in ("D:/prime-game/.claude/worktrees/5970", "D:/prime-game/.claude/worktrees/59", "E:/prime-game/.claude/worktrees/597"):
            self.assertFalse(pattern.search(text), text)

    def test_the_newest_recent_transcript_naming_the_worktree_is_the_callers(self) -> None:
        now = time.time()
        project = self.dir / "projects" / "D--prime-game" / "sid"
        mine = transcript(project / "subagents" / "workflows" / "wf_1" / "agent-mine.jsonl", "Work ONLY in the worktree D:/prime-game/.claude/worktrees/597", [170000], now - 60)
        transcript(project / "subagents" / "workflows" / "wf_1" / "agent-old.jsonl", "D:/prime-game/.claude/worktrees/597", [90000], now - 600)
        transcript(project / "subagents" / "workflows" / "wf_2" / "agent-other.jsonl", "D:/prime-game/.claude/worktrees/572", [10000], now)
        transcript(project / "subagents" / "workflows" / "wf_1" / "journal.jsonl", "D:/prime-game/.claude/worktrees/597", [], now)
        stale = transcript(self.dir / "projects" / "D--prime-game--claude-worktrees-597" / "s.jsonl", "D:/prime-game/.claude/worktrees/597", [1], now - 7 * 3600)
        dirs = ctx.project_dirs(self.dir, Path("D:/prime-game"))
        self.assertEqual([d.name for d in dirs], ["D--prime-game", "D--prime-game--claude-worktrees-597"])
        self.assertEqual(ctx.find_transcript(dirs, WT, now), mine)
        os.utime(stale, (now, now))
        self.assertEqual(ctx.find_transcript(dirs, WT, now), stale)
        self.assertIsNone(ctx.find_transcript(dirs, Path("D:/prime-game/.claude/worktrees/9"), now))

    def test_without_a_transcript_argument_it_finds_the_callers(self) -> None:
        transcript(self.dir / "projects" / "D--prime-game" / "sid" / "agent-mine.jsonl", "D:/prime-game/.claude/worktrees/597", [155000])
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(self.dir)}), mock.patch.object(ctx, "ROOT", WT), \
                mock.patch("runner.metrics.main_checkout", return_value=Path("D:/prime-game")):  # fmt: skip
            rc, out = self.run_ctx()
        self.assertEqual(rc, 0)
        self.assertIn("ctx: 155,000 tokens of context (hand over at 150,000), from agent-mine.jsonl", out)
        self.assertIn("HANDOFF NOW", out)


if __name__ == "__main__":
    unittest.main()
