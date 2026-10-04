"""lint's § check (#338): a duplicate § in a doc and a § reference to ARCHITECTURE or AGENT_WORKFLOW that resolves to
no heading fail; which doc a § belongs to follows the instruction-diet ADR's scope rules."""

import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, lint, refs
from runner.common import ROOT

ARCH = "# Architecture\n## 1. Layers\n### 1.1 Sub\n## 4. Protocol\n### 4.5 Host\n#### 4.5.1 Ticks\n"
FLOW = "# Agent Workflow\n## 3. Files\n## 11. Godot\n### 2.1 Cloud\n"
DOCS = {"docs/ARCHITECTURE.md": ARCH, "docs/AGENT_WORKFLOW.md": FLOW}


def check(files: dict[str, str]) -> refs.Report:
    return refs.check(Path("."), {**DOCS, **files})


def docs_of(path: str, text: str, texts: dict[str, str] | None = None) -> list[str | None]:
    """The doc each § reference of a file belongs to."""
    texts = {**DOCS, **(texts or {}), path: text}
    own = refs.own_doc(path, text)
    declared = None if own else refs.declared_doc(path, texts)
    return [doc for _, _, doc in refs.references(path, text, own, declared)]


class ScopeTest(unittest.TestCase):
    def test_a_doc_named_before_it_in_the_same_sentence(self) -> None:
        self.assertEqual(
            docs_of("x.md", "See `docs/ARCHITECTURE.md` §4.5 and §1, then AGENT_WORKFLOW.md §11 and §3."),
            ["ARCHITECTURE", "ARCHITECTURE", "AGENT_WORKFLOW", "AGENT_WORKFLOW"],
        )

    def test_a_sentence_can_cross_a_line_break(self) -> None:
        text = "The design (ARCHITECTURE\n§4.5 and the rest\nof §1).\n"
        self.assertEqual(docs_of("x.md", text), ["ARCHITECTURE"] * 2)

    def test_the_doc_named_right_after_it(self) -> None:
        text = "AGENT_WORKFLOW §3, §4.5 of ARCHITECTURE, §11 in `docs/AGENT_WORKFLOW.md`, §1 of the M5 ADR."
        self.assertEqual(docs_of("x.md", text), ["AGENT_WORKFLOW", "ARCHITECTURE", "AGENT_WORKFLOW", "other"])

    def test_a_doc_named_after_it_with_a_section_of_its_own_takes_that_section_only(self) -> None:
        text = "## 2. Design\nIt puts §2.4 in `ARCHITECTURE.md` §4, and §2 of ARCHITECTURE.\n"
        self.assertEqual(docs_of("docs/decisions/2026-x.md", text), ["other", "ARCHITECTURE", "ARCHITECTURE"])

    def test_a_docs_own_section_beats_a_doc_named_in_an_earlier_sentence(self) -> None:
        text = "The designer (`docs/AGENT_WORKFLOW.md` §11). Its classes are data (§4.5), the rest (§1).\n"
        self.assertEqual(docs_of("docs/ARCHITECTURE.md", text), ["AGENT_WORKFLOW", "ARCHITECTURE", "ARCHITECTURE"])

    def test_in_a_file_without_sections_the_paragraph_names_the_doc(self) -> None:
        text = "# Design: ARCHITECTURE §4.5.\n# The ticks come first (§4.5.1).\nvar x := 1  # (§1)\n\n# (§4.5)\n"
        self.assertEqual(docs_of("tools/a.gd", text), ["ARCHITECTURE", "ARCHITECTURE", None, None])

    def test_a_list_item_and_a_table_row_are_paragraphs_of_their_own(self) -> None:
        text = "- AGENT_WORKFLOW §3.\n- Then §4.5.\n\n| a | ARCHITECTURE §1. |\n| b | §1.1 |\n"
        self.assertEqual(docs_of("notes.md", text), ["AGENT_WORKFLOW", None, "ARCHITECTURE", None])

    def test_a_code_file_takes_its_area_claude_md_first_doc_link(self) -> None:
        area = {"core/CLAUDE.md": "# core\nRead the root `CLAUDE.md`. Design: `docs/ARCHITECTURE.md` (§3, §9).\n"}
        self.assertEqual(docs_of("core/match/m.gd", "## The loop (§3.1).\n", area), ["ARCHITECTURE"])
        self.assertEqual(docs_of("core/CLAUDE.md", area["core/CLAUDE.md"], area), ["ARCHITECTURE", "ARCHITECTURE"])
        gdd = {"content/CLAUDE.md": "# content\nRead `docs/GDD.md` and `docs/ARCHITECTURE.md`.\n"}
        self.assertEqual(docs_of("content/a.tres", "; §9 rules\n", gdd), ["other"])
        self.assertEqual(docs_of("tests/a.gd", "# (§9.4)\n", area), [None])  # the root's CLAUDE.md declares nothing

    def test_other_docs_and_adrs_own_their_sections(self) -> None:
        self.assertEqual(
            docs_of("x.md", "KICKOFF §4, the M5 ADR's §1.1, `docs/GDD.md` §2, `AGENT_WORKFLOW-proposal.md` §12.4."),
            ["other"] * 4,
        )
        adr = "## Decision\nIts §3 and ARCHITECTURE §4.5.\n"
        self.assertEqual(docs_of("docs/decisions/2026-x.md", adr), ["other", "ARCHITECTURE"])
        self.assertEqual(docs_of(".claude/skills/s/SKILL.md", "## 2. Launch\nAs in §2.8.\n"), ["other"])


