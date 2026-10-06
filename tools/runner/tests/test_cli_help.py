"""Root CLAUDE.md's commands section against cli.py (#340): its names line lists every command and only commands, and
each command's --help still says what the commands table that the names line replaced said."""

import argparse
import re
import unittest

from runner import cli, common

# Not for agents or humans to type: Claude Code's hooks call it (.claude/hooks/run-hook.sh).
UNLISTED = {"hook"}

# What each row of the old commands table said, as phrases its --help must contain (whitespace and case ignored). A
# command added later needs only a description; a phrase changes when its help is reworded, never silently dropped.
OLD_ROWS = {
    "agents-check": ["subagent and workflow agent", "model family"],
    "board": ["board move <issue> in-progress", "in-review", "project board"],
    "bots": [
        "host and client sessions",
        "information-leak test",
        "--instances N (N > 1): one scenario over ENet, a process per bot",
        "hostile and a malformed peer against the host",
        "no --seed: a random one, printed",
    ],
    "check": [
        "headless import",
        "warnings policy",
        "UID lint",
        "parse and load of every script and scene",
        "LFS asset without a docs/credits/ entry",
    ],
    "credits": ["CREDITS.md from docs/credits/", "an LFS asset has no entry"],
    "doctor": ["check the environment", "print a fix", "first in every session", "--quick"],
    "host": [
        "over ENet in a window",
        "tiled on one PC",
        "--headless: M3's session, printing the roster, the phase and the counters",
        "CLAUDECODE",
        "never pass --windows",
        "host --local --seconds",
    ],
    "join": [
        "join a host over ENet in a window",
        "--headless: M3's session, printing the roster, the phase and the counters",
        "CLAUDECODE",
        "never pass --windows",
    ],
    "lint": [
        "gdformat",
        "gdlint",
        "all project GDScript",
        "CLAUDE.md budgets",
        "frontmatter of rules, skills and agents",
        "relative links in skills",
    ],
    "load": [
        "busy loops (2 per logical CPU, 600 s",
        "in a verify slot",
        "test something under load",
        "in the background",
        "after its 'load: running' line",
        "no slot free in time: exit 1",
    ],
    "merge": [
        "--base release/<x>",
        "verify on the merged tree, push by hash",
        "--base main",
        "through GitHub when its gate passes",
        "--sync-main",
        "--dry-run",
        "§7.1",
    ],
    "merge-check": [
        "open PRs onto their base and pairwise",
        "textual conflicts and symbol overlaps; exit 1 on either",
        "--trial: the PRs merged in order onto the base in a scratch worktree, then verify",
    ],
    "merge-train": [
        "PRs into main one by one",
        "publish in each one's worktree",
        "its CI, then merge's gate",
        "a PR that fails is skipped with the reason",
        "a background job",
        "--base",
        "--dry-run",
        "--recent",
    ],
    "metrics": ["API list $ per task workflow", "transcripts", "--since", "--until", "--compact"],
    "mutants": ["each fault of the spec in a scratch worktree of HEAD", "its tests there", "exit 2: tell the human"],
    "normalize": [".tscn/.tres", "as the editor would"],
    "perf": [
        "tick time",
        "bytes per peer",
        "10 by default",
        "compared with the baseline or the last run",
        "not part of verify",
    ],
    "permissions": ["transcripts", "the permission rules and the guard", "--before"],
    "pins": ["pinned tool versions", "--get"],
    "playcheck": [
        "off-screen windows",
        "bots for the rest",
        "scripted steps",
        "PNGs at its named steps",
        "CI and verify never run it",
    ],
    "publish": [
        "rebase the task branch on its PR's base (else start --base, else main)",
        "run verify",
        "push the branch with a lease",
    ],
    "run": [
        "pinned Godot",
        "fails on a non-zero exit, a timeout or an ERROR: line",
        "own checks use --headless",
        "-- <user args>",
    ],
    "selftest": ["the runner's own tests"],
    "shot": ["off-screen PNG of a scene"],
    "start": [
        "<area>/<n>-<slug>",
        "from main or --base P (the branch of a parent's open PR)",
        "in its worktree",
        "assign the issue",
        "In progress",
        "start-task",
        "--here",
        "--include",
        "--stash",
        "--dry-run",
    ],
    "test": [
        "GdUnit4 tests, headless",
        "with no paths, every suite under res://tests in K processes at once",
        "exit code and results.xml",
        "orphan nodes fail it",
        "--repeat N: N runs in a row",
        "flaky hunt",
        "--shards K",
        "the frame-bound suites at fixed fps",
        "as in verify",
        "--fixed-fps",
        "--real-time",
    ],
    "verify": [
        "everything CI runs",
        "doctor, then a Python lane and a Godot lane at once",
        "one of 2 machine-wide slots, waiting at most 600 s",
        "definition-of-done gate",
    ],
    "wait": [
        "at most S s (default 240)",
        "last line exit=<n>",
        "print its summary and return n",
        "124",
        "still running",
        "no log",
        "--verified: 0 when the newest verify passed at HEAD with a clean tree",
    ],
    "wave": [
        "finished and running runs and handover args",
        "the whole wave comment's body (runs, PRs, merge-check, cost, housekeeping, handover args",
        "--base B",
        "posts nothing",
        "launch args as JSON",
    ],
    "worktree-done": ["remove a task's worktree", "merged", "pushed spike", "--pushed"],
}

