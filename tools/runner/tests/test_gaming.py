"""`gaming` (#1505): the switch's file, and that it holds every window run (exit 3, before anything starts) while
headless commands run as before."""

import contextlib
import io
import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest import mock

from runner import cli, gaming, hostjoin, launch, playcheck, shot
from runner.common import IS_WINDOWS, Failure, Result

NOW = datetime(2026, 11, 1, 21, 30, tzinfo=UTC)


class Switch(unittest.TestCase):
    """A temp file in place of the machine's, through gaming.FILE_VAR."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.file = Path(tmp.name) / "prime-game" / gaming.NAME
        self.env = {gaming.FILE_VAR: str(self.file)}
        patched = mock.patch.dict("os.environ", self.env)
        patched.start()
        self.addCleanup(patched.stop)

    def turn_on(self) -> None:
        gaming.main(on=True, env=self.env, now=NOW, out=lambda _: None)


class PathTest(unittest.TestCase):
    def test_the_variable_replaces_the_machine_file(self) -> None:
        self.assertEqual(gaming.path({gaming.FILE_VAR: "x/y.json"}), Path("x/y.json"))

    def test_the_machine_file_is_outside_every_checkout_beside_the_verify_slots(self) -> None:
        if IS_WINDOWS:
            where = gaming.path({"LOCALAPPDATA": r"C:\Users\h\AppData\Local"})
            self.assertEqual(where, Path(r"C:\Users\h\AppData\Local") / "prime-game" / "gaming-mode.json")
        else:
            where = gaming.path({"XDG_CACHE_HOME": "/home/h/.cache"})
            self.assertEqual(where, Path("/home/h/.cache/prime-game/gaming-mode.json"))


class SwitchTest(Switch):
    def test_on_status_off(self) -> None:
        said: list[str] = []
        self.assertEqual(gaming.main(status=True, env=self.env, out=said.append), 0)
        self.assertIn("gaming mode: off", said[-1])
        self.assertEqual(gaming.main(on=True, env=self.env, now=NOW, out=said.append), 0)
        self.assertIn("on since 2026-11-01T21:30:00Z", said[-1])
        self.assertIn("refuse with exit 3", said[-1])
        self.assertEqual(json.loads(self.file.read_text(encoding="utf-8"))["since"], "2026-11-01T21:30:00Z")
        self.assertTrue(gaming.is_on(self.env))
        gaming.main(status=True, env=self.env, out=said.append)
        self.assertIn("gaming mode: on since 2026-11-01T21:30:00Z", said[-1])
        self.assertEqual(gaming.main(off=True, env=self.env, out=said.append), 0)
        self.assertIn("off; window runs go ahead again", said[-1])
        self.assertFalse(self.file.exists())
        self.assertFalse(gaming.is_on(self.env))
        self.assertEqual(gaming.main(off=True, env=self.env, out=said.append), 0)
        self.assertIn("already off", said[-1])

    def test_on_twice_keeps_it_on(self) -> None:
        self.turn_on()
        self.turn_on()
        self.assertTrue(gaming.is_on(self.env))

    def test_a_file_it_cannot_parse_counts_as_on(self) -> None:
        self.file.parent.mkdir(parents=True)
        self.file.write_text("{not json", encoding="utf-8")
        self.assertEqual(gaming.since(self.env), "")
        with self.assertRaises(gaming.GamingMode):
            gaming.refuse_windows("shot", self.env)

    def test_one_choice_exactly(self) -> None:
        with self.assertRaises(Failure):
            gaming.main(env=self.env)
        with self.assertRaises(Failure):
            gaming.main(on=True, off=True, env=self.env)

    def test_the_cli_turns_it_on_and_off(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["gaming", "--on"]), 0)
            self.assertTrue(self.file.is_file())
            self.assertEqual(cli.main(["gaming", "--status"]), 0)
            self.assertEqual(cli.main(["gaming", "--off"]), 0)
        self.assertFalse(self.file.exists())


class Started(Exception):
    """A window run reached the code that starts Godot (or imports the project first)."""


def nothing_starts() -> contextlib.ExitStack:
    """Every way a window run starts a process raises Started instead."""
    stack = contextlib.ExitStack()
    boom = Started("a window run got past the switch")
    for target, name in (
        (shot, "godot"),
        (shot, "ensure_import"),
        (launch, "run"),
        (launch, "require_godot"),
        (launch, "gui_exe"),
        (launch, "ensure_import"),
        (playcheck, "require_godot"),
        (hostjoin, "require_godot"),
        (hostjoin, "supervise"),
        (hostjoin, "start"),
    ):
        stack.enter_context(mock.patch.object(target, name, side_effect=boom))
    return stack


class WindowRunsRefuseTest(Switch):
    WINDOW_RUNS = (
        ["shot", "tools/shot/probe.tscn"],
        ["playcheck"],
        ["run", "tools/shot/probe.tscn"],
        ["run", "tools/shot/probe.tscn", "--offscreen"],
        ["host", "--windows", "--local", "--seconds", "5"],
        ["join", "127.0.0.1", "--windows", "--seconds", "5"],
    )

    def run_cli(self, argv: list[str]) -> tuple[int, str]:
        out = io.StringIO()
        with nothing_starts(), contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            rc = cli.main(argv)
        return rc, out.getvalue()

    def test_every_window_run_refuses_with_exit_3_and_the_line(self) -> None:
        self.turn_on()
        for argv in self.WINDOW_RUNS:
            with self.subTest(argv=argv):
                rc, said = self.run_cli(argv)
                self.assertEqual(rc, 3, said)
                self.assertIn(gaming.LINE, said)

    def test_with_gaming_mode_off_they_get_past_the_switch(self) -> None:
        # Off: the same commands reach the code that starts Godot (here a stub that raises Started).
        for argv in self.WINDOW_RUNS:
            with self.subTest(argv=argv), mock.patch.object(shot, "has_display", return_value=True), \
                    mock.patch.object(playcheck, "IS_CI", False), self.assertRaises(Started):  # fmt: skip
                self.run_cli(argv)

    def test_host_and_join_headless_run_as_before(self) -> None:
        self.turn_on()
        self.assertFalse(hostjoin.choose_windows(headless=True, windows=False))
        with mock.patch.dict("os.environ", {hostjoin.AGENT_ENV: "1"}), mock.patch.object(hostjoin, "say"):
            self.assertFalse(hostjoin.choose_windows(headless=False, windows=False))


class HeadlessCommandsRunTest(Switch):
    def test_verify_check_test_lint_bots_perf_reach_their_work(self) -> None:
        self.turn_on()
        from runner import bots, check, gdunit, lint, perf, verify

        for argv, module, name in (
            (["verify", "--changed"], verify, "main"),
            (["check"], check, "main"),
            (["test"], gdunit, "main"),
            (["lint"], lint, "main"),
            (["bots"], bots, "main"),
            (["perf"], perf, "main"),
        ):
            with self.subTest(argv=argv), mock.patch.object(module, name, return_value=0) as entry:
                self.assertEqual(cli.main(argv), 0)
                entry.assert_called_once()

    def test_run_headless_starts_godot(self) -> None:
        self.turn_on()
        started: list[list[str]] = []

        def fake_run(cmd: list[str], **_kwargs: object) -> Result:
            started.append(cmd)
            return Result(0, "", False, 0.1)

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(launch, "run", fake_run), \
                mock.patch.object(launch, "require_godot", return_value="g"), \
                mock.patch.object(launch, "ensure_import"), mock.patch.object(launch, "LOGS", Path(tmp)), \
                mock.patch.object(launch, "say"), mock.patch.object(launch, "ok"):  # fmt: skip
            self.assertEqual(launch.main("tools/run/probe.gd", headless=True), 0)
        self.assertEqual(len(started), 1)
        self.assertIn("--headless", started[0])

    def test_the_bots_and_perf_runs_are_headless(self) -> None:
        # Their own window-free path: launch.main(headless=True), which the switch never stops (above).
        self.turn_on()
        from runner import bots, perf

        seen: list[dict[str, object]] = []

        def fake_main(_target: str, **kwargs: object) -> int:
            seen.append(kwargs)
            return 0

        with mock.patch.object(launch, "main", fake_main), mock.patch.object(perf, "launch", launch):
            perf.run_godot(2, 20, False, Path("raw.json"))
            with mock.patch.object(bots, "say", create=True):
                bots.main(None, instances=1, seconds=None, transport="enet")
        self.assertTrue(seen)
        self.assertTrue(all(kwargs.get("headless") is True for kwargs in seen), seen)


if __name__ == "__main__":
    unittest.main()
