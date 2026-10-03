"""`host` and `join`: the options, windows or headless, the processes they start, the clean stop and the report.

The supervision tests run small Python processes in place of Godot; the real run starts a headless host and two
local clients of tools/run/headless_session.gd on a free port of 127.0.0.1 and waits for the full lobby roster.
Nothing here opens a window: the windowed command lines are only built. verify's `game` step runs the game scene.
"""

import io
import os
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, hostjoin, verify
from runner.common import ROOT, Failure, godot_bin, kill_tree

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
if what in ("host", "late-host", "game-host"):
    say("session: hosting base_mode.tres on 127.0.0.1:1")
if what == "menu-host":
    say("session: cannot host: port taken")
if what == "error":
    say("SCRIPT ERROR: boom")
if what == "game-host":
    say("session: welcomed as Player1 [1]")
if what in ("welcomed", "leaves"):
    say("session: welcomed as Player2 [5]")
if what == "leaves":
    sys.exit(0)
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
        for command in (["host"], ["join", "10.0.0.2"]):
            args = cli.build_parser().parse_args(command)
            self.assertEqual((args.headless, args.windows), (False, False))
            self.assertTrue(cli.build_parser().parse_args([*command, "--headless"]).headless)
            self.assertTrue(cli.build_parser().parse_args([*command, "--windows"]).windows)
            with self.subTest(command=command), mock.patch("sys.stderr", new_callable=io.StringIO):
                with self.assertRaises(SystemExit):
                    cli.build_parser().parse_args([*command, "--headless", "--windows"])

    def test_the_host_and_its_local_clients(self) -> None:
        stop = Path("stop")
        files = [f"--stop-file={stop}", f"--alive-file={Path('stop.alive')}"]
        parts = hostjoin.host_parts(24999, 2, local=True, stop=stop)
        self.assertEqual([p.label for p in parts], ["host", "client 2", "client 3"])
        self.assertEqual(parts[0].user_args, ["--host", "--local", "--port=24999", *files])
        for part in parts[1:]:
            self.assertEqual(part.user_args, ["--join=127.0.0.1", "--port=24999", *files])
        alone = hostjoin.host_parts(None, 0, local=False, stop=stop)
        self.assertEqual([p.user_args for p in alone], [["--host", *files]])
        joiner = hostjoin.join_parts("192.168.0.195", None, stop=stop)
        self.assertEqual([p.user_args for p in joiner], [["--join=192.168.0.195", *files]])

    def test_the_godot_command_runs_the_script_headless(self) -> None:
        parts = hostjoin.join_parts("10.0.0.2", 7, stop=Path("s"))
        hostjoin.set_commands(parts, "godot")
        cmd = parts[0].cmd
        self.assertIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("-s") + 1], f"res://{hostjoin.SCRIPT}")
        self.assertEqual(
            cmd[cmd.index("--") + 1 :], ["--join=10.0.0.2", "--port=7", "--stop-file=s", "--alive-file=s.alive"]
        )
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


AREA = (0, 0, 1920, 1040)