ANSI = re.compile(r"\x1b\[[0-9;]*m")
BACKTICKED = re.compile(r"`([^`]+)`")


def commands(parser: argparse.ArgumentParser) -> dict[str, argparse.ArgumentParser]:
    action = next(a for a in parser._actions if isinstance(a, argparse._SubParsersAction))
    return dict(action.choices)


def squeezed(text: str) -> str:
    """Help text with its colour codes and every whitespace removed (argparse wraps it, also at hyphens), lowercased."""
    return re.sub(r"\s+", "", ANSI.sub("", text)).lower()


def commands_section(text: str | None = None) -> list[str]:
    """The lines from `## Commands` up to the next heading, without its trailing blank lines (a blank line inside
    the section still counts, so the section cannot grow past one)."""
    if text is None:
        text = (common.ROOT / "CLAUDE.md").read_text(encoding="utf-8")
    lines = text.splitlines()
    start = lines.index("## Commands")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("#")), len(lines))
    section = lines[start:end]
    while section and not section[-1].strip():
        section.pop()
    return section


def names_line() -> str:
    found = [line for line in commands_section() if line.startswith("Commands: ")]
    if len(found) != 1:
        raise AssertionError(f"root CLAUDE.md's commands section needs one line starting 'Commands: ', found {found}")
    return found[0]


def listed_names(line: str) -> list[str]:
    """The command names of the names line: its backticked words, without the flags in its notes."""
    return [name for name in BACKTICKED.findall(line) if not name.startswith("-")]


class NamesLineTest(unittest.TestCase):
    def test_the_names_line_lists_every_command_and_only_commands(self) -> None:
        listed = listed_names(names_line())
        known = set(commands(cli.build_parser())) - UNLISTED
        self.assertEqual(sorted(known - set(listed)), [], "commands of cli.py missing from root CLAUDE.md's names line")
        self.assertEqual(sorted(set(listed) - known), [], "names in root CLAUDE.md's names line that cli.py lacks")
        self.assertEqual(len(listed), len(set(listed)), "a name is listed twice")

    def test_the_names_are_in_alphabetical_order(self) -> None:
        listed = listed_names(names_line())
        self.assertEqual(listed, sorted(listed), "a new command slots in alphabetically")

    def test_the_names_line_marks_bots_as_the_leak_test_and_chaos_as_hostile_peers(self) -> None:
        line = names_line()
        note = line[line.index("`bots`") :].split(")", 1)[0]
        self.assertIn("information-leak test", note)
        self.assertIn("`--chaos`", note)
        self.assertIn("hostile peers", note)

    def test_the_commands_section_is_at_most_five_lines(self) -> None:
        section = commands_section()
        self.assertLessEqual(len(section), 5, section)
        self.assertTrue(any("--help" in line for line in section), "the section points at <command> --help")

    def test_the_commands_section_runs_to_the_next_heading_past_a_blank_line(self) -> None:
        text = "## Rules\nr\n\n## Commands\na\nb\n\nc\nd\ne\n\n## Shell\ns\n"
        self.assertEqual(commands_section(text), ["## Commands", "a", "b", "", "c", "d", "e"])
        self.assertEqual(commands_section("## Commands\na\n\n"), ["## Commands", "a"])

    def test_listed_names_skip_the_flags_of_a_note(self) -> None:
        line = "Commands: `a` `bots` (the leak test; `--chaos`: hostile) `c-d`"
        self.assertEqual(listed_names(line), ["a", "bots", "c-d"])


class HelpTest(unittest.TestCase):
    def test_each_command_has_a_description_for_its_help(self) -> None:
        for name, parser in commands(cli.build_parser()).items():
            if name not in UNLISTED:
                with self.subTest(command=name):
                    self.assertTrue((parser.description or "").strip(), f"{name} --help needs a description")

    def test_each_help_says_what_its_old_row_said(self) -> None:
        parsers = commands(cli.build_parser())
        self.assertEqual(sorted(set(OLD_ROWS) - set(parsers)), [], "a command of the old table is gone from cli.py")
        for name, phrases in OLD_ROWS.items():
            text = squeezed(parsers[name].format_help())
            for phrase in phrases:
                with self.subTest(command=name, phrase=phrase):
                    self.assertIn(squeezed(phrase), text)

    def test_the_runner_help_names_the_rules_of_the_old_section(self) -> None:
        text = squeezed(cli.build_parser().format_help())
        rules = ["each command's --help", "Godot, Python and gdtoolkit run only through the runner", "tools/out/logs/"]
        for phrase in rules:
            with self.subTest(phrase=phrase):
                self.assertIn(squeezed(phrase), text)

    def test_a_description_keeps_its_paragraphs_and_its_indented_lists(self) -> None:
        parser = cli._Parser(prog="x", description="first words\n\nsecond words\n\nexit codes:\n  0  ok\n  1  not ok")
        text = parser.format_help()
        self.assertIn("first words\n\nsecond words\n\nexit codes:\n  0  ok\n  1  not ok", text)


if __name__ == "__main__":
    unittest.main()
