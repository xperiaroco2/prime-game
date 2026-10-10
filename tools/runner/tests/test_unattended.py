"""Issue #750: the "nobody is watching" sign. With a manager's sign for the session, every guard ask is a deny with the
same reason and one line more; without it, or with one that is not in force, the answer is today's ask. The `unattended`
command sets and clears the sign."""

import io
import json
import re
import shutil
import tempfile
import unittest
import unittest.mock
from datetime import UTC, datetime, timedelta
from pathlib import Path

from runner import cli, hooks, unattended
from runner.common import ROOT, Failure

# The main checkout, also when the selftest runs in a worktree (as test_hooks does).
MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
SESSION = "6f1c2a9e-0b3d-4c58-9a47-1d2e3f4a5b6c"
OTHER = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
PROJECTS = "C:\\Users\\x\\.claude\\projects\\D--prime-game"
ASKS = "Copy-Item x .claude\\settings.json"


class SignFolderCase(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)

    def write(self, session: str = SESSION, until: datetime | None = None, **fields: object) -> Path:
        until = until or datetime.now(UTC) + timedelta(hours=9)
        data = {"session": session, "until": hooks.sign_stamp(until), **fields}
        path = self.folder / f"{session}.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def clear_folder(self) -> None:
        for old in self.folder.iterdir():
            shutil.rmtree(old) if old.is_dir() else old.unlink()


class GuardAnswerTest(SignFolderCase):
    def answer(self, command: str = ASKS, tool: str = "PowerShell", **payload: object) -> dict[str, str]:
        """The hook's answer (empty: silent) to a call of the session, the sign folder patched."""
        call = {"tool_name": tool, "tool_input": {"command": command}, "cwd": MAIN, "session_id": SESSION, **payload}
        out = io.StringIO()
        with (
            unittest.mock.patch.object(hooks, "unattended_folder", return_value=str(self.folder)),
            unittest.mock.patch("sys.stdout", out),
        ):
            self.assertEqual(hooks.pre_tool_use(call), 0)
        text = out.getvalue()
        return json.loads(text)["hookSpecificOutput"] if text else {}

    def test_without_a_sign_the_guard_asks_as_before(self) -> None:
        output = self.answer()
        self.assertEqual(output["permissionDecision"], "ask")
        self.assertNotIn(hooks.UNATTENDED_NOTE, output["permissionDecisionReason"])

    def test_with_the_sign_the_ask_is_a_deny_with_the_same_reason_and_one_line_more(self) -> None:
        asked = self.answer()
        self.write()
        denied = self.answer()
        self.assertEqual(denied["hookEventName"], "PreToolUse")
        self.assertEqual(denied["permissionDecision"], "deny")
        self.assertEqual(denied["permissionDecisionReason"], asked["permissionDecisionReason"] + "\n" + hooks.UNATTENDED_NOTE)
        self.assertEqual(hooks.UNATTENDED_NOTE, "unattended: put this command in the For-you block for the engineer")

    def test_every_kind_of_ask_becomes_a_deny(self) -> None:
        self.write()
        for tool, command in (
            ("PowerShell", "Remove-Item -Recurse core"),
            ("Bash", f'git -C "{MAIN}" clean -fdx'),
            ("Bash", "gh issue close 5 --repo someone/else"),
            ("Bash", "cp x .claude/settings.json"),
        ):
            with self.subTest(command=command):
                output = self.answer(command, tool)
                self.assertEqual(output["permissionDecision"], "deny")
                self.assertTrue(output["permissionDecisionReason"].endswith(hooks.UNATTENDED_NOTE))

    def test_the_sign_allows_nothing(self) -> None:
        self.write()
        self.assertEqual(self.answer("git status; tools\\run.cmd lint"), {})
        # a call with nothing to ask about stays as it is, in acceptEdits too; an ask there is a deny, not an allow
        with unittest.mock.patch.object(hooks, "unattended", return_value=False):
            self.assertEqual(self.answer("git status", permission_mode="acceptEdits"), {})
        self.assertEqual(self.answer(permission_mode="acceptEdits")["permissionDecision"], "deny")

    def test_a_sign_that_is_not_in_force_for_the_session_counts_for_nothing(self) -> None:
        path = self.folder / f"{SESSION}.json"
        now = datetime.now(UTC)
        cases = {
            "another session's": lambda: self.write(OTHER),
            "ended": lambda: self.write(until=now - timedelta(minutes=1)),
            "more than a night ahead": lambda: self.write(until=now + timedelta(hours=40)),
            "names another session": lambda: path.write_text(json.dumps({"session": OTHER, "until": hooks.sign_stamp(now + timedelta(hours=2))})),
            "without an end": lambda: path.write_text(json.dumps({"session": SESSION}), encoding="utf-8"),
            "an end that is no time": lambda: path.write_text(json.dumps({"session": SESSION, "until": "tomorrow"}), encoding="utf-8"),
            "not a JSON object": lambda: path.write_text("[1]", encoding="utf-8"),
            "not JSON": lambda: path.write_text("{not json", encoding="utf-8"),
            "a folder": lambda: path.mkdir(),
        }
        for name, make in cases.items():
            with self.subTest(sign=name):
                self.clear_folder()
                make()
                self.assertEqual(self.answer()["permissionDecision"], "ask")

    def test_the_sign_ends_at_its_time(self) -> None:
        now = datetime.now(UTC)
        self.write(until=now + timedelta(minutes=5))
        self.assertEqual(self.answer()["permissionDecision"], "deny")
        self.assertIsNotNone(hooks.read_sign(SESSION, str(self.folder), now + timedelta(minutes=4)))
        self.assertIsNone(hooks.read_sign(SESSION, str(self.folder), now + timedelta(minutes=5)))
        self.assertIsNone(hooks.read_sign(SESSION, str(self.folder), now + timedelta(hours=1)))

    def test_a_session_id_that_is_not_an_id_never_names_a_file(self) -> None:
        self.write()
        now = datetime.now(UTC)
        for name in ("", "../" + SESSION, SESSION + "/..", "*", "6f1c2a9e"):
            with self.subTest(session=name):
                self.assertIsNone(hooks.read_sign(name, str(self.folder), now))
        self.assertEqual(self.answer(session_id="../x")["permissionDecision"], "ask")

    def test_another_session_of_the_human_still_asks(self) -> None:
        self.write()
        theirs = f"{PROJECTS}\\{OTHER}.jsonl"
        self.assertEqual(self.answer(session_id=OTHER)["permissionDecision"], "ask")
        self.assertEqual(self.answer(session_id=OTHER, transcript_path=theirs)["permissionDecision"], "ask")
        self.assertEqual(self.answer(session_id="", transcript_path=theirs)["permissionDecision"], "ask")

    def test_the_managers_workflow_agents_are_covered_through_their_transcript(self) -> None:
        self.write()
        agent = f"{PROJECTS}\\{SESSION}\\subagents\\workflows\\wf_00bf975a-2bd\\agent-a99aa5faf02b2e7b2.jsonl"
        self.assertEqual(self.answer(session_id=OTHER, transcript_path=agent)["permissionDecision"], "deny")
        self.assertEqual(self.answer(session_id="", transcript_path=f"{PROJECTS}\\{SESSION}.jsonl")["permissionDecision"], "deny")

    def test_the_main_checkout_holds_the_signs_for_every_worktree(self) -> None:
        self.assertEqual(hooks.main_root("D:\\prime-game\\.claude\\worktrees\\750"), "D:\\prime-game")
        self.assertEqual(hooks.main_root("D:/prime-game/.claude/worktrees/750/"), "D:/prime-game")
        self.assertEqual(hooks.main_root("D:/prime-game"), "D:/prime-game")
        self.assertEqual(Path(hooks.unattended_folder()).parts[-3:], hooks.UNATTENDED_FOLDER)

    def test_the_hook_reads_the_sign_only_where_it_asks(self) -> None:
        self.write()
        out = io.StringIO()
        call = {"tool_name": "Bash", "tool_input": {"command": "git status"}, "cwd": MAIN, "session_id": SESSION}
        with (
            unittest.mock.patch.object(hooks, "manager_sign", side_effect=AssertionError("read without an ask")),
            unittest.mock.patch("sys.stdout", out),
        ):
            self.assertEqual(hooks.pre_tool_use(call), 0)
        self.assertEqual(out.getvalue(), "")


