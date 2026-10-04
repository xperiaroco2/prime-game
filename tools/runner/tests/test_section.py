"""`section <doc> [<§>...]`: a doc's outline and exactly the sections asked for (#338; instruction-diet ADR, N1)."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from runner import cli, section
from runner.common import ROOT, Failure

DOC = """# Doc
Intro.

## 1. One
Text of one.

```
## 9. Not a heading (in a fence)
```

### 1.1 One one
Text of one one.

#### 1.1.1 Deep
Deep text.

## 2. Two [applied]
Text of two.

#### Unnumbered (kind)
Under two.
## 3 Three
Last line.
"""


class HeadingsTest(unittest.TestCase):
    def test_numbers_titles_and_ranges(self) -> None:
        found = section.headings(DOC)
        self.assertEqual(
            [(h.level, h.number, h.title, h.start, h.end) for h in found],
            [
                (1, None, "Doc", 1, 23),
                (2, "1", "One", 4, 16),
                (3, "1.1", "One one", 11, 16),
                (4, "1.1.1", "Deep", 14, 16),
                (2, "2", "Two [applied]", 17, 21),
                (4, None, "Unnumbered (kind)", 20, 21),
                (2, "3", "Three", 22, 23),
            ],
        )

    def test_a_heading_in_a_fence_is_text(self) -> None:
        self.assertNotIn("9", [h.number for h in section.headings(DOC)])

    def test_tildes_fence_too_and_a_backtick_line_inside_does_not_close_it(self) -> None:
        text = "## 1. A\n~~~\n```\n## 2. B\n~~~\n## 3. C\n"
        self.assertEqual([h.number for h in section.headings(text)], ["1", "3"])


class ExtractTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.doc = self.root / "docs" / "DOC.md"
        self.doc.parent.mkdir(parents=True)
        self.doc.write_bytes(DOC.encode("utf-8"))
        self.lines = DOC.splitlines()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_a_section_runs_to_the_next_heading_of_its_level_or_higher(self) -> None:
        out = section.extract(self.doc, ["1"], self.root)
        self.assertEqual(out[0], "--- docs/DOC.md:4-16 §1 One")
        self.assertEqual(out[1:], self.lines[3:16])
        self.assertIn("Deep text.", out)
        self.assertNotIn("## 2. Two [applied]", out)

    def test_each_key_form_and_several_sections_in_order(self) -> None:
        out = section.extract(self.doc, ["§1.1.1", "2.", "§ 3"], self.root)
        heads = [line for line in out if line.startswith("--- ")]
        self.assertEqual(
            heads,
            [
                "--- docs/DOC.md:14-16 §1.1.1 Deep",
                "--- docs/DOC.md:17-21 §2 Two [applied]",
                "--- docs/DOC.md:22-23 §3 Three",
            ],
        )
        self.assertEqual(out[-2:], ["## 3 Three", "Last line."])

    def test_an_unnumbered_heading_by_its_title(self) -> None:
        out = section.extract(self.doc, ["unnumbered"], self.root)
        self.assertEqual(out, ["--- docs/DOC.md:20-21 Unnumbered (kind)", "#### Unnumbered (kind)", "Under two."])

    def test_a_missing_section_fails_and_a_number_never_matches_a_title(self) -> None:
        for key in ("4", "§1.2", "1.1.1.1"):
            with self.assertRaises(Failure, msg=key) as caught:
                section.extract(self.doc, [key], self.root)
            self.assertIn("no such section", str(caught.exception))
        with self.assertRaises(Failure):
            section.extract(self.doc, ["nothing like it"], self.root)

    def test_the_outline_lists_every_heading_with_its_lines_and_tokens(self) -> None:
        rows = section.outline(self.doc, self.root)
        self.assertTrue(rows[0].startswith("docs/DOC.md: 23 lines, ~"), rows[0])
        self.assertEqual(rows[2], "  §1 One  [lines 4-16, ~" + rows[2].split("~")[1])
        self.assertTrue(rows[3].startswith("    §1.1 One one  [lines 11-16, ~"), rows[3])
        self.assertTrue(rows[6].startswith("      Unnumbered (kind)  [lines 20-21, ~"), rows[6])
        self.assertEqual(len(rows), 8)

    def test_tokens_are_characters_over_the_measured_ratio(self) -> None:
        self.assertEqual(section.tokens(["x" * 234]), "~100")  # 235 characters with the newline
        self.assertEqual(section.tokens(["x" * 4699]), "~2.0k")

    def test_a_doc_by_name_path_or_part_of_an_adr(self) -> None:
        (self.root / "docs" / "ARCHITECTURE.md").write_text("# A\n", encoding="utf-8")
        adrs = self.root / "docs" / "decisions"
        adrs.mkdir()
        (adrs / "2026-10-04-instruction-diet.md").write_text("# D\n", encoding="utf-8")
        (adrs / "2026-10-01-m4-first-person-client.md").write_text("# M4\n", encoding="utf-8")
        (adrs / "2026-10-02-m5-voice.md").write_text("# M5\n", encoding="utf-8")
        self.assertEqual(section.doc_path("ARCHITECTURE", self.root).name, "ARCHITECTURE.md")
        self.assertEqual(section.doc_path("architecture", self.root).name, "ARCHITECTURE.md")
        self.assertEqual(section.doc_path("docs/DOC.md", self.root), self.root / "docs" / "DOC.md")
        self.assertEqual(section.doc_path("instruction-diet", self.root).name, "2026-10-04-instruction-diet.md")
        with self.assertRaises(Failure) as caught:
            section.doc_path("-m", self.root)
        self.assertIn("matches 2 ADRs", str(caught.exception))
        with self.assertRaises(Failure):
            section.doc_path("GDD", self.root)


class AmbiguousTitleTest(unittest.TestCase):
    def test_a_title_part_shared_by_two_headings_fails_with_both(self) -> None:
        found = section.headings("## 1. Alpha one\n## 2. Alpha two\n## 3. Beta\n")
        with self.assertRaises(Failure) as caught:
            section.find(found, "alpha")
        self.assertIn("2 headings match", str(caught.exception))
        self.assertIn("line 1: Alpha one", str(caught.exception))
        self.assertEqual(section.find(found, "beta").number, "3")


class RealDocsTest(unittest.TestCase):
    """The repo's own docs: a § read returns its whole section and nothing of the next one."""

    def test_architecture_4_5_holds_its_text_and_stops_before_4_6(self) -> None:
        out = section.extract(ROOT / "docs" / "ARCHITECTURE.md", ["4.5"])
        self.assertTrue(out[0].startswith("--- docs/ARCHITECTURE.md:"), out[0])
        self.assertTrue(out[1].startswith("### 4.5 "), out[1])
        self.assertFalse(any(line.startswith("### 4.6 ") for line in out))
        text = (ROOT / "docs" / "ARCHITECTURE.md").read_text(encoding="utf-8").splitlines()
        end = int(out[0].split(":")[1].split()[0].split("-")[1])
        self.assertTrue(text[end].startswith("### 4.6 "), text[end])

    def test_agent_workflow_has_no_duplicate_section_numbers(self) -> None:
        for name in ("ARCHITECTURE", "AGENT_WORKFLOW"):
            numbers = [h.number for h in section.headings(section.doc_path(name).read_text(encoding="utf-8"))]
            numbered = [n for n in numbers if n]
            self.assertEqual(len(numbered), len(set(numbered)), name)


class CommandTest(unittest.TestCase):
    def run_cli(self, *argv: str) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cli.main(["section", *argv])
        return rc, out.getvalue()

    def test_the_outline_and_a_section_through_the_command(self) -> None:
        rc, out = self.run_cli("AGENT_WORKFLOW")
        self.assertEqual(rc, 0)
        self.assertIn("  §2 Environment  [lines ", out)
        rc, out = self.run_cli("AGENT_WORKFLOW", "§2.1")
        self.assertEqual(rc, 0)
        self.assertIn("### 2.1 ", out)
        self.assertNotIn("## 3. ", out)

    def test_a_missing_section_or_doc_exits_1(self) -> None:
        self.assertEqual(self.run_cli("AGENT_WORKFLOW", "99")[0], 1)
        self.assertEqual(self.run_cli("NO_SUCH_DOC")[0], 1)


if __name__ == "__main__":
    unittest.main()
