"""`host` and `join`: the options, the processes they start, the clean stop and the report.

The supervision tests run small Python processes in place of Godot; the real run starts a headless host and two
local clients of tools/run/headless_session.gd on a free port of 127.0.0.1 and waits for the full lobby roster.
"""

import io
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, hostjoin, verify
from runner.common import ROOT, Failure, godot_bin

LOCALHOST = hostjoin.LOCALHOST

# A stand-in for the Godot script: argv[1] picks what it does, --stop-file= is the runner's stop file.
FAKE = """
import pathlib, sys, time
what = sys.argv[1]
stop = pathlib.Path(next(a for a in sys.argv if a.startswith("--stop-file=")).split("=", 1)[1])
def say(text):
    print(text, flush=True)
if what == "dies":
    say("session: cannot host: no levels")
    sys.exit(1)
if what == "refused":
    say("session: could not join: full (the host's lobby is full)")
    sys.exit(1)
if what == "late-host":
    time.sleep(0.5)
if what in ("host", "late-host"):
    say("session: hosting base_mode.tres on 127.0.0.1:1")
if what == "error":
    say("SCRIPT ERROR: boom")
say("session: roster: Player1 [1]")
while what == "stubborn" or not stop.exists():
    time.sleep(0.05)
say("session: stopped")
"""


def fake(label: str, what: str, stop: Path) -> hostjoin.Part:
    part = hostjoin.Part(label, [])
    part.cmd = [sys.executable, "-c", FAKE, what, f"--stop-file={stop}"]
    return part


class OptionsTest(unittest.TestCase):
    def test_parser(self) -> None:
        args = cli.build_parser().parse_args(["host"])
        self.assertEqual((args.port, args.clients, args.local, args.seconds), (None, 0, False, None))
        args = cli.build_parser().parse_args(["host", "--port", "24999", "--clients", "2", "--local", "--seconds", "9"])
        self.assertEqual((args.port, args.clients, args.local, args.seconds), (24999, 2, True, 9))
        args = cli.build_parser().parse_args(["join", "192.168.0.195", "--port", "24999"])
        self.assertEqual((args.address, args.port, args.seconds), ("192.168.0.195", 24999, None))

    def test_the_host_and_its_local_clients(self) -> None:
        stop = Path("stop")
        parts = hostjoin.host_parts(24999, 2, local=True, stop=stop)
        self.assertEqual([p.label for p in parts], ["host", "client 2", "client 3"])
        self.assertEqual(parts[0].user_args, ["--host", "--local", "--port=24999", f"--stop-file={stop}"])
        for part in parts[1:]:
            self.assertEqual(part.user_args, ["--join=127.0.0.1", "--port=24999", f"--stop-file={stop}"])
        alone = hostjoin.host_parts(None, 0, local=False, stop=stop)
        self.assertEqual([p.user_args for p in alone], [["--host", f"--stop-file={stop}"]])
        joiner = hostjoin.join_parts("192.168.0.195", None, stop=stop)
        self.assertEqual([p.user_args for p in joiner], [["--join=192.168.0.195", f"--stop-file={stop}"]])

    def test_the_godot_command_runs_the_script_headless(self) -> None:
        parts = hostjoin.join_parts("10.0.0.2", 7, stop=Path("s"))
        hostjoin.set_commands(parts, "godot")
        cmd = parts[0].cmd
        self.assertIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("-s") + 1], f"res://{hostjoin.SCRIPT}")
        self.assertEqual(cmd[cmd.index("--") + 1 :], ["--join=10.0.0.2", "--port=7", "--stop-file=s"])
        self.assertTrue((ROOT / hostjoin.SCRIPT).is_file())

    def test_wrong_options_fail_before_godot_starts(self) -> None:
        for kwargs, text in (
            ({"port": 0}, "--port"),
            ({"port": 65536}, "--port"),
            ({"port": None, "clients": -1}, "--clients"),
            ({"port": None, "clients": hostjoin.MAX_CLIENTS + 1}, "--clients"),
            ({"port": None, "seconds": 0}, "--seconds"),
            ({"port": None, "address": " "}, "address"),
            ({"port": None, "address": "--port"}, "address"),
        ):
            with self.subTest(kwargs=kwargs), self.assertRaises(Failure) as caught:
                hostjoin.check_options(**kwargs)  # type: ignore[arg-type]
            self.assertIn(text, str(caught.exception))
        hostjoin.check_options(port=24600, clients=hostjoin.MAX_CLIENTS, seconds=1, address="127.0.0.1")
        with mock.patch.object(hostjoin, "say"), mock.patch.object(hostjoin, "require_godot") as godot:
            with self.assertRaises(Failure):
                hostjoin.host(port=None, clients=99, local=False, seconds=None)
            with self.assertRaises(Failure):
                hostjoin.join("", port=None, seconds=None)
        godot.assert_not_called()


class SupervisionTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(tmp.cleanup)
        self.stop = Path(tmp.name) / "stop"
        out = mock.patch("sys.stdout", new_callable=io.StringIO)
        self.out = out.start()
        self.addCleanup(out.stop)

    def run_parts(self, parts: list[hostjoin.Part], **kwargs: object) -> list[hostjoin.Part]:
        hostjoin.supervise(parts, stop=self.stop, cwd=ROOT, **kwargs)  # type: ignore[arg-type]
        return parts

    def test_the_clients_start_once_the_host_hosts_and_every_part_stops_cleanly(self) -> None:
        started: list[tuple[str, bool]] = []
        real_start = hostjoin.start

        def recording(part: hostjoin.Part, **kwargs: object) -> None:
            hosting = any(line.startswith(hostjoin.HOSTING) for line in parts[0].lines)
            started.append((part.label, hosting))
            real_start(part, **kwargs)  # type: ignore[arg-type]

        parts = [fake("host", "late-host", self.stop), fake("client 2", "client", self.stop)]
        with mock.patch.object(hostjoin, "start", recording):
            self.run_parts(parts, seconds=2)
        self.assertEqual(started, [("host", False), ("client 2", True)])
        self.assertEqual([p.problem for p in parts], ["", ""], self.out.getvalue())
        for part in parts:
            self.assertEqual(part.lines[-1], "session: stopped")
        self.assertIn("[client 2] session: roster: Player1 [1]", self.out.getvalue())
        self.assertIn("2s passed, stopping", self.out.getvalue())
        self.assertFalse(self.stop.exists())

    def test_ctrl_c_stops_every_part_cleanly(self) -> None:
        real_sleep = time.sleep
        interrupted: list[bool] = []

        def interrupt_once(seconds: float) -> None:
            # Ctrl+C once both parts run and printed their roster; the grace wait then sleeps for real.
            if not interrupted and all(any("roster" in line for line in p.lines) for p in parts):
                interrupted.append(True)
                raise KeyboardInterrupt
            real_sleep(seconds)

        parts = [fake("host", "host", self.stop), fake("client 2", "client", self.stop)]
        with mock.patch.object(hostjoin.time, "sleep", interrupt_once):
            self.run_parts(parts, seconds=None)
        self.assertIn("Ctrl+C, stopping", self.out.getvalue())
        self.assertEqual([p.problem for p in parts], ["", ""], self.out.getvalue())

    def test_until_ends_the_wait(self) -> None:
        parts = [fake("join", "client", self.stop)]
        began = time.monotonic()
        self.run_parts(parts, seconds=60, until=lambda ps: any("roster" in line for line in ps[0].lines))
        self.assertLess(time.monotonic() - began, 30)
        self.assertEqual(parts[0].problem, "")

    def test_a_part_that_ignores_the_stop_is_killed_and_fails(self) -> None:
        parts = [fake("join", "stubborn", self.stop)]
        with mock.patch.object(hostjoin, "GRACE_SECONDS", 1):
            self.run_parts(parts, seconds=1)
            self.assertIn("was killed", parts[0].problem)

    def test_a_refused_join_fails_with_its_reason(self) -> None:
        parts = self.run_parts([fake("join", "refused", self.stop)], seconds=30)
        self.assertEqual(parts[0].problem, "exited 1 (could not join: full (the host's lobby is full))")

    def test_a_host_that_never_hosts_starts_no_client(self) -> None:
        parts = self.run_parts([fake("host", "dies", self.stop), fake("client 2", "client", self.stop)], seconds=30)
        self.assertEqual(parts[0].problem, "exited 1 (cannot host: no levels)")
        self.assertEqual(parts[1].problem, "never started")

    def test_an_engine_error_line_fails_the_part_and_the_report(self) -> None:
        parts = self.run_parts([fake("join", "error", self.stop)], seconds=1)
        self.assertIn("engine error line", parts[0].problem)
        with tempfile.TemporaryDirectory() as tmp:
            hostjoin.write_logs(parts, Path(tmp))
            self.assertEqual(hostjoin.report(parts), 1)
            self.assertIn("SCRIPT ERROR: boom", (Path(tmp) / "join.log").read_text("utf-8"))
        self.assertIn("SCRIPT ERROR: boom", self.out.getvalue())

    def test_a_host_run_replaces_the_client_logs_and_leaves_a_join_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            for old in ("client-2.log", "client-5.log", "join.log"):
                (logs / old).write_text("old", "utf-8")
            parts = [hostjoin.Part("host", []), hostjoin.Part("client 2", [])]
            parts[1].lines = ["new"]
            hostjoin.write_logs(parts, logs)
            self.assertEqual(sorted(p.name for p in logs.iterdir()), ["client-2.log", "host.log", "join.log"])
            self.assertEqual((logs / "client-2.log").read_text("utf-8"), "new\n")
            self.assertEqual((logs / "join.log").read_text("utf-8"), "old")


