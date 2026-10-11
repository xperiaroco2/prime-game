"""`metrics --adr-reads` (#793): the ADR reads by file, whole against section, over a small synthetic transcript written
here (never a real one): how each tool call is told whole from a section read, and the table's rows."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import UNTIL, Fixture, assistant, bash, tool_result, usage, write_lines
from runner.tests.test_metrics_instructions import ROOT, SID, instructions, read

ADR = ROOT / "docs" / "decisions"
A, B, C = (ADR / f"2026-10-0{n}-{name}.md" for n, name in ((1, "alpha"), (2, "beta"), (3, "gamma")))
REL_A, REL_B, REL_C = (f"docs/decisions/{p.name}" for p in (A, B, C))


def lines(n: int) -> str:
    return "\n".join(f"{i:6}\tline {i} of an ADR" for i in range(1, n + 1))


def calls(tag: str, *steps: tuple[dict, str]) -> list[dict]:
    """The transcript lines of a tool call per step: the call, then its result."""
    out: list[dict] = []
    for i, (tool, text) in enumerate(steps):
        out += [assistant(2 * i, f"{tag}-m{i}", usage(write=2000 if i == 0 else 0, read=1000 * i), tool=tool),
                tool_result(2 * i + 1, tool["id"], text)]  # fmt: skip
    return out


class Project:
    def __init__(self, root: Path) -> None:
        self.dir = root / "projects" / "D--prime-game"
        wf = self.dir / SID / "subagents" / "workflows" / "wf_adr"
        impl = [instructions(0, (ROOT / "CLAUDE.md", 2350))] + calls(
            "i",
            (read("r1", A), lines(200)),  # whole
            (read("r2", A, offset=10, limit=20), lines(20)),  # section: a limit
            (bash("b1", f"cat {REL_B}"), lines(200)),  # whole: cat
            (bash("b2", f"cd /d/{ROOT.name} && sed -n 1,30p {REL_B}"), lines(30)),  # section: a range
            (bash("b3", f"tools/run.sh section {REL_B} 3"), lines(40)),  # section: the runner's command
            (read("r3", C), lines(20)),  # small: a short file in full
            ({"id": "g1", "name": "Grep", "input": {"pattern": "x", "path": str(A)}}, lines(8)),  # section: a Grep
            (bash("b4", f"git show HEAD:{REL_A}"), lines(300)),  # no read
            (bash("b5", f"head -n 40 {REL_C}"), lines(40)),  # section: head
        )
        review = [instructions(0, (ROOT / "CLAUDE.md", 2350))] + calls("c", (read("c1", A), lines(200)))
        Fixture.run(wf, [
            ("k-i", "a-impl", "implement:#40", "Implement", {"verify_green": True}, impl),
            ("k-c", "a-code", "review:code:#40", "Review", {"findings": []}, review),
        ])  # fmt: skip
        write_lines(self.dir / f"{SID}.jsonl", [assistant(0, "msg-m0", usage(write=1000))])


class AdrReadsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Project(Path(self.tmp.name))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self, **kwargs: object):
        data = metrics.collect([self.project.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL), **kwargs)

    def rows(self) -> dict[str, dict]:
        _md, record, _compact = self.build()
        adr = record["instructions"]["adr_reads"]
        return {f["file"]: f for f in adr["top"]}

    def test_each_read_is_whole_section_or_small(self) -> None:
        rows = self.rows()
        self.assertEqual({k: (v["reads"], v["whole"], v["section"], v["small"]) for k, v in rows.items()},
                         {REL_A: (4, 2, 2, 0), REL_B: (3, 1, 2, 0), REL_C: (2, 0, 1, 1)})  # fmt: skip

    def test_tokens_cost_and_roles_per_file(self) -> None:
        rows = self.rows()
        chars = sum(len(lines(n)) for n in (200, 30, 40))
        self.assertAlmostEqual(rows[REL_B]["tokens"], chars / metrics.CHARS_PER_TOKEN)
        self.assertGreater(rows[REL_A]["usd"], 0)
        self.assertLessEqual(rows[REL_A]["whole_usd"], rows[REL_A]["usd"])
        self.assertEqual({r.rsplit(" ", 1)[0] for r in rows[REL_A]["roles"]}, {"implementer", "code-reviewer"})
        self.assertEqual(rows[REL_C]["whole_usd"], 0.0)
        usd = [f["usd"] for f in self.build()[1]["instructions"]["adr_reads"]["top"]]
        self.assertEqual(usd, sorted(usd, reverse=True), "the top files come by list $")

    def test_the_table_is_shown_only_on_request(self) -> None:
        md, _record, _compact = self.build()
        self.assertNotIn("### ADR reads by file (#793)", md)
        md, record, _compact = self.build(adr_reads=True)
        self.assertIn("### ADR reads by file (#793)", md)
        text = "\n".join(md)
        self.assertIn("| `2026-10-01-alpha.md` | 4 | 2 | 2 | 0 |", text)
        self.assertIn("all 3 files | 9 | 3 | 5 | 1 |", text)
        self.assertEqual(record["instructions"]["adr_reads"]["all"]["reads"], 9)

    def test_the_top_is_cut_at_ten(self) -> None:
        agents = [("implementer", {"instructions": [
            {"what": "ADRs", "how": "Read", "file": f"docs/decisions/{n:02}.md", "tokens": 10.0, "write": 0.0,
             "rewrite": 0.0, "read": float(n), "limited": False, "lines": 200} for n in range(12)]})]  # fmt: skip
        adr = metrics.adr_record(agents)
        self.assertEqual((adr["files"], len(adr["top"]), adr["all"]["reads"]), (12, 10, 12))
        self.assertEqual(adr["top"][0]["file"], "docs/decisions/11.md")

    def test_no_adr_read_says_so(self) -> None:
        agents = [("implementer", {"instructions": [{"what": "root CLAUDE.md", "how": "launch", "file": "CLAUDE.md",
                                                     "tokens": 1.0, "write": 0.0, "rewrite": 0.0, "read": 0.0}]})]
        self.assertIn("No tool read an ADR", "\n".join(metrics.adr_section(metrics.adr_record(agents))))


class ReadScopeTest(unittest.TestCase):
    def test_which_calls_ask_for_a_part(self) -> None:
        cases = [
            ("Read", {"file_path": "x.md"}, False), ("Read", {"file_path": "x.md", "offset": 5}, True),
            ("Read", {"file_path": "x.md", "limit": 30}, True), ("Bash", {"command": "cat x.md"}, False),
            ("Bash", {"command": "sed -n '1,9p' x.md"}, True), ("Bash", {"command": "head -n 5 x.md"}, True),
            ("Bash", {"command": "tail -20 x.md"}, True), ("PowerShell", {"command": "Get-Content x.md -TotalCount 9"}, True),
            ("PowerShell", {"command": "Get-Content x.md"}, False), ("Grep", {"path": "x.md"}, False),
            ("Bash", {"command": "cat x.md | head -n 5"}, True), ("Bash", {"command": "cat x.md|tail"}, True),
            ("PowerShell", {"command": "Get-Content x.md | Select-Object -First 9"}, True),
            # A path that holds a parameter's or a command's name is still a whole read (#793 review).
            ("Bash", {"command": "cat docs/decisions/2026-10-01-m4-first-person-client.md"}, False),
            ("PowerShell", {"command": "Get-Content docs\\decisions\\2026-10-01-m4-first-person-client.md"}, False),
            ("Bash", {"command": "cat docs/decisions/2026-09-28-godot-editor-save-first-convention.md"}, False),
            ("Bash", {"command": "cat docs/decisions/2026-10-11-head-tail-sed-n.md"}, False),
        ]  # fmt: skip
        for name, inp, expected in cases:
            with self.subTest(name=name, inp=inp):
                self.assertEqual(metrics.read_limited(name, inp), expected)

    def test_the_runners_section_command_is_a_section_read(self) -> None:
        self.assertEqual(metrics.doc_targets("Bash", {"command": f"cd /d/x && tools/run.sh section {REL_A} 4"}),
                         [(REL_A, "section command", "section")])
        self.assertEqual(metrics.doc_targets("Bash", {"command": "tools/run.sh section tools/runner/cli.py"}), [])
        # A `cat` beside the `section` step is a plain read of its doc, a `git diff` beside it none (#793 review).
        both = f"cd /d/x && tools/run.sh section {REL_A} 2; cat {REL_B}; git diff {REL_C}"
        self.assertEqual(metrics.doc_targets("Bash", {"command": both}),
                         [(REL_A, "section command", "section"), (REL_B, "shell read", "plain")])  # fmt: skip
        item = metrics.read_items([(REL_A, "section command", "section")], "x\ny")[0]
        self.assertEqual((item["limited"], item["lines"]), (True, 2))
        self.assertNotIn("text", metrics.read_items([("docs/ARCHITECTURE.md", "section command", "section")], "x")[0])

    def test_scope_of_an_item(self) -> None:
        self.assertEqual(metrics.read_scope({"limited": True, "lines": 900}), "section")
        self.assertEqual(metrics.read_scope({"limited": False, "lines": 151}), "whole")
        self.assertEqual(metrics.read_scope({"limited": False, "lines": 150}), "small")


if __name__ == "__main__":
    unittest.main()