class WindowsTest(unittest.TestCase):
    """E20: windows for a human, headless where CLAUDECODE is set, --headless always headless; no window opens here."""

    def setUp(self) -> None:
        self.calls: list[dict[str, object]] = []

        def supervise(parts: list[hostjoin.Part], **kwargs: object) -> None:
            self.calls.append({"parts": parts, **kwargs})

        self.godot = mock.MagicMock(return_value="godot")
        for target, name, value in (
            (hostjoin, "require_godot", self.godot),
            (hostjoin, "ensure_out", mock.MagicMock()),
            (hostjoin, "supervise", supervise),
            (hostjoin, "write_logs", mock.MagicMock()),
            (hostjoin, "report", mock.MagicMock(return_value=0)),
            (hostjoin, "screen_area", mock.MagicMock(return_value=AREA)),
            (hostjoin.launch, "ensure_import", mock.MagicMock()),
            (hostjoin.shot, "has_display", mock.MagicMock(return_value=True)),
        ):
            patcher = mock.patch.object(target, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        out = mock.patch("sys.stdout", new_callable=io.StringIO)
        self.out = out.start()
        self.addCleanup(out.stop)

    def env(self, agent: bool) -> "mock._patch[dict[str, str]]":
        clean = {key: value for key, value in os.environ.items() if key != hostjoin.AGENT_ENV}
        return mock.patch.dict(os.environ, {**clean, **({hostjoin.AGENT_ENV: "1"} if agent else {})}, clear=True)

    def host(self, *, agent: bool, **kwargs: object) -> list[hostjoin.Part]:
        options: dict[str, object] = {"port": 24999, "clients": 2, "local": True, "seconds": None, **kwargs}
        with self.env(agent):
            self.assertEqual(hostjoin.host(**options), 0)  # type: ignore[arg-type]
        return self.calls[-1]["parts"]  # type: ignore[return-value]

    def join(self, *, agent: bool, headless: bool = False) -> list[hostjoin.Part]:
        with self.env(agent):
            self.assertEqual(hostjoin.join("192.168.0.195", port=None, seconds=None, headless=headless), 0)
        return self.calls[-1]["parts"]  # type: ignore[return-value]

    def assert_headless_session(self, parts: list[hostjoin.Part]) -> None:
        for part in parts:
            self.assertIn("--headless", part.cmd)
            self.assertEqual(part.cmd[part.cmd.index("-s") + 1], f"res://{hostjoin.SCRIPT}")
            self.assertNotIn("--position", part.cmd)

    def assert_game_windows(self, parts: list[hostjoin.Part]) -> None:
        for part in parts:
            self.assertNotIn("--headless", part.cmd)
            self.assertNotIn("--display-driver", part.cmd)
            self.assertNotIn("-s", part.cmd)
            self.assertEqual(part.cmd[part.cmd.index("--") - 1], f"res://{hostjoin.GAME}")
            self.assertEqual(part.cmd[part.cmd.index("--") + 1 :], part.user_args)

    def test_the_defaults_windows_for_a_human_headless_for_an_agent_and_the_explicit_flags(self) -> None:
        for agent, headless, windows, shown in (
            (False, False, False, True),
            (True, False, False, False),
            (False, True, False, False),
            (True, True, False, False),
            (False, False, True, True),
            (True, False, True, True),
        ):
            with self.subTest(agent=agent, headless=headless, windows=windows):
                env = {hostjoin.AGENT_ENV: "1"} if agent else {}
                self.assertEqual(hostjoin.windowed(headless=headless, windows=windows, env=env), shown)
        with self.assertRaises(Failure):
            hostjoin.windowed(headless=True, windows=True, env={})

    def test_a_human_host_with_clients_opens_the_game_in_tiled_windows(self) -> None:
        parts = self.host(agent=False)
        self.assert_game_windows(parts)
        self.assertEqual(parts[0].user_args[:3], ["--host", "--local", "--port=24999"])
        self.assertEqual(parts[1].user_args[:2], ["--join=127.0.0.1", "--port=24999"])
        tiles = [hostjoin.Tile(8, 48, 824, 464), hostjoin.Tile(968, 48, 824, 464), hostjoin.Tile(8, 568, 824, 464)]
        for part, tile in zip(parts, tiles, strict=True):
            self.assertEqual(part.cmd[part.cmd.index("--position") + 1], f"{tile.x},{tile.y}")
            self.assertEqual(part.cmd[part.cmd.index("--resolution") + 1], f"{tile.width}x{tile.height}")
        self.assertNotIn("--audio-driver", parts[0].cmd)
        self.assertIsNone(self.calls[-1]["on_hosting"])  # --local: nobody joins from another PC
        self.assertTrue((ROOT / hostjoin.GAME).is_file())

    def test_an_agent_host_or_join_is_the_headless_session_and_says_why(self) -> None:
        self.assert_headless_session(self.host(agent=True))
        self.assertIn(f"{hostjoin.AGENT_ENV} is set", self.out.getvalue())
        self.assert_headless_session(self.join(agent=True))

    def test_headless_is_always_the_session_and_windows_always_the_game(self) -> None:
        self.assert_headless_session(self.host(agent=False, headless=True))
        self.assertNotIn(f"{hostjoin.AGENT_ENV} is set", self.out.getvalue())
        self.assert_game_windows(self.host(agent=True, windows=True))

    def test_a_host_on_every_interface_prints_what_to_type_on_another_pc(self) -> None:
        self.host(agent=False, local=False, clients=0)
        self.assertIs(self.calls[-1]["on_hosting"], hostjoin.lan_hint)
        with mock.patch.object(hostjoin, "lan_addresses", return_value=["192.168.0.195"]):
            hostjoin.lan_hint("session: hosting base_mode.tres on *:24600")
        self.assertIn(
            "session: from another machine: tools\\run.cmd join <address> --port 24600 (this one: 192.168.0.195)",
            self.out.getvalue(),
        )
        self.host(agent=False, local=False, clients=0, headless=True)
        self.assertIsNone(self.calls[-1]["on_hosting"])  # the headless session prints its own

    def test_only_windows_must_be_welcomed(self) -> None:
        # The headless session exits 1 when no session forms; a window stays at its menu, so the runner checks it.
        with mock.patch.object(hostjoin, "check_windowed_parts") as check:
            self.host(agent=False, clients=0)
            self.join(agent=False)
            self.assertEqual(check.call_count, 2)
            self.host(agent=True)
            self.join(agent=False, headless=True)
            self.assertEqual(check.call_count, 2)

    def test_a_lone_window_is_not_tiled(self) -> None:
        self.assertNotIn("--position", self.host(agent=False, clients=0)[0].cmd)
        parts = self.join(agent=False)
        self.assert_game_windows(parts)
        self.assertNotIn("--position", parts[0].cmd)

    def test_a_window_without_a_desktop_fails_before_godot_starts(self) -> None:
        with mock.patch.object(hostjoin.shot, "has_display", return_value=False), self.assertRaises(Failure) as caught:
            self.host(agent=False)
        self.assertIn("--headless", str(caught.exception))
        self.godot.assert_not_called()

    def test_tiles_fill_the_area_in_a_grid_without_overlap(self) -> None:
        for count in range(2, hostjoin.MAX_CLIENTS + 2):
            with self.subTest(count=count):
                placed = hostjoin.tiles(count, (100, 50, 2560, 1400))
                self.assertEqual(len(placed), count)
                frame, bar = hostjoin.FRAME, hostjoin.TITLE_BAR
                # Each window's whole outline: the frame on the left, right and bottom, the title bar on top.
                outer = [(t.x - frame, t.y - bar, t.x + t.width + frame, t.y + t.height + frame) for t in placed]
                for tile, (left, top, right, bottom) in zip(placed, outer, strict=True):
                    self.assertGreaterEqual(left, 100)
                    self.assertGreaterEqual(top, 50)
                    self.assertLessEqual(right, 100 + 2560)
                    self.assertLessEqual(bottom, 50 + 1400)
                    self.assertLessEqual(abs(tile.width * 9 - tile.height * 16), 16)
                for i, a in enumerate(outer):
                    for b in outer[i + 1 :]:
                        apart_x = a[2] <= b[0] or b[2] <= a[0]
                        apart_y = a[3] <= b[1] or b[3] <= a[1]
                        self.assertTrue(apart_x or apart_y, (a, b))


class ScreenAreaTest(unittest.TestCase):
    def test_the_screen_area_is_a_rectangle(self) -> None:
        _x, _y, width, height = hostjoin.screen_area()
        self.assertGreater(width, 0)
        self.assertGreater(height, 0)


class GameCheckTest(unittest.TestCase):
    """verify's `game` step: the main scene headless through its command line; what passes and what fails."""

    def test_the_step_runs_the_game_scene_headless_host_and_one_client_on_its_port(self) -> None:
        seen: list[list[hostjoin.Part]] = []

        def supervise(parts: list[hostjoin.Part], **_kwargs: object) -> None:
            seen.append(parts)

        with (
            mock.patch.object(verify, "free_udp_port", return_value=23459),
            mock.patch.object(hostjoin, "require_godot", return_value="godot"),
            mock.patch.object(hostjoin, "ensure_out"),
            mock.patch.object(hostjoin.launch, "ensure_import"),
            mock.patch.object(hostjoin, "supervise", supervise),
            mock.patch.object(hostjoin, "write_logs"),
            mock.patch.object(hostjoin, "report", return_value=0),
            mock.patch("sys.stdout", new_callable=io.StringIO),
        ):
            self.assertEqual(verify.game(), 0)
        host, client = seen[0]
        for part in (host, client):
            self.assertIn("--headless", part.cmd)
            self.assertEqual(part.cmd[part.cmd.index("--") - 1], f"res://{hostjoin.GAME}")
            self.assertIn("--port=23459", part.user_args)
        self.assertEqual(host.user_args[:2], ["--host", "--local"])
        self.assertIn(hostjoin.NO_REPLAY, host.user_args)
        self.assertEqual(client.user_args[0], "--join=127.0.0.1")

    def checked(self, *whats: str) -> list[hostjoin.Part]:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            stop = Path(tmp) / "stop"
            parts = [fake("host", whats[0], stop), *(fake(f"client {i}", w, stop) for i, w in enumerate(whats[1:], 2))]
            with mock.patch("sys.stdout", new_callable=io.StringIO):
                hostjoin.supervise(parts, seconds=3, stop=stop, until=hostjoin._settled_in_lobby())
        hostjoin.check_game_parts(parts)
        return parts

    def test_welcomed_parts_that_stop_for_the_stop_file_pass(self) -> None:
        with mock.patch.object(hostjoin, "GAME_SETTLE_SECONDS", 0.2):
            parts = self.checked("game-host", "welcomed")
        self.assertEqual([p.problem for p in parts], ["", ""])

    def test_a_part_never_welcomed_fails(self) -> None:
        parts = self.checked("game-host", "client")
        self.assertEqual(parts[1].problem, "never welcomed: it reached no lobby")

    def test_a_part_that_exits_without_the_stop_file_fails(self) -> None:
        parts = self.checked("game-host", "leaves")
        self.assertIn("did not end through the stop file", parts[1].problem)


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
        with mock.patch.object(hostjoin, "_sleep", interrupt_once):
            self.run_parts(parts, seconds=None)
        self.assertIn("Ctrl+C, stopping", self.out.getvalue())
        self.assertEqual([p.problem for p in parts], ["", ""], self.out.getvalue())

    def test_each_part_gets_its_own_prime_instance_and_the_runner_environment(self) -> None:
        # The M5 ADR's E47 as amended (§1.7): each window of `host --clients N` keeps its own settings file.
        show = 'import os\nprint("instance", os.environ.get("PRIME_INSTANCE"), os.environ.get("PRIME_PROBE"))\n'
        parts = [fake("host", "host", self.stop), fake("client 2", "client", self.stop)]
        parts.append(fake("client 3", "client", self.stop))
        for part in parts:
            part.cmd[2] = show + part.cmd[2]
        with mock.patch.dict(os.environ, {"PRIME_PROBE": "kept"}):
            self.run_parts(parts, seconds=2)
        self.assertEqual([p.lines[0] for p in parts], [f"instance {n} kept" for n in (1, 2, 3)], self.out.getvalue())

    def test_until_ends_the_wait(self) -> None:
        parts = [fake("join", "client", self.stop)]
        began = time.monotonic()
        self.run_parts(parts, seconds=60, until=lambda ps: any("roster" in line for line in ps[0].lines))
        self.assertLess(time.monotonic() - began, 30)
        self.assertEqual(parts[0].problem, "")

    def test_the_runner_keeps_the_alive_file_fresh_while_it_runs_and_removes_it_after(self) -> None:
        alive = hostjoin.alive_file(self.stop)
        ages: list[float] = []

        def watch(_parts: list[hostjoin.Part]) -> bool:
            ages.append(time.time() - alive.stat().st_mtime)
            return len(ages) >= 30

        with mock.patch.object(hostjoin, "ALIVE_BEAT_SECONDS", 0.2):
            self.run_parts([fake("join", "client", self.stop)], seconds=60, until=watch)
        self.assertEqual(len(ages), 30)
        # 30 polls of 0.1 s with a 0.2 s beat: a beat that never came would leave the file 3 s old.
        self.assertLess(max(ages), 1.5)
        self.assertFalse(alive.exists())

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

    def test_a_host_that_cannot_host_but_keeps_running_gets_no_client(self) -> None:
        # The game shows its menu with the reason instead of exiting; the clients must not wait HOST_READY_SECONDS.
        began = time.monotonic()
        parts = self.run_parts([fake("host", "menu-host", self.stop), fake("client 2", "client", self.stop)], seconds=2)
        self.assertLess(time.monotonic() - began, 30)
        self.assertEqual(parts[1].problem, "never started")

    def test_a_window_that_formed_no_session_fails_with_why(self) -> None:
        # The game goes back to its menu instead of exiting: exit 0 and the stop line alone would say "passed".
        lone = self.run_parts([fake("host", "menu-host", self.stop)], seconds=1)
        joined = self.run_parts([fake("join", "client", self.stop)], seconds=1)
        welcomed = self.run_parts([fake("join", "welcomed", self.stop)], seconds=1)
        for parts in (lone, joined, welcomed):
            hostjoin.check_windowed_parts(parts)
        self.assertEqual(lone[0].problem, "never welcomed: cannot host: port taken")
        self.assertEqual(joined[0].problem, "never welcomed: it reached no lobby")
        self.assertEqual(welcomed[0].problem, "")
        ended = hostjoin.Part("join", [])
        ended.proc = mock.MagicMock(returncode=0, poll=mock.MagicMock(return_value=0))
        ended.lines = ["session: joining 10.0.0.2:24600", "session: ended: wrong version", "session: stopped"]
        hostjoin.check_windowed_parts([ended])
        self.assertEqual(ended.problem, "never welcomed: ended: wrong version")

    def test_on_hosting_gets_the_host_line(self) -> None:
        got: list[str] = []
        self.run_parts([fake("host", "host", self.stop)], seconds=1, on_hosting=got.append)
        self.assertEqual(got, ["session: hosting base_mode.tres on 127.0.0.1:1"])

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


@verify.starts_godot
@unittest.skipUnless(godot_bin() and (ROOT / ".godot").is_dir(), "needs Godot (GODOT_BIN) and the imported project")
class RealSessionTest(unittest.TestCase):
    """tools/run/headless_session.gd under a real headless Godot: a host and two local clients on 127.0.0.1."""

    FULL = re.compile(r"session: roster: Player1 \[1\], Player2 \[\d+\], Player3 \[\d+\]$")

    def test_a_host_and_two_local_clients_reach_the_lobby_roster(self) -> None:
        def everyone(parts: list[hostjoin.Part]) -> bool:
            return all(any(self.FULL.match(line) for line in part.lines) for part in parts)

        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            parts = hostjoin.host_parts(verify.free_udp_port(), 2, local=True, stop=Path(tmp) / "stop")
            parts[0].user_args.append("--no-replay")  # keep the developer's newest replays
            hostjoin.set_commands(parts, str(godot_bin()))
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                hostjoin.supervise(parts, seconds=60, stop=Path(tmp) / "stop", until=everyone)
        self.assertTrue(everyone(parts), out.getvalue())
        self.assertEqual([p.problem for p in parts], ["", "", ""], out.getvalue())
        for part in parts:
            self.assertIn("session: phase: lobby", part.lines, out.getvalue())
        self.assertEqual(parts[0].lines[-1], "session: stopped", out.getvalue())

    def test_a_host_whose_runner_is_gone_stops_by_itself(self) -> None:
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            stop = Path(tmp) / "stop"
            alive = hostjoin.alive_file(stop)
            alive.write_text("alive\n", encoding="ascii")
            parts = hostjoin.host_parts(verify.free_udp_port(), 0, local=True, stop=stop)
            parts[0].user_args.append("--no-replay")
            hostjoin.set_commands(parts, str(godot_bin()))
            host = parts[0]
            with mock.patch("sys.stdout", new_callable=io.StringIO):
                hostjoin.start(host)
                assert host.proc is not None
                try:
                    deadline = time.monotonic() + 60
                    while not any(line.startswith(hostjoin.HOSTING) for line in host.lines):
                        self.assertTrue(host.running and time.monotonic() < deadline, host.lines)
                        time.sleep(0.1)
                    # A killed runner: its alive file is no longer touched, and here it is gone.
                    alive.unlink()
                    host.proc.wait(timeout=20)
                finally:
                    if host.running:
                        kill_tree(host.proc)
                    if host.reader is not None:
                        host.reader.join(timeout=5)
                    if host.proc.stdout is not None:
                        host.proc.stdout.close()
        self.assertEqual(host.proc.returncode, 0, host.lines)
        self.assertTrue(any("the runner is gone" in line for line in host.lines), host.lines)
        self.assertEqual(host.lines[-1], "session: stopped", host.lines)

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
