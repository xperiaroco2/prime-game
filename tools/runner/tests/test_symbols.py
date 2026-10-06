"""`section <code file> [<symbol>...]`: a .py, .gd or .js file's outline and exactly the symbols asked for (#468)."""

import re
import tempfile
import unittest
from pathlib import Path

from runner import symbols
from runner.common import ROOT, Failure

PY = '''"""Module doc."""

import os
from dataclasses import dataclass

# The thing.
# Two lines of comment.
@dataclass
class Thing:
    size: int

    # A method's comment.
    def grow(self) -> None:
        self.size += 1

    @staticmethod
    def make() -> "Thing":
        return Thing(1)


# Leading.
def top(a: int) -> int:
    return a


TABLE = {
    "a": 1,
    "b": 2,
}


async def later() -> None:
    pass


for name in ["x", "y"]:
    print(name)
    print(name)
    print(name)
    print(name)
    print(name)

if __name__ == "__main__":
    top(1)
'''

GD = '''extends Node
class_name Thing

signal moved(to: Vector3)
const SPEED := 4.0
@export var label: String = ""

# Sends a move.
@rpc("any_peer")
func send(to: Vector3) -> void:
\tmoved.emit(to)


static func make() -> Thing:
\treturn Thing.new()


const HELP := """
func fake():
\tpass
"""


class Inner:
\tvar size := 1

\tfunc grow() -> void:
\t\tsize += 1

\t# Shrinks.
\tfunc shrink() -> void:
\t\tsize -= 1


func last(
\ta: int,
) -> int:
\treturn a
'''

JS = r"""export const meta = {
  name: 'x',
}

const RULES = [
  'one',
  `two ${'three'}`,
].filter(Boolean).join('\n')

const TEXT = `first
const NOT = 1
${RULES} last`

// Does f.
function f(a) {
  return a
}

async function g() {
  return 1
}

const RE = /it's/
const Q = 'it\'s'
const P = 'D:\\'
const AFTER = 1
if (AFTER) {
  log(1)
  log(2)
  log(3)
  log(4)
}
log(`${AFTER}`)
"""

FIND = """class A:
    def setUp(self) -> None:
        pass


class B:
    def setUp(self) -> None:
        pass

    def setup_more(self) -> None:
        pass


def Helper() -> None:
    pass


for x in range(3):
    print(x)
    print(x)
    print(x)
    print(x)
    print(x)
"""


def rows(found: list[symbols.Symbol]) -> list[tuple[int, str, str, int, int]]:
    return [(s.level, s.kind, s.qualified, s.start, s.end) for s in found]


class PythonTest(unittest.TestCase):
    def test_symbols_kinds_and_ranges(self) -> None:
        self.assertEqual(
            rows(symbols.symbols(PY, ".py")),
            [
                (1, "class", "Thing", 6, 18),
                (2, "def", "Thing.grow", 12, 14),
                (2, "def", "Thing.make", 16, 18),
                (1, "def", "top", 21, 23),
                (1, "assign", "TABLE", 26, 29),
                (1, "async def", "later", 32, 33),
                (1, "block", 'for name in ["x", "y"]:', 36, 41),
            ],
        )

    def test_a_file_that_does_not_parse_fails_with_a_grep_hint(self) -> None:
        with self.assertRaises(Failure) as caught:
            symbols.symbols("def f(:\n", ".py")
        self.assertIn("does not parse (line 1)", str(caught.exception))
        self.assertIn("grep -n", str(caught.exception))


class GdscriptTest(unittest.TestCase):
    def test_symbols_kinds_and_ranges(self) -> None:
        self.assertEqual(
            rows(symbols.symbols(GD, ".gd")),
            [
                (1, "signal", "moved", 4, 4),
                (1, "const", "SPEED", 5, 5),
                (1, "var", "label", 6, 6),
                (1, "func", "send", 8, 11),
                (1, "static func", "make", 14, 15),
                (1, "const", "HELP", 18, 21),
                (1, "class", "Inner", 24, 32),
                (2, "func", "Inner.grow", 27, 28),
                (2, "func", "Inner.shrink", 30, 32),
                (1, "func", "last", 35, 38),
            ],
        )


class JavascriptTest(unittest.TestCase):
    def test_symbols_kinds_and_ranges(self) -> None:
        self.assertEqual(
            rows(symbols.symbols(JS, ".js")),
            [
                (1, "const", "meta", 1, 3),
                (1, "const", "RULES", 5, 8),
                (1, "const", "TEXT", 10, 12),
                (1, "function", "f", 14, 17),
                (1, "async function", "g", 19, 21),
                (1, "const", "RE", 23, 23),
                (1, "const", "Q", 24, 24),
                (1, "const", "P", 25, 25),
                (1, "const", "AFTER", 26, 26),
                (1, "block", "if (AFTER) {", 27, 32),
            ],
        )

    def test_a_jsdoc_comment_leads_its_function(self) -> None:
        text = "const A = 1\n\n/**\n * Does f.\n */\nfunction f() {\n  return 1\n}\n"
        self.assertEqual(rows(symbols.symbols(text, ".js"))[1], (1, "function", "f", 3, 8))


class FindTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.path = self.root / "tools" / "x.py"
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(FIND.encode("utf-8"))
        self.found = symbols.symbols(FIND, ".py")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_each_key_form(self) -> None:
        self.assertEqual(symbols.find(self.found, "B.setUp").start, 7)
        self.assertEqual(symbols.find(self.found, "Helper").qualified, "Helper")
        self.assertEqual(symbols.find(self.found, "helper").qualified, "Helper")
        self.assertEqual(symbols.find(self.found, "b.setup").qualified, "B.setUp")
        self.assertEqual(symbols.find(self.found, "setup_m").qualified, "B.setup_more")

    def test_an_ambiguous_or_missing_name_fails(self) -> None:
        with self.assertRaises(Failure) as caught:
            symbols.find(self.found, "setUp")
        self.assertIn("line 2: def A.setUp", str(caught.exception))
        self.assertIn("line 7: def B.setUp", str(caught.exception))
        for key in ("nothing", "for", "4.5"):
            with self.assertRaises(Failure, msg=key) as caught:
                symbols.find(self.found, key)
            self.assertIn("no such symbol", str(caught.exception))

    def test_several_symbols_in_order_each_whole(self) -> None:
        lines = FIND.splitlines()
        out = symbols.extract(self.path, ["Helper", "A.setUp"], self.root)
        self.assertEqual(out[0], "--- tools/x.py:14-15 def Helper")
        self.assertEqual(out[1:3], lines[13:15])
        self.assertEqual(out[3], "--- tools/x.py:2-3 def A.setUp")
        self.assertEqual(out[4:], lines[1:3])

    def test_the_outline_rows(self) -> None:
        out = symbols.outline(self.path, self.root)
        self.assertTrue(out[0].startswith("tools/x.py: 23 lines, ~"), out[0])
        self.assertTrue(out[1].startswith("class A  [lines 1-3, ~"), out[1])
        self.assertTrue(out[2].startswith("  def setUp  [lines 2-3, ~"), out[2])
        self.assertTrue(out[-1].startswith("block for x in range(3):  [lines 18-23, ~"), out[-1])
        self.assertEqual(len(out), 8)


def _ranges_are_disjoint(case: unittest.TestCase, found: list[symbols.Symbol], count: int, name: str) -> None:
    tops = [s for s in found if s.level == 1]
    for before, after in zip(tops, tops[1:]):
        case.assertLess(before.end, after.start, f"{name}: {before} overlaps {after}")
    for symbol in found:
        case.assertLessEqual(symbol.start, symbol.end, f"{name}: {symbol}")
        case.assertLessEqual(symbol.end, count, f"{name}: {symbol}")


class RealFilesTest(unittest.TestCase):
    """The scanner on the repository's own code: every definition is found, and no range crosses another."""

    def owner(self, found: list[symbols.Symbol], name: str, line: int, lines: list[str]) -> symbols.Symbol | None:
        """The symbol named `name` whose leading comments and decorators run down to `line`."""
        for symbol in found:
            if symbol.name == name and symbol.start <= line <= symbol.end:
                above = lines[symbol.start - 1 : line - 1]
                if all(not text.strip() or text.lstrip().startswith(("#", "@", "//")) for text in above):
                    return symbol
        return None

    def test_every_const_of_the_workflow_scripts(self) -> None:
        for name in ("issue-task.js", "pr-rebase.js"):
            path = ROOT / ".claude" / "workflows" / name
            lines = path.read_text(encoding="utf-8").splitlines()
            found = symbols.symbols("\n".join(lines), ".js")
            _ranges_are_disjoint(self, found, len(lines), name)
            for number, text in enumerate(lines, 1):
                match = re.match(r"^(?:export )?const (\w+)", text)
                if match:
                    with self.subTest(file=name, line=number):
                        self.assertIsNotNone(self.owner(found, match.group(1), number, lines))

    def test_rules_ends_on_its_join(self) -> None:
        path = ROOT / ".claude" / "workflows" / "pr-rebase.js"
        out = symbols.extract(path, ["RULES"])
        self.assertTrue(out[-1].startswith("]") and ".join(" in out[-1], out[-1])

    def test_every_gdscript_func(self) -> None:
        for area in ("core", "server", "net", "client", "voice"):
            for path in sorted((ROOT / area).rglob("*.gd")):
                lines = path.read_text(encoding="utf-8").splitlines()
                found = symbols.symbols("\n".join(lines), ".gd")
                _ranges_are_disjoint(self, found, len(lines), path.name)
                for number, text in enumerate(lines, 1):
                    match = re.match(r"^(?:static )?func (\w+)", text)
                    if match:
                        with self.subTest(file=path.relative_to(ROOT).as_posix(), line=number):
                            self.assertIsNotNone(self.owner(found, match.group(1), number, lines))

    def test_every_runner_def_and_class(self) -> None:
        for path in sorted((ROOT / "tools" / "runner").glob("*.py")):
            lines = path.read_text(encoding="utf-8").splitlines()
            found = symbols.symbols("\n".join(lines), ".py")
            _ranges_are_disjoint(self, found, len(lines), path.name)
            for number, text in enumerate(lines, 1):
                match = re.match(r"^(?:async )?(?:def|class) (\w+)", text)
                if match:
                    with self.subTest(file=path.name, line=number):
                        self.assertIsNotNone(self.owner(found, match.group(1), number, lines))


if __name__ == "__main__":
    unittest.main()
