"""The reviewer agent files read docs by section (#433; the instruction-diet ADR's N1 (a), as the workflow prompts since
#339): a reviewer launched by hand (finish-task, the routing table) gets the same reading as a workflow's reviewer."""

import re
import unittest

from runner import guard, instructions, permissions
from runner.common import ROOT

from .test_permissions import MAIN, OwnRepo

AGENTS = ROOT / ".claude" / "agents"
REVIEWERS = ("code-reviewer", "netcode-security-reviewer")
# The runner commands each reviewer may run: `section` only prints part of a doc or a code file (#468); `bots` is the
# information-leak test.
RUNNER_COMMANDS = {"code-reviewer": {"section"}, "netcode-security-reviewer": {"bots", "section"}}
OUTLINE = "`tools/run.sh section docs/ARCHITECTURE.md`"
# The always-read sections of the netcode reviewers, with the labels of NETCODE_SECTIONS in the workflows.
NETCODE_PARTS = (
    "§5 (per-peer filtering)",
    "§4.2 (each event's audience)",
    "§4.6 (the client, the bots and the leak test)",
    "tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6`",
)
RUN_RE = re.compile(r"tools[\\/]run\.(?:sh|cmd) ([a-z][\w-]*)")
SPAN_RE = re.compile(r"`([^`]*)`")
SECTION_RE = re.compile(r"tools[\\/]run\.(?:sh|cmd) section((?: [^ ]+)*)")
SETTINGS = permissions.Rules.load(ROOT / ".claude" / "settings.json")


def text(name: str) -> str:
    return (AGENTS / f"{name}.md").read_text(encoding="utf-8")


def allowed(name: str) -> str:
    """The "Allowed shell commands" item of the agent file, its lines joined."""
    body = text(name).split("\n- ")
    item = next(part for part in body if part.startswith("Read-only. Allowed shell commands:"))
    return " ".join(item.split())


class ReviewerAgentFilesTest(unittest.TestCase):
    def test_they_name_architecture_sections_never_the_whole_doc(self) -> None:
        for name in REVIEWERS:
            whole = " ".join(text(name).split())
            with self.subTest(agent=name):
                # Every mention of the doc, the description included, is a `section` call on it: the bare file name
                # ("against CLAUDE.md, ARCHITECTURE.md and the content API") is the old whole-doc wording.
                self.assertEqual(re.findall(r"(?<!section docs/)ARCHITECTURE\.md", whole), [])
                # The outline prints the size; a figure in the file goes stale as the doc grows.
                self.assertNotRegex(whole, r"\d+k tokens")
                self.assertIn(OUTLINE + " prints", whole)
                self.assertRegex(whole, r"`tools/run\.sh section docs/ARCHITECTURE\.md \d+(\.\d+)*( \d+(\.\d+)*)*`")

    def test_the_netcode_reviewer_always_reads_the_leak_sections_as_the_workflows_do(self) -> None:
        whole = " ".join(text("netcode-security-reviewer").split())
        sentence = re.search(r"Always read ARCHITECTURE §5.*?`\.", whole)
        self.assertIsNotNone(sentence, "no 'Always read ARCHITECTURE §5 ...' sentence")
        assert sentence is not None
        self.assertIn("whatever the change touches", sentence.group(0))
        for part in NETCODE_PARTS:
            self.assertIn(part, sentence.group(0))
        for script in ("issue-task.js", "pr-rebase.js"):
            source = (ROOT / ".claude" / "workflows" / script).read_text(encoding="utf-8")
            for part in NETCODE_PARTS:
                with self.subTest(script=script, part=part):
                    self.assertIn(part.rstrip("`"), source)

    def test_they_allow_section_in_both_shells_and_no_other_runner_command(self) -> None:
        for name in REVIEWERS:
            item = allowed(name)
            with self.subTest(agent=name):
                self.assertIn("`tools/run.sh section`", item)
                self.assertIn("`tools\\run.cmd section`", item)
                self.assertEqual(set(RUN_RE.findall(item)), RUNNER_COMMANDS[name], item)

    def test_they_run_section_from_the_worktree_under_review(self) -> None:
        # A workflow launches a reviewer with its cwd in the main checkout: without a `cd`, `section` would print
        # main's doc, not the branch's, and a diff that edits ARCHITECTURE would be read against the old text.
        for name in REVIEWERS:
            whole = " ".join(text(name).split())
            with self.subTest(agent=name):
                self.assertIn("from the worktree under review (prefix `cd <worktree> &&`", whole)
                self.assertIn("`cd <dir> &&`", allowed(name))
        command = "cd D:/prime-game/.claude/worktrees/433 && tools/run.sh section docs/ARCHITECTURE.md 5 4.2 4.6"
        got = permissions.verdict(SETTINGS, guard, "Bash", command, str(ROOT), MAIN, OwnRepo(), False)
        self.assertEqual(got[0], permissions.PASS, got)

    def test_they_stay_read_only(self) -> None:
        for name in REVIEWERS:
            fm = instructions.parse(text(name))
            tools = instructions._as_list(fm.fields.get("tools"))
            disallowed = instructions._as_list(fm.fields.get("disallowedTools"))
            with self.subTest(agent=name):
                self.assertEqual(instructions.agent_problems(AGENTS / f"{name}.md"), [])
                self.assertEqual(sorted(tools), sorted(["Read", "Grep", "Glob", "Bash", "PowerShell"]))
                for tool in instructions.READ_ONLY:
                    self.assertIn(tool, disallowed)

    def test_each_section_call_they_show_runs_without_a_prompt(self) -> None:
        # The shared permission rules and the guard already let `section` run outside bypass: the agent files need no
        # settings or guard change (.claude/settings*.json and the guard are the engineer's).
        spans = [span for name in REVIEWERS for span in SPAN_RE.findall(text(name))]
        # The arguments of each `section` call the files show; a bare `section` is shown with the outline's doc.
        args = {m.group(1).strip() or "docs/ARCHITECTURE.md" for s in spans if (m := SECTION_RE.fullmatch(s))}
        self.assertGreaterEqual(len(args), 3, sorted(args))
        for arg in sorted(args):
            for tool, runner in (("Bash", "tools/run.sh"), ("PowerShell", "tools\\run.cmd")):
                command = f"{runner} section {arg}"
                with self.subTest(tool=tool, command=command):
                    got = permissions.verdict(SETTINGS, guard, tool, command, str(ROOT), MAIN, OwnRepo(), False)
                    self.assertEqual(got[0], permissions.PASS, got)


