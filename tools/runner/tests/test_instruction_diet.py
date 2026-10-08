"""The trimmed instruction files keep what other files cite (#561).

Root CLAUDE.md keeps every heading other files name ("root CLAUDE.md, Shell") and the Shell rules they point to;
orchestrate-stage's SKILL.md is a core whose index names a file for every section it moved out, and no section
number is lost, since workflow scripts, `wave` and the docs cite "orchestrate-stage §n". The byte budgets
themselves are lint's (instructions.ROOT_BYTES and SKILL_BYTES, test_instructions.py).
"""

import re
import unittest

from runner import common

ROOT_HEADINGS = (
    "Hard rules",
    "Architecture invariants",
    "Commands",
    "Shell",
    "Ownership",
    "Routing",
    "Definition of done",
    "Stop and ask before",
    "Talking to the humans",
    "Memory",
    "Dictation glossary",
)
# The Shell rules other files cite or that keep an unattended run from a prompt or lost work.
SHELL_RULES = (
    "`Remove-Item` go in separate commands",
    "`tests/scratch/`",
    "Push only your task branch",
    "no hand force push",
    "No `git stash`",
    "`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>`",
    "`wait <log>`",
    "block no call over 180 s",
    "`sleep 3000`",
    "AGENT_WORKFLOW §2.2",
)
SKILL = common.ROOT / ".claude" / "skills" / "orchestrate-stage"
INDEX_ROW = re.compile(r"^\| ([^|]+?) \| [^|]+ \| \[([\w.-]+\.md)\]\(\2\) \|$")


def sections(text: str) -> dict[str, str]:
    """Each `## ` heading's title with the text up to the next `## ` heading."""
    found: dict[str, str] = {}
    title = ""
    for line in text.splitlines():
        if line.startswith("## "):
            title = line[3:]
            found[title] = ""
        elif title:
            found[title] += line + "\n"
    return found


def numbered(path) -> set[int]:
    return {int(m) for m in re.findall(r"^## (\d+)\. ", path.read_text(encoding="utf-8"), re.MULTILINE)}


class RootClaudeMdTest(unittest.TestCase):
    def setUp(self) -> None:
        self.sections = sections((common.ROOT / "CLAUDE.md").read_text(encoding="utf-8"))

    def test_it_keeps_the_headings_other_files_cite_in_order(self) -> None:
        titles = list(self.sections)
        self.assertEqual(len(titles), len(ROOT_HEADINGS), titles)
        for title, expected in zip(titles, ROOT_HEADINGS):
            self.assertTrue(title.startswith(expected), (title, expected))

    def test_the_shell_section_keeps_the_rules_others_cite(self) -> None:
        shell = next(text for title, text in self.sections.items() if title.startswith("Shell"))
        for rule in SHELL_RULES:
            self.assertIn(rule, shell)

    def test_the_command_for_a_human_bullet_stays_in_talking_to_the_humans(self) -> None:
        talking = next(text for title, text in self.sections.items() if title.startswith("Talking to the humans"))
        self.assertIn("\n- A command for a human goes in the chat itself", "\n" + talking)

    def test_the_shell_quirks_it_points_to_exist(self) -> None:
        workflow = (common.ROOT / "docs" / "AGENT_WORKFLOW.md").read_text(encoding="utf-8")
        quirks = workflow.split("### 2.2 Shell notes for agents\n", 1)[1].split("\n## 3.", 1)[0]
        for quirk in ("`bash` on PATH is the WSL launcher", "`$PYTHON_BIN`", "arrives as", "%ERRORLEVEL%",
                      "quoted arguments containing spaces"):
            self.assertIn(quirk, quirks)


class OrchestrateStageCoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.core = (SKILL / "SKILL.md").read_text(encoding="utf-8")
        self.rows = [m.groups() for m in map(INDEX_ROW.match, self.core.splitlines()) if m]

    def test_the_index_links_every_file_of_the_skill(self) -> None:
        files = sorted(p.name for p in SKILL.glob("*.md") if p.name != "SKILL.md")
        self.assertEqual(sorted({name for _, name in self.rows}), files)

    def test_every_section_the_index_names_has_its_heading_in_that_file(self) -> None:
        self.assertTrue(self.rows)
        for cell, name in self.rows:
            for number in re.findall(r"§(\d+)", cell):
                self.assertIn(int(number), numbered(SKILL / name), f"{name} lacks '## {number}.' ({cell})")

    def test_no_section_number_is_lost(self) -> None:
        found = set().union(*(numbered(p) for p in SKILL.glob("*.md") if p.name not in ("budget.md", "handover.md")))
        self.assertEqual(found, set(range(1, 11)))

    def test_each_section_left_out_of_the_core_is_in_the_index(self) -> None:
        indexed = {int(n) for cell, _ in self.rows for n in re.findall(r"§(\d+)", cell)}
        self.assertEqual(set(range(1, 11)) - numbered(SKILL / "SKILL.md") - indexed, set())


if __name__ == "__main__":
    unittest.main()
