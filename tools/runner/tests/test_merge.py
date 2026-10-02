"""merge-check and merge (#181): the symbol reader, the semantic check on the M4 failures rebuilt as small git
repositories, the trial, the merge's refusals and pushes, and the commands a manager types through the guard."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, guard, merge, permissions
from runner.common import ROOT, Failure, Result
from runner.tests.test_githooks import _rmtree

MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT)).replace("\\", "/")
RULES = permissions.Rules.load(ROOT / ".claude" / "settings.json")

# --- the M4 failures, rebuilt -----------------------------------------------------------------------------------------

PLAYER_RULES = """class_name PlayerRules
extends Resource
## How players move.

@export var walk_speed_mps := 4.0
@export var ghost_speed_factor := 0.5


func speed(downed: bool) -> float:
\tvar factor := ghost_speed_factor if downed else 1.0
\treturn walk_speed_mps * factor
"""
BASE_MODE = """[gd_resource type="Resource" script_class="PlayerRules" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/content/player_rules.gd" id="1"]

[resource]
script = ExtResource("1")
walk_speed_mps = 4.0
ghost_speed_factor = 0.4
"""
CONTROLLER = """class_name PlayerController
extends CharacterBody3D

var rules: PlayerRules


func _speed() -> float:
\treturn rules.walk_speed_mps
"""
WIRE_SCHEMA = """class_name WireSchema
extends RefCounted

const VERSION := 3


static func _events() -> Array[WireRow]:
\treturn [
\t\t_down(58, &"Disconnecting", 33, [_id("reason")]),
\t\t_down(59, &"KnockedDown", 16, [_peer("peer"), _vec3("position")]),
\t]


static func _state_and_voice() -> Array[WireRow]:
\tvar avatar := (
\t\tWireField
\t\t. record(
\t\t\t"",
\t\t\t[
\t\t\t\t_vec3("position"),
\t\t\t\tWireField.bits(PackedStringArray(["downed"])),
\t\t\t\tWireField.maybe("held_item", WireField.Type.ITEM),
\t\t\t]
\t\t)
\t)
\tvar avatars := WireField.map("avatars", _peer(""), avatar, 15, false)
\tvar snapshot := _row(
\t\t96,
\t\t&"Snapshot",
\t\t1024,
\t\t[_of("tick", _tick()), avatars]
\t)
\tvar voice_up := _row(112, &"VoiceUp", 502, [_u16("seq")])
\treturn [snapshot, voice_up]
"""
SNAPSHOT_TEST = """extends GdUnitTestSuite


func _snapshot(tick: int, at: Vector3) -> void:
\tvar avatar := {
\t\t"position": at,
\t\t"downed": false,
\t\t"held_item": -1,
\t}
\t_harness.send_message(WireMessage.new(&"Snapshot", {"tick": tick, "avatars": {1: avatar}}))
"""
RUNNER_VERIFY = '''"""The runner's verify, cut down."""


def write(text: str) -> None:
    print(text)


def main() -> int:
    write("verify")
    return 0


class _Quiet:
    def write(self, _text: str) -> None:
        pass

    def flush(self) -> None:
        pass
'''


# #210 gave `gdunit.main` the parameter `shards` with a default; #200 (mutants) still called it the old way.
GDUNIT = '''"""`test`, cut down."""


def main(paths: list[str] | None = None, run_import: bool = True) -> int:
    """`test`."""
    return 0 if run_import else len(paths or [])
'''
GDUNIT_210 = GDUNIT.replace("run_import: bool = True)", "run_import: bool = True, shards: int | None = None)")
MUTANTS_200 = {
    "tools/runner/mutants.py": "from . import gdunit\n\n\ndef step(paths: list[str]) -> int:\n"
    "    return gdunit.main(paths=paths, run_import=False)\n",
    "tools/runner/tests/test_mutants.py": "import inspect\nimport unittest\n\nfrom runner import gdunit\n\n\n"
    "class StepTest(unittest.TestCase):\n    def test_step(self) -> None:\n"
    '        self.assertIn("run_import", inspect.signature(gdunit.main).parameters)\n',
}


def _git(where: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=where, capture_output=True, text=True, encoding="utf-8", timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )  # fmt: skip
    if res.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {res.stderr}")
    return res.stdout.strip()


class Repo:
    """A bare remote and a clone of it whose main holds `files` and, pushed, release/m1: the way the runner sees
    origin. Built once per test class and copied for each test (each git call costs about 60 ms on Windows)."""

    templates: dict[type, tuple[Path, str]] = {}

    def __init__(self, test: unittest.TestCase, files: dict[str, str | None]) -> None:
        template, self.base = self._template(type(test), files)
        self.tmp = Path(tempfile.mkdtemp(prefix="merge-"))
        test.addCleanup(_rmtree, str(self.tmp))
        shutil.copytree(template, self.tmp, dirs_exist_ok=True)
        self.work = self.tmp / "work"
        config = self.work / ".git" / "config"
        text = config.read_text(encoding="utf-8").replace(template.as_posix(), self.tmp.as_posix())
        config.write_text(text, encoding="utf-8", newline="\n")

    @classmethod
    def _template(cls, owner: type, files: dict[str, str | None]) -> tuple[Path, str]:
        if owner not in cls.templates:
            tmp = Path(tempfile.mkdtemp(prefix="merge-template-"))
            owner.addClassCleanup(_rmtree, str(tmp))  # type: ignore[attr-defined]
            owner.addClassCleanup(cls.templates.pop, owner)  # type: ignore[attr-defined]
            _git(tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
            _git(tmp, "clone", "-q", (tmp / "remote.git").as_posix(), "work")
            work = tmp / "work"
            for key, value in (
                ("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false"),
                ("core.autocrlf", "false"),
            ):  # fmt: skip
                _git(work, "config", key, value)
            base = Repo.commit_in(work, files, "base")
            _git(work, "branch", "release/m1")
            _git(work, "push", "-q", "origin", "main", "release/m1")
            cls.templates[owner] = (tmp, base)
        return cls.templates[owner]

    @staticmethod
    def commit_in(work: Path, files: dict[str, str | None], message: str) -> str:
        for name, text in files.items():
            path = work / name
            if text is None:
                path.unlink()
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
        _git(work, "add", "-A")
        _git(work, "commit", "-q", "-m", message)
        return _git(work, "rev-parse", "HEAD")

    def commit(self, files: dict[str, str | None], message: str) -> str:
        return self.commit_in(self.work, files, message)

    def install_hook(self) -> None:
        """The committed pre-push hook, which blocks pushes to main and every non-fast-forward (about 1.5 s a push)."""
        hooks = self.tmp / "hooks"
        hooks.mkdir()
        shutil.copy(ROOT / ".claude" / "githooks" / "pre-push", hooks / "pre-push")
        (hooks / "pre-push").chmod(0o755)
        _git(self.work, "config", "core.hooksPath", hooks.as_posix())

    def branch(self, name: str, start: str = "main") -> None:
        _git(self.work, "switch", "-q", "-c", name, start)

    def push(self, *refs: str) -> None:
        """What happens on GitHub (a human's merge, main moving): past the pre-push hook, which guards the runner."""
        _git(self.work, "push", "-q", "--no-verify", "origin", *refs)

    def remote(self, ref: str) -> str:
        return _git(self.tmp / "remote.git", "rev-parse", ref)


def _change(label: str, before: str, after: str) -> merge.Change:
    return merge.build_change(label, before, after)


class DeclarationsTest(unittest.TestCase):
    def test_gdscript_members_not_locals(self) -> None:
        text = (
            "class_name Box\nextends Node\nsignal opened(by: int)\nconst SIZE := 3\n@export_range(0, 1) var fill := 0.5\n"
            "var health: int = 5:\n\tset(value):\n\t\thealth = value\nenum Kind { SMALL, LARGE = 2 }\n"
            "enum {\n\tLOOSE,\n}\n\n\nstatic func make(\n\tsize: int,\n\tlabel := \"x\",\n) -> Box:\n"
            "\tvar local := size\n\treturn null\n\n\nclass Inner:\n\tvar depth := 1\n\n\tfunc _init() -> void:\n"
            "\t\tvar inside := 2\n"
        )
        found = {(d.scope, d.name, d.kind) for d in merge.declarations(text)}
        self.assertEqual(
            found,
            {
                ("", "Box", "class_name"), ("", "opened", "signal"), ("", "SIZE", "const"), ("", "fill", "var"),
                ("", "health", "var"), ("", "Kind", "enum"), ("Kind", "SMALL", "enum value"),
                ("Kind", "LARGE", "enum value"), ("", "LOOSE", "enum value"), ("", "make", "func"),
                ("", "Inner", "class"), ("Inner", "depth", "var"), ("Inner", "_init", "func"),
            },
        )  # fmt: skip
        make = next(d for d in merge.declarations(text) if d.name == "make")
        self.assertEqual((make.line, make.end), (15, 18))
        self.assertEqual(make.signature, "static (size:int, label:=)->Box")

    def test_a_default_value_is_no_signature_change_but_a_new_parameter_is(self) -> None:
        def sig(text: str) -> str:
            return merge.declarations(text)[0].signature

        self.assertEqual(sig("func f(a: int = 1) -> void:\n\tpass\n"), sig("func f(a: int = 2) -> void:\n\tpass\n"))
        self.assertNotEqual(sig("func f(a: int) -> void:\n\tpass\n"), sig("func f(a: int, b: int) -> void:\n\tpass\n"))

    def test_only_parameters_with_defaults_appended_keep_old_calls_binding(self) -> None:
        def gd(params: str, tail: str = " -> int") -> str:
            return merge.declarations(f"func f({params}){tail}:\n\treturn 0\n")[0].signature

        def py(params: str) -> str:
            return merge.declarations(f"def f({params}) -> int:\n    return 0\n", python=True)[0].signature

        old = gd("a: int, b := 1")
        for name, new, binds in (
            ("one appended with a default", gd("a: int, b := 1, c: String = \"\""), True),
            ("two appended with defaults", gd("a: int, b := 1, c := 2, d := 3"), True),
            ("appended without a default", gd("a: int, b := 1, c: int"), False),
            ("one removed", gd("a: int"), False),
            ("one renamed", gd("a: int, bb := 1"), False),
            ("reordered", gd("b := 1, a: int"), False),
            ("retyped", gd("a: float, b := 1"), False),
            ("a default dropped", gd("a: int, b: int"), False),
            ("inserted before an old one, with a default", gd("a: int, c := 0, b := 1"), False),
            ("the return type changed", gd("a: int, b := 1, c := 2", " -> float"), False),
            ("static", "static " + gd("a: int, b := 1, c := 2"), False),
        ):
            with self.subTest(name):
                self.assertEqual(merge.appends_defaults(old, new), binds, (old, new))
        self.assertFalse(merge.appends_defaults(old, old))  # no change is no compatible change
        self.assertTrue(merge.appends_defaults(py("self, x"), py("self, x, *args, y=0, **kwargs")))
        self.assertFalse(merge.appends_defaults(py("self, x"), py("self, x, *, y")))  # a required keyword
        self.assertTrue(merge.appends_defaults(gd(""), gd("a := 0")))

    def test_python_members_not_locals(self) -> None:
        text = (
            '"""Doc with def fake(): inside."""\nimport os\nTIMEOUT = 5\nREPO: object = None\n\n\n'
            "@dataclass\nclass Row:\n    check: str\n    count: int = 0\n\n    def cells(self) -> str:\n"
            "        inner = 1\n        return ''\n\n\ndef main(argv: list[str] | None = None) -> int:\n"
            "    def helper():\n        pass\n    value = 2\n    return 0\n"
        )
        found = {(d.scope, d.name, d.kind) for d in merge.declarations(text, python=True)}
        self.assertEqual(
            found,
            {
                ("", "TIMEOUT", "const"), ("", "REPO", "const"), ("", "Row", "class"), ("Row", "check", "var"),
                ("Row", "count", "var"), ("Row", "cells", "def"), ("", "main", "def"),
            },
        )  # fmt: skip

    def test_wire_rows_follow_the_variable_to_its_row(self) -> None:
        rows = merge.WireRows(WIRE_SCHEMA)
        lines = WIRE_SCHEMA.split("\n")
        downed = next(i for i, line in enumerate(lines, 1) if '"downed"' in line)
        knocked = next(i for i, line in enumerate(lines, 1) if "KnockedDown" in line)
        self.assertEqual(rows.rows_of(downed), {"Snapshot"})
        self.assertEqual(rows.rows_of(knocked), {"KnockedDown"})
        self.assertEqual(rows.rows_of(4), set())  # VERSION: no row

    def test_diff_parser_reads_renames_deletes_and_line_numbers(self) -> None:
        text = (
            "diff --git a/x.gd b/y.gd\nsimilarity index 90%\nrename from x.gd\nrename to y.gd\n--- a/x.gd\n+++ b/y.gd\n"
            "@@ -3 +3,2 @@\n--- not a header\n+one\n+two\ndiff --git a/gone.tres b/gone.tres\ndeleted file mode 100644\n"
            "--- a/gone.tres\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-a\n-b\n"
        )
        first, second = merge.parse_diff(text)
        self.assertEqual((first.old, first.new, first.removed, first.added), ("x.gd", "y.gd", [3], [3, 4]))
        self.assertEqual((second.old, second.new, second.removed), ("gone.tres", None, [1, 2]))


class SemanticTest(unittest.TestCase):
    """build_change and both_ways on real commits: what one side removes or changes, used by the other's added lines."""

    def setUp(self) -> None:
        self.repo = Repo(
            self,
            {
                "core/content/player_rules.gd": PLAYER_RULES, "content/modes/base_mode.tres": BASE_MODE,
                "client/player/player_controller.gd": CONTROLLER, "net/messages/wire_schema.gd": WIRE_SCHEMA,
                "core/match/notes.gd": "extends RefCounted\n\nvar _cache := {}\n\n\nfunc note() -> void:\n"
                "\tvar tally := 0\n\tprint(tally)\n",
                "tools/runner/verify.py": RUNNER_VERIFY, "tools/runner/gdunit.py": GDUNIT,
            },
        )  # fmt: skip
        self.base = self.repo.base
        patch = mock.patch.object(merge, "REPO", self.repo.work)
        patch.start()
        self.addCleanup(patch.stop)

    def side(self, name: str, files: dict[str, str | None]) -> merge.Change:
        self.repo.branch("side/" + name.lstrip("#"), self.base)
        head = self.repo.commit(files, name)
        return _change(name, self.base, head)

    def test_153_renamed_a_field_that_154_read(self) -> None:
        renamed = PLAYER_RULES.replace("ghost_speed_factor := 0.5", "crawl_speed_mps := 1.2").replace(
            "ghost_speed_factor if", "0.0 if"
        )
        a = self.side("#153", {"core/content/player_rules.gd": renamed, "content/modes/base_mode.tres":
                               BASE_MODE.replace("ghost_speed_factor = 0.4", "crawl_speed_mps = 1.0")})  # fmt: skip
        reads = CONTROLLER + "\n\nfunc _crawl() -> float:\n\treturn rules.walk_speed_mps * rules.ghost_speed_factor\n"
        b = self.side("#154", {"client/player/player_controller.gd": reads})
        found = merge.both_ways(a, b)
        self.assertEqual({(o.symbol.name, o.symbol.kind) for o in found}, {("ghost_speed_factor", "var")})
        (one,) = found
        self.assertEqual((one.owner, one.user), ("#153", "#154"))
        self.assertEqual((one.symbol.path, one.symbol.line), ("core/content/player_rules.gd", 6))
        self.assertEqual(one.uses, [merge.Use("client/player/player_controller.gd", 12)])
        text = merge.describe(one)
        self.assertIn("core/content/player_rules.gd:6", text)
        self.assertIn("client/player/player_controller.gd:12", text)
        # The .tres rename of the same field is no second symbol.
        self.assertEqual([s.kind for s in a.symbols if s.name == "ghost_speed_factor"], ["var"])

    def test_156_added_a_snapshot_flag_that_a_154_test_lacked(self) -> None:
        flagged = WIRE_SCHEMA.replace('["downed"]', '["downed", "invulnerable"]').replace("VERSION := 3", "VERSION := 4")
        a = self.side("#156", {"net/messages/wire_schema.gd": flagged})
        b = self.side("#154", {"tests/unit/client/net/client_session_snapshots_test.gd": SNAPSHOT_TEST})
        rows = {s.name: s.change for s in a.symbols if s.kind == "wire row"}
        self.assertEqual(rows, {"Snapshot": "changed: fields +invulnerable"})  # not VoiceUp, not the VERSION line
        found = merge.both_ways(a, b)
        self.assertEqual([o.symbol.name for o in found], ["Snapshot"])
        self.assertEqual(found[0].uses, [merge.Use("tests/unit/client/net/client_session_snapshots_test.gd", 10)])

    def test_a_pair_with_no_shared_symbols_is_clean(self) -> None:
        a = self.side("#1", {"core/match/notes.gd": "extends RefCounted\n\nvar _cache := {}\n\n\nfunc note() -> void:"
                             "\n\tpass\n\n\nfunc tally(votes: Array) -> int:\n\treturn votes.size()\n"})  # fmt: skip
        b = self.side("#2", {"client/player/player_controller.gd": CONTROLLER + "\n\nfunc _jump() -> void:\n\tpass\n"})
        self.assertEqual(merge.both_ways(a, b), [])
        self.assertEqual(merge.textual(_git(self.repo.work, "rev-parse", "side/1"), _git(self.repo.work, "rev-parse", "side/2")), [])

    def test_private_names_match_only_in_their_file_and_locals_never(self) -> None:
        a = self.side("#1", {"core/match/notes.gd": "extends RefCounted\n\n\nfunc note() -> void:\n\tvar local := 1\n"})
        self.assertEqual({s.name for s in a.symbols}, {"_cache"})
        elsewhere = self.side("#2", {"client/x.gd": "extends Node\n\nvar _cache := []\n\n\nfunc f() -> void:\n"
                                     "\t_cache.append(tally)\n"})  # fmt: skip
        self.assertEqual(merge.both_ways(a, elsewhere), [])  # #1 removed the local `tally`: no member
        same = self.side("#3", {"core/match/notes.gd": "extends RefCounted\n\nvar _cache := {}\n\n\nfunc note() -> void:"
                                "\n\tpass\n\n\nfunc clear() -> void:\n\t_cache.clear()\n"})  # fmt: skip
        self.assertEqual([o.symbol.name for o in merge.both_ways(a, same)], ["_cache"])

    def test_a_tres_field_back_to_its_default_is_no_symbol_and_a_deleted_file_is_one(self) -> None:
        a = self.side("#1", {"content/modes/base_mode.tres": BASE_MODE.replace("ghost_speed_factor = 0.4\n", ""),
                             "client/player/player_controller.gd": None})  # fmt: skip
        self.assertEqual(
            {(s.name, s.kind) for s in a.symbols},
            {("client/player/player_controller.gd", "file"), ("PlayerController", "class_name")},
        )
        b = self.side("#2", {"levels/x.tscn": '[ext_resource type="Script" path="res://client/player/player_controller.gd"'
                             ' id="1"]\n'})  # fmt: skip
        self.assertEqual([o.symbol.kind for o in merge.both_ways(a, b)], ["file"])

    def test_a_module_level_python_name_matches_only_through_its_module(self) -> None:
        # #198 against #192 on 2026-10-02: `main` and `write` of verify.py were flagged at `metrics.main(`, a
        # parameter called `main`, `f.write(` and a regex string. Only a use through the module counts, and a member
        # of a private class (`_Quiet.write`) matches only in its own file.
        lanes = RUNNER_VERIFY.replace("def main() -> int:", 'def main(lane: str = "") -> int:')
        lanes = lanes.replace("def write(text: str) -> None:\n    print(text)\n\n\n", "")
        a = self.side("#198", {"tools/runner/verify.py": lanes.replace("    def write(self, _text: str) -> None:\n"
                                                                       "        pass\n\n", "")})  # fmt: skip
        self.assertEqual(
            {(s.name, s.module, s.own) for s in a.symbols},
            {("main", "verify", ""), ("write", "verify", ""), ("write", "", "tools/runner/verify.py")},
        )
        noise = self.side("#192", {
            "tools/runner/metrics.py": "import re\nfrom . import metrics\n\nSELF = re.compile(r\"run\\s+selftest\")\n\n\n"
            "def history_paths(main: str) -> list[str]:\n    with open(main) as f:\n        f.write(main)\n"
            "    return [metrics.main()]\n",
            "core/match/notes.gd": "extends RefCounted\n\n\nfunc main() -> void:\n\twrite(1)\n",
        })  # fmt: skip
        self.assertEqual(merge.both_ways(a, noise), [])
        real = self.side("#193", {
            "tools/runner/cli.py": "from . import verify\n\n\ndef run() -> int:\n    return verify.main()\n",
            "tools/runner/tests/test_x.py": "from unittest import mock\n\nfrom runner.verify import (\n    write,\n)\n"
            "from runner import verify\n\n\ndef test() -> None:\n    write(\"x\")\n"
            "    mock.patch.object(verify, \"write\")\n",
            "tools/runner/verify.py": RUNNER_VERIFY + "\n\ndef again() -> int:\n    return main()\n",
        })  # fmt: skip
        found = {o.symbol.name: [(u.path, u.line) for u in o.uses] for o in merge.both_ways(a, real)}
        self.assertEqual(found, {
            "main": [("tools/runner/cli.py", 5), ("tools/runner/verify.py", 22)],
            "write": [("tools/runner/tests/test_x.py", 4), ("tools/runner/tests/test_x.py", 10),
                      ("tools/runner/tests/test_x.py", 11)],
        })  # fmt: skip

    def test_210_appended_a_default_parameter_that_200_did_not_pass_a_note(self) -> None:
        # #207: merge-check flagged `gdunit.main` gaining `shards=None` (#210) against #200's calls that still bind.
        a = self.side("#210", {"tools/runner/gdunit.py": GDUNIT_210})
        b = self.side("#200", MUTANTS_200)
        found = merge.both_ways(a, b)
        self.assertEqual([(o.symbol.name, o.owner, o.note) for o in found], [("main", "#210", True)])
        self.assertEqual([(u.path, u.line) for u in found[0].uses],
                         [("tools/runner/mutants.py", 5), ("tools/runner/tests/test_mutants.py", 9)])  # fmt: skip
        row = merge.Row.of("#200 + #210", [], found)
        self.assertEqual((row.overlaps, row.cells()), ([], ("clean", "clean; note: `main`")))
        self.assertIn("old calls still bind", merge.describe(found[0]))
        # A new parameter without a default breaks those calls: an overlap again.
        required = self.side("#211", {"tools/runner/gdunit.py": GDUNIT.replace("run_import: bool = True)",
                                                                             "run_import: bool = True, shards: int)")})  # fmt: skip
        row = merge.Row.of("#200 + #211", [], merge.both_ways(required, b))
        self.assertEqual(([o.symbol.name for o in row.overlaps], row.notes), (["main"], []))
        self.assertEqual(row.cells()[1], "overlap: `main`")

    def test_an_appended_default_stays_an_overlap_where_the_other_side_patches_the_function(self) -> None:
        # A stand-in for gdunit.main with the old arguments (test_verify.py's side_effect fakes, an exact
        # assert_called_once_with) breaks once #210's own callers pass `shards`: only a direct call still binds.
        a = self.side("#210", {"tools/runner/gdunit.py": GDUNIT_210})
        patching = self.side("#212", {
            "tools/runner/tests/test_x.py": "from unittest import mock\n\nfrom runner import gdunit\n\n\n"
            "def test() -> None:\n    with mock.patch.object(gdunit, \"main\", side_effect=lambda paths, run_import: 0):\n"
            "        pass\n",
        })  # fmt: skip
        found = merge.both_ways(a, patching)
        self.assertEqual([(o.symbol.name, o.note) for o in found], [("main", False)])
        self.assertEqual([(u.path, u.line) for u in found[0].named], [("tools/runner/tests/test_x.py", 7)])
        row = merge.Row.of("#210 + #212", [], found)
        self.assertEqual((row.cells()[1], row.notes), ("overlap: `main`", []))
        self.assertTrue(merge.describe(found[0]).endswith("; patched by name at tools/runner/tests/test_x.py:7"))

    def test_a_textual_conflict_names_the_file(self) -> None:
        self.side("#1", {"core/match/notes.gd": "extends Node\n"})
        self.side("#2", {"core/match/notes.gd": "extends Object\n"})
        one, two = (_git(self.repo.work, "rev-parse", b) for b in ("side/1", "side/2"))
        self.assertEqual(merge.textual(one, two), ["core/match/notes.gd"])


def _gh_result(data: object, rc: int = 0) -> Result:
    return Result(rc, data if isinstance(data, str) else json.dumps(data), False, 0.0)


class FakeGitHub:
    """`gh pr list|view|checks` from a table of PRs; `merged` PRs show MERGED once the push happened."""

    def __init__(self, repo: Repo) -> None:
        self.repo, self.prs, self.checks = repo, {}, {}

    def add(self, number: int, head: str, base: str, **extra: object) -> None:
        oid = _git(self.repo.work, "rev-parse", head)
        self.prs[number] = {
            "number": number, "title": f"feat: task {number}", "state": "OPEN", "baseRefName": base,
            "headRefName": head, "headRefOid": oid, "isDraft": False, "headRepositoryOwner": {"login": "owner"},
            **extra,
        }  # fmt: skip
        self.checks[number] = [{"name": "verify", "state": "SUCCESS", "bucket": "pass"}]

    def view(self, number: int) -> dict:
        data = dict(self.prs[number])
        if data["state"] == "OPEN":
            base = f"refs/heads/{data['baseRefName']}"
            on_base = subprocess.run(
                ["git", "merge-base", "--is-ancestor", data["headRefOid"], base], cwd=self.repo.tmp / "remote.git",
                capture_output=True,
            ).returncode == 0  # fmt: skip
            data["state"] = "MERGED" if on_base else "OPEN"
        return data

    def __call__(self, *args: str) -> Result:
        if args[:2] == ("pr", "list"):
            return _gh_result([v for v in map(self.view, self.prs) if v["state"] == "OPEN"])
        if args[:2] == ("pr", "view"):
            return _gh_result(self.view(int(args[2])))
        if args[:2] == ("pr", "checks"):
            checks = self.checks[int(args[2])]
            return _gh_result(checks, 0 if checks else 1) if checks else _gh_result("no checks reported", 1)
        raise AssertionError(f"unexpected gh {args}")


class CommandTest(unittest.TestCase):
    """merge-check, --trial and merge against a local remote, with gh and verify stubbed."""

    def setUp(self) -> None:
        self.repo = Repo(
            self,
            {
                "core/content/player_rules.gd": PLAYER_RULES, "client/player/player_controller.gd": CONTROLLER,
                "tools/runner/gdunit.py": GDUNIT,
            },
        )  # fmt: skip
        self.gh = FakeGitHub(self.repo)
        self.verified: list[set[str]] = []
        self.verify_rc = 0
        self.printed: list[str] = []
        for patch in (
            mock.patch.object(merge, "REPO", self.repo.work),
            mock.patch.object(merge, "SCRATCH", self.repo.tmp / "out" / "merge"),
            mock.patch.object(merge, "gh", self.gh),
            mock.patch.object(merge, "verify_in", self.fake_verify),
            mock.patch.object(merge, "_cwd", lambda: self.repo.work),
            mock.patch.object(merge, "CONFIRM_WAIT", 0.0),
            mock.patch.object(merge, "say", lambda text="": self.printed.append(text)),
            mock.patch.object(merge, "ok", lambda text: self.printed.append(text)),
            mock.patch.object(merge, "bad", lambda text, fix="": self.printed.append(text)),
            mock.patch.object(merge, "warn", lambda text: self.printed.append(text)),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def fake_verify(self, path: Path, log: str) -> Result:
        files = {p.relative_to(path).as_posix() for p in path.rglob("*") if p.is_file() and ".git" not in p.parts}
        self.verified.append(files)
        for report in (f"tools/out/logs/{log}.log", "tools/out/gdunit/results.xml"):
            (path / report).parent.mkdir(parents=True, exist_ok=True)
            (path / report).write_text(f"{log}: {self.verify_rc}\n", encoding="utf-8", newline="\n")
        return Result(self.verify_rc, "verify summary", False, 0.0)

    def kept(self, log: str) -> dict[str, str]:
        """The merged tree's reports kept after a red verify, by path."""
        root = self.repo.tmp / "out" / "merge-logs" / log
        return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in root.rglob("*") if p.is_file()}

    def task(self, number: int, files: dict[str, str | None], base: str = "release/m1") -> str:
        branch = f"core/{number}-task"
        self.repo.branch(branch, f"origin/{base}" if base != "main" else "main")
        head = self.repo.commit(files, f"task {number}")
        # As a push would leave it, without one (a fetch keeps a tracking ref the remote lacks).
        _git(self.repo.work, "update-ref", f"refs/remotes/origin/{branch}", head)
        self.gh.add(number, branch, base)
        _git(self.repo.work, "switch", "-q", "main")
        return branch

    def scratch_left(self) -> list[Path]:
        return list((self.repo.tmp / "out" / "merge").glob("*"))

    # merge-check

    def test_merge_check_prints_the_table_and_fails_on_an_overlap_or_a_conflict(self) -> None:
        renamed = PLAYER_RULES.replace("ghost_speed_factor", "crawl_speed_mps")
        self.task(153, {"core/content/player_rules.gd": renamed})
        self.task(154, {"client/player/player_controller.gd": CONTROLLER + "\nfunc f() -> float:\n"
                        "\treturn rules.ghost_speed_factor\n"})  # fmt: skip
        self.task(155, {"core/other.gd": "extends Node\n"})
        self.task(156, {"core/other.gd": "extends Object\n"})
        self.assertEqual(merge.check([]), 1)
        text = "\n".join(self.printed)
        self.assertIn("| check | textual | semantic |", text)
        self.assertIn("| #153 + #154 | clean | overlap: `ghost_speed_factor` |", text)
        self.assertIn("| #153 + #155 | clean | clean |", text)
        self.assertIn("| #154 onto release/m1 | clean | clean |", text)
        self.assertIn("| #155 + #156 | conflict: core/other.gd | clean |", text)
        self.assertIn("`ghost_speed_factor` (var, removed) by #153 at core/content/player_rules.gd:6", text)
        self.assertIn("merge-check: 1 textual conflicts and 1 overlaps in 10 checks.", text)
        self.printed.clear()
        self.assertEqual(merge.check([153, 155], base="release/m1"), 0)
        self.assertIn("merge-check: clean (0 textual conflicts and 0 overlaps in 3 checks)", self.printed)
        # A named PR into another base is an error, not a silent "no open PRs to check".
        self.task(157, {"core/c.gd": "extends Node\n"}, base="main")
        with self.assertRaises(Failure) as caught:
            merge.check([153, 157], base="release/m1")
        self.assertIn("#157 targets main, not release/m1", str(caught.exception))

    def test_merge_check_onto_a_base_that_took_the_other_side_already(self) -> None:
        renamed = PLAYER_RULES.replace("ghost_speed_factor", "crawl_speed_mps")
        branch = self.task(153, {"core/content/player_rules.gd": renamed})
        self.task(154, {"client/player/player_controller.gd": CONTROLLER + "\nfunc f() -> float:\n"
                        "\treturn rules.ghost_speed_factor\n"})  # fmt: skip
        self.repo.push(f"origin/{branch}:refs/heads/release/m1")  # #153 merged (a fast-forward)
        self.assertEqual(merge.check([154]), 1)
        self.assertIn("| #154 onto release/m1 (1 commits since its fork) | clean | overlap: `ghost_speed_factor` |",
                      "\n".join(self.printed))  # fmt: skip
        # A child PR whose parent branch is gone is named and skipped (not clean), not a crash of the whole check.
        self.gh.add(160, "core/154-task", "core/153-gone")
        self.printed.clear()
        self.assertEqual(merge.check([160]), 1)
        self.assertTrue(any("origin/core/153-gone is gone" in line for line in self.printed))
        self.assertTrue(self.printed[-1].startswith("merge-check: 0 textual conflicts and 0 overlaps in 0 checks; "
                                                    "not checked: #160."))  # fmt: skip

    def test_a_compatible_signature_change_is_a_note_and_no_overlap(self) -> None:
        self.task(200, MUTANTS_200, base="main")
        self.task(210, {"tools/runner/gdunit.py": GDUNIT_210}, base="main")
        self.assertEqual(merge.check([], base="main"), 0)
        text = "\n".join(self.printed)
        self.assertIn("| #200 + #210 | clean | clean; note: `main` |", text)
        self.assertIn("- note: `main` (def, changed (paths:list[str]|None=, run_import:bool=)->int -> "
                      "(paths:list[str]|None=, run_import:bool=, shards:int|None=)->int; old calls still bind) by #210 "
                      "at tools/runner/gdunit.py:4; used by #200 at tools/runner/mutants.py:5", text)  # fmt: skip
        self.assertIn("merge-check: clean (0 textual conflicts and 0 overlaps in 3 checks)", text)

    def test_merge_check_pairs_prs_across_bases_that_change_the_same_shared_files(self) -> None:
        # #301 into main renames a parameter of gdunit.main, which #302 into release/m1 calls in the same file; #302
        # and #304 (main) both create docs/AGENT_WORKFLOW.md; #303 changes only core/; #305 is stacked on #302.
        renamed = GDUNIT.replace("run_import: bool", "import_first: bool")
        self.task(301, {"tools/runner/gdunit.py": renamed}, base="main")
        calls = GDUNIT + "\n\ndef again(paths: list[str]) -> int:\n    return main(paths, run_import=False)\n"
        self.task(302, {"tools/runner/gdunit.py": calls, "docs/AGENT_WORKFLOW.md": "# Workflow\n\nm1\n"})
        self.task(303, {"core/other.gd": "extends Node\n"})
        self.task(304, {"docs/AGENT_WORKFLOW.md": "# Workflow\n\nmain\n"}, base="main")
        self.task(305, {"tools/x.py": "X = 1\n"}, base="core/302-task")
        self.assertEqual(merge.check([]), 1)
        text = "\n".join(self.printed)
        self.assertIn("### across bases (main, release/m1): pairs that change the same files under tools/, .claude/, "
                      ".github/ or docs/AGENT_WORKFLOW.md", text)  # fmt: skip
        self.assertIn("| check | shared files | textual | semantic |", text)
        self.assertIn("| #301 (main) + #302 (release/m1) | tools/runner/gdunit.py | clean | overlap: `main` |", text)
        self.assertIn("| #302 (release/m1) + #304 (main) | docs/AGENT_WORKFLOW.md | conflict: docs/AGENT_WORKFLOW.md "
                      "| clean |", text)  # fmt: skip
        self.assertIn("no shared file in common, not compared: #301 (main) + #303 (release/m1); #301 (main) + "
                      "#305 (core/302-task); #303 (release/m1) + #304 (main); #304 (main) + #305 (core/302-task)",
                      text)  # fmt: skip
        self.assertNotIn("#302 (release/m1) + #305", text)  # stacked on #302: the same track, within its own base
        self.assertIn("`main` (def, changed (paths:list[str]|None=, run_import:bool=)->int -> (paths:list[str]|None=, "
                      "import_first:bool=)->int) by #301 at tools/runner/gdunit.py:4; used by #302 at "
                      "tools/runner/gdunit.py:10", text)  # fmt: skip
        # The per-base tables stay as they were: 3 checks into main, 3 into release/m1, 1 onto core/302-task.
        self.assertIn("| #301 + #304 | clean | clean |", text)
        self.assertIn("| #302 + #303 | clean | clean |", text)
        self.assertIn("merge-check: 1 textual conflicts and 1 overlaps in 9 checks.", text)
        self.assertIn("Across bases: name the pair on both tracks' plan issues", text)
        # One base checked: its PRs with every open PR into another base.
        self.printed.clear()
        self.assertEqual(merge.check([], base="main"), 1)
        self.assertIn("merge-check: 1 textual conflicts and 1 overlaps in 5 checks.", "\n".join(self.printed))
        # A PR with no shared file: its base's checks, and every cross-base pair named as not compared.
        self.printed.clear()
        self.assertEqual(merge.check([303]), 0)
        text = "\n".join(self.printed)
        self.assertIn("no shared file in common, not compared: #301 (main) + #303 (release/m1); #303 (release/m1) + "
                      "#304 (main)", text)  # fmt: skip
        self.assertNotIn("| check | shared files |", text)
        self.assertIn("merge-check: clean (0 textual conflicts and 0 overlaps in 1 checks)", text)

    def test_a_stage_pr_under_review_does_not_hide_its_fix_ups_from_the_check_across_bases(self) -> None:
        # The stage's PR #400 (release/m1 into main) is open while the human reviews it. #401, a fix-up into
        # release/m1, still lands in release/m1 and is paired with #402 into main; it is no partner of #400 itself.
        self.repo.branch("stage", "origin/release/m1")
        stage = self.repo.commit({"core/stage.gd": "extends Node\n"}, "stage work")
        self.repo.push("stage:refs/heads/release/m1")
        _git(self.repo.work, "switch", "-q", "main")
        _git(self.repo.work, "fetch", "-q", "origin")
        self.gh.add(400, "release/m1", "main", headRefOid=stage)
        calls = GDUNIT + "\n\ndef again(paths: list[str]) -> int:\n    return main(paths, run_import=False)\n"
        self.task(401, {"tools/runner/gdunit.py": calls})
        self.task(402, {"tools/runner/gdunit.py": GDUNIT.replace("run_import: bool", "import_first: bool")}, "main")
        self.assertEqual(merge.check([]), 1)
        text = "\n".join(self.printed)
        self.assertIn("### across bases (main, release/m1)", text)
        self.assertIn("| #401 (release/m1) + #402 (main) | tools/runner/gdunit.py | clean | overlap: `main` |", text)
        self.assertNotIn("#400 (main) + #401", text)
        self.assertNotIn("#401 (release/m1) + #400", text)
        self.assertIn("| #400 + #402 | clean | clean |", text)  # both land in main: the per-base table

    def test_trial_merges_in_order_verifies_and_removes_the_worktree(self) -> None:
        self.task(1, {"core/a.gd": "extends Node\n"})
        self.task(2, {"core/b.gd": "extends Node\n"})
        self.assertEqual(merge.check([1, 2], trial=True), 0)
        self.assertTrue({"core/a.gd", "core/b.gd"} <= self.verified[0])
        self.assertEqual(self.scratch_left(), [])
        self.assertEqual(_git(self.repo.work, "worktree", "list").count("\n"), 0)  # only the checkout itself
        self.assertEqual(self.kept("merge-trial"), {})  # a green verify keeps nothing
        self.verify_rc = 1
        self.assertEqual(merge.check([1, 2], trial=True), 1)
        self.assertEqual(self.scratch_left(), [])
        reports = {"logs/merge-trial.log": "merge-trial: 1\n", "gdunit/results.xml": "merge-trial: 1\n"}
        self.assertEqual(self.kept("merge-trial"), reports)

    def test_trial_stops_at_a_conflict_and_removes_the_worktree(self) -> None:
        self.task(1, {"core/a.gd": "extends Node\n"})
        self.task(2, {"core/a.gd": "extends Object\n"})
        self.assertEqual(merge.check([1, 2], trial=True), 1)
        self.assertEqual(self.verified, [])
        self.assertEqual(self.scratch_left(), [])
        self.assertTrue(any("does not merge cleanly: core/a.gd" in line for line in self.printed))

    # merge

    def test_merge_pushes_the_verified_merge_commit_by_hash_through_the_pre_push_hook(self) -> None:
        branch = self.task(7, {"core/a.gd": "extends Node\n"})
        self.repo.install_hook()
        tip = self.repo.remote("release/m1")
        self.assertEqual(merge.merge(7, base="release/m1"), 0)
        merged = self.repo.remote("release/m1")
        parents = _git(self.repo.tmp / "remote.git", "log", "-1", "--format=%P", merged).split()
        self.assertEqual(parents, [tip, self.gh.prs[7]["headRefOid"]])
        message = _git(self.repo.tmp / "remote.git", "log", "-1", "--format=%B", merged)
        self.assertEqual(message, f"Merge pull request #7 from owner/{branch}\n\nfeat: task 7")
        self.assertIn("core/a.gd", self.verified[0])
        self.assertEqual(self.scratch_left(), [])
        self.assertTrue(self.printed[-1].startswith(f"wave: merged #7 ({branch}) into release/m1 as {merged[:12]}"))

    def test_a_failed_gh_after_the_push_still_exits_0_with_the_wave_line(self) -> None:
        self.task(7, {"core/a.gd": "extends Node\n"})
        tip = self.repo.remote("release/m1")
        real = self.gh.__call__

        def flaky(*args: str) -> Result:
            if args[:2] == ("pr", "view") and self.repo.remote("release/m1") != tip:
                return _gh_result("error connecting to api.github.com", 1)
            return real(*args)

        with mock.patch.object(merge, "gh", flaky):
            self.assertEqual(merge.merge(7, base="release/m1"), 0)
        self.assertNotEqual(self.repo.remote("release/m1"), tip)
        self.assertTrue(any("does not show #7 merged yet" in line for line in self.printed))
        self.assertTrue(self.printed[-1].startswith("wave: merged #7"))

    def test_a_red_verify_pushes_nothing(self) -> None:
        self.task(7, {"core/a.gd": "extends Node\n"})
        tip = self.repo.remote("release/m1")
        self.verify_rc = 1
        with self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("nothing was pushed", str(caught.exception))
        self.assertIn("merge-logs/merge-7", str(caught.exception))
        reports = {"logs/merge-7.log": "merge-7: 1\n", "gdunit/results.xml": "merge-7: 1\n"}
        self.assertEqual(self.kept("merge-7"), reports)
        self.assertEqual((self.repo.remote("release/m1"), len(self.verified)), (tip, 1))
        self.assertEqual(self.scratch_left(), [])

    def test_a_conflict_pushes_nothing(self) -> None:
        self.task(7, {"core/a.gd": "extends Node\n"})
        self.repo.commit({"core/a.gd": "extends Object\n"}, "release moved")
        self.repo.push("main:release/m1")
        tip = self.repo.remote("release/m1")
        with self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("does not merge cleanly: core/a.gd", str(caught.exception))
        self.assertEqual((self.repo.remote("release/m1"), self.verified), (tip, []))

    def test_an_already_merged_pr_is_only_fetched(self) -> None:
        branch = self.task(7, {"core/a.gd": "extends Node\n"})
        self.repo.push(f"origin/{branch}:refs/heads/release/m1")
        tip = self.repo.remote("release/m1")
        self.assertEqual(merge.merge(7, base="release/m1"), 0)
        self.assertEqual((self.repo.remote("release/m1"), self.verified), (tip, []))
        self.assertIn("already merged", self.printed[-1])

    def test_refusals_change_nothing(self) -> None:
        self.task(7, {"core/a.gd": "extends Node\n"})
        self.task(8, {"core/b.gd": "extends Node\n"}, base="main")  # a PR into main, green: still refused
        tip, main = self.repo.remote("release/m1"), self.repo.remote("main")
        cases = {
            "main": (lambda: merge.merge(8, base="main"), "only humans merge into main"),
            "main, synced": (lambda: merge.merge(None, base="main", sync_main=True), "only humans merge into main"),
            "a branch that is not release/": (lambda: merge.merge(7, base="core/7-task"), "only into a release branch"),
            "neither a PR nor --sync-main": (lambda: merge.merge(None, base="release/m1"), "name one PR"),
            "both": (lambda: merge.merge(7, base="release/m1", sync_main=True), "name one PR"),
        }
        for name, (call, expected) in cases.items():
            with self.subTest(name), self.assertRaises(Failure) as caught:
                call()
            self.assertIn(expected, str(caught.exception))
        self.assertEqual(self.repo.remote("main"), main)
        for name, change, expected in (
            ("closed", {"state": "CLOSED"}, "is closed"),
            ("another base", {"baseRefName": "release/m2"}, "targets release/m2"),
            ("draft", {"isDraft": True}, "is a draft"),
        ):
            with self.subTest(name):
                saved = dict(self.gh.prs[7])
                self.gh.prs[7].update(change)
                with self.assertRaises(Failure) as caught:
                    merge.merge(7, base="release/m1")
                self.assertIn(expected, str(caught.exception))
                self.gh.prs[7] = saved
        for name, checks in (
            ("pending", [{"name": "verify", "state": "PENDING", "bucket": "pending"}]),
            ("failing", [{"name": "verify", "state": "FAILURE", "bucket": "fail"}]),
            ("none", []),
        ):
            with self.subTest(name):
                self.gh.checks[7] = checks
                with self.assertRaises(Failure) as caught:
                    merge.merge(7, base="release/m1")
                self.assertIn("CI is not green", str(caught.exception))
        self.assertEqual((self.repo.remote("release/m1"), self.verified), (tip, []))

    def test_refuses_a_moved_head_and_a_base_that_has_it(self) -> None:
        branch = self.task(7, {"core/a.gd": "extends Node\n"})
        tip = self.repo.remote("release/m1")
        _git(self.repo.work, "switch", "-q", branch)
        self.repo.commit({"core/a.gd": "extends Object\n"}, "pushed after GitHub's view")
        self.repo.push(branch)  # the head on origin moves; gh still reports the old headRefOid
        _git(self.repo.work, "switch", "-q", "main")
        with self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("it moved", str(caught.exception))
        self.assertEqual((self.repo.remote("release/m1"), self.verified), (tip, []))
        # GitHub still shows #7 open although the base already holds its head (a merge by hand GitHub has not seen).
        self.gh.prs[7]["headRefOid"] = self.repo.remote(branch)
        self.repo.push(f"{self.gh.prs[7]['headRefOid']}:refs/heads/release/m1")
        tip = self.repo.remote("release/m1")
        with mock.patch.object(self.gh, "view", lambda n: dict(self.gh.prs[n])), self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("already has #7's head", str(caught.exception))
        self.assertEqual((self.repo.remote("release/m1"), self.verified), (tip, []))
        self.assertEqual(self.scratch_left(), [])

    def test_refuses_a_task_checkout_here_or_as_the_current_folder(self) -> None:
        self.task(7, {"core/a.gd": "extends Node\n"})
        _git(self.repo.work, "switch", "-q", "core/7-task")
        with self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("task's checkout", str(caught.exception))
        _git(self.repo.work, "switch", "-q", "main")
        worktree = self.repo.tmp / "main-copy" / ".claude" / "worktrees" / "42"
        _git(self.repo.work, "worktree", "add", "-q", "--detach", str(worktree), "main")
        with mock.patch.object(merge, "_cwd", lambda: worktree), self.assertRaises(Failure) as caught:
            merge.merge(7, base="release/m1")
        self.assertIn("task's checkout", str(caught.exception))
        self.assertEqual(self.verified, [])

    def test_sync_main_merges_main_into_the_release_branch(self) -> None:
        self.assertEqual(merge.merge(None, base="release/m1", sync_main=True), 0)
        self.assertIn("already has main", self.printed[-1])
        main = self.repo.commit({"tools/x.py": "X = 1\n"}, "main moves")
        self.repo.push("main")
        tip = self.repo.remote("release/m1")
        self.assertEqual(merge.merge(None, base="release/m1", sync_main=True), 0)
        merged = self.repo.remote("release/m1")
        self.assertEqual(_git(self.repo.tmp / "remote.git", "log", "-1", "--format=%P", merged).split(), [tip, main])
        self.assertEqual(_git(self.repo.tmp / "remote.git", "log", "-1", "--format=%s", merged),
                         "Merge branch 'main' into release/m1")  # fmt: skip
        self.assertIn("tools/x.py", self.verified[0])
        self.verify_rc = 1
        self.repo.commit({"tools/y.py": "Y = 1\n"}, "main moves again")
        self.repo.push("main")
        with self.assertRaises(Failure):
            merge.merge(None, base="release/m1", sync_main=True)
        self.assertEqual(self.repo.remote("release/m1"), merged)


class TypedCommandsTest(unittest.TestCase):
    """What a manager types runs without a prompt: the merge's own git commands run inside the runner's process,
    which the permission rules and the guard never see."""

    TYPED = [
        ("PowerShell", r"tools\run.cmd merge-check"),
        ("PowerShell", r"tools\run.cmd merge-check --trial 192 193"),
        ("PowerShell", r"tools\run.cmd merge 154 --base release/m4"),
        ("PowerShell", r"tools\run.cmd merge --sync-main --base release/m5"),
        ("Bash", "tools/run.sh merge-check --base main"),
        ("Bash", "tools/run.sh merge 154 --base release/m4"),
        ("Bash", "cd /d/prime-game/.claude/worktrees/release-m5 && tools/run.sh merge --sync-main --base release/m5"),
    ]

    def test_from_the_main_checkout_and_from_a_worktree(self) -> None:
        for cwd in (MAIN, f"{MAIN}/.claude/worktrees/release-m5", f"{MAIN}/.claude/worktrees/181"):
            for tool, command in self.TYPED:
                with self.subTest(cwd=cwd, command=command):
                    verdict = permissions.verdict(RULES, guard, tool, command, cwd, MAIN, guard.NoRepo(), bypass=False)
                    self.assertEqual(verdict[0], permissions.PASS, verdict)

    def test_the_parser(self) -> None:
        parser = cli.build_parser()
        args = parser.parse_args(["merge", "154", "--base", "release/m4"])
        self.assertEqual((args.pr, args.base, args.sync_main), (154, "release/m4", False))
        args = parser.parse_args(["merge-check", "--trial", "1", "2"])
        self.assertEqual((args.prs, args.trial, args.base), ([1, 2], True, None))
        with mock.patch("sys.stderr"), self.assertRaises(SystemExit):
            parser.parse_args(["merge", "154"])  # --base is required


if __name__ == "__main__":
    unittest.main()
