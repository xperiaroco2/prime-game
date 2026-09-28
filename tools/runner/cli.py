"""Command-line entry of the task runner."""

from __future__ import annotations

import argparse
import json
import sys

from . import pins
from .common import Failure, bad


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run",
        description="prime-game task runner. Windows: tools\\run.cmd <command>; bash: tools/run.sh <command>.",
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="command")

    p = sub.add_parser("doctor", help="check the environment and print fixes")
    p.add_argument("--quick", action="store_true", help="only what verify needs (Python, Godot, gdtoolkit, addons)")

    p = sub.add_parser("lint", help="gdformat --check + gdlint; CLAUDE.md budgets and rule/agent frontmatter")
    p.add_argument("--fix", action="store_true", help="reformat instead of checking (then strips CR)")
    p.add_argument("files", nargs="*", help="repo-relative .gd files (default: all project GDScript)")

    p = sub.add_parser("check", help="import, warnings policy, UID lint, parse and load check")
    p.add_argument("files", nargs="*", help="res:// paths to check (default: the whole project)")

    p = sub.add_parser("test", help="GdUnit4 tests, headless")
    p.add_argument("paths", nargs="*", help="test files or directories (default: res://tests)")

    sub.add_parser("verify", help="everything CI runs, in the same order (definition of done)")
    sub.add_parser("selftest", help="unit tests of the runner itself")

    p = sub.add_parser("board", help="the GitHub project board")
    board_sub = p.add_subparsers(dest="board_command", required=True, metavar="board_command")
    p = board_sub.add_parser("move", help="put an issue on the board in a column (agents use only these two)")
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument("column", choices=["in-progress", "in-review"])

    p = sub.add_parser("publish", help="fetch, rebase the task branch on its base, verify, push with a lease")
    p.add_argument("--base", help="branch to rebase on (default: the open PR's base, else main)")

    p = sub.add_parser("pins", help="print pinned tool versions as JSON")
    p.add_argument("--get", choices=sorted(pins.ALL), help="print one value only")
    return parser


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure:
            reconfigure(encoding="utf-8", errors="replace")
    args = build_parser().parse_args(argv)
    try:
        if args.command == "doctor":
            from . import doctor

            return doctor.main(quick=args.quick)
        if args.command == "lint":
            from . import lint

            return lint.main(fix=args.fix, files=args.files or None)
        if args.command == "check":
            from . import check

            return check.main(files=args.files or None)
        if args.command == "test":
            from . import gdunit

            return gdunit.main(paths=args.paths or None)
        if args.command == "verify":
            from . import verify

            return verify.main()
        if args.command == "selftest":
            from . import verify

            return verify.selftest()
        if args.command == "board":
            from . import board

            return board.move(args.issue, args.column)
        if args.command == "publish":
            from . import publish

            return publish.main(base=args.base)
        if args.command == "pins":
            print(pins.ALL[args.get] if args.get else json.dumps(pins.ALL, indent=2))
            return 0
    except Failure as exc:
        bad(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130
    return 2