class CheckTest(unittest.TestCase):
    def test_references_that_resolve_pass_and_are_counted(self) -> None:
        report = check({"core/x.gd": "# ARCHITECTURE §4.5.1 and §1.1; AGENT_WORKFLOW §2.1.\n"})
        self.assertEqual(report.errors, [])
        self.assertEqual(report.resolved, 3)

    def test_a_dangling_reference_fails_with_its_file_and_line(self) -> None:
        report = check({"core/x.gd": "extends Node\n# ARCHITECTURE §4.6 and §4.5\n", "a.md": "AGENT_WORKFLOW §8.2"})
        self.assertEqual(
            report.errors,
            [
                "a.md:1: §8.2 is not a section of docs/AGENT_WORKFLOW.md",
                "core/x.gd:2: §4.6 is not a section of docs/ARCHITECTURE.md",
            ],
        )

    def test_a_docs_own_dangling_reference_fails(self) -> None:
        report = check({"docs/ARCHITECTURE.md": ARCH + "Text (§4.6).\n"})
        self.assertEqual(report.errors, ["docs/ARCHITECTURE.md:7: §4.6 is not a section of docs/ARCHITECTURE.md"])

    def test_no_doc_in_scope_and_other_docs_are_reported_not_failed(self) -> None:
        report = check({"tests/a.gd": "# (§99)\n", "b.md": "KICKOFF §99\n"})
        self.assertEqual(report.errors, [])
        self.assertEqual(report.unscoped, ["tests/a.gd:1: §99"])
        self.assertEqual(report.other, 1)
        self.assertIn("1 have no doc in scope", report.notes[0])

    def test_a_duplicate_section_number_fails(self) -> None:
        report = check({"docs/AGENT_WORKFLOW.md": FLOW + "## 3. Again\n", "docs/decisions/x.md": "## 1. A\n## 1. B\n"})
        self.assertEqual(
            report.errors,
            [
                "docs/AGENT_WORKFLOW.md: §3 is the number of more than one heading",
                "docs/decisions/x.md: §1 is the number of more than one heading",
            ],
        )

    def test_a_section_in_a_fence_neither_counts_nor_duplicates(self) -> None:
        fenced = FLOW + "```\n## 3. Example\n## 7. Example\n```\n"
        report = check({"docs/AGENT_WORKFLOW.md": fenced, "a.md": "AGENT_WORKFLOW §7\n"})
        self.assertEqual(report.errors, ["a.md:1: §7 is not a section of docs/AGENT_WORKFLOW.md"])


class TrackedTest(unittest.TestCase):
    def test_only_tracked_text_files_outside_the_archive_addons_and_these_examples(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            files = {
                "a.md": b"AGENT_WORKFLOW \xc2\xa799\n",
                "docs/history/old.md": b"x",
                "addons/x/README.md": b"x",
                "bin.dll": b"MZ\0\0",
                "untracked.md": b"x",
                "tools/runner/refs.py": b"x",
            }
            for name, data in files.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_bytes(data)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "a.md", "docs", "addons", "bin.dll", "tools"], check=True)
            self.assertEqual(sorted(refs.tracked_texts(root)), ["a.md"])


class LintTest(unittest.TestCase):
    def test_lint_fails_on_a_dangling_reference_and_prints_the_fix(self) -> None:
        bad = refs.Report(errors=["a.md:1: §9 is not a section of docs/AGENT_WORKFLOW.md"])
        out = io.StringIO()
        with mock.patch.object(refs, "check", return_value=bad), contextlib.redirect_stdout(out):
            self.assertTrue(lint.section_refs())
        self.assertIn("FAIL  a.md:1: §9", out.getvalue())
        self.assertIn("never renumber a section", out.getvalue())

    def test_lint_passes_with_the_counts(self) -> None:
        out = io.StringIO()
        with mock.patch.object(refs, "check", return_value=refs.Report(resolved=5)):
            with contextlib.redirect_stdout(out):
                self.assertFalse(lint.section_refs())
        self.assertIn("ok    § references: 5 to ARCHITECTURE and AGENT_WORKFLOW resolve", out.getvalue())

    def test_the_repo_resolves(self) -> None:
        """The same check as `lint`, on this checkout: every § reference to the two docs resolves."""
        self.assertEqual(refs.check(ROOT).errors, [])

    def test_refs_lists_the_unscoped_ones(self) -> None:
        report = refs.Report(unscoped=["tests/a.gd:1: §9"])
        out = io.StringIO()
        with mock.patch.object(refs, "check", return_value=report), contextlib.redirect_stdout(out):
            self.assertEqual(cli.main(["section", "--refs"]), 0)
        self.assertIn("note  tests/a.gd:1: §9: no doc in scope", out.getvalue())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["section", "--refs", "ARCHITECTURE"]), 2)
            self.assertEqual(cli.main(["section"]), 2)


if __name__ == "__main__":
    unittest.main()
