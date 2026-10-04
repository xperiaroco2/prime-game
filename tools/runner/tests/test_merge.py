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

from runner import cli, common, guard, merge, permissions
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
    """`gh pr list|view|checks|merge` and `gh api user` from a table of PRs; a PR shows MERGED once its base has its
    head. `pr merge` checks its exact arguments and makes GitHub's merge commit on the remote's main."""

    def __init__(self, repo: Repo) -> None:
        self.repo, self.prs, self.checks = repo, {}, {}
        self.user = merge.ENGINEER_LOGIN
        self.merges: list[tuple[str, ...]] = []
        self.merge_rc = 0  # 1: GitHub refuses the merge and changes nothing

    def add(self, number: int, head: str, base: str, **extra: object) -> None:
        oid = _git(self.repo.work, "rev-parse", head)
        self.prs[number] = {
            "number": number, "title": f"feat: task {number}", "state": "OPEN", "baseRefName": base,
            "headRefName": head, "headRefOid": oid, "isDraft": False, "headRepositoryOwner": {"login": "owner"},
            "author": {"login": merge.ENGINEER_LOGIN}, "body": "## Needs the engineer\nNone.\n",
            "mergeable": "MERGEABLE", "latestReviews": [], "mergeCommit": None, **extra,
        }  # fmt: skip
        self.checks[number] = [{"name": "verify", "state": "SUCCESS", "bucket": "pass"}]

    def merge(self, args: tuple[str, ...]) -> Result:
        self.merges.append(args)
        number = int(args[2])
        data = self.prs[number]
        if args != ("pr", "merge", str(number), "--merge", "--match-head-commit", data["headRefOid"]):
            raise AssertionError(f"unexpected gh {args}")
        if self.merge_rc:
            return _gh_result("GraphQL: Pull Request is not mergeable", self.merge_rc)
        remote = self.repo.tmp / "remote.git"
        main = _git(remote, "rev-parse", "refs/heads/main")
        tree = _git(remote, "merge-tree", "--write-tree", main, data["headRefOid"]).split()[0]
        message = merge.merge_message(merge.PullRequest.of(data))
        commit = _git(
            remote, "-c", "user.name=GitHub", "-c", "user.email=noreply@github.com", "commit-tree", tree, "-p", main,
            "-p", data["headRefOid"], "-m", message,
        )  # fmt: skip
        _git(remote, "update-ref", "refs/heads/main", commit, main)
        data["mergeCommit"] = {"oid": commit}
        return _gh_result("")

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
        if args[:2] == ("pr", "merge"):
            return self.merge(args)
        if args == ("api", "user"):
            return _gh_result({"login": self.user})
        raise AssertionError(f"unexpected gh {args}")


class MergeCase(unittest.TestCase):
    """A local remote whose main holds FILES, with gh and verify stubbed (no tests of its own)."""

    FILES = {
        "core/content/player_rules.gd": PLAYER_RULES, "client/player/player_controller.gd": CONTROLLER,
        "tools/runner/gdunit.py": GDUNIT,
    }  # fmt: skip

    def setUp(self) -> None:
        self.repo = Repo(self, self.FILES)
        self.gh = FakeGitHub(self.repo)
        self.verified: list[set[str]] = []
        self.user_dirs: list[Path] = []
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
            # The scratch worktrees' user:// folders go to a temporary app-data folder, never the real one (#233).
            mock.patch.dict(os.environ, {common.app_data_var() or "PRIME_NO_APP_DATA": str(self.repo.tmp / "data")}),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def fake_verify(self, path: Path, log: str) -> Result:
        files = {p.relative_to(path).as_posix() for p in path.rglob("*") if p.is_file() and ".git" not in p.parts}
        self.verified.append(files)
        user = common.worktree_user_dir(path)  # what the merged tree's Godot runs make
        if user is not None:
            (user / "logs").mkdir(parents=True)
            (user / "logs" / "godot.log").write_text("session: stopped\n", encoding="utf-8")
            self.user_dirs.append(user)
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

    def user_dirs_left(self) -> list[Path]:
        """The scratch worktrees' user:// folders still in the (temporary) app-data folder."""
        return [user for user in self.user_dirs if user.exists()]


