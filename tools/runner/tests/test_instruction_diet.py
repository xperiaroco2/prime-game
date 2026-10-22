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
)
HUMAN_SESSIONS = common.ROOT / "docs" / "HUMAN_SESSIONS.md"
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
    "only with `publish`",
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
        # #1257: the keep-alive timer left root (workflow agents never wait that long); the manager docs keep it.
        for doc in (common.ROOT / "docs" / "MANAGERS.md", SKILL / "SKILL.md"):
            self.assertIn("background `sleep 3000`", doc.read_text(encoding="utf-8"), doc)

    def test_talking_to_the_humans_is_a_pointer_to_the_doc_that_holds_the_rules(self) -> None:
        # #836: no workflow agent acts on these lines, so a human's chat reads them from the doc, found by this pointer.
        talking = " ".join(next(t for title, t in self.sections.items() if title.startswith("Talking")).split())
        self.assertIn("`docs/HUMAN_SESSIONS.md`", talking)
        for word in ("dictation", "a command for a human", "launching a workflow", "memory", "glossary"):
            self.assertIn(word, talking)
        self.assertLess(len(talking), 600, "a pointer, not the rules again")
        self.assertTrue(HUMAN_SESSIONS.is_file())

    def test_the_human_sessions_doc_is_read_again_after_a_compaction(self) -> None:
        # Review of #836: root is re-injected after a compaction, the doc is not, so each pointer says to read it again.
        talking = " ".join(next(t for title, t in self.sections.items() if title.startswith("Talking")).split())
        managers = " ".join((common.ROOT / "docs" / "MANAGERS.md").read_text(encoding="utf-8").split())
        intro = " ".join(HUMAN_SESSIONS.read_text(encoding="utf-8").split("\n## ")[0].split())
        for where, text in (("root CLAUDE.md", talking), ("docs/MANAGERS.md", managers), ("the doc's intro", intro)):
            self.assertIn("again after a compaction", text, where)

    def test_the_moved_rules_load_from_the_human_sessions_doc(self) -> None:
        doc = sections(HUMAN_SESSIONS.read_text(encoding="utf-8"))
        self.assertEqual(list(doc), ["Talking to the humans", "Launching a workflow", "Memory", "Dictation glossary"])
        self.assertIn("\n- A command for a human goes in the chat itself", "\n" + doc["Talking to the humans"])
        self.assertIn("state the agent count (fewer than 5) and rough cost, wait", " ".join(doc["Launching a workflow"].split()))
        self.assertIn("log-intervention", doc["Memory"])
        self.assertIn("Add a row per real misrecognition", doc["Dictation glossary"])
        self.assertRegex(doc["Dictation glossary"], r"\| Heard \| Meant \|\n\|---\|---\|\n\| ")

    def test_the_moved_rules_are_no_longer_loaded_by_every_agent(self) -> None:
        root = (common.ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        for gone in ("A command for a human goes in the chat itself", "personal → `~/.claude/CLAUDE.md`", "| Heard | Meant |"):
            self.assertNotIn(gone, root)

    def test_what_cites_talking_to_the_humans_names_the_doc(self) -> None:
        for rel in (".claude/skills/finish-task/SKILL.md", ".claude/skills/orchestrate-stage/SKILL.md",
                    ".claude/workflows/issue-task.js", ".claude/workflows/pr-rebase.js"):
            text = " ".join((common.ROOT / rel).read_text(encoding="utf-8").split())
            self.assertNotIn('root `CLAUDE.md`, "Talking to the humans"', text, rel)
            self.assertNotIn('root CLAUDE.md, "Talking to the humans"', text, rel)
            self.assertIn('HUMAN_SESSIONS.md', text, rel)
        managers = (common.ROOT / "docs" / "MANAGERS.md").read_text(encoding="utf-8")
        self.assertIn("HUMAN_SESSIONS.md", managers)

    def test_log_intervention_promotes_a_talking_rule_into_the_human_sessions_doc(self) -> None:
        # Review of #836: without it the next correction on how to talk to a human goes back into root.
        skill = (common.ROOT / ".claude" / "skills" / "log-intervention" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("`docs/HUMAN_SESSIONS.md` for how an agent talks to a human", skill)

    def test_the_dropped_rows_and_sentences_keep_a_pointer(self) -> None:
        # Review of #561: the Routing table's skill rows and the retarget sentence of the Definition of done had none.
        routing = next(text for title, text in self.sections.items() if title.startswith("Routing"))
        self.assertIn("`orchestrate-stage` (`docs/MANAGERS.md`)", routing)
        done = next(text for title, text in self.sections.items() if title.startswith("Definition of done"))
        self.assertIn("`gh pr edit <n> --base <its base>` (AGENT_WORKFLOW §8.5)", " ".join(done.split()))

    def test_every_section_reference_names_its_document(self) -> None:
        root = (common.ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        for match in re.finditer(r"\(§\d", root):
            self.fail(f"a bare section reference at {match.start()}: {root[match.start():match.start() + 12]!r}")

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

    def test_a_handover_start_reads_neither_gotchas_nor_the_kickoff_template(self) -> None:
        # Review of #561: handovers are most manager starts; the index names them only for a stage's first kickoff.
        rows = {name: cell for cell, name in self.rows}
        self.assertIn("not a handover's", self.core.split("[gotchas.md]", 1)[0].splitlines()[-1])
        self.assertIn("not at your own start", self.core.split("[kickoff-template.md]", 1)[0].splitlines()[-1])
        self.assertIn("gotchas.md", rows)

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
