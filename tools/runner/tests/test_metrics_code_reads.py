"""`metrics`' code reads per agent role (#468): big whole-file code reads and re-reads, from small synthetic transcripts
written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import assistant, bash, tool_result, usage, write_lines
from runner.tests.test_metrics_instructions import read

WT = "/d/prime-game/.claude/worktrees/468"


def numbered(first: int, last: int, word: str = "code") -> str:
    """A Read result as the Read tool returns it (cat -n), lines first to last."""
    return "\n".join(f"{n:6}\t{word} line {n} of the file" for n in range(first, last + 1))


def chars(text: str, numbers: range) -> int:
    """The characters of these numbered lines of a Read result, each with its newline."""
    return sum(len(line) + 1 for line in text.split("\n") if int(line.split("\t")[0]) in numbers)


class CodeReadTest(unittest.TestCase):
    def test_which_calls_are_code_reads(self) -> None:
        root = metrics.REPO_ROOT
        whole = metrics.code_read("Read", {"file_path": str(root / "tools" / "x.py")})
        self.assertEqual(whole, [("tools/x.py", True, None)])
        part = metrics.code_read("Read", {"file_path": f"D:{WT}/core/a.gd", "offset": 10, "limit": 5})
        self.assertEqual(part, [("core/a.gd", False, None)])
        self.assertEqual(metrics.code_read("Read", {"file_path": str(root / "docs" / "X.md")}), [])
        self.assertEqual(metrics.code_read("Read", {"file_path": "C:/elsewhere/y.py"}), [])
        self.assertEqual(metrics.code_read("Bash", {"command": f"cd {WT} && cat tools/y.gd"}), [("tools/y.gd", True, [])])
        sed = metrics.code_read("Bash", {"command": f"cd {WT} && sed -n '1,5p;9,12p' {WT}/tools/x.py"})
        self.assertEqual(sed, [("tools/x.py", False, [(1, 5), (9, 12)])])
        piped = metrics.code_read("PowerShell", {"command": "sed -n 7p tools/x.py | cut -c1-80"})
        self.assertEqual(piped, [("tools/x.py", False, [(7, 7)])])
        # Each step of a chain counts; an echo between them or a `;` inside the sed script splits nothing.
        chain = "sed -n 1,60p a/b.gd && echo ---- && sed -n '170,215p;300p' a/b.gd; sed -n 5p c.js 2>/dev/null"
        self.assertEqual(
            metrics.code_read("Bash", {"command": chain}),
            [("a/b.gd", False, [(1, 60)]), ("a/b.gd", False, [(170, 215), (300, 300)]), ("c.js", False, [(5, 5)])],
        )
        for command in (f"cd {WT} && cat tools/y.gd | head", "cat docs/ARCHITECTURE.md", "sed -n 1,5p README",
                        "git show HEAD:tools/x.py", "cat a.py b.py", "sed -n '/def f/,/^def/p' tools/x.py",
                        "cat > tools/x.py <<'EOF'", "sed -i 's/a/b/' tools/x.py"):
            with self.subTest(command=command):
                self.assertEqual(metrics.code_read("Bash", {"command": command}), [])
        self.assertEqual(metrics.code_read("Grep", {"path": str(root / "tools" / "x.py")}), [])
        self.assertEqual(metrics.code_edits(f"cd {WT} && sed -i 's/a;b/c/' tools/x.py && sed -n 3p tools/x.py"),
                         ["tools/x.py"])


class CodeReadsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "agent.jsonl"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def counts(self, calls: list[tuple[dict, str]]) -> dict:
        lines: list[dict] = []
        for index, (tool, text) in enumerate(calls):
            lines.append(assistant(index, f"m{index}", usage(inp=10, out=5), tool=tool))
            lines.append(tool_result(index + 0.5, tool["id"], text))
        write_lines(self.path, lines)
        return metrics.read_agent(self.path)["code_reads"]

    def test_big_reads_and_re_reads(self) -> None:
        x_py = metrics.REPO_ROOT / "tools" / "x.py"
        first, shifted, whole = numbered(1, 20), numbered(11, 30), numbered(1, 500)
        gd, small, part = numbered(1, 450, "gd"), numbered(1, 300), numbered(3, 12, "gd")
        sed = numbered(1, 9, "sed")
        got = self.counts([
            (read("r1", x_py, offset=1, limit=20), first),
            (read("r2", x_py, offset=1, limit=20), first),  # a whole re-read
            (read("r3", x_py, offset=11, limit=20), shifted),  # a partial re-read: lines 11 to 20
            (read("r4", metrics.REPO_ROOT / "docs" / "X.md"), whole),  # a doc: #337's, not counted here
            (bash("b1", f"cd {WT} && cat tools/y.gd"), gd),  # big
            (read("r5", metrics.REPO_ROOT / "tools" / "small.py"), small),  # whole, but 300 lines
            ({"id": "e1", "name": "Edit", "input": {"file_path": str(x_py)}}, "ok"),
            (read("r6", x_py), whole),  # big; after the edit, not a re-read
            (read("r7", x_py), "File unchanged since last read. The content from the earlier Read is current."),
            (bash("b2", f"cd {WT} && git rebase origin/main"), "Successfully rebased"),
            (bash("b3", f"cd {WT} && sed -n '1,5p;9,12p' tools/y.gd"), sed),  # after the rebase, not a re-read
            (bash("b4", f"cd {WT} && sed -n '1,5p;9,12p' tools/y.gd"), sed),  # a whole re-read
            (bash("b5", f"cd {WT} && sed -i 's/x/y/' tools/y.gd && sed -n '1,5p;9,12p' tools/y.gd"), sed),  # edited: no
            (read("r8", metrics.REPO_ROOT / "tools" / "y.gd", offset=3, limit=10), part),  # partial: 3 to 5, 9 to 12
        ])
        self.assertEqual((got["big"], got["repeat"], got["partial"]), (2, 2, 2))
        self.assertAlmostEqual(got["big_tokens"], (len(gd) + len(whole)) / metrics.CHARS_PER_TOKEN)
        again = chars(first, range(1, 21)) + chars(shifted, range(11, 21)) + len(sed) + chars(part, range(3, 6))
        again += chars(part, range(9, 13))
        self.assertAlmostEqual(got["repeat_tokens"], again / metrics.CHARS_PER_TOKEN)

    def test_a_compaction_forgets_what_was_read(self) -> None:
        x_py = metrics.REPO_ROOT / "tools" / "x.py"
        text = numbered(1, 30)
        lines = [
            assistant(0, "m0", usage(inp=10), tool=read("r1", x_py)),
            tool_result(0.5, "r1", text),
            {"type": "system", "subtype": "compact_boundary", "timestamp": tool_result(1, "r1")["timestamp"]},
            assistant(2, "m1", usage(inp=10), tool=read("r2", x_py)),
            tool_result(2.5, "r2", text),
        ]
        write_lines(self.path, lines)
        got = metrics.read_agent(self.path)["code_reads"]
        self.assertEqual((got["repeat"], got["partial"]), (0, 0))

    def test_the_role_table(self) -> None:
        def agent(role: str, calls: int, usd: float, big: int, repeat: int, partial: int) -> dict:
            reads = {"big": big, "big_tokens": 4000.0 * big, "repeat": repeat, "partial": partial,
                     "repeat_tokens": 1000.0 * (repeat + partial)}
            tokens = {"usd_input": usd, "usd_cache_write": 0.0, "usd_cache_read": 0.0, "usd_output": 0.0}
            return {"role": role, "data": {"start": 1.0, "tool_calls": calls, "tokens": tokens, "code_reads": reads}}

        counted = [
            {"agents": [agent("implement", 100, 6.0, 3, 1, 2), agent("review", 20, 1.0, 1, 0, 0)]},
            {"agents": [agent("implement", 60, 4.0, 1, 3, 0), {"role": "review", "data": None}]},
        ]
        md = metrics.code_read_section(counted)
        self.assertEqual(md[0], "## Code reads per agent role (#468)")
        body = "\n".join(md)
        self.assertIn("| implement | 2 | 80.0 | $5.00 | 4 (2.00) | 16k | 4 / 2 (3.00) | 6k |", body)
        self.assertIn("| review | 1 | 20.0 | $1.00 | 1 (1.00) | 4k | 0 / 0 (0.00) | 0k |", body)
        self.assertLess(body.index("| implement |"), body.index("| review |"))
        self.assertEqual(metrics.code_read_section([{"agents": []}]), [])


if __name__ == "__main__":
    unittest.main()
