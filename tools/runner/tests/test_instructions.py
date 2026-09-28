"""Instruction-file lint: frontmatter parsing, loaded-line counting, budgets, agent frontmatter."""

import tempfile
import unittest
from pathlib import Path

from runner import instructions

AGENT = """---
name: helper
description: Read-only helper. Never edits files.
model: sonnet
tools: Read, Grep
disallowedTools: Edit, Write, NotebookEdit, Agent
---

Body.
"""


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))  # exact bytes: write_text would turn "\n" into CRLF on Windows


def lines(n: int) -> str:
    return "".join(f"line {i}\n" for i in range(n))


class ParseTest(unittest.TestCase):
    def test_list_and_scalar(self) -> None:
        fm = instructions.parse('---\npaths:\n  - "**/*.gd"\n  - "tests/**"\nname: x\n---\nbody\n')
        self.assertIsNone(fm.error)
        self.assertEqual(fm.fields, {"paths": ["**/*.gd", "tests/**"], "name": "x"})
        self.assertEqual(fm.body, ["body"])

    def test_unquoted_glob_is_rejected(self) -> None:
        # YAML reads a leading * as an alias; Claude Code would then load the rule unscoped.
        self.assertIn("quote", instructions.parse("---\npaths:\n  - **/*.gd\n---\n").error or "")

    def test_colon_space_in_plain_value_is_rejected(self) -> None:
        self.assertIsNotNone(instructions.parse("---\ndescription: Use it: now\n---\n").error)

    def test_unclosed_frontmatter(self) -> None:
        self.assertIn("closing", instructions.parse("---\nname: x\n").error or "")

    def test_no_frontmatter(self) -> None:
        fm = instructions.parse("# Title\ntext\n")
        self.assertEqual((fm.fields, fm.error, fm.body), ({}, None, ["# Title", "text"]))


class LoadedLinesTest(unittest.TestCase):
    def test_comments_are_free_but_not_inside_code(self) -> None:
        body = [
            "# T",
            "<!-- see docs/interventions/x.md -->",
            "<!--",
            "multi-line note",
            "-->",
            "```",
            "<!-- kept in code -->",
            "```",
            "text <!-- inline --> stays",
        ]
        self.assertEqual(instructions.loaded_lines(body), 5)


class BudgetTest(unittest.TestCase):
    def check(self, files: dict[str, str]) -> instructions.Report:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, text in files.items():
                write(root, rel, text)
            return instructions.check(root)

    def test_within_budgets(self) -> None:
        report = self.check(
            {
                "CLAUDE.md": lines(120),
                "core/CLAUDE.md": lines(100),
                ".claude/rules/gdscript.md": '---\npaths:\n  - "**/*.gd"\n---\n' + lines(60),
                ".claude/agents/helper.md": AGENT,
            }
        )
        self.assertEqual(report.errors, [])
        self.assertIn("launch-time instructions 120/150 lines (CLAUDE.md 120)", report.notes)

    def test_unscoped_rule_counts_toward_root_budget(self) -> None:
        report = self.check({"CLAUDE.md": lines(120), ".claude/rules/style.md": lines(31)})
        self.assertTrue(any("151 lines" in e and "budget 150" in e for e in report.errors), report.errors)

    def test_broken_rule_frontmatter_fails(self) -> None:
        report = self.check({"CLAUDE.md": lines(10), ".claude/rules/x.md": "---\npaths:\n  - **/*.gd\n---\n"})
        self.assertTrue(any("load this rule at every launch" in e for e in report.errors), report.errors)

    def test_nested_and_rule_budgets(self) -> None:
        report = self.check(
            {
                "CLAUDE.md": lines(10),
                "content/CLAUDE.md": lines(101),
                ".claude/rules/big.md": '---\npaths: "tests/**"\n---\n' + lines(61),
                "addons/x/CLAUDE.md": lines(500),
            }
        )
        self.assertEqual(
            sorted(report.errors),
            [".claude/rules/big.md: 61 lines, budget 60", "content/CLAUDE.md: 101 lines, budget 100"],
        )

    def test_missing_root_claude_md(self) -> None:
        self.assertIn("CLAUDE.md is missing at the repo root", self.check({}).errors)

    def test_control_character_in_markdown_fails(self) -> None:
        # The real case: "\r" from a script escape turned `tools\run.cmd` into "tools<CR>un.cmd".
        report = self.check({"CLAUDE.md": "ok\r\n", "docs/x.md": "a\r\n`tools\run.cmd`\n\tindented tab is fine\n"})
        self.assertEqual(report.errors, ["docs/x.md:2: control character 0x0D"])  # CRLF on line 1 is fine

    def test_agent_model_guard_and_read_only(self) -> None:
        bad = AGENT.replace("model: sonnet", "model: fable").replace(", Agent", "")
        report = self.check({"CLAUDE.md": "x\n", ".claude/agents/helper.md": bad})
        joined = " | ".join(report.errors)
        self.assertIn("model: must be one of", joined)
        self.assertIn("disallowedTools: must include Agent", joined)


SKILL = """---
name: start-task
description: Start work on an issue. Use for "start task 42".
argument-hint: "[issue-number]"
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\\run.cmd *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
---

Body.
"""


class SkillTest(unittest.TestCase):
    def problems(self, text: str, folder: str = "start-task") -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "CLAUDE.md", "x\n")
            write(root, f".claude/skills/{folder}/SKILL.md", text)
            return instructions.check(root).errors

    def test_valid_skill(self) -> None:
        self.assertEqual(self.problems(SKILL), [])

    def test_tool_rules_split_outside_parentheses(self) -> None:
        self.assertEqual(
            instructions.tool_rules("Read Grep, Bash(git add *) PowerShell(git add *)"),
            ["Read", "Grep", "Bash(git add *)", "PowerShell(git add *)"],
        )

    def test_bash_rule_needs_a_powershell_twin(self) -> None:
        text = SKILL.replace("  - PowerShell(gh issue view *)\n", "")
        self.assertEqual(self.problems(text), [".claude/skills/start-task/SKILL.md: allowed-tools: Bash(gh issue view *) has no PowerShell twin"])

    def test_section_6_rules(self) -> None:
        cases = {
            "context: fork\n": "context: fork loses the conversation",
            "disable-model-invocation: true\n": "model-invocable",
            "user-invocable: no\n": "user-invocable",
            "allowed_tools: Read\n": "unknown field(s) allowed_tools",
            "shell: cmd\n": "shell: must be",
        }
        for line, text in cases.items():
            with self.subTest(line=line):
                joined = " | ".join(self.problems(SKILL.replace("---\n\nBody", line + "---\n\nBody")))
                self.assertIn(text, joined)

    def test_names(self) -> None:
        self.assertIn("name: must be 'start-task'", " ".join(self.problems(SKILL.replace("name: start-task", "name: begin"))))
        reserved = self.problems(SKILL.replace("name: start-task", "name: doctor"), folder="doctor")
        self.assertTrue(any("bundled /doctor" in p for p in reserved), reserved)

    def test_listing_cap_and_missing_file(self) -> None:
        long = SKILL.replace("Use for", "x" * 1600)
        self.assertTrue(any("listing cuts at 1536" in p for p in self.problems(long)))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "CLAUDE.md", "x\n")
            (root / ".claude" / "skills" / "empty").mkdir(parents=True)
            self.assertIn(".claude/skills/empty/SKILL.md: missing", " ".join(instructions.check(root).errors))


if __name__ == "__main__":
    unittest.main()
