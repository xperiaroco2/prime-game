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
    p.add_argument("files", nargs="*", help="repo-relative .gd files or folders (default: all project GDScript)")

    p = sub.add_parser("check", help="import, warnings policy, UID lint, parse and load check")
    p.add_argument("files", nargs="*", help="res:// paths to check (default: the whole project)")

    p = sub.add_parser("test", help="GdUnit4 tests, headless")
    p.add_argument("paths", nargs="*", help="test files or directories (default: res://tests)")
    p.add_argument(
        "--repeat", type=int, metavar="N", help="N runs in a row with a per-suite comparison (the nightly flaky job)"
    )
    p.add_argument(
        "--shards",
        type=int,
        metavar="K",
        help="K GdUnit4 processes at once (1: one process). Default: with no paths, from the CPU count; with paths, 1",
    )

    sub.add_parser("verify", help="everything CI runs, in the same order (definition of done)")
    sub.add_parser("selftest", help="unit tests of the runner itself")
    p = sub.add_parser("bots", help="bot scenarios through the network layers and the information-leak test")
    p.add_argument("scenarios", nargs="*", help="scenario file names in content/scenarios/ (default: every one)")
    p.add_argument("--instances", type=int, default=1, help="over ENet, one process per bot: one scenario of N bots")
    p.add_argument("--seconds", type=int, help="hard timeout of the run (default 300 in one process, 180 over ENet)")
    p.add_argument("--chaos", action="store_true", help="the chaos bots: a hostile and a malformed peer against the host")
    p.add_argument("--seed", type=int, help="--chaos: the first seed (default: random, printed)")
    p.add_argument("--runs", type=int, default=1, help="--chaos: seeds to run, from --seed up (default 1)")
    p.add_argument("--long", action="store_true", help="--chaos: the match in which the hostile also dies")
    p.add_argument("--enet", action="store_true", help="--chaos: over ENet on 127.0.0.1 (the invariants only)")

    from .mutants import HELP as MUTANTS_HELP, TEST_SECONDS

    p = sub.add_parser(
        "mutants",
        help="plant each fault of a spec in a scratch worktree of HEAD and run its tests there",
        epilog=MUTANTS_HELP,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("spec", help="the JSON spec of the mutants (format below)")
    p.add_argument(
        "--seconds",
        type=int,
        default=TEST_SECONDS,
        help=f"hard timeout of each test run; a longer one is an error (default {TEST_SECONDS})",
    )

    p = sub.add_parser(
        "playcheck", help="scripted game windows off-screen (and bots) with screenshots at named steps; never on CI"
    )
    p.add_argument("scenarios", nargs="*", help="scenario names in tools/playcheck/scenarios/ (default: every one)")
    p.add_argument("--seconds", type=int, help="hard timeout of each scenario's run (default 300)")

    p = sub.add_parser("perf", help="the host's cost with 10 bots: tick time, snapshot sizes, bytes per peer (not verify)")
    p.add_argument("--bots", type=int, default=10, help="bots in the match, 2 to 10 (default 10)")
    p.add_argument("--seconds", type=int, default=60, help="the round's length, 20 to 600 (default 60)")
    p.add_argument("--enet", action="store_true", help="real sockets on 127.0.0.1 and the real clock (default loopback)")
    p.add_argument("--baseline", help="report to compare with (default tools/out/perf/baseline.json, else the last)")

    p = sub.add_parser("board", help="the GitHub project board")
    board_sub = p.add_subparsers(dest="board_command", required=True, metavar="board_command")
    p = board_sub.add_parser("move", help="put an issue on the board in a column (agents use only these two)")
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument("column", choices=["in-progress", "in-review"])

    p = sub.add_parser("publish", help="fetch, rebase the task branch on its base, verify, push with a lease")
    p.add_argument("--base", help="branch to rebase on (default: the open PR's base, else start --base, else main)")

    # Merge safety (#181): checks across open PRs, and a manager's merge into a release branch.
    p = sub.add_parser("merge-check", help="open PRs onto their base and pairwise: textual conflicts, symbol overlaps")
    p.add_argument("prs", nargs="*", type=int, help="PR numbers (default: every open PR, grouped by base)")
    p.add_argument(
        "--base",
        help="only the PRs into this base (and their pairs across bases where both change shared files); with "
        "--trial, the base to merge onto",
    )
    p.add_argument(
        "--trial", action="store_true", help="merge the PRs in order onto the base in a scratch worktree, then verify"
    )
    p = sub.add_parser("merge", help="merge a PR (or main) into release/<x>: verify on the merged tree, push by hash")
    p.add_argument("pr", nargs="?", type=int, help="the PR to merge")
    p.add_argument("--base", required=True, help="the release branch, release/<x> (main is refused)")
    p.add_argument("--sync-main", action="store_true", help="merge origin/main into the base instead of a PR")

    p = sub.add_parser("start", help="put the checkout on the task branch of an issue; assign it; board In progress")
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument("--area", help="branch prefix when the issue has no single area label")
    p.add_argument(
        "--base", help="branch from origin/<base>, a parent with an open PR (default main); publish and the PR use it"
    )
    dirty = p.add_mutually_exclusive_group()
    dirty.add_argument("--include", action="store_true", help="carry uncommitted changes onto the task branch")
    dirty.add_argument("--stash", action="store_true", help="stash uncommitted changes first (never discarded)")
    where = p.add_mutually_exclusive_group()
    where.add_argument("--worktree", action="store_true", help="use .claude/worktrees/<n>: the engineer's default")
    where.add_argument("--here", action="store_true", help="work in this checkout, not a worktree (the exception for the engineer)")
    p.add_argument("--dry-run", action="store_true", help="say what would happen; only a git fetch runs")

    p = sub.add_parser("worktree-done", help="remove .claude/worktrees/<n> after its branch was merged")
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument(
        "--pushed", action="store_true", help="also when the branch is not merged but origin has all its commits"
    )

    p = sub.add_parser("normalize", help="re-save .tscn/.tres files in headless editor context")
    p.add_argument("files", nargs="+", help="repo-relative or res:// paths")

    p = sub.add_parser("shot", help="render a scene off-screen in a real window and save a PNG")
    p.add_argument("scene", help="the .tscn to render (repo-relative or res://)")
    p.add_argument("--out", help="PNG path (default: tools/out/shots/<scene>.png)")
    p.add_argument("--size", default="1280x720", help="window size WxH (default 1280x720)")
    p.add_argument("--frames", type=int, default=10, help="frames to wait before the capture (default 10)")

    p = sub.add_parser(
        "run",
        help="run a scene or script with the pinned Godot; arguments after -- reach the game",
        usage="run <scene.tscn | script.gd> [options] [-- <user args>]",
    )
    p.add_argument("target", help="a .tscn or a .gd that extends SceneTree (repo-relative or res://)")
    view = p.add_mutually_exclusive_group()
    view.add_argument("--headless", action="store_true", help="no window (GODOT_BIN); CI and agent checks")
    view.add_argument("--offscreen", action="store_true", help="a real window at the off-screen position of shot")
    p.add_argument("--seconds", type=int, default=60, help="hard timeout; kills the process tree (default 60)")
    p.add_argument("--instances", type=int, default=1, help="copies at once, each with its own log (default 1)")
    p.add_argument("--audio", choices=["dummy", "default"], default="dummy", help="audio driver (default dummy)")

    p = sub.add_parser("host", help="host the game over ENet in a window (--headless: M3's session); Ctrl+C stops")
    p.add_argument("--port", type=int, help="UDP port (default: the game's placeholder port)")
    p.add_argument("--clients", type=int, default=0, help="also start N clients joined on 127.0.0.1 (windows tiled)")
    p.add_argument("--local", action="store_true", help="listen on 127.0.0.1 only (this PC's clients; no firewall)")
    p.add_argument("--seconds", type=int, help="stop cleanly after N seconds (default: until Ctrl+C)")
    _view_options(p)

    p = sub.add_parser("join", help="join a host over ENet in a window (--headless: M3's session); Ctrl+C stops")
    p.add_argument("address", help="the host's address, such as 192.168.0.195 or 127.0.0.1")
    p.add_argument("--port", type=int, help="UDP port (default: the game's placeholder port)")
    p.add_argument("--seconds", type=int, help="stop cleanly after N seconds (default: until Ctrl+C)")
    _view_options(p)

    sub.add_parser("credits", help="write CREDITS.md from docs/credits/ (check verifies it and LFS coverage)")

    p = sub.add_parser(
        "agents-check", help="assert each subagent and workflow agent was served by the model family it asked for"
    )
    scope = p.add_mutually_exclusive_group()
    scope.add_argument("--session", help="session id (default: this Claude Code session, else all)")
    scope.add_argument("--all", action="store_true", help="every session of this checkout")

    p = sub.add_parser(
        "metrics", help="time, tokens and API list $ of the task workflows, from this checkout's transcripts"
    )
    p.add_argument(
        "--session",
        nargs="+",
        action="extend",
        default=[],
        metavar="ID[=LABEL]",
        help="only these sessions (an id or its prefix; =LABEL names its rows, default the first 8 characters)",
    )
    p.add_argument("--since", help="ISO 8601 time: only runs that started at or after it (a wave's start)")
    p.add_argument("--until", help="ISO 8601 time: only runs whose last line is before it (default now)")
    p.add_argument(
        "--ci", type=int, default=0, metavar="N", help="also CI from gh: the jobs and steps of the last N green runs"
    )
    p.add_argument("--out", help="folder for metrics.md and metrics.json (default tools/out/metrics)")
    p.add_argument("--compact", action="store_true", help="print only the summary of at most ten lines (wave comments)")

    p = sub.add_parser(
        "wave",
        help="a manager's runs and handover args from its transcript and the journals (a wave comment's body; "
        "posts nothing)",
    )
    what = p.add_mutually_exclusive_group(required=True)
    what.add_argument("--since", help="ISO 8601 time: write the wave comment's body, with the runs finished since it")
    what.add_argument("--args", type=int, metavar="N", help="print the args of issue N's latest launch as JSON")
    p.add_argument("--session", help="the manager session's id or its prefix (default: this Claude Code session)")
    p.add_argument("--workflow", metavar="NAME", help="--args: only launches of this workflow (issue-task, pr-rebase)")
    p.add_argument(
        "--out", help="the body's file (default tools/out/wave/wave-<session8>.md); with --args, also the JSON's"
    )

    p = sub.add_parser("pins", help="print pinned tool versions as JSON")
    p.add_argument("--get", choices=sorted(pins.ALL), help="print one value only")

    p = sub.add_parser("permissions", help="replay local transcripts through the permission rules and the guard")
    p.add_argument("--before", default="origin/main", help="the revision to compare with (default origin/main)")
    p.add_argument("--projects", default="", help="transcript folders glob under ~/.claude/projects")

    p = sub.add_parser("hook", help="Claude Code hooks (run by .claude/hooks/run-hook.sh, input on stdin)")
    p.add_argument("name", choices=["guard", "gd-edit"])
    return parser


def _view_options(p: argparse.ArgumentParser) -> None:
    """`host` and `join`: windows by default, headless in an agent's shell (CLAUDECODE set; the M4 ADR's E20)."""
    view = p.add_mutually_exclusive_group()
    view.add_argument("--headless", action="store_true", help="M3's headless session, no window; agents' checks")
    view.add_argument("--windows", action="store_true", help="windows where CLAUDECODE is set; agents never pass it")


def split_user_args(argv: list[str]) -> tuple[list[str], list[str]]:
    """`run … -- <args>`: everything after the first -- goes to the game untouched, never to argparse."""
    if argv[:1] == ["run"] and "--" in argv:
        cut = argv.index("--")
        return argv[:cut], argv[cut + 1 :]
    return argv, []


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure:
            reconfigure(encoding="utf-8", errors="replace")
    argv, user_args = split_user_args(sys.argv[1:] if argv is None else argv)
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

            if args.repeat is not None:
                if args.shards is not None:
                    raise Failure("--repeat runs one process per run; drop --shards")
                return gdunit.repeat(args.repeat, paths=args.paths or None)
            shards = {"shards": args.shards} if args.shards is not None else {}
            return gdunit.main(paths=args.paths or None, **shards)
        if args.command == "verify":
            from . import verify

            return verify.main()
        if args.command == "selftest":
            from . import verify

            return verify.selftest()
        if args.command == "bots":
            from . import bots

            if args.chaos:
                if args.scenarios or args.instances != 1:
                    raise Failure("--chaos plays its own match: no scenario names and no --instances")
                return bots.chaos(args.seed, args.runs, long=args.long, enet=args.enet, seconds=args.seconds)
            if args.seed is not None or args.runs != 1 or args.long or args.enet:
                raise Failure("--seed, --runs, --long and --enet need --chaos")
            return bots.main(args.scenarios, instances=args.instances, seconds=args.seconds)
        if args.command == "mutants":
            from . import mutants

            return mutants.main(args.spec, seconds=args.seconds)
        if args.command == "playcheck":
            from . import playcheck

            return playcheck.main(args.scenarios, seconds=args.seconds)
        if args.command == "perf":
            from . import perf

            return perf.main(bots=args.bots, seconds=args.seconds, enet=args.enet, baseline=args.baseline)
        if args.command == "board":
            from . import board

            return board.move(args.issue, args.column)
        if args.command == "publish":
            from . import publish

            return publish.main(base=args.base)
        if args.command == "merge-check":
            from . import merge

            return merge.check(args.prs, base=args.base, trial=args.trial)
        if args.command == "merge":
            from . import merge

            return merge.merge(args.pr, base=args.base, sync_main=args.sync_main)
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
                base=args.base,
            )
        if args.command == "worktree-done":
            from . import start

            return start.worktree_done(args.issue, pushed=args.pushed)
        if args.command == "normalize":
            from . import normalize

            return normalize.main(args.files)
        if args.command == "shot":
            from . import shot

            return shot.main(args.scene, out=args.out, size=args.size, frames=args.frames)
        if args.command == "run":
            from . import launch

            return launch.main(
                args.target,
                headless=args.headless,
                offscreen=args.offscreen,
                seconds=args.seconds,
                instances=args.instances,
                audio=args.audio,
                user_args=user_args,
            )
        if args.command == "host":
            from . import hostjoin

            return hostjoin.host(
                port=args.port,
                clients=args.clients,
                local=args.local,
                seconds=args.seconds,
                headless=args.headless,
                windows=args.windows,
            )
        if args.command == "join":
            from . import hostjoin

            return hostjoin.join(
                args.address, port=args.port, seconds=args.seconds, headless=args.headless, windows=args.windows
            )
        if args.command == "credits":
            from . import credits

            return credits.main()
        if args.command == "agents-check":
            from . import agents_check

            return agents_check.main(session=args.session, all_sessions=args.all)
        if args.command == "metrics":
            from . import metrics

            return metrics.main(
                args.session, since=args.since, until=args.until, ci=args.ci, out=args.out, compact=args.compact
            )
        if args.command == "wave":
            from . import wave

            return wave.main(
                session=args.session, since=args.since, args_issue=args.args, out=args.out, workflow=args.workflow
            )
        if args.command == "pins":
            print(pins.ALL[args.get] if args.get else json.dumps(pins.ALL, indent=2))
            return 0
        if args.command == "permissions":
            from . import permissions

            return permissions.main(["--before", args.before, "--projects", args.projects])
        if args.command == "hook":
            from . import hooks

            return hooks.main(args.name)
    except Failure as exc:
        bad(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130
    return 2
