"""Command-line entry of the task runner."""

from __future__ import annotations

import argparse
import json
import sys

from . import pins
from .common import Failure, bad


class _Formatter(argparse.HelpFormatter):
    """Refills each paragraph of a description or epilog on its own; a paragraph with an indented line (a list of
    exit codes) is kept as written."""

    def _fill_text(self, text: str, width: int, indent: str) -> str:
        paragraphs = text.split("\n\n")
        return "\n\n".join(
            "\n".join(indent + line for line in para.splitlines())
            if any(line.startswith(" ") for line in para.splitlines())
            else super(_Formatter, self)._fill_text(para, width, indent)
            for para in paragraphs
        )


class _Parser(argparse.ArgumentParser):
    """Every command's parser: its description and epilog keep their paragraphs (`<command> --help`)."""

    def __init__(self, *args: object, **kwargs: object) -> None:
        kwargs.setdefault("formatter_class", _Formatter)
        super().__init__(*args, **kwargs)  # type: ignore[arg-type]


# Root CLAUDE.md lists the command names only; each command's --help is where an agent reads what it does, so its
# description keeps everything the old commands table said (tools/runner/tests/test_cli_help.py checks it).
def build_parser() -> argparse.ArgumentParser:
    parser = _Parser(
        prog="run",
        description="prime-game task runner. Windows: tools\\run.cmd <command>; Git Bash and CI: tools/run.sh "
        "<command>. Each command's --help says what it does and its options; special exit codes where a command "
        "has them.",
        epilog="Godot, Python and gdtoolkit run only through the runner. Logs: tools/out/logs/; reports: "
        "tools/out/gdunit/.",
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="command")

    p = sub.add_parser(
        "doctor",
        help="check the environment and print fixes",
        description="Check the environment and print a fix for each problem. Run it first in every session. On "
        "Windows the full run also adds the worktrees' root CLAUDE.md and rules to the claudeMdExcludes of the main "
        "checkout's .claude/settings.local.json (#385, #406); --quick only reads them.",
    )
    p.add_argument("--quick", action="store_true", help="only what verify needs (Python, Godot, gdtoolkit, addons)")

    p = sub.add_parser(
        "lint",
        help="gdformat --check + gdlint; CLAUDE.md budgets and rule/agent frontmatter",
        description="gdformat --check and gdlint on the named .gd files or folders. With none: all project GDScript, "
        "plus the CLAUDE.md budgets (the lines Claude Code loads), the frontmatter of rules, skills and agents, and the "
        "relative links in skills.",
    )
    p.add_argument("--fix", action="store_true", help="reformat instead of checking (then strips CR)")
    p.add_argument("files", nargs="*", help="repo-relative .gd files or folders (default: all project GDScript)")

    p = sub.add_parser(
        "check",
        help="import, warnings policy, UID lint, parse and load check",
        description="Headless import, the warnings policy, UID lint, then parse and load of every script and scene "
        "(or of the named res:// paths). It also fails on an LFS asset without a docs/credits/ entry (see credits).",
    )
    p.add_argument("files", nargs="*", help="res:// paths to check (default: the whole project)")

    p = sub.add_parser(
        "test",
        help="GdUnit4 tests, headless",
        description="GdUnit4 tests, headless. With no paths, every suite under res://tests in K processes at once "
        "(--shards), the frame-bound suites at fixed fps in shards of their own, as in verify; with paths, one "
        "process in real time (--fixed-fps or --real-time chooses the clock). A run is judged by the exit code and "
        "results.xml (reports: tools/out/gdunit/), never by the console; orphan nodes fail it. --repeat N: N runs in "
        "a row with a per-suite comparison (a flaky hunt).",
    )
    p.add_argument("paths", nargs="*", help="test files or directories (default: res://tests)")
    p.add_argument(
        "--repeat", type=int, metavar="N", help="N runs in a row with a per-suite comparison (the nightly flaky job)"
    )
    p.add_argument(
        "--shards",
        type=int,
        metavar="K",
        help="K GdUnit4 processes at once (1: one at a time). Default: with no paths, from the CPU count; with paths, 1",
    )
    clock = p.add_mutually_exclusive_group()
    clock.add_argument(
        "--fixed-fps",
        dest="fixed_fps",
        action="store_const",
        const=True,
        help="suites on a simulated clock (the engine's --fixed-fps 60): every named one. With no paths this is the "
        "default (verify's and CI's, #341): gdunit.FIXED_FPS_SUITES in shards of their own, the rest real-time",
    )
    clock.add_argument(
        "--real-time",
        dest="fixed_fps",
        action="store_const",
        const=False,
        help="every suite in real time (the default for named paths and --repeat, so the nightly flaky job): the #222 "
        "class, several physics steps in one frame under load, shows only so",
    )

    sub.add_parser(
        "verify",
        help="everything CI runs, in the same order (definition of done)",
        description="Everything CI runs, in the same order: doctor, then a Python lane and a Godot lane at once. On "
        "a PC a run first takes one of 2 machine-wide slots, waiting at most 600 s (in a quiet window of slots "
        "--quiet, the one slot). The definition-of-done gate. "
        "Every agent runs it in the background into a log and polls it with wait (docs/AGENT_WORKFLOW.md §11).",
    )
    p = sub.add_parser(
        "selftest",
        help="unit tests of the runner itself",
        description="The runner's own tests (tools/runner/tests), part of verify.",
    )
    p.add_argument(
        "--group",
        choices=("all", "python", "godot"),
        default="all",
        help="python: only the tests that start no Godot (CI's minimum-Python job, #349); godot: only those that do; "
        "all (default): both, then the count check",
    )
    p = sub.add_parser(
        "wait",
        help="wait at most S s for a background job's last line exit=<n>: its summary and exit code; "
        "else 124 (still running); 2: no log",
        description="Wait at most S s (default 240) for a background job's last line exit=<n> (the job run as "
        "`<command> > <log> 2>&1; echo \"exit=$?\" >> <log>`), then print its summary and return n. Else 124 with a "
        "'still running' line: call wait again, never start the job again. 2 with a 'wait: ' line: no log, or one "
        "it cannot read. --verified: 0 when the newest verify passed at HEAD with a clean tree under 2 hours ago "
        "(publish reuses it).",
    )
    p.add_argument(
        "log", nargs="?", help="the job's log: its output, then the line exit=<n> (docs/AGENT_WORKFLOW.md §11)"
    )
    p.add_argument(
        "--verified",
        action="store_true",
        help="no log: 0 when the newest verify passed at HEAD with a clean tree under 2 hours ago (publish reuses "
        "it instead of verifying again)",
    )
    p.add_argument("--max", type=int, default=240, metavar="S", help="seconds to wait, 1 to 270 (default 240)")
    p = sub.add_parser(
        "bots",
        help="bot scenarios through the network layers and the information-leak test",
        description="Bot scenarios (content/scenarios/) through the host and client sessions, and the "
        "information-leak test. --instances N (N > 1): one scenario over ENet, a process per bot. --chaos: the "
        "chaos bots, a hostile and a malformed peer against the host (no --seed: a random one, printed).",
    )
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
        description="Plant each fault of the spec in a scratch worktree of HEAD and run its tests there.\n"
        "Exit 2: tell the human (exit codes below).",
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
        "playcheck",
        help="scripted game windows off-screen (and bots) with screenshots at named steps; never on CI",
        description="The game in off-screen windows (bots for the rest of the players) running a scenario's scripted "
        "steps, with PNGs at its named steps. Desktop only: CI and verify never run it; an agent may.",
    )
    p.add_argument("scenarios", nargs="*", help="scenario names in tools/playcheck/scenarios/ (default: every one)")
    p.add_argument("--seconds", type=int, help="hard timeout of each scenario's run (default 300)")

    p = sub.add_parser(
        "perf",
        help="the host's cost with 10 bots: tick time, snapshot sizes, bytes per peer (not verify)",
        description="The host's cost in a match of bots (10 by default): tick time, snapshot sizes and bytes per "
        "peer, compared with the baseline or the last run. Not part of verify.",
    )
    p.add_argument("--bots", type=int, default=10, help="bots in the match, 2 to 10 (default 10)")
    p.add_argument("--seconds", type=int, default=60, help="the round's length, 20 to 600 (default 60)")
    p.add_argument("--enet", action="store_true", help="real sockets on 127.0.0.1 and the real clock (default loopback)")
    p.add_argument("--baseline", help="report to compare with (default tools/out/perf/baseline.json, else the last)")

    p = sub.add_parser(
        "load",
        help="bounded busy loops to test under load, in a verify slot (waits like verify; none free in time: exit 1)",
        description="Busy loops (2 per logical CPU, 600 s by default) in a verify slot, to test something under load. "
        "It takes the slot like verify (the same wait); no slot free in time: exit 1. Start it in the background, "
        "take your steps after its 'load: running' line, and let the load end (or wait for it with wait <log>).",
    )
    p.add_argument("--loops", type=int, help="busy processes, 1 to 256 (default 2 per logical CPU)")
    p.add_argument("--seconds", type=float, default=600.0, help="how long they run, up to 1140 (default 600)")

    p = sub.add_parser(
        "slots",
        help="who holds and waits for the verify slots (--status); one slot for a while (--quiet <hours> | off)",
        description="The machine-wide verify slots, shared by every checkout of this PC (docs/AGENT_WORKFLOW.md §11). "
        "--status prints the quiet window, the holders (worktree, branch, pid, since), the runs waiting for a slot, "
        "the runs going on without one, and the last hour's verify runs that ran without a slot (over the limit), "
        "from the slots folder and the verify history; its last line says whether a run waits or runs over the "
        "limit (a manager launches nothing while one does). --quiet <hours> (more than 0, at most 24) starts a quiet window for the engineer's "
        "own use of the PC: until its end time every new verify and load run takes one slot, and its slot line names "
        "the window; a run already in a slot finishes there, and a run already waiting joins the window. --quiet off ends it. An expired, unreadable or "
        "malformed quiet file is ignored with a warning, and a run still waits at most 600 s.",
    )
    what = p.add_mutually_exclusive_group(required=True)
    what.add_argument(
        "--status", action="store_true", help="print the holders, the waiters and the runs without a slot"
    )
    what.add_argument(
        "--quiet", metavar="HOURS|off", help="one slot for HOURS (more than 0, at most 24) from now; off ends it"
    )

    p = sub.add_parser(
        "board",
        help="the GitHub project board",
        description="The GitHub project board. board move <issue> in-progress (or in-review) puts an open issue on "
        "the board in that column.",
    )
    board_sub = p.add_subparsers(dest="board_command", required=True, metavar="board_command")
    p = board_sub.add_parser(
        "move",
        help="put an issue on the board in a column (agents use only these two)",
        description="Put an open issue on the project board in that column (agents use only these two).",
    )
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument("column", choices=["in-progress", "in-review"])

    p = sub.add_parser(
        "publish",
        help="fetch, rebase the task branch on its base, verify (unless an identical tree was just verified green), "
        "push with a lease",
        description="Fetch, rebase the task branch on its PR's base (else start --base, else main), run verify, "
        "push the branch with a lease. The only way a rebased branch goes up. The verify is skipped, and publish says "
        "so, when an identical tree was just verified green: the newest verify passed at the same head, tree and "
        "runner, with a clean tree then and now, under 2 hours ago (wait --verified tells in advance).",
    )
    p.add_argument("--base", help="branch to rebase on (default: the open PR's base, else start --base, else main)")

    # Merge safety (#181): checks across open PRs, and a manager's merge into a release branch or, gated, main (#300).
    p = sub.add_parser(
        "merge-check",
        help="open PRs onto their base and pairwise: textual conflicts, symbol overlaps",
        description="Open PRs onto their base and pairwise: textual conflicts and symbol overlaps; exit 1 on either. "
        "--trial: the PRs merged in order onto the base in a scratch worktree, then verify.",
    )
    p.add_argument("prs", nargs="*", type=int, help="PR numbers (default: every open PR, grouped by base)")
    p.add_argument(
        "--base",
        help="only the PRs into this base (and their pairs across bases where both change shared files); with "
        "--trial, the base to merge onto",
    )
    p.add_argument(
        "--trial", action="store_true", help="merge the PRs in order onto the base in a scratch worktree, then verify"
    )
    p = sub.add_parser(
        "merge",
        help="merge a PR (or main) into release/<x> (verify on the merged tree, push by hash), or a PR into main "
        "through GitHub when its gate passes",
        description="A manager's merge (docs/AGENT_WORKFLOW.md §7.1). --base release/<x>: the PR (or, with "
        "--sync-main, origin/main) merged into it, verify on the merged tree, push by hash. --base main: the PR "
        "merged through GitHub when its gate passes.",
    )
    p.add_argument("pr", nargs="?", type=int, help="the PR to merge")
    p.add_argument("--base", required=True, help="release/<x>, or main (a PR through the gate, #300)")
    p.add_argument("--sync-main", action="store_true", help="merge origin/main into the base instead of a PR")
    p.add_argument("--dry-run", action="store_true", help="print the gate's verdict and merge nothing")
    p = sub.add_parser(
        "merge-train",
        help="merge PRs into main one by one: publish each in its worktree (a red verify retried once), wait for its "
        "CI, then merge's gate; a PR that fails is skipped with the reason (a background job: poll it with wait)",
        description="A manager's merge of PRs into main one by one, in the order given: publish in each one's "
        "worktree (a red verify retried once), its CI, then merge's gate; a PR that fails is skipped with the reason "
        "and the train goes on. A background job: run it into a log and poll it with wait.",
    )
    p.add_argument("prs", nargs="+", type=int, help="the PRs to merge, in this order")
    p.add_argument("--base", required=True, help="main (the only base it merges into)")
    p.add_argument("--dry-run", action="store_true", help="print the plan and each gate's verdict now; merge nothing")
    p.add_argument(
        "--recent",
        type=int,
        default=10,
        metavar="M",
        help="a worktree whose last commit is younger than M minutes counts as held by a live run (0: off; default 10)",
    )

    p = sub.add_parser(
        "start",
        help="put the checkout on the task branch of an issue; assign it; board In progress",
        description="Put the task branch <area>/<n>-<slug> of issue n, from main or --base P (the branch of a "
        "parent's open PR), in the checkout (the engineer: in its worktree .claude/worktrees/<n>); assign the issue "
        "and move it to In progress on the board (skill start-task).",
    )
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

    p = sub.add_parser(
        "worktree-done",
        help="remove .claude/worktrees/<n> after its branch was merged",
        description="Remove a task's worktree .claude/worktrees/<n> after its branch was merged (with --pushed, a "
        "pushed spike's).",
    )
    p.add_argument("issue", type=int, help="issue number")
    p.add_argument(
        "--pushed", action="store_true", help="also when the branch is not merged but origin has all its commits"
    )

    p = sub.add_parser(
        "normalize",
        help="re-save .tscn/.tres files in headless editor context",
        description="Re-save .tscn/.tres files as the editor would (headless editor context).",
    )
    p.add_argument("files", nargs="+", help="repo-relative or res:// paths")

    p = sub.add_parser(
        "shot",
        help="render a scene off-screen in a real window and save a PNG",
        description="An off-screen PNG of a scene: render it in a real window at an off-screen position and save it.",
    )
    p.add_argument("scene", help="the .tscn to render (repo-relative or res://)")
    p.add_argument("--out", help="PNG path (default: tools/out/shots/<scene>.png)")
    p.add_argument("--size", default="1280x720", help="window size WxH (default 1280x720)")
    p.add_argument("--frames", type=int, default=10, help="frames to wait before the capture (default 10)")

    p = sub.add_parser(
        "run",
        help="run a scene or script with the pinned Godot; arguments after -- reach the game",
        usage="run <scene.tscn | script.gd> [options] [-- <user args>]",
        description="Run a scene or script with the pinned Godot; arguments after -- reach the game. It fails on a "
        "non-zero exit, a timeout or an ERROR: line. An agent's own checks use --headless.",
    )
    p.add_argument("target", help="a .tscn or a .gd that extends SceneTree (repo-relative or res://)")
    view = p.add_mutually_exclusive_group()
    view.add_argument("--headless", action="store_true", help="no window (GODOT_BIN); CI and agent checks")
    view.add_argument("--offscreen", action="store_true", help="a real window at the off-screen position of shot")
    p.add_argument("--seconds", type=int, default=60, help="hard timeout; kills the process tree (default 60)")
    p.add_argument("--instances", type=int, default=1, help="copies at once, each with its own log (default 1)")
    p.add_argument("--audio", choices=["dummy", "default"], default="dummy", help="audio driver (default dummy)")

    host_join = (
        "--headless: M3's session, printing the roster, the phase and the counters. Where CLAUDECODE is set (an "
        "agent's shell) that is the default: an agent's runs stay headless and never pass --windows. An agent's check: "
        "host --local --seconds S."
    )
    p = sub.add_parser(
        "host",
        help="host the game over ENet in a window (--headless: M3's session); Ctrl+C stops",
        description="Host the game over ENet in a window; --clients N more windows join it (tiled on one PC). "
        f"Ctrl+C or --seconds stops it cleanly. {host_join}",
    )
    p.add_argument("--port", type=int, help="UDP port (default: the game's placeholder port)")
    p.add_argument("--clients", type=int, default=0, help="also start N clients joined on 127.0.0.1 (windows tiled)")
    p.add_argument("--local", action="store_true", help="listen on 127.0.0.1 only (this PC's clients; no firewall)")
    p.add_argument("--seconds", type=int, help="stop cleanly after N seconds (default: until Ctrl+C)")
    _view_options(p)

    p = sub.add_parser(
        "join",
        help="join a host over ENet in a window (--headless: M3's session); Ctrl+C stops",
        description=f"Join a host over ENet in a window. Ctrl+C or --seconds stops it cleanly. {host_join}",
    )
    p.add_argument("address", help="the host's address, such as 192.168.0.195 or 127.0.0.1")
    p.add_argument("--port", type=int, help="UDP port (default: the game's placeholder port)")
    p.add_argument("--seconds", type=int, help="stop cleanly after N seconds (default: until Ctrl+C)")
    _view_options(p)

    p = sub.add_parser(
        "section",
        help="a doc's outline (§, title, lines, tokens) or exactly the sections named; --refs: § references",
        description="Print a doc's outline (§, title, line range, token estimate) or exactly the sections named, "
        "each up to the next heading of the same or a higher level. A doc is a path, ARCHITECTURE, AGENT_WORKFLOW "
        "or part of an ADR's file name. Read a long doc by section instead of whole. lint fails a duplicate § and a "
        "§ reference that does not resolve; --refs runs that check and lists each reference with no doc in scope.",
    )
    p.add_argument("doc", nargs="?", help="a path, ARCHITECTURE, AGENT_WORKFLOW, or part of an ADR's file name")
    p.add_argument("sections", nargs="*", help="§ numbers (4.5 or §4.5) or, for unnumbered headings, title words")
    p.add_argument("--refs", action="store_true", help="lint's § check, listing each reference with no doc in scope")

    sub.add_parser(
        "credits",
        help="write CREDITS.md from docs/credits/ (check verifies it and LFS coverage)",
        description="Write CREDITS.md from docs/credits/. check fails when it is stale or an LFS asset has no entry.",
    )

    p = sub.add_parser(
        "agents-check",
        help="assert each subagent and workflow agent was served by the model family it asked for",
        description="Assert that each subagent and workflow agent ran on the model family it asked for.",
    )
    scope = p.add_mutually_exclusive_group()
    scope.add_argument("--session", help="session id (default: this Claude Code session, else all)")
    scope.add_argument("--all", action="store_true", help="every session of this checkout")

    p = sub.add_parser(
        "metrics",
        help="time, tokens and API list $ of the task workflows, from this checkout's transcripts",
        description="Time, tokens and API list $ per task workflow, from this checkout's transcripts. --track: each "
        "track's share of the week against its --budget.",
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
    p.add_argument("--no-gh", action="store_true", help="skip GitHub: the quality scorecard's CI, PR signals unknown")
    p.add_argument(
        "--track",
        nargs="+",
        action="extend",
        default=[],
        metavar="NAME",
        help="each track's %% of the week since --since (the reset), over the main checkout's, -ui's and -art's "
        "sessions; a session's track: --session ID=TRACK, else its kickoff's 'Track: <name>' line, else its checkout's "
        "(-ui: ui, -art: art), else untracked; 'all' names every track found",
    )
    p.add_argument(
        "--budget",
        nargs="+",
        action="extend",
        type=float,
        default=[],
        metavar="PCT",
        help="with --track: each named track's budget in %% of the week, in their order, and its plan to date "
        "(budget x days since --since / 7)",
    )

    p = sub.add_parser(
        "wave",
        help="a manager's runs and handover args from its transcript and the journals (a wave comment's body; "
        "posts nothing)",
        description="A manager's finished and running runs and handover args, from its transcript and the journals: "
        "--since T writes the whole wave comment's body (runs, PRs, merge-check, cost, housekeeping, handover args; "
        "--base B: whose merges, open PRs and merge-check; it posts nothing; its last line is the handover verdict, "
        "'handover due: <why>' or 'handover not due'); --args N prints issue N's latest launch args as JSON.",
    )
    what = p.add_mutually_exclusive_group(required=True)
    what.add_argument("--since", help="ISO 8601 time: write the wave comment's body, with the runs finished since it")
    what.add_argument("--args", type=int, metavar="N", help="print the args of issue N's latest launch as JSON")
    p.add_argument("--session", help="the manager session's id or its prefix (default: this Claude Code session)")
    p.add_argument("--workflow", metavar="NAME", help="--args: only launches of this workflow (issue-task, pr-rebase)")
    p.add_argument(
        "--out", help="the body's file (default tools/out/wave/wave-<session8>.md); with --args, also the JSON's"
    )
    p.add_argument("--base", metavar="B", help="--since: whose merges, open PRs and merge-check to report (default main)")
    p.add_argument("--plan", type=int, metavar="N", help="--since: the plan issue, named in the header")
    p.add_argument("--title", metavar="T", help="--since: the body's title (default 'Wave report since <T>')")
    p.add_argument("--notes", metavar="FILE", help="--since: the manager's own text, placed under the title")
    p.add_argument("--stage-since", metavar="T", help="--since: add the stage's total API list $ and %% of the week")
    p.add_argument(
        "--no-merge-check", dest="merge_check", action="store_false", help="--since: skip merge-check (no git fetch)"
    )

    p = sub.add_parser(
        "pins", help="print pinned tool versions as JSON", description="Print the pinned tool versions as JSON."
    )
    p.add_argument("--get", choices=sorted(pins.ALL), help="print one value only")

    p = sub.add_parser(
        "permissions",
        help="replay local transcripts through the permission rules and the guard",
        description="Replay this machine's transcripts through the permission rules and the guard, compared with "
        "--before.",
    )
    p.add_argument("--before", default="origin/main", help="the revision to compare with (default origin/main)")
    p.add_argument("--projects", default="", help="transcript folders glob under ~/.claude/projects")
    p.add_argument("--since", default="", help="only calls from this day on (YYYY-MM-DD)")
    p.add_argument("--mode", choices=["bypass", "default"], default="bypass", help="the permission mode to model")
    p.add_argument("--list", action="store_true", help="list each cause that stops a call, with examples")
    p.add_argument("--observed", action="store_true", help="the prompts, denials and blocks the transcripts record")

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

            fixed = {"fixed_fps": args.fixed_fps} if args.fixed_fps is not None else {}
            if args.repeat is not None:
                if args.shards is not None:
                    raise Failure("--repeat runs one process per run; drop --shards")
                return gdunit.repeat(args.repeat, paths=args.paths or None, **fixed)
            shards = {"shards": args.shards} if args.shards is not None else {}
            return gdunit.main(paths=args.paths or None, **shards, **fixed)
        if args.command == "verify":
            from . import verify

            return verify.main()
        if args.command == "selftest":
            from . import verify

            return verify.selftest(args.group)
        if args.command == "wait":
            from . import wait

            if args.verified == (args.log is not None):
                print("wait: give a log, or --verified alone", flush=True)
                return wait.MISSING  # never 1, which reads like a red job
            return wait.verified() if args.verified else wait.main(args.log, max_seconds=args.max)
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
        if args.command == "load":
            from . import load

            return load.main(args.loops, args.seconds)
        if args.command == "slots":
            from . import slots

            if args.status:
                return slots.status()
            return slots.quiet_command(args.quiet, me=slots.this_checkout())
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

            return merge.merge(args.pr, base=args.base, sync_main=args.sync_main, dry_run=args.dry_run)
        if args.command == "merge-train":
            from . import train

            return train.main(args.prs, base=args.base, dry_run=args.dry_run, recent_minutes=args.recent)
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
        if args.command == "section":
            from . import refs, section

            if args.refs == bool(args.doc):
                print("section: give a doc (and sections), or --refs alone", flush=True)
                return 2
            return refs.main() if args.refs else section.main(args.doc, args.sections)
        if args.command == "credits":
            from . import credits

            return credits.main()
        if args.command == "agents-check":
            from . import agents_check

            return agents_check.main(session=args.session, all_sessions=args.all)
        if args.command == "metrics":
            from . import metrics

            return metrics.main(
                args.session, since=args.since, until=args.until, ci=args.ci, out=args.out, compact=args.compact,
                no_gh=args.no_gh, track=args.track, budget=args.budget,
            )
        if args.command == "wave":
            from . import wave

            return wave.main(
                session=args.session, since=args.since, args_issue=args.args, out=args.out, workflow=args.workflow,
                base=args.base, plan=args.plan, title=args.title, notes=args.notes, stage_since=args.stage_since,
                merge_check=args.merge_check,
            )  # fmt: skip
        if args.command == "pins":
            print(pins.ALL[args.get] if args.get else json.dumps(pins.ALL, indent=2))
            return 0
        if args.command == "permissions":
            from . import permissions

            extra = ["--list"] * args.list + ["--observed"] * args.observed
            forwarded = ["--before", args.before, "--projects", args.projects, "--since", args.since]
            return permissions.main(forwarded + ["--mode", args.mode] + extra)
        if args.command == "hook":
            from . import hooks

            return hooks.main(args.name)
    except Failure as exc:
        bad(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130
    return 2
