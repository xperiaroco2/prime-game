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

    p = sub.add_parser("start", help="put the checkout on the task branch of an issue; assign it; board In progress")
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument("--area", help="branch prefix when the issue has no single area label")
    dirty = p.add_mutually_exclusive_group()
    dirty.add_argument("--include", action="store_true", help="carry uncommitted changes onto the task branch")
    dirty.add_argument("--stash", action="store_true", help="stash uncommitted changes first (never discarded)")
    where = p.add_mutually_exclusive_group()
    where.add_argument("--worktree", action="store_true", help="use .claude/worktrees/<n> (engineer only)")
    where.add_argument("--here", action="store_true", help="never a worktree, even with another session active")
    p.add_argument("--dry-run", action="store_true", help="say what would happen; only a git fetch runs")

    p = sub.add_parser("worktree-done", help="remove .claude/worktrees/<n> after its branch was merged")
    p.add_argument("issue", type=int, help="issue number")

    p = sub.add_parser("normalize", help="re-save .tscn/.tres files in headless editor context")
    p.add_argument("files", nargs="+", help="repo-relative or res:// paths")

    p = sub.add_parser("shot", help="render a scene off-screen in a real window and save a PNG")
    p.add_argument("scene", help="the .tscn to render (repo-relative or res://)")
    p.add_argument("--out", help="PNG path (default: tools/out/shots/<scene>.png)")
    p.add_argument("--size", default="1280x720", help="window size WxH (default 1280x720)")
    p.add_argument("--frames", type=int, default=10, help="frames to wait before the capture (default 10)")

    sub.add_parser("credits", help="write CREDITS.md from docs/credits/ (check verifies it and LFS coverage)")

    p = sub.add_parser("agents-check",help="assert each subagent was served by the model family it asked for")
    scope = p.add_mutually_exclusive_group()
    scope.add_argument("--session", help="session id (default: this Claude Code session, else all)")
    scope.add_argument("--all", action="store_true", help="every session of this checkout")

    p = sub.add_parser("pins", help="print pinned tool versions as JSON")
    p.add_argument("--get", choices=sorted(pins.ALL), help="print one value only")

    p = sub.add_parser("hook", help="Claude Code hooks (run by .claude/hooks/run-hook.sh, input on stdin)")
    p.add_argument("name", choices=["guard", "gd-edit"])
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
        if args.command == "start":
            from . import start

            return start.main(
                args.issue,
                area=args.area,
                stash=args.stash,
                include=args.include,
                worktree=args.worktree,
                here=args.here,
                dry_run=args.dry_run,
            )
        if args.command == "worktree-done":
            from . import start

            return start.worktree_done(args.issue)
        if args.command == "normalize":
            from . import normalize

            return normalize.main(args.files)
        if args.command == "shot":
            from . import shot

            return shot.main(args.scene, out=args.out, size=args.size, frames=args.frames)
        if args.command == "credits":
            from . import credits

            return credits.main()
        if args.command == "agents-check":
            from . import agents_check

            return agents_check.main(session=args.session, all_sessions=args.all)
        if args.command == "pins":
            print(pins.ALL[args.get] if args.get else json.dumps(pins.ALL, indent=2))
            return 0
        if args.command == "hook":
            from . import hooks

            return hooks.main(args.name)
    except Failure as exc:
        bad(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130
    return 2
