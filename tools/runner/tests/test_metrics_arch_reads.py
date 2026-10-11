"""`metrics --adr-reads`' ARCHITECTURE table (#834): docs/ARCHITECTURE.md's tool reads by role, whole against section,
and the repeats of lines the same agent had read already, over small synthetic transcripts written here (never real
ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import assistant, bash, tool_result, usage, write_lines
from runner.tests.test_metrics_instructions import read

WT = "/d/prime-game/.claude/worktrees/834"
ARCH = metrics.REPO_ROOT / "docs" / "ARCHITECTURE.md"
OUTLINE = ("docs/ARCHITECTURE.md: 900 lines, ~160k tokens (characters / 2.35)\n"
           "# Architecture  [lines 1-900, ~160k tokens]")


def numbered(first: int, last: int) -> str:
    """A Read result as the Read tool returns it (cat -n), lines first to last."""
    return "\n".join(f"{n:6}\tline {n} of the architecture doc" for n in range(first, last + 1))


def section(first: int, last: int, name: str = "§4.5 The host session") -> str:
    """What the runner's `section` prints for one section: its head line, then its lines."""
    return "\n".join([f"--- docs/ARCHITECTURE.md:{first}-{last} {name}"]
                     + [f"line {n} of the architecture doc" for n in range(first, last + 1)])  # fmt: skip


def plain(first: int, last: int) -> str:
    return "\n".join(f"line {n} of the architecture doc" for n in range(first, last + 1))


def sec(tool_id: str, *keys: str) -> dict:
    return bash(tool_id, f"cd {WT} && tools/run.sh section docs/ARCHITECTURE.md {' '.join(keys)}".rstrip())


def edit(tool_id: str) -> dict:
    return {"id": tool_id, "name": "Edit", "input": {"file_path": str(ARCH), "old_string": "a", "new_string": "b"}}


class ArchReadsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "agent.jsonl"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def items(self, steps: list[tuple[dict, str]], compact_after: int | None = None) -> list[dict]:
        """The ARCHITECTURE items of one agent's transcript: each step a tool call and its result; a compaction after
        the step of that index."""
        lines: list[dict] = []
        for i, (tool, text) in enumerate(steps):
            lines += [assistant(2 * i, f"m{i}", usage(write=2000 if i == 0 else 0, read=1000 * i), tool=tool),
                      tool_result(2 * i + 1, tool["id"], text)]  # fmt: skip
            if i == compact_after:
                stamp = tool_result(2 * i + 1.5, "x")["timestamp"]
                lines.append({"type": "system", "subtype": "compact_boundary", "timestamp": stamp})
        lines.append(assistant(2 * len(steps), "end", usage(read=1000)))
        write_lines(self.path, lines)
        data = metrics.read_agent(self.path)
        return [item for item in data["instructions"] if item.get("file") == "docs/ARCHITECTURE.md"]

    def again(self, steps: list[tuple[dict, str]], compact_after: int | None = None) -> list[tuple[int, int]]:
        """(lines read again, lines) of each ARCHITECTURE item; (0, 0) when its lines cannot be told."""
        return [(i.get("arch_again", 0), i.get("arch_lines", 0)) for i in self.items(steps, compact_after)]

    def test_the_same_section_twice_is_a_repeat(self) -> None:
        got = self.again([
            (sec("s0"), OUTLINE),  # the outline: line 0
            (sec("s1", "4.5"), section(100, 140)),
            (sec("s2", "4.5"), section(100, 140)),  # all 41 lines again
            (sec("s3"), OUTLINE),  # the outline again
            (sec("s4", "4.5", "9.3"), section(100, 140) + "\n" + section(500, 509, "§9.3 Bots")),  # partly
        ])  # fmt: skip
        self.assertEqual(got, [(0, 1), (0, 41), (41, 41), (1, 1), (41, 51)])

    def test_a_read_a_cat_and_a_sed_range_count_by_line(self) -> None:
        got = self.again([
            (read("r1", ARCH, offset=130, limit=20), numbered(130, 149)),
            (bash("b1", f"cd {WT} && sed -n 120,135p docs/ARCHITECTURE.md"), plain(120, 135)),  # 130-135 again
            (read("r2", ARCH), numbered(1, 300)),  # whole: 16 + 20 - 6 lines again
            (bash("b2", f"cat {WT}/docs/ARCHITECTURE.md"), plain(1, 300)),  # whole again
        ])  # fmt: skip
        self.assertEqual(got, [(0, 20), (6, 16), (30, 300), (300, 300)])

    def test_a_search_head_or_tail_is_never_a_repeat(self) -> None:
        got = self.again([
            (read("r1", ARCH), numbered(1, 300)),
            ({"id": "g1", "name": "Grep", "input": {"pattern": "host", "path": str(ARCH)}}, "12:host\n40:host"),
            (bash("b1", "grep -n host docs/ARCHITECTURE.md"), "12:host"),
            (bash("b2", "head -n 40 docs/ARCHITECTURE.md"), plain(1, 40)),
            (bash("b3", "tail -n 40 docs/ARCHITECTURE.md"), plain(261, 300)),
            # `section` piped on prints a part of what its head line names.
            (bash("b4", f"cd {WT} && tools/run.sh section docs/ARCHITECTURE.md 4.5 | head -n 20"), section(1, 19)),
            (bash("b5", "tools/run.sh section docs/ARCHITECTURE.md | grep 4.5"), "    4.5 The host session"),
        ])  # fmt: skip
        self.assertEqual(got, [(0, 300), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0)])

    def test_an_edit_a_rebase_or_a_compaction_makes_the_next_read_fresh(self) -> None:
        steps = [(edit("e1"), "ok"), (bash("e1", f"sed -i 's/a/b/' {WT}/docs/ARCHITECTURE.md"), ""),
                 (bash("e1", "git rebase origin/main"), "ok"), (bash("e1", "tools/run.sh publish"), "ok")]
        for step in steps:
            with self.subTest(step=step[0]):
                got = self.again([(sec("s1", "4.5"), section(100, 140)), step, (sec("s2", "4.5"), section(100, 140))])
                # A `sed -i` names the doc, so the instruction table counts it as a read too (whose lines are none).
                self.assertEqual([got[0], got[-1]], [(0, 41), (0, 41)])
        twice = [(sec("s1", "4.5"), section(100, 140)), (sec("s2", "4.5"), section(100, 140))]
        got = self.again(twice, compact_after=0)
        self.assertEqual(got, [(0, 41), (0, 41)])
        # A step that changes nothing keeps them, and another file's edit too.
        other = {"id": "e1", "name": "Edit", "input": {"file_path": str(metrics.REPO_ROOT / "docs" / "GDD.md")}}
        got = self.again([(sec("s1", "4.5"), section(100, 140)), (other, "ok"), (bash("b", "git status"), "clean"),
                          (sec("s2", "4.5"), section(100, 140))])  # fmt: skip
        self.assertEqual(got, [(0, 41), (41, 41)])

    def test_the_role_table(self) -> None:
        def item(how: str, usd: float, again: int = 0, of: int = 0, **extra: object) -> dict:
            got = {"what": "ARCHITECTURE", "how": how, "file": "docs/ARCHITECTURE.md", "tokens": 100.0, "write": 0.0,
                   "rewrite": 0.0, "read": usd, "limited": True, "lines": 40} | extra  # fmt: skip
            return got | ({"arch_again": again, "arch_lines": of} if of else {})

        agents = [
            ("implementer", {"instructions": [
                item("Read", 4.0, 0, 300, limited=False, lines=300),  # whole
                item("Read", 2.0, 300, 300, limited=False, lines=300),  # whole and a repeat
                item("section command", 1.0, 20, 40),  # a partial repeat: half its lines
                item("Grep", 0.5),
                {"what": "root CLAUDE.md", "how": "launch", "file": "CLAUDE.md", "tokens": 1.0, "write": 0.0,
                 "rewrite": 0.0, "read": 9.0},
            ]}),
            ("implementer", {"instructions": [item("section command", 1.0, 0, 40)]}),
            ("code-reviewer", {"instructions": [item("section command", 0.5, 40, 40)]}),
            ("publisher", {"instructions": []}),
        ]  # fmt: skip
        arch = metrics.arch_record(agents)
        rows = {r["role"]: r for r in arch["roles"]}
        self.assertEqual(list(rows), ["implementer", "code-reviewer"], "by list $; an agent with no read is no row")
        impl = rows["implementer"]
        self.assertEqual({k: impl[k] for k in ("agents", "reads", "whole", "section", "small", "repeats", "partial")},
                         {"agents": 2, "reads": 5, "whole": 2, "section": 3, "small": 0, "repeats": 1, "partial": 1})
        self.assertAlmostEqual(impl["usd"], 8.5)
        self.assertAlmostEqual(impl["whole_usd"], 6.0)
        self.assertAlmostEqual(impl["repeat_usd"], 2.5)
        self.assertEqual((arch["all"]["reads"], arch["all"]["repeats"]), (6, 2))
        self.assertAlmostEqual(arch["all"]["repeat_usd"], 3.0)
        text = "\n".join(metrics.arch_section(arch))
        self.assertIn("### ARCHITECTURE.md reads by role (#834)", text)
        self.assertIn("| implementer | 2 | 5 | 2 | 3 | 0 | 1 | 1 |", text)
        self.assertIn("| all roles | 3 | 6 | 2 | 4 | 0 | 2 | 1 |", text)
        self.assertIn("No tool read docs/ARCHITECTURE.md", "\n".join(metrics.arch_section(metrics.arch_record([]))))

    def test_the_table_comes_with_adr_reads(self) -> None:
        from runner.tests.test_metrics import UNTIL
        from runner.tests.test_metrics_adr_reads import Project

        project = Project(Path(self.tmp.name))
        data = metrics.collect([project.dir], {}, None, metrics.parse_time(UNTIL))
        md, record, _compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        self.assertNotIn("### ARCHITECTURE.md reads by role (#834)", md)
        self.assertEqual(record["instructions"]["arch_reads"]["all"]["reads"], 0)
        md, _record, _compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL), adr_reads=True)
        self.assertIn("### ARCHITECTURE.md reads by role (#834)", md)


if __name__ == "__main__":
    unittest.main()