class CommandTest(SignFolderCase):
    NOW = datetime(2026, 10, 10, 22, 0, tzinfo=UTC)

    def run_command(self, *args: object, env: dict[str, str] | None = None, **kwargs: object) -> list[str]:
        lines: list[str] = []
        env = {unattended.SESSION_VAR: SESSION} if env is None else env
        rc = unattended.main(*args, env=env, now=self.NOW, folder=self.folder, out=lines.append, **kwargs)  # type: ignore[arg-type]
        self.assertEqual(rc, 0)
        return lines

    def test_hours_set_a_sign_the_guard_reads_and_off_clears_it(self) -> None:
        lines = self.run_command(None, 9.0, False, False, False)
        self.assertIn("2026-10-11T07:00:00Z", lines[0])
        self.assertEqual(hooks.read_sign(SESSION, str(self.folder), self.NOW), self.NOW + timedelta(hours=9))
        data = json.loads((self.folder / f"{SESSION}.json").read_text(encoding="utf-8"))
        self.assertEqual((data["session"], data["since"]), (SESSION, "2026-10-10T22:00:00Z"))
        self.assertIn("in force until 2026-10-11T07:00:00Z", self.run_command(None, None, False, False, True)[0])
        self.assertIn("1 sign(s) cleared", self.run_command(None, None, True, False, False)[0])
        self.assertIsNone(hooks.read_sign(SESSION, str(self.folder), self.NOW))
        self.assertIn("no sign to clear", self.run_command(None, None, True, False, False)[0])
        self.assertIn("no sign; the guard asks", self.run_command(None, None, False, False, True)[0])

    def test_until_takes_an_iso_time_or_the_next_clock_time(self) -> None:
        self.run_command("2026-10-11T05:30Z", None, False, False, False)
        self.assertEqual(hooks.read_sign(SESSION, str(self.folder), self.NOW), datetime(2026, 10, 11, 5, 30, tzinfo=UTC))
        local = self.NOW.astimezone()
        wanted = local.replace(hour=(local.hour + 2) % 24, minute=0, second=0, microsecond=0)
        got = unattended.parse_until(wanted.strftime("%H:%M"), self.NOW)
        self.assertEqual(got.astimezone().strftime("%H:%M"), wanted.strftime("%H:%M"))
        self.assertTrue(self.NOW < got <= self.NOW + timedelta(hours=24))
        again = unattended.parse_until(local.strftime("%H:%M"), self.NOW)  # the time of now: tomorrow's
        self.assertTrue(self.NOW + timedelta(hours=23) < again <= self.NOW + timedelta(hours=24, minutes=1))
        self.assertEqual(unattended.parse_until("2026-10-11T05:30", self.NOW), datetime(2026, 10, 11, 5, 30).astimezone())

    def test_a_sign_must_end_in_the_future_within_a_night(self) -> None:
        for until, hours in ((None, 0.0), (None, -1.0), (None, 17.0), ("2026-10-10T21:00Z", None), ("2026-10-12T05:30Z", None),
                             ("tomorrow", None), ("25:00", None), ("12:xx", None)):  # fmt: skip
            with self.subTest(until=until, hours=hours):
                with self.assertRaises(Failure):
                    self.run_command(until, hours, False, False, False)
        self.assertEqual(list(self.folder.iterdir()), [])
        with self.assertRaises(Failure):
            self.run_command(None, None, False, False, False)  # neither
        with self.assertRaises(Failure):
            self.run_command("07:00", 5.0, False, False, False)  # both

    def test_the_sign_needs_the_session_it_is_for(self) -> None:
        for env in ({}, {unattended.SESSION_VAR: ""}, {unattended.SESSION_VAR: "../x"}):
            with self.subTest(env=env):
                with self.assertRaises(Failure):
                    self.run_command(None, 9.0, False, False, False, env=env)
                with self.assertRaises(Failure):
                    self.run_command(None, None, True, False, False, env=env)
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_a_new_sign_replaces_the_session_s_and_removes_the_ones_that_ended(self) -> None:
        old = self.write(OTHER, until=self.NOW - timedelta(hours=1))
        junk = self.folder / "junk.json"
        junk.write_text("{", encoding="utf-8")
        kept = self.write("1a2b3c4d-1111-4222-8333-444455556666", until=self.NOW + timedelta(hours=3))
        self.run_command(None, 2.0, False, False, False)
        self.run_command(None, 9.0, False, False, False)
        self.assertEqual(sorted(p.name for p in self.folder.iterdir()), sorted([kept.name, f"{SESSION}.json"]))
        self.assertFalse(old.exists() or junk.exists())
        self.assertEqual(hooks.read_sign(SESSION, str(self.folder), self.NOW), self.NOW + timedelta(hours=9))

    def test_off_clears_only_this_session_s_sign_unless_all(self) -> None:
        self.write(SESSION, until=self.NOW + timedelta(hours=3))
        other = self.write(OTHER, until=self.NOW + timedelta(hours=3))
        self.run_command(None, None, True, False, False)
        self.assertEqual([p.name for p in self.folder.iterdir()], [other.name])
        self.write(SESSION, until=self.NOW + timedelta(hours=3))
        self.run_command(None, None, True, True, False, env={})  # --all needs no session
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_status_names_the_signs_and_tells_which_is_in_force(self) -> None:
        self.write(SESSION, until=self.NOW + timedelta(hours=3))
        self.write(OTHER, until=self.NOW - timedelta(hours=3))
        lines = self.run_command(None, None, False, False, True)
        self.assertEqual(len(lines), 2)
        self.assertTrue(any(SESSION[:8] in line and "(this session)" in line and "in force until" in line for line in lines))
        self.assertTrue(any(OTHER[:8] in line and "ignores it" in line for line in lines))


class CliTest(unittest.TestCase):
    def parse(self, *args: str) -> object:
        return cli.build_parser().parse_args(["unattended", *args])

    def test_one_of_until_hours_off_status_is_required(self) -> None:
        for args in ([], ["--until", "07:00", "--hours", "3"], ["--off", "--status"]):
            with self.subTest(args=args), unittest.mock.patch("sys.stderr", io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.parse(*args)
        parsed = self.parse("--off", "--all")
        self.assertEqual((parsed.off, parsed.all), (True, True))  # type: ignore[attr-defined]

    def test_the_help_says_what_the_sign_does(self) -> None:
        text = " ".join(cli.build_parser()._subparsers._group_actions[0].choices["unattended"].format_help().split())  # type: ignore[union-attr, attr-defined]
        for phrase in ("deny", "For-you block", "fails closed", "at most 16 h", "human's own session never counts"):
            self.assertIn(phrase, text)


if __name__ == "__main__":
    unittest.main()