@unittest.skipUnless(godot_bin() and (ROOT / ".godot").is_dir(), "needs Godot (GODOT_BIN) and the imported project")
class RealSessionTest(unittest.TestCase):
    """tools/run/headless_session.gd under a real headless Godot: a host and two local clients on 127.0.0.1."""

    FULL = re.compile(r"session: roster: Player1 \[1\], Player2 \[\d+\], Player3 \[\d+\]$")

    def test_a_host_and_two_local_clients_reach_the_lobby_roster(self) -> None:
        def everyone(parts: list[hostjoin.Part]) -> bool:
            return all(any(self.FULL.match(line) for line in part.lines) for part in parts)

        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            parts = hostjoin.host_parts(verify.free_udp_port(), 2, local=True, stop=Path(tmp) / "stop")
            hostjoin.set_commands(parts, str(godot_bin()))
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                hostjoin.supervise(parts, seconds=60, stop=Path(tmp) / "stop", until=everyone)
        self.assertTrue(everyone(parts), out.getvalue())
        self.assertEqual([p.problem for p in parts], ["", "", ""], out.getvalue())
        for part in parts:
            self.assertIn("session: phase: lobby", part.lines, out.getvalue())
        self.assertEqual(parts[0].lines[-1], "session: stopped", out.getvalue())

    def join_nobody(self, seconds: int | None) -> hostjoin.Part:
        """A real join of a free port of 127.0.0.1 that nothing listens on."""
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            parts = hostjoin.join_parts(LOCALHOST, verify.free_udp_port(), stop=Path(tmp) / "stop")
            hostjoin.set_commands(parts, str(godot_bin()))
            with mock.patch("sys.stdout", new_callable=io.StringIO):
                hostjoin.supervise(parts, seconds=seconds, stop=Path(tmp) / "stop")
        return parts[0]

    def test_a_join_that_nobody_answers_fails_with_connect_failed(self) -> None:
        part = self.join_nobody(60)
        self.assertTrue(part.problem.startswith("exited 1 (could not join: connect_failed"), part.lines)

    def test_a_join_stopped_before_welcome_fails(self) -> None:
        # Shorter than ENet's join timeout: the old stop exited 0, so such a check passed with nobody joined.
        part = self.join_nobody(2)
        self.assertEqual(part.problem, "exited 1 (stopped before the host welcomed it)", part.lines)


if __name__ == "__main__":
    unittest.main()