class CommandTest(MergeCase):
    """merge-check, --trial and merge into a release branch against a local remote, with gh and verify stubbed."""

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
        self.assertIn("### across bases (main, release/m1): pairs that both change files under tools/, .claude/, "
                      ".github/ or docs/AGENT_WORKFLOW.md", text)  # fmt: skip
        self.assertIn("| check | shared files | textual | semantic |", text)
        self.assertIn("| #301 (main) + #302 (release/m1) | tools/runner/gdunit.py | clean | overlap: `main` |", text)
        self.assertIn("| #302 (release/m1) + #304 (main) | docs/AGENT_WORKFLOW.md | conflict: docs/AGENT_WORKFLOW.md "
                      "| clean |", text)  # fmt: skip
        # Different shared files on each side are compared too (#231).
        self.assertIn("| #301 (main) + #305 (release/m1 via core/302-task) | #301: tools/runner/gdunit.py; #305: "
                      "tools/x.py | clean | clean |", text)  # fmt: skip
        self.assertIn("| #304 (main) + #305 (release/m1 via core/302-task) | #304: docs/AGENT_WORKFLOW.md; #305: "
                      "tools/x.py | clean | clean |", text)  # fmt: skip
        self.assertIn("no shared file on both sides, not compared: #301 (main) + #303 (release/m1); #303 (release/m1) "
                      "+ #304 (main)", text)  # fmt: skip
        self.assertNotIn("#302 (release/m1) + #305", text)  # stacked on #302: the same track, within its own base
        self.assertIn("`main` (def, changed (paths:list[str]|None=, run_import:bool=)->int -> (paths:list[str]|None=, "
                      "import_first:bool=)->int) by #301 at tools/runner/gdunit.py:4; used by #302 at "
                      "tools/runner/gdunit.py:10", text)  # fmt: skip
        # The per-base tables stay as they were: 3 checks into main, 3 into release/m1, 1 onto core/302-task.
        self.assertIn("| #301 + #304 | clean | clean |", text)
        self.assertIn("| #302 + #303 | clean | clean |", text)
        self.assertIn("merge-check: 1 textual conflicts and 1 overlaps in 11 checks.", text)
        self.assertIn("Across bases: name the pair on both tracks' plan issues", text)
        # One base checked: its PRs with every open PR into another base.
        self.printed.clear()
        self.assertEqual(merge.check([], base="main"), 1)
        self.assertIn("merge-check: 1 textual conflicts and 1 overlaps in 7 checks.", "\n".join(self.printed))
        # A PR with no shared file: its base's checks, and every cross-base pair named as not compared.
        self.printed.clear()
        self.assertEqual(merge.check([303]), 0)
        text = "\n".join(self.printed)
        self.assertIn("no shared file on both sides, not compared: #301 (main) + #303 (release/m1); #303 (release/m1) "
                      "+ #304 (main)", text)  # fmt: skip
        self.assertNotIn("| check | shared files |", text)
        self.assertIn("merge-check: clean (0 textual conflicts and 0 overlaps in 1 checks)", text)

    def test_merge_check_pairs_prs_across_bases_that_change_different_shared_files(self) -> None:
        # #231: the #210/#200 shape across bases. #311 into main renames a parameter of gdunit.main in
        # tools/runner/gdunit.py; #312 into release/m1 calls it from tools/runner/mutants.py, a file #311 never changes.
        # #313 into main changes a shared file but uses nothing of #312's; #314 into release/m1 changes only core/.
        self.task(311, {"tools/runner/gdunit.py": GDUNIT.replace("run_import: bool", "import_first: bool")}, "main")
        self.task(312, MUTANTS_200)
        self.task(313, {"docs/AGENT_WORKFLOW.md": "# Workflow\n\nmain\n"}, base="main")
        self.task(314, {"core/other.gd": "extends Node\n"})
        self.assertEqual(merge.check([]), 1)
        text = "\n".join(self.printed)
        self.assertIn("### across bases (main, release/m1): pairs that both change files under tools/, .claude/, "
                      ".github/ or docs/AGENT_WORKFLOW.md (textual: the files both change)", text)  # fmt: skip
        self.assertIn("| #311 (main) + #312 (release/m1) | #311: tools/runner/gdunit.py; #312: "
                      "tools/runner/mutants.py, tools/runner/tests/test_mutants.py | clean | overlap: `main` |",
                      text)  # fmt: skip
        self.assertIn("`main` (def, changed (paths:list[str]|None=, run_import:bool=)->int -> (paths:list[str]|None=, "
                      "import_first:bool=)->int) by #311 at tools/runner/gdunit.py:4; used by #312 at "
                      "tools/runner/mutants.py:5, tools/runner/tests/test_mutants.py:9", text)  # fmt: skip
        self.assertIn("| #312 (release/m1) + #313 (main) | #312: tools/runner/mutants.py, "
                      "tools/runner/tests/test_mutants.py; #313: docs/AGENT_WORKFLOW.md | clean | clean |",
                      text)  # fmt: skip
        # Only one side changes a shared file: not compared.
        self.assertIn("no shared file on both sides, not compared: #311 (main) + #314 (release/m1); #313 (main) + "
                      "#314 (release/m1)", text)  # fmt: skip
        self.assertIn("merge-check: 0 textual conflicts and 1 overlaps in 8 checks.", text)
        # The rename made compatible (a parameter appended with a default): a note across bases, no overlap.
        self.printed.clear()
        self.gh.prs.pop(311)
        self.task(315, {"tools/runner/gdunit.py": GDUNIT_210}, base="main")
        self.assertEqual(merge.check([312]), 0)
        text = "\n".join(self.printed)
        self.assertIn("| #312 (release/m1) + #315 (main) | #312: tools/runner/mutants.py, "
                      "tools/runner/tests/test_mutants.py; #315: tools/runner/gdunit.py | clean | clean; "
                      "note: `main` |", text)  # fmt: skip

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
        data = common.app_data_dir()
        godot = "godot" if common.IS_LINUX else "Godot"
        default = data / godot / "app_userdata" / "PrimeGame" if data else None  # the main checkout's: it stays
        if default is not None:
            default.mkdir(parents=True)
        self.assertEqual(merge.check([1, 2], trial=True), 0)
        self.assertTrue({"core/a.gd", "core/b.gd"} <= self.verified[0])
        self.assertEqual(self.scratch_left(), [])
        if common.app_data_var() is not None:
            self.assertEqual(len(self.user_dirs), 1)
        self.assertEqual(self.user_dirs_left(), [])  # its user:// folder went with the scratch worktree (#233)
        self.assertTrue(default is None or default.is_dir())
        self.assertEqual(_git(self.repo.work, "worktree", "list").count("\n"), 0)  # only the checkout itself
        self.assertEqual(self.kept("merge-trial"), {})  # a green verify keeps nothing
        self.verify_rc = 1
        self.assertEqual(merge.check([1, 2], trial=True), 1)
        self.assertEqual(self.scratch_left(), [])
        reports = {"logs/merge-trial.log": "merge-trial: 1\n", "gdunit/results.xml": "merge-trial: 1\n"}
        self.assertEqual(self.kept("merge-trial"), reports)
        self.assertEqual(self.user_dirs_left(), [])  # also after a red verify

    def test_a_scratch_worktree_that_stays_keeps_its_user_dir(self) -> None:
        # As mutants does: the folder goes only with the tree, so a tree finished by hand makes no second one.
        self.task(1, {"core/a.gd": "extends Node\n"})
        with mock.patch.object(merge, "_remove", lambda path: None):  # a program still has the tree open
            self.assertEqual(merge.check([1], trial=True), 0)
        left = self.scratch_left()
        self.assertEqual(len(left), 1)
        self.assertEqual(self.user_dirs_left(), self.user_dirs)
        merge._remove(left[0])
        self.assertEqual(self.scratch_left(), [])

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
        self.assertEqual(self.user_dirs_left(), [])
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
        # A PR into main goes through its gate since #300: MainGateTest covers its refusals and its merge.
        tip, main = self.repo.remote("release/m1"), self.repo.remote("main")
        cases = {
            "main, synced": (
                lambda: merge.merge(None, base="main", sync_main=True), "--sync-main goes only into a release branch"
            ),
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


LINK = "https://github.com/o/r/issues/170#issuecomment-1"
APPROVED = f"Approved by the engineer: {LINK}\n"
RELAYED = "## Cross-area\nagreed with the designer, relayed by the engineer; @SwiftySinister\n"


class MainGateTest(MergeCase):
    """merge <pr> --base main (#300): the gate's refusals, each with its reason, and the merge through GitHub."""

    FILES = {
        **MergeCase.FILES, "docs/decisions/2026-01-01-old.md": "# Old\n", "tools/runner/guard.py": "X = 1\n",
        "docs/GDD.md": "# GDD\n",
    }  # fmt: skip

    def pr(self, number: int, files: dict[str, str | None], body: str | None = None, **extra: object) -> str:
        """An open PR into main whose head is on origin (GitHub's merge needs its commits there)."""
        branch = self.task(number, files, base="main")
        self.repo.push(branch)
        if body is not None:
            self.gh.prs[number]["body"] = body
        self.gh.prs[number].update(extra)
        return branch

    def verdict(self, number: int, dry_run: bool = True) -> tuple[int, str]:
        self.printed.clear()
        rc = merge.merge(number, base="main", dry_run=dry_run)
        return rc, "\n".join(self.printed)

    def main_moves_on_github(self) -> str:
        """Another PR merged on GitHub: a commit on the remote's main that this checkout has not fetched."""
        remote = self.repo.tmp / "remote.git"
        main = _git(remote, "rev-parse", "refs/heads/main")
        tree = _git(remote, "rev-parse", f"{main}^{{tree}}")
        commit = _git(remote, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit-tree", tree, "-p", main,
                      "-m", "another merge")  # fmt: skip
        _git(remote, "update-ref", "refs/heads/main", commit, main)
        return commit

    def assert_refused(self, number: int, expected: str, dry_run: bool = True) -> str:
        main = self.repo.remote("main")
        rc, text = self.verdict(number, dry_run)
        self.assertEqual(rc, 1, text)
        self.assertIn(f"gate: refused: {expected}", text)
        self.assertEqual((self.repo.remote("main"), self.gh.merges), (main, []))
        return text

    def test_a_clean_pr_merges_through_github(self) -> None:
        branch = self.pr(30, {"core/a.gd": "extends Node\n"})
        main = self.repo.remote("main")
        self.assertEqual(merge.merge(30, base="main"), 0)
        oid = self.gh.prs[30]["headRefOid"]
        self.assertEqual(self.gh.merges, [("pr", "merge", "30", "--merge", "--match-head-commit", oid)])
        merged = self.repo.remote("main")
        remote = self.repo.tmp / "remote.git"
        self.assertEqual(_git(remote, "log", "-1", "--format=%P", merged).split(), [main, oid])
        self.assertEqual(_git(remote, "log", "-1", "--format=%B", merged),
                         f"Merge pull request #30 from owner/{branch}\n\nfeat: task 30")  # fmt: skip
        self.assertEqual(self.verified, [])  # no local verify: CI tested this tree (the head contains main)
        self.assertEqual(self.scratch_left(), [])
        self.assertEqual(_git(self.repo.work, "rev-parse", "origin/main"), merged)  # fetched afterwards
        self.assertTrue(self.printed[-1].startswith(
            f"wave: merged #30 ({branch}) into main as {merged[:12]} through GitHub; gate: CI green on an up-to-date "
            "head"), self.printed[-1])  # fmt: skip
        self.assertEqual(self.verdict(30, dry_run=False)[0], 0)
        self.assertIn("already merged into main; fetched only", self.printed[-1])
        self.assertEqual(len(self.gh.merges), 1)

    def test_refusals_on_github_facts(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        saved, checks = dict(self.gh.prs[30]), list(self.gh.checks[30])
        cases = [
            ("another base", {"baseRefName": "release/m1"}, None, "#30 targets release/m1, not main"),
            ("draft", {"isDraft": True}, None, "#30 is a draft"),
            ("the designer's PR", {"author": {"login": "SwiftySinister"}}, None,
             "#30 is not authored by the engineer's account xperiaroco2 (author: SwiftySinister)"),
            ("the designer's session", {}, "SwiftySinister", "gh runs as SwiftySinister, not the engineer's account"),
            ("the designer's PR in the designer's session", {"author": {"login": "SwiftySinister"}}, "SwiftySinister",
             "#30 is not authored by the engineer's account"),
            ("a conflict", {"mergeable": "CONFLICTING"}, None, "GitHub says it is not mergeable"),
        ]  # fmt: skip
        for name, change, user, expected in cases:
            with self.subTest(name):
                self.gh.prs[30] = {**saved, **change}
                self.gh.user = user or merge.ENGINEER_LOGIN
                self.assert_refused(30, expected, dry_run=False)
        self.gh.prs[30], self.gh.user = saved, merge.ENGINEER_LOGIN
        for name, failing in (
            ("pending", [{"name": "verify", "state": "PENDING", "bucket": "pending"}]),
            ("failing", [{"name": "verify", "state": "FAILURE", "bucket": "fail"}]),
            ("none", []),
        ):
            with self.subTest(name):
                self.gh.checks[30] = failing
                self.assert_refused(30, "CI is not green on its head", dry_run=False)
        self.gh.checks[30] = checks
        self.gh.prs[30]["state"] = "CLOSED"
        with self.assertRaises(Failure) as caught:
            merge.merge(30, base="main")
        self.assertIn("#30 is closed, not open", str(caught.exception))
        self.assertEqual(self.gh.merges, [])

    def test_refuses_a_head_behind_main_and_a_moved_head(self) -> None:
        branch = self.pr(31, {"core/a.gd": "extends Node\n"})
        self.main_moves_on_github()  # another PR merged after #31 was published: its CI tested another tree
        self.assert_refused(31, "behind main (origin/main ", dry_run=False)
        self.gh.prs.pop(31)
        _git(self.repo.work, "fetch", "-q", "origin")
        _git(self.repo.work, "switch", "-q", "main")
        _git(self.repo.work, "merge", "-q", "--ff-only", "origin/main")
        branch = self.pr(32, {"core/b.gd": "extends Node\n"})
        _git(self.repo.work, "switch", "-q", branch)
        self.repo.commit({"core/b.gd": "extends Object\n"}, "pushed after GitHub's view")
        self.repo.push(branch)  # GitHub still reports the old head
        _git(self.repo.work, "switch", "-q", "main")
        self.assert_refused(32, "origin/core/32-task is not at the PR's head", dry_run=False)

    def test_main_moving_after_the_gate_refuses_the_merge(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        real, moved = merge.fetch, []

        def fetch_then_main_moves() -> None:
            real()
            if not moved:  # the gate's fetch saw main; GitHub merges another PR right after it
                moved.append(self.main_moves_on_github())

        with mock.patch.object(merge, "fetch", fetch_then_main_moves), self.assertRaises(Failure) as caught:
            merge.merge(30, base="main")
        self.assertIn("origin/main moved since the fetch", str(caught.exception))
        self.assertIn("Nothing was merged", str(caught.exception))
        self.assertEqual((self.repo.remote("main"), self.gh.merges), (moved[0], []))

    def test_a_refused_github_merge_changes_nothing_and_a_late_success_counts(self) -> None:
        self.pr(30, {"core/a.gd": "extends Node\n"})
        main = self.repo.remote("main")
        self.gh.merge_rc = 1
        with self.assertRaises(Failure) as caught:
            merge.merge(30, base="main")
        self.assertIn("GitHub refused the merge of #30: GraphQL: Pull Request is not mergeable. Nothing was merged.",
                      str(caught.exception))  # fmt: skip
        self.assertEqual(self.repo.remote("main"), main)
        # gh exits 1 although GitHub merged it (a timeout after the merge): GitHub's state counts.
        self.gh.merge_rc = 0
        real = self.gh.merge

        def merged_then_timed_out(args: tuple[str, ...]) -> Result:
            real(args)
            return _gh_result("timeout", 1)

        with mock.patch.object(self.gh, "merge", merged_then_timed_out):
            self.assertEqual(merge.merge(30, base="main"), 0)
        self.assertTrue(any("gh pr merge exited 1, but GitHub shows #30 merged" in line for line in self.printed))
        self.assertTrue(self.printed[-1].startswith("wave: merged #30"), self.printed[-1])
        self.assertNotEqual(self.repo.remote("main"), main)

    def test_designer_area_needs_the_designers_review_or_the_relay_phrase(self) -> None:
        # Each designer path, a hint in a comment and a review that is no approval: GateTextTest.test_exceptions.
        self.pr(40, {"content/x.tres": "x = 1\n"})
        self.assert_refused(40, "the designer's area (content/x.tres) without the designer's approving review")
        self.gh.prs[40]["body"] = RELAYED
        self.assertEqual(self.verdict(40)[0], 0, self.printed)
        self.gh.prs[40]["body"] = ""
        self.gh.prs[40]["latestReviews"] = [{"author": {"login": "SwiftySinister"}, "state": "APPROVED"}]
        self.assertEqual(self.verdict(40)[0], 0, self.printed)

    def test_permission_and_safety_files_are_always_refused(self) -> None:
        # Each safety path: GateTextTest.test_exceptions.
        self.pr(50, {"tools/runner/guard.py": "Y = 2\n"}, body=RELAYED + APPROVED)
        self.assert_refused(50, "permission and safety files (tools/runner/guard.py): the engineer merges these")
        self.gh.prs.pop(50)
        self.pr(59, {"tools/runner/tests/test_guard.py": "Y = 2\n"})
        self.assertEqual(self.verdict(59)[0], 0)

    def test_adrs_need_the_engineers_approval_line(self) -> None:
        # Deleted and new ADRs and the forms of the line: GateTextTest.test_exceptions.
        old = "docs/decisions/2026-01-01-old.md"
        self.pr(60, {old: "# Old, amended\n", "docs/AGENT_WORKFLOW.md": "# Workflow\n"})
        text = self.assert_refused(60, f"ADRs {old} (changed) without an \"Approved by the engineer: <GitHub link>\"")
        self.assertIn("refused (1 reason)", text)  # docs/AGENT_WORKFLOW.md needs nothing
        self.gh.prs[60]["body"] = APPROVED
        self.assertEqual(self.verdict(60)[0], 0, self.printed)

    def test_needs_the_engineer_items_must_be_answered(self) -> None:
        body = (
            "## Needs the engineer\n1. **Night-time wakes.** As built.\n   - A) Allow them.\n   - B) No timer.\n\n"
            f"   Recommendation: A. Answered: {LINK}\n2. The scope of the rule. Keep it.\n\n## Merge order\nNone.\n"
        )
        self.pr(70, {"core/a.gd": "extends Node\n"}, body=body)
        self.assert_refused(70, "\"Needs the engineer\": item 2 (\"The scope of the rule. Keep it.\") has no")
        self.gh.prs[70]["body"] = body.replace("Keep it.", f"Keep it. Answered: {LINK}")
        self.assertEqual(self.verdict(70)[0], 0)

    def test_a_closing_release_pr_needs_the_go(self) -> None:
        # The milestone's closing PR: release/m1 into main, with provisional content and a new ADR in its diff.
        self.repo.branch("stage", "origin/release/m1")
        stage = self.repo.commit({"content/x.tres": "x = 1\n", "docs/decisions/2026-10-04-m1.md": "# M1\n"}, "stage")
        self.repo.push("stage:refs/heads/release/m1")
        _git(self.repo.work, "switch", "-q", "main")
        _git(self.repo.work, "fetch", "-q", "origin")
        self.gh.add(80, "release/m1", "main", headRefOid=stage)
        text = self.assert_refused(80, "a milestone's closing PR (release/m1) merges after the engineer's go")
        self.assertIn("the designer's area (content/x.tres)", text)
        self.assertIn("ADRs docs/decisions/2026-10-04-m1.md (new)", text)
        self.assertIn("refused (3 reasons)", text)
        self.gh.prs[80]["body"] = APPROVED + "## Needs the engineer\nNone.\n"
        self.assertEqual(self.verdict(80, dry_run=False)[0], 0, self.printed)
        self.assertEqual(_git(self.repo.tmp / "remote.git", "log", "-1", "--format=%P", "main").split()[1], stage)

    def test_dry_run_lists_every_refusal_and_merges_nothing(self) -> None:
        self.pr(90, {"tools/runner/guard.py": "Y = 2\n"}, isDraft=True)
        self.gh.checks[90] = [{"name": "verify", "state": "FAILURE", "bucket": "fail"}]
        text = self.assert_refused(90, "#90 is a draft")
        for expected in ("CI is not green on its head: verify: FAILURE", "permission and safety files",
                         "gate: #90 into main: refused (3 reasons); nothing was merged"):  # fmt: skip
            self.assertIn(expected, text)
        self.gh.prs.pop(90)
        self.pr(91, {"core/a.gd": "extends Node\n"}, mergeable="UNKNOWN")  # just pushed: GitHub has not computed it
        main = self.repo.remote("main")
        self.assertEqual(self.verdict(91), (0, "\n".join(self.printed)))
        self.assertIn("gate: #91 would merge into main", self.printed[-1])
        self.assertEqual((self.repo.remote("main"), self.gh.merges), (main, []))
        # From a task's checkout: a dry run works, a merge is refused (workflow agents never merge).
        worktree = self.repo.tmp / "main-copy" / ".claude" / "worktrees" / "42"
        _git(self.repo.work, "worktree", "add", "-q", "--detach", str(worktree), "main")
        with mock.patch.object(merge, "_cwd", lambda: worktree):
            self.assertEqual(self.verdict(91)[0], 0)
            with self.assertRaises(Failure) as caught:
                merge.merge(91, base="main")
        self.assertIn("task's checkout", str(caught.exception))
        self.assertEqual(self.gh.merges, [])

    def test_merge_check_flags_and_stacked_prs_are_notes_not_refusals(self) -> None:
        # #153 renames a field #154 reads and a parameter that #161 (into release/m1) passes; #155 is stacked on it.
        renamed = PLAYER_RULES.replace("ghost_speed_factor", "crawl_speed_mps")
        gdunit = GDUNIT.replace("run_import: bool", "import_first: bool")
        branch = self.pr(153, {"core/content/player_rules.gd": renamed, "tools/runner/gdunit.py": gdunit})
        self.pr(154, {"client/player/player_controller.gd": CONTROLLER + "\nfunc f() -> float:\n"
                      "\treturn rules.ghost_speed_factor\n"})  # fmt: skip
        self.task(155, {"core/c.gd": "extends Node\n"}, base=branch)
        calls = GDUNIT + "\n\ndef again(paths: list[str]) -> int:\n    return main(paths, run_import=False)\n"
        self.task(161, {"tools/runner/gdunit.py": calls})
        rc, text = self.verdict(153)
        self.assertEqual(rc, 0, text)
        self.assertIn("gate: note: #155 is stacked on it: GitHub retargets it to main", text)
        self.assertIn("gate: note: merge-check: #153 + #154: overlap: `ghost_speed_factor`: after this merge #154 is "
                      "behind main and needs pr-rebase", text)  # fmt: skip
        self.assertIn("gate: note: merge-check across bases: #153 (main) + #161 (release/m1): overlap: `main`: after "
                      "this merge, merge --sync-main --base release/m1, then pr-rebase #161 before it merges", text)
        self.assertIn("gate: #153 would merge into main", text)


class GateTextTest(unittest.TestCase):
    """The gate's reading of a PR body and its paths (#300), without git."""

    def test_needs_the_engineer_in_every_form(self) -> None:
        unanswered = "1. Night-time wakes.\n   - A) Allow them.\n   - B) No timer.\n\n   Recommendation: A.\n"
        answered = unanswered.replace("Recommendation: A.", f"Recommendation: A. Answered: {LINK}")
        for label in ("## Needs the engineer", "**Needs the engineer**", "**Needs the engineer:**",
                      "Needs the engineer:", "### Needs the engineer (1)"):  # fmt: skip
            with self.subTest(label):
                body = f"## Summary\nText.\n\n{label}\n{unanswered}\n## Merge order\nIndependent.\n"
                self.assertEqual(merge.open_needs(body), ["item 1 (\"Night-time wakes.\") has no \"Answered: <GitHub "
                                                          "link>\""])  # fmt: skip
                self.assertEqual(merge.open_needs(body.replace(unanswered, answered)), [])
        # "- " items count like numbered ones; nested option bullets are part of their item.
        self.assertEqual(len(merge.open_needs(f"## Needs the engineer\n- One.\n  - (a) x\n- Two. Answered: {LINK}\n")), 1)
        for empty in ("## Needs the engineer\nNone.\n", "## Needs the engineer\n\n## Merge order\nx\n",
                      "**Needs the engineer:** nothing\n", "Needs the engineer: none, nothing blocking.\n",
                      "## Summary\nNo section and no mention.\n",
                      "<!-- ## Needs the engineer\n1. a template hint -->\n"):  # fmt: skip
            with self.subTest(empty):
                self.assertEqual(merge.open_needs(empty), [])
        # Fail closed: text the gate cannot read as items, a mention without a section, a link off GitHub.
        self.assertIn("text but no numbered", merge.open_needs("## Needs the engineer\nPlease confirm the scope.\n")[0])
        self.assertIn("no section starts with it", merge.open_needs("Listed under Needs the engineer.\n")[0])
        self.assertEqual(len(merge.open_needs("## Needs the engineer\n1. x Answered: https://example.com/1\n")), 1)

    def test_needs_the_engineer_with_sub_labels(self) -> None:
        # Questions written as sub-headings or bold labels are items: they do not end the section (#300's review).
        for body in ("## Needs the engineer\n### 1. ADR approval\nPlease check.\n### 2. Pair\nA or B?\n",
                     "**Needs the engineer**\n**1. ADR approval**\nPlease check.\n**2. Pair**\nA or B?\n",
                     "## Needs the engineer\n**ADR approval**\nPlease check.\n**Pair**\nA or B?\n## Merge order\nx\n",
                     "## Needs the engineer\n## 1. ADR approval\nPlease check.\n## 2. Pair\nA or B?\n"):  # fmt: skip
            with self.subTest(body):
                problems = merge.open_needs(body)
                self.assertEqual(len(problems), 2, problems)
                self.assertIn("item 1 (\"ADR approval\") has no", problems[0])
                answered = body.replace("Please check.", f"Please check. Answered: {LINK}")
                self.assertEqual(len(merge.open_needs(answered.replace("A or B?", f"A. Answered: {LINK}"))), 0)
        # A sub-heading that groups items (a closing PR's "From #153") is no question of its own; its items are.
        grouped = f"## Needs the engineer\n### From #153\nContext.\n1. One. Answered: {LINK}\n2. Two.\n### From #154\n"
        problems = merge.open_needs(grouped + f"- Three. Answered: {LINK}\n")
        self.assertEqual(problems, ["item 2 (\"Two.\") has no \"Answered: <GitHub link>\""])
        self.assertEqual(merge.open_needs(grouped.replace("2. Two.", f"2. Two. Answered: {LINK}") + "None.\n"), [])
        # Fail closed: a bold or plain label section that ends at once on another bold label cannot be read.
        for body in ("**Needs the engineer**\n**ADR approval**\nPlease check.\n",
                     "Needs the engineer:\n\n**ADR approval**\nPlease check.\n"):  # fmt: skip
            with self.subTest(body):
                self.assertIn("cannot read", merge.open_needs(body)[0])
        self.assertEqual(merge.open_needs("**Needs the engineer:** none\n**Merge order**\nx\n"), [])

    def test_exceptions(self) -> None:
        def reasons(path: str, body: str = "", status: str = "M", **kw: bool) -> list[str]:
            return merge.exception_reasons([(status, path)], body, "core/1-x", **kw)

        for path in ("content/x.tres", "levels/a.tscn", "docs/GDD.md", "docs/design/a.md",
                     ".claude/skills/new-mechanic/SKILL.md", ".claude/skills/new-level-piece/SKILL.md"):  # fmt: skip
            with self.subTest(path):
                self.assertIn(f"the designer's area ({path})", reasons(path)[0])
                self.assertEqual(reasons(path, RELAYED.upper()), [])
                self.assertEqual(reasons(path, designer_approved=True), [])
                # The template's hint carries the phrase inside an HTML comment: it does not count; nor the go.
                self.assertEqual(len(reasons(path, f"<!-- \"{merge.RELAY_PHRASE}\" -->\n" + APPROVED)), 1)
        for path in (".claude/settings.json", ".claude/settings.local.json", ".claude/githooks/pre-push",
                     "tools/runner/guard.py"):  # fmt: skip
            with self.subTest(path):
                self.assertIn(f"permission and safety files ({path})", reasons(path, RELAYED + APPROVED)[0])
        for path in ("tools/runner/tests/test_guard.py", ".claude/skills/finish-task/SKILL.md", "docs/designs.md"):
            self.assertEqual(reasons(path), [])
        old = "docs/decisions/2026-01-01-old.md"
        for status, kind in (("M", "changed"), ("D", "deleted"), ("A", "new")):
            with self.subTest(kind):
                self.assertIn(f"ADRs {old} ({kind}) without", reasons(old, status=status)[0])
                for body in (f"<!-- {APPROVED} -->", "Approved by the engineer: https://example.com/x\n",
                             f"Not yet: Approved by the engineer: {LINK}\n"):  # fmt: skip
                    self.assertEqual(len(reasons(old, body, status)), 1, body)
                for body in (APPROVED, f"- **Approved by the engineer:** {LINK}\n", f"Text.\n  {APPROVED}"):
                    self.assertEqual(reasons(old, body, status), [], body)
        adr = [("A", "docs/decisions/x.md")]
        self.assertEqual(merge.exception_reasons([("M", "core/a.gd")], "", "core/1-x"), [])
        self.assertEqual(len(merge.exception_reasons(adr, "", "core/1-x")), 1)
        self.assertEqual(merge.exception_reasons(adr, APPROVED, "core/1-x"), [])
        # The go of a closing PR clears its designer-area paths and ADRs, never the safety files.
        paths = [("M", "content/x.tres"), *adr, ("M", ".claude/settings.json")]
        reasons = merge.exception_reasons(paths, APPROVED, "release/m5")
        self.assertEqual(len(reasons), 1)
        self.assertIn("permission and safety files (.claude/settings.json)", reasons[0])
        self.assertEqual(len(merge.exception_reasons(paths, "", "release/m5")), 4)
        self.assertEqual(merge.exception_reasons([("M", "content/x.tres")], "", "c/1-x", designer_approved=True), [])

    def test_the_owners_match_codeowners(self) -> None:
        owners = (ROOT / ".github" / "CODEOWNERS").read_text(encoding="utf-8")
        self.assertRegex(owners, rf"(?m)^\*\s+@{merge.ENGINEER_LOGIN}\s*$")
        self.assertRegex(owners, rf"(?m)^/content/\s+@{merge.DESIGNER_LOGIN}\s*$")


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
        ("PowerShell", r"tools\run.cmd merge 154 --base main"),
        ("PowerShell", r"cd D:\prime-game; tools\run.cmd merge 154 --base main"),
        ("PowerShell", r"tools\run.cmd merge 154 --base main --dry-run"),
        ("Bash", "tools/run.sh merge 154 --base main --dry-run"),
    ]

    def test_from_the_main_checkout_and_from_a_worktree(self) -> None:
        for cwd in (MAIN, f"{MAIN}/.claude/worktrees/release-m5", f"{MAIN}/.claude/worktrees/181"):
            for tool, command in self.TYPED:
                with self.subTest(cwd=cwd, command=command):
                    verdict = permissions.verdict(RULES, guard, tool, command, cwd, MAIN, guard.NoRepo(), bypass=False)
                    self.assertEqual(verdict[0], permissions.PASS, verdict)

    def test_a_typed_gh_pr_merge_stays_denied(self) -> None:
        # Only the runner's own subprocess merges through GitHub, after the gate (#300).
        for tool in ("PowerShell", "Bash"):
            for command in ("gh pr merge 154 --merge --match-head-commit abc", "gh pr merge 154 --admin"):
                with self.subTest(tool=tool, command=command):
                    verdict = permissions.verdict(RULES, guard, tool, command, MAIN, MAIN, guard.NoRepo(), bypass=False)
                    self.assertEqual(verdict[0], permissions.DENIED, verdict)

    def test_the_parser(self) -> None:
        parser = cli.build_parser()
        args = parser.parse_args(["merge", "154", "--base", "release/m4"])
        self.assertEqual((args.pr, args.base, args.sync_main, args.dry_run), (154, "release/m4", False, False))
        args = parser.parse_args(["merge", "154", "--base", "main", "--dry-run"])
        self.assertEqual((args.pr, args.base, args.dry_run), (154, "main", True))
        args = parser.parse_args(["merge-check", "--trial", "1", "2"])
        self.assertEqual((args.prs, args.trial, args.base), ([1, 2], True, None))
        with mock.patch("sys.stderr"), self.assertRaises(SystemExit):
            parser.parse_args(["merge", "154"])  # --base is required


if __name__ == "__main__":
    unittest.main()