class LeanAgentFilesTest(unittest.TestCase):
    """#466: the lean types of the workflows outside issue-task and pr-rebase
    (docs/decisions/2026-10-06-lean-reader-and-writer-types.md)."""

    READER_TOOLS = ["Read", "Grep", "Glob", "Bash", "PowerShell", "WebFetch", "WebSearch"]

    def test_the_reader_is_read_only_on_sonnet(self) -> None:
        fm = instructions.parse(text("lean-reader"))
        self.assertEqual(instructions.agent_problems(AGENTS / "lean-reader.md"), [])
        self.assertEqual(fm.fields.get("model"), "sonnet")  # finders and gatherers; a skeptic's call passes opus
        self.assertEqual(sorted(instructions._as_list(fm.fields.get("tools"))), sorted(self.READER_TOOLS))
        disallowed = instructions._as_list(fm.fields.get("disallowedTools"))
        for tool in (*instructions.READ_ONLY, "Skill"):
            self.assertIn(tool, disallowed)

    def test_the_writer_adds_only_edit_and_write_on_opus(self) -> None:
        fm = instructions.parse(text("lean-writer"))
        self.assertEqual(instructions.agent_problems(AGENTS / "lean-writer.md"), [])
        self.assertEqual(fm.fields.get("model"), "opus")
        self.assertEqual(
            sorted(instructions._as_list(fm.fields.get("tools"))), sorted([*self.READER_TOOLS, "Edit", "Write"])
        )

    def test_their_bodies_stay_short(self) -> None:
        # Each body is the whole system prompt of every agent of its type: a line here is paid on every launch.
        for name in ("lean-reader", "lean-writer"):
            with self.subTest(agent=name):
                body = instructions.parse(text(name)).body
                self.assertLessEqual(instructions.loaded_lines(body), 15)
                self.assertIn("docs/decisions/2026-10-06-lean-reader-and-writer-types.md", " ".join(body))


class LeanReadingTest(unittest.TestCase):
    """#468: the lean agent files carry the reading rule for code, briefly. issue-task and pr-rebase give theirs the
    whole line in the prompt too; a lean reader or writer launched by another workflow has only its file."""

    def test_the_lean_files_carry_the_reading_line(self) -> None:
        for name in ("task-implementer", "task-publisher", "lean-reader", "lean-writer"):
            with self.subTest(agent=name):
                body = " ".join(" ".join(instructions.parse(text(name)).body).split())
                item = next((part for part in body.split(" - ") if "#468" in part), "")
                for phrase in ("over 400 lines", "`cd <your worktree> && tools/run.sh section <file>`", "`grep -n`",
                               "an edit, a rebase, a checkout, a failed Edit or a compaction", "parallel calls"):
                    self.assertIn(phrase, item)


if __name__ == "__main__":
    unittest.main()
