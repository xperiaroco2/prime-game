"""`playcheck`: the scenario parser, the plan, the fields of `wait text` and `wait shown` (FIELDS equals the keys of
playcheck_window.gd's GameView), the processes' command lines, and runs that pass, fail a step, time out, print an
engine error or miss a PNG, each stopping every process it started.

The runs start small Python processes in place of the game's windows and the bots; nothing here opens a window or
starts Godot (`playcheck` needs a desktop session and never runs on CI). The window's own step timeouts are tested in
GDScript: tests/unit/tools/playcheck_steps_test.gd.
"""

import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, hostjoin, playcheck, shot
from runner.common import ROOT, Failure

BOTS = "tools/playcheck/scenarios/spectate_bots.tres"

GOOD = f"""
# A comment line, and a comment after a step.
players 3
windows 2
bots {BOTS}
role 3 dissident
setting match_duration 5
clock 120
timeout 20

window 1
wait phase lobby          # the lobby
press ready
wait ready on timeout=5
wait ready 2 on
wait life 2 downed timeout=90
wait event KnockedDown peer=2 tick=40 ratio=0.5 phase=round
wait screen round
wait players 3
frames 30
shot host_view

window 2
wait esc closed
wait pointer captured
hold give_up
wait life dead
release give_up
shot spectating
"""


def scenario(text: str = GOOD, name: str = "probe") -> playcheck.Scenario:
    return playcheck.parse(text, name)


def with_header(steps: str, header: str = "players 2\nwindows 2") -> str:
    return f"{header}\n{steps}"


class ParserTest(unittest.TestCase):
    def test_a_full_scenario_becomes_each_windows_plan(self) -> None:
        s = scenario()
        self.assertEqual((s.players, s.windows, s.bots), (3, 2, f"res://{BOTS}"))
        self.assertEqual((s.roles, s.settings), ({3: "dissident"}, {"match_duration": 5}))
        self.assertEqual((s.clock, s.timeout), (120, 20.0))
        self.assertEqual(s.shots(), ["host_view", "spectating"])
        self.assertEqual(s.labels(), ["window 1", "window 2", "bots"])
        out = Path("/out/probe")
        plan = playcheck.plan(s, out)
        self.assertEqual((plan["players"], plan["windows"], plan["peers"]), (3, 2, str(out / "peers")))
        first, second = plan["steps"]["1"], plan["steps"]["2"]  # type: ignore[index]
        # Window 1 sends the setup before its own steps, once everyone is in its roster.
        self.assertEqual(
            first[0],
            {
                "line": 0,
                "text": "setup (ForceRole, ForceClock, ChangeSettings)",
                "do": "setup",
                "roles": {"3": "dissident"},
                "settings": {"match_duration": 5},
                "clock": 120,
                "players": 3,
                "timeout_s": 20.0 + playcheck.BOTS_START_SECONDS,
            },
        )
        self.assertEqual(
            first[1],
            {"line": 12, "text": "wait phase lobby", "do": "wait", "what": "phase", "value": "lobby", "timeout_s": 20},
        )
        self.assertEqual(first[2], {"line": 13, "text": "press ready", "do": "press", "action": "ready"})
        self.assertEqual(first[3]["value"], True)
        self.assertEqual((first[3]["player"], first[3]["timeout_s"]), (0, 5.0))
        self.assertEqual((first[4]["player"], first[5]["player"], first[5]["value"]), (2, 2, "downed"))
        self.assertEqual(first[5]["timeout_s"], 90.0)
        self.assertEqual(
            (first[6]["event"], first[6]["fields"]),
            ("KnockedDown", {"peer": 2, "tick": 40, "ratio": 0.5, "phase": "round"}),
        )
        self.assertEqual((first[7]["value"], first[8]["value"], first[9]["count"]), ("round", 3, 30))
        shot_step = {"line": 21, "text": "shot host_view", "do": "shot", "name": "host_view"}
        self.assertEqual(first[10], {**shot_step, "path": str(out / "host_view.png")})
        self.assertEqual([step["do"] for step in second], ["wait", "wait", "hold", "wait", "release", "shot"])
        self.assertEqual((second[0]["value"], second[1]["value"]), (False, True))
        json.dumps(plan)  # the windows read it as JSON

    def test_the_setup_wait_adds_the_bots_start_time(self) -> None:
        """The bots' headless process starts once window 1 hosts, and under load it took more than the scenario's
        timeout to join, so window 1's setup failed with 2 of 3 players (#354, #406)."""
        steps = "timeout 25\nrole 1 dissident\nwindow 1\nshot a"
        with_bots = scenario(with_header(steps, f"players 3\nwindows 2\nbots {BOTS}"))
        self.assertEqual(with_bots.steps[1][0].do, "setup")
        self.assertEqual(with_bots.steps[1][0].args["timeout_s"], 25.0 + playcheck.BOTS_START_SECONDS)
        self.assertEqual(playcheck.BOTS_START_SECONDS, hostjoin.HOST_READY_SECONDS)
        windows_only = scenario(with_header(steps))
        self.assertEqual(windows_only.steps[1][0].do, "setup")
        self.assertEqual(windows_only.steps[1][0].args["timeout_s"], 25.0)
        # A wait keeps the scenario's timeout: only the setup waits for the bots' process to start.
        waits = scenario(with_header(steps + "\nwait phase lobby", f"players 3\nwindows 2\nbots {BOTS}"))
        self.assertEqual((waits.steps[1][2].do, waits.steps[1][2].args["timeout_s"]), ("wait", 25.0))

    def test_a_window_without_the_setup_gives_its_first_wait_after_ready_the_bots_start_time(self) -> None:
        """Window 2 waits for the round from its own welcome, and the round needs the late bots in and ready too
        (#406's review): its first wait after `press ready` gets the bots' start time, its other waits do not."""
        steps = (
            "timeout 25\nrole 3 dissident\nwindow 1\nwait phase lobby\npress ready\nwait screen round timeout=60\n"
            "window 2\nwait phase lobby\npress ready\nwait screen round timeout=60\nwait life downed\nshot a"
        )
        with_bots = scenario(with_header(steps, f"players 3\nwindows 2\nbots {BOTS}"))
        first, second = with_bots.steps[1], with_bots.steps[2]
        self.assertEqual(first[0].do, "setup")
        # Window 1's setup already waited for every player, so its own round wait keeps its timeout.
        self.assertEqual([step.args["timeout_s"] for step in first[1:] if step.do == "wait"], [25.0, 60.0])
        self.assertEqual(
            [step.args["timeout_s"] for step in second if step.do == "wait"],
            [25.0, 60.0 + playcheck.BOTS_START_SECONDS, 25.0],
        )
        # Without the setup, window 1 waits for the bots the same way.
        no_setup = scenario(with_header(steps.replace("role 3 dissident\n", ""), f"players 3\nwindows 2\nbots {BOTS}"))
        self.assertEqual(
            [step.args["timeout_s"] for step in no_setup.steps[1] if step.do == "wait"],
            [25.0, 60.0 + playcheck.BOTS_START_SECONDS],
        )
        windows_only = scenario(with_header(steps.replace("role 3 dissident\n", "")))
        self.assertEqual(
            [step.args["timeout_s"] for step in windows_only.steps[2] if step.do == "wait"], [25.0, 60.0, 25.0]
        )

    def test_without_roles_settings_or_clock_there_is_no_setup_step(self) -> None:
        s = scenario(with_header("window 1\nshot a\nwindow 2\nwait phase lobby"))
        self.assertEqual([step.do for step in s.steps[1]], ["shot"])

    def test_a_window_without_a_section_has_no_steps(self) -> None:
        plan = playcheck.plan(scenario(with_header("window 2\nshot a")), Path("/out"))
        step = {"line": 4, "text": "shot a", "do": "shot", "name": "a", "path": str(Path("/out/a.png"))}
        self.assertEqual(plan["steps"], {"1": [], "2": [step]})

    def test_each_mistake_names_its_line_and_what_is_wrong(self) -> None:
        cases = [
            ("windows 2\nwindow 1\nshot a", 1, "needs `players <n>` and `windows <n>`"),
            ("players 2\nwindows 3\nwindow 1\nshot a", 1, "windows 3 is more than players 2"),
            ("players 3\nwindows 2\nwindow 1\nshot a", 1, "players 3 to 3 need `bots <file.tres>`"),
            (f"players 2\nwindows 2\nbots {BOTS}\nwindow 1\nshot a", 1, "there are none"),
            (f"players 2\nwindows 1\nbots {BOTS}\nwindow 1\nshot a", 3, f"{BOTS} has bots = 3, but players is 2"),
            (f"players 4\nwindows 2\nbots {BOTS}\nwindow 1\nshot a", 3, "has bots = 3, but players is 4"),
            ("players 2\nwindows 4", 2, "windows must be a whole number from 1 to 3"),
            ("players 11", 1, "players must be a whole number from 1 to 10"),
            ("players 2\nwindows 2\nbots content/nothing.tres", 3, "bots: content/nothing.tres not found"),
            ("players 2\nwindows 2\nbots ../x.tres", 3, "give a .tres inside the project"),
            ("players 2\nwindows 2\nmap greybox", 3, "unknown header line `map`"),
            ("players 2\nwindows 2\nrole 2", 3, "wrong number of words for `role`"),
            ("players 2\nwindows 2\nrole 3 dissident\nwindow 1\nshot a", 3, "player 3: the scenario has 2"),
            ("players 2\nwindows 2\nrole 2 Dissident", 3, "a role id looks like dissident"),
            ("players 2\nwindows 2\nrole 2 a\nrole 2 b", 4, "player 2 already has a role"),
            ("players 2\nwindows 2\nsetting duration five", 3, "a setting is `setting <id> <whole number>`"),
            ("players 2\nwindows 2\ntimeout 0", 3, "timeout must be seconds above 0"),
            ("players 2\nwindows 2\nwindow 3\nshot a", 3, "window 3: the scenario has 2"),
            ("players 2\nwindows 2\nwindow 1\nshot a\nwindow 1", 5, "window 1 has two sections"),
            ("players 2\nwindows 2\nwindow 1 2", 3, "a section is `window <n>`"),
            ("players 2\nwindows 2\nwindow 1\njump", 4, "unknown step `jump`"),
            ("players 2\nwindows 2\nwindow 1\nwait", 4, "`wait` needs what to wait for"),
            ("players 2\nwindows 2\nwindow 1\nwait phase", 4, "a wait is `wait phase <id>`"),
            ("players 2\nwindows 2\nwindow 1\nwait screen hud", 4, "a wait is"),
            ("players 2\nwindows 2\nwindow 1\nwait life 2 sleeping", 4, "a wait is"),
            ("players 2\nwindows 2\nwindow 1\nwait life 5 dead", 4, "player 5: the scenario has 2"),
            ("players 2\nwindows 2\nwindow 1\nwait ready yes", 4, "a wait is"),
            ("players 2\nwindows 2\nwindow 1\nwait event knockedDown", 4, "a wait is"),
            ("players 2\nwindows 2\nwindow 1\nwait event Died peer", 4, "an event field is `name=value`"),
            ("players 2\nwindows 2\nwindow 1\nwait event Died peer=2 peer=2", 4, "each name once"),
            ("players 2\nwindows 2\nwindow 1\nwait event Died peer=x", 4, "a player must be a whole number"),
            ("players 2\nwindows 2\nwindow 1\nwait esc shut", 4, "a wait is"),
            ("players 2\nwindows 2\nwindow 1\nwait phase lobby timeout=0", 4, "timeout= must be seconds above 0"),
            ("players 2\nwindows 2\nwindow 1\nwait phase lobby timeout=601", 4, "at most 600"),
            ("players 2\nwindows 2\nwindow 1\nframes 2 timeout=5", 4, "only a wait takes timeout="),
            ("players 2\nwindows 2\nwindow 1\nframes 0", 4, "frames must be a whole number from 1 to 600"),
            ("players 2\nwindows 2\nwindow 1\nframes", 4, "`frames` takes one word"),
            ("players 2\nwindows 2\nwindow 1\npress Ready", 4, "an input action looks like ui_cancel"),
            ("players 2\nwindows 2\nwindow 1\nshot A-B", 4, "a shot's name is [a-z0-9_]"),
            ("players 2\nwindows 2\nwindow 1\nhold give_up\nshot a", 4, "holds give_up and never releases it"),
            ("players 2\nwindows 2\nwindow 1\nhold g\nhold g\nrelease g\nshot a", 5, "holds g twice"),
            ("players 2\nwindows 2\nwindow 1\nrelease g\nshot a", 4, "releases g, which it does not hold"),
            ("players 2\nwindows 2\nwindow 2\nhold g\nwindow 1\nrelease g\nshot a", 4, "window 2 holds g and never"),
            ("players 2\nwindows 2\nwindow 1\nwait text hud.nope has a", 4, "`wait text` has no field 'hud.nope'"),
            ("players 2\nwindows 2\nwindow 1\nwait text", 4, "`wait text` has no field; the fields are hud.role,"),
            ("players 2\nwindows 2\nwindow 1\nwait text hud.hand equals a", 4, "is|has|lacks <text ...>`; the fields"),
            ("players 2\nwindows 2\nwindow 1\nwait text hud.hand", 4, "is|has|lacks <text ...>`; the fields"),
            ("players 2\nwindows 2\nwindow 1\nwait text hud.hand has", 4, "`wait text hud.hand has` needs the text"),
            ("players 2\nwindows 2\nwindow 1\nwait text hud.hand is timeout=5", 4, "needs the text"),
            ("players 2\nwindows 2\nwindow 1\nwait shown hud.hand yes", 4, "`wait shown <field> on|off`; the"),
            ("players 2\nwindows 2\nwindow 1\nwait shown hud.hand on off", 4, "`wait shown <field> on|off`"),
            ("players 2\nwindows 2\nwindow 1\nwait shown Hud.hand on", 4, "`wait shown` has no field 'Hud.hand'"),
            ("players 2\nwindows 2\nwindow 1\nbutton", 4, "`button` needs the button's text"),
            ("players 2\nwindows 2\nwindow 1\nbutton   # Resume", 4, "`button` needs the button's text"),
            ("players 2\nwindows 2\nwindow 1\nbutton Resume timeout=5", 4, "only a wait takes timeout="),
            ("players 2\nwindows 2\nwindow 1\naim", 4, "an aim is `aim item <kind>`"),
            ("players 2\nwindows 2\nwindow 1\naim knife", 4, "an aim is `aim item <kind>`"),
            ("players 2\nwindows 2\nwindow 1\naim item Knife", 4, "an aim is `aim item <kind>`"),
            ("players 2\nwindows 2\nwindow 1\naim item knife package", 4, "an aim is"),
            ("players 2\nwindows 2\nwindow 1\naim off now", 4, "an aim is"),
            ("players 2\nwindows 2\nwindow 1\naim item knife\nshot a", 4, "window 1 aims and never stops"),
            ("players 2\nwindows 2\nwindow 1\naim off\nshot a", 4, "window 1 has `aim off` without an `aim item`"),
            ("players 2\nwindows 2\nwindow 1\naim item a\naim item b\naim off\nshot a", 5, "aims again"),
            ("players 2\nwindows 2\nwindow 1\naim item a\naim off\naim off\nshot a", 6, "`aim off` without"),
            ("players 2\nwindows 2\nwindow 2\naim item a\naim off\nwindow 1\naim off\nshot a", 7, "window 1 has `aim off`"),
            ("players 2\nwindows 2\nwindow 1\naim item a timeout=5", 4, "only a wait takes timeout="),
            ("players 2\nwindows 2\nwindow 1\nwait phase lobby", 1, "at least one `shot`"),
            ("players 2\nwindows 2\nwindow 1\nshot a\nwindow 2\nshot a", 1, "shot names must be unique: a"),
        ]
        for text, line, why in cases:
            with self.subTest(text=text):
                with self.assertRaises(Failure) as caught:
                    scenario(text, "bad")
                self.assertTrue(str(caught.exception).startswith(f"bad.txt:{line}: "), str(caught.exception))
                self.assertIn(why, str(caught.exception))

    def test_text_shown_and_button_become_their_plan_entries(self) -> None:
        steps = (
            "window 1\n"
            "wait text lobby.roster has (host,   you)  ready timeout=9\n"
            "wait text esc.tabs lacks Lobby\n"
            "wait text hud.hand is Hand: Knife\n"
            "wait shown hud.crosshair off\n"
            "button Back  to lobby   # the end screen's\n"
            "shot a"
        )
        first = scenario(with_header(steps)).steps[1]
        roster = {"what": "text", "field": "lobby.roster", "op": "has", "value": "(host, you) ready", "timeout_s": 9.0}
        self.assertEqual(first[0].args, roster)
        self.assertEqual(first[0].text, "wait text lobby.roster has (host, you) ready timeout=9")
        self.assertEqual(
            (first[1].args["field"], first[1].args["op"], first[1].args["value"]), ("esc.tabs", "lacks", "Lobby")
        )
        self.assertEqual((first[2].args["op"], first[2].args["value"]), ("is", "Hand: Knife"))
        self.assertEqual(first[2].args["timeout_s"], playcheck.DEFAULT_TIMEOUT)
        self.assertEqual(
            first[3].args,
            {"what": "shown", "field": "hud.crosshair", "value": False, "timeout_s": playcheck.DEFAULT_TIMEOUT},
        )
        # The button's text goes under "label": the step's "text" is its line.
        button = {"line": 8, "text": "button Back to lobby", "do": "button", "label": "Back to lobby"}
        self.assertEqual(first[4].plan(), button)

    def test_aim_item_and_aim_off_become_their_plan_entries_in_pairs(self) -> None:
        steps = "window 1\naim item knife   # the nearest\nframes 5\naim off\naim item package\naim off\nshot a"
        first = scenario(with_header(steps)).steps[1]
        self.assertEqual(first[0].plan(), {"line": 4, "text": "aim item knife", "do": "aim", "kind": "knife"})
        self.assertEqual(first[2].plan(), {"line": 6, "text": "aim off", "do": "aim", "kind": ""})
        self.assertEqual([(step.do, step.args.get("kind")) for step in first[3:5]], [("aim", "package"), ("aim", "")])
        # Each window pairs its own aims.
        both = scenario(with_header("window 1\naim item knife\naim off\nwindow 2\naim item knife\naim off\nshot a"))
        self.assertEqual([step.args["kind"] for step in both.steps[2][:2]], ["knife", ""])

    def test_every_field_has_a_text_and_a_shown_wait(self) -> None:
        for name in playcheck.FIELDS:
            for wait in (f"wait text {name} has x", f"wait text {name} lacks x y", f"wait shown {name} on"):
                with self.subTest(wait=wait):
                    parsed = scenario(with_header(f"window 1\n{wait}\nshot a")).steps[1][0]
                    self.assertEqual(parsed.args["field"], name)

    def test_the_fields_are_the_keys_of_the_windows_game_view(self) -> None:
        window = (ROOT / "tools" / "playcheck" / "playcheck_window.gd").read_text(encoding="utf-8")
        view = re.search(r"^class GameView:\n(.*?)^\S", window, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(view, "no class GameView in playcheck_window.gd")
        assert view is not None
        keys = re.findall(r'^\t+"([a-z]+\.[a-z]+)":', view.group(1), re.MULTILINE)
        self.assertEqual(len(keys), len(set(keys)), f"a key twice in GameView: {sorted(keys)}")
        self.assertEqual(sorted(keys), sorted(playcheck.FIELDS))
        self.assertEqual(len(playcheck.FIELDS), len(set(playcheck.FIELDS)))

    def test_the_screens_are_game_flows_in_lower_case(self) -> None:
        # #494 added FAILURE; a screen GameFlow gains must be one a scenario can wait for.
        flow = (ROOT / "client" / "app" / "game_flow.gd").read_text(encoding="utf-8")
        enum = re.search(r"^enum Screen \{\n(.*?)^\}", flow, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(enum, "no enum Screen in game_flow.gd")
        assert enum is not None
        names = re.findall(r"^\t([A-Z_]+),", enum.group(1), re.MULTILINE)
        self.assertEqual(tuple(name.lower() for name in names), playcheck.SCREENS)

    def test_every_scenario_in_the_folder_parses_and_its_bots_file_exists(self) -> None:
        names = playcheck.available()
        self.assertIn("esc_menu", names)
        self.assertIn("spectate", names)
        self.assertIn("items", names)
        self.assertIn("end", names)
        for name in names:
            with self.subTest(name=name):
                s = playcheck.load(name)
                self.assertTrue(s.shots())
                if s.bots:
                    self.assertTrue((ROOT / s.bots.removeprefix("res://")).is_file())

    def test_a_botscenarios_bots_is_read_from_its_resource_section_default_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sub = '[sub_resource type="Resource" id="x"]\nbots = 9\n\n'
            (root / "five.tres").write_text(f"[gd_resource]\n\n{sub}[resource]\nmode = 1\nbots = 5\n", encoding="utf-8")
            (root / "none.tres").write_text(f"[gd_resource]\n\n{sub}[resource]\nmode = 1\n", encoding="utf-8")
            with mock.patch.object(playcheck, "ROOT", root):
                self.assertEqual(playcheck.bots_count("res://five.tres"), 5)
                self.assertEqual(playcheck.bots_count("res://none.tres"), 1)
        self.assertEqual(playcheck.bots_count(f"res://{BOTS}"), 3)

    def test_an_unknown_scenario_lists_the_ones_there_are(self) -> None:
        with self.assertRaises(Failure) as caught:
            playcheck.load("nothing_here")
        self.assertIn("there are: ", str(caught.exception))
        self.assertIn("esc_menu", str(caught.exception))
        for other in ("../esc_menu", "content/esc_menu.txt", "Esc_Menu", "C:/esc_menu", "/esc_menu"):
            with self.subTest(other=other), self.assertRaises(Failure):
                playcheck.load(other)
        for same in ("esc_menu.txt", "tools/playcheck/scenarios/esc_menu.txt", r"tools\playcheck\scenarios\esc_menu"):
            self.assertEqual(playcheck.load(same).name, "esc_menu")


class CommandTest(unittest.TestCase):
    def test_the_windows_are_off_screen_never_headless_and_window_1_hosts(self) -> None:
        s = scenario()
        stop = Path("/logs/stop-1")
        parts = playcheck.make_parts(s, Path("/out/probe/plan.json"), 24999, stop)
        playcheck.set_commands(parts, "godot.exe")
        self.assertEqual([p.label for p in parts], ["window 1", "window 2", "bots"])
        for part in parts[:2]:
            cmd = part.cmd
            self.assertNotIn("--headless", cmd)
            self.assertEqual(cmd[cmd.index("--position") + 1], shot.POSITION)
            self.assertEqual(cmd[cmd.index("--resolution") + 1], playcheck.SIZE)
            self.assertEqual(cmd[cmd.index("--audio-driver") + 1], "Dummy")
            self.assertEqual(cmd[cmd.index("-s") + 1], playcheck.WINDOW_SCRIPT)
            self.assertIn(f"--plan={Path('/out/probe/plan.json')}", cmd)
            self.assertIn(f"--stop-file={stop}", cmd)
            self.assertIn(f"--alive-file={hostjoin.alive_file(stop)}", cmd)
            self.assertIn("--port=24999", cmd)
        host, guest, bots = (p.cmd for p in parts)
        own = [f"--plan={Path('/out/probe/plan.json')}", "--window=1", "--host", "--local"]
        self.assertEqual(host[host.index("--") + 1 :][:4], own)
        self.assertIn(hostjoin.NO_REPLAY, host)
        self.assertIn("--window=2", guest)
        self.assertIn(f"--join={hostjoin.LOCALHOST}", guest)
        self.assertIn("--headless", bots)
        self.assertNotIn("--position", bots)
        self.assertEqual(bots[bots.index("-s") + 1], playcheck.BOTS_SCRIPT)
        for arg in (f"--scenario=res://{BOTS}", "--first=3", f"--peers={Path('/out/probe/peers')}", "--port=24999"):
            self.assertIn(arg, bots)

    def test_a_scenario_of_windows_only_starts_no_bots(self) -> None:
        parts = playcheck.make_parts(scenario(with_header("window 1\nshot a")), Path("/p.json"), 1, Path("/s"))
        self.assertEqual([p.label for p in parts], ["window 1", "window 2"])

    def test_the_cli_takes_scenarios_and_seconds(self) -> None:
        args = cli.build_parser().parse_args(["playcheck"])
        self.assertEqual((args.scenarios, args.seconds), ([], None))
        args = cli.build_parser().parse_args(["playcheck", "esc_menu", "spectate", "--seconds", "90"])
        self.assertEqual((args.scenarios, args.seconds), (["esc_menu", "spectate"], 90))

    def test_without_a_desktop_session_or_on_ci_it_fails_before_anything_starts(self) -> None:
        with mock.patch("sys.stdout", new_callable=io.StringIO):
            for ci, display in ((True, True), (False, False)):
                with self.subTest(ci=ci, display=display):
                    with (
                        mock.patch.object(playcheck, "IS_CI", ci),
                        mock.patch.object(shot, "has_display", return_value=display),
                        mock.patch.object(playcheck, "require_godot") as godot,
                    ):
                        with self.assertRaises(Failure) as caught:
                            playcheck.main(["esc_menu"])
                        self.assertIn("needs a desktop session", str(caught.exception))
                        godot.assert_not_called()

    def test_wrong_seconds_or_names_fail_before_godot_starts(self) -> None:
        with (
            mock.patch("sys.stdout", new_callable=io.StringIO),
            mock.patch.object(playcheck, "IS_CI", False),
            mock.patch.object(shot, "has_display", return_value=True),
            mock.patch.object(playcheck, "require_godot") as godot,
        ):
            for names, seconds in ((["esc_menu"], 0), (["esc_menu"], playcheck.MAX_SECONDS + 1), (["nope"], 60)):
                with self.subTest(names=names, seconds=seconds), self.assertRaises(Failure):
                    playcheck.main(names, seconds=seconds)
            godot.assert_not_called()

    def test_without_seconds_each_scenario_gets_the_default(self) -> None:
        with (
            mock.patch("sys.stdout", new_callable=io.StringIO),
            mock.patch.object(playcheck, "IS_CI", False),
            mock.patch.object(shot, "has_display", return_value=True),
            mock.patch.object(playcheck, "require_godot", return_value="godot"),
            mock.patch.object(playcheck, "ensure_out"),
            mock.patch.object(playcheck.launch, "ensure_import"),
            mock.patch.object(playcheck, "run_one", return_value=0) as run_one,
        ):
            self.assertEqual(playcheck.main(["esc_menu"]), 0)
            self.assertEqual(run_one.call_args.args[2], playcheck.DEFAULT_SECONDS)
            playcheck.main(["esc_menu"], seconds=90)
            self.assertEqual(run_one.call_args.args[2], 90)


# A stand-in for one window or the bots: argv[1] says how it behaves; the rest are the part's arguments.
FAKE = """
import json, pathlib, sys, time
what = sys.argv[1]
args = dict(a.split("=", 1) for a in sys.argv[2:] if a.startswith("--") and "=" in a)
stop = pathlib.Path(args["--stop-file"])
window = args.get("--window", "")
def say(text):
    print(text, flush=True)
if window == "1":
    say("session: hosting base_mode.tres on 127.0.0.1:1")
if window:
    plan = json.loads(pathlib.Path(args["--plan"]).read_text(encoding="utf-8"))
    for i, step in enumerate(plan["steps"][window], start=1):
        say(f"PLAYCHECK at step {i} (line {step['line']}: {step['text']})")
        if what == "hang" and i == 2:
            break
        if what == "fail" and i == 2:
            say(f"PLAYCHECK fail step {i} (line {step['line']}: {step['text']}): timed out after 30.0 s; "
                "the window saw phase 'lobby'")
            sys.exit(1)
        if step["do"] == "shot" and what != "noshot":
            pathlib.Path(step["path"]).write_bytes(b"\\x89PNG\\r\\n\\x1a\\n" + b"0" * 16)
    if what == "error":
        say("ERROR: Parent node is busy adding/removing children")
    if what != "hang":
        say(f"PLAYCHECK done window {window}")
else:
    say("PLAYCHECK at bot 3 step 1 (Ready)")
    if what == "botfail":
        say("PLAYCHECK fail bot 3 (peer 5), step 5 (WalkTo) at tick 9: a target it cannot know")
        sys.exit(1)
while not stop.exists():
    time.sleep(0.05)
say("session: stopped")
if what == "slowexit":
    time.sleep(1.5)
"""


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        for name, value in (("OUT_DIR", self.tmp / "out"), ("LOG_DIR", self.tmp / "logs")):
            patcher = mock.patch.object(playcheck, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        stop = mock.patch.object(hostjoin, "stop_file", return_value=self.tmp / "stop")
        stop.start()
        self.addCleanup(stop.stop)
        out = mock.patch("sys.stdout", new_callable=io.StringIO)
        self.out = out.start()
        self.addCleanup(out.stop)

    def run_scenario(
        self, behaviours: dict[str, str], seconds: int = 30, grace: float = 5, window_grace: float = 5
    ) -> tuple[int, list[hostjoin.Part]]:
        s = scenario()
        seen: list[hostjoin.Part] = []

        def fake_commands(parts: list[hostjoin.Part], _exe: str) -> None:
            for part in parts:
                part.cmd = [sys.executable, "-c", FAKE, behaviours.get(part.label, "ok"), *part.user_args]
            seen.extend(parts)

        with (
            mock.patch.object(playcheck, "set_commands", fake_commands),
            mock.patch.object(hostjoin, "GRACE_SECONDS", grace),
            mock.patch.object(playcheck, "WINDOW_GRACE_SECONDS", window_grace),
        ):
            code = playcheck.run_one(s, "godot", seconds, 24999)
        return code, seen

    def assert_all_stopped(self, parts: list[hostjoin.Part]) -> None:
        for part in parts:
            self.assertIsNotNone(part.proc, part.label)
            self.assertIsNotNone(part.proc.poll(), f"{part.label} still runs")  # type: ignore[union-attr]
        self.assertFalse((self.tmp / "stop").exists())

    def test_windows_that_finish_their_steps_pass_with_their_pngs_and_logs(self) -> None:
        code, parts = self.run_scenario({})
        self.assertEqual(code, 0, self.out.getvalue())
        self.assert_all_stopped(parts)
        out = self.tmp / "out" / "probe"
        self.assertTrue((out / "host_view.png").is_file())
        self.assertTrue((out / "spectating.png").is_file())
        self.assertTrue((out / "peers").is_dir())
        self.assertEqual(json.loads((out / "plan.json").read_text(encoding="utf-8"))["players"], 3)
        for label in ("window-1", "window-2", "bots"):
            self.assertTrue((self.tmp / "logs" / "probe" / f"{label}.log").is_file())
        printed = self.out.getvalue()
        self.assertIn("ok    window 1: its steps done", printed)
        self.assertIn("ok    bots: played", printed)
        self.assertIn("playcheck probe: passed", printed)
        self.assertIn(f"PLAYCHECK {out / 'host_view.png'}", printed)
        self.assertRegex(printed, r"ok    window 1: its steps done, stopped in \d+\.\ds")

    def test_a_window_gets_its_own_longer_grace_to_exit_and_the_bots_hostjoins(self) -> None:
        # #354: a window's renderer teardown can take seconds under load after `session: stopped`.
        behaviours = {"window 1": "slowexit", "window 2": "slowexit", "bots": "slowexit"}
        code, parts = self.run_scenario(behaviours, grace=0.5, window_grace=10)
        self.assertEqual(code, 1, self.out.getvalue())
        self.assert_all_stopped(parts)
        self.assertEqual([p.grace for p in parts], [10, 10, None])
        for window in parts[:2]:
            self.assertEqual(playcheck.problem(window), "", self.out.getvalue())
            seconds = window.stop_seconds
            assert seconds is not None
            self.assertGreaterEqual(seconds, 1.4)
        self.assertTrue(parts[2].killed)
        printed = self.out.getvalue()
        self.assertIn("FAIL  bots: did not stop within 0.5s of the stop and was killed", printed)
        self.assertIn("its last line came", printed)
        self.assertNotIn("FAIL  window", printed)

    def test_a_step_that_times_out_fails_the_run_with_its_line_and_every_process_stops(self) -> None:
        code, parts = self.run_scenario({"window 2": "fail"})
        self.assertEqual(code, 1)
        self.assert_all_stopped(parts)
        self.assertEqual(
            playcheck.problem(parts[1]),
            "step 2 (line 25: wait pointer captured): timed out after 30.0 s; the window saw phase 'lobby'",
        )
        printed = self.out.getvalue()
        self.assertIn("FAIL  window 2: step 2 (line 25: wait pointer captured): timed out", printed)
        self.assertIn("playcheck probe: FAILED", printed)
        # The others stopped cleanly through the stop file.
        self.assertEqual(parts[0].lines[-1], "session: stopped")
        self.assertEqual(parts[2].lines[-1], "session: stopped")

    def test_a_window_cut_short_by_another_failure_says_so(self) -> None:
        code, parts = self.run_scenario({"window 1": "hang", "window 2": "fail"})
        self.assertEqual(code, 1)
        self.assertIn(
            "FAIL  window 1: stopped before its steps were done, since another process failed; it was at step 2 "
            "(line 12: wait phase lobby)",
            self.out.getvalue(),
        )

    def test_a_window_that_never_finishes_fails_at_the_runs_time_limit_naming_its_last_step(self) -> None:
        code, parts = self.run_scenario({"window 1": "hang"}, seconds=3)
        self.assertEqual(code, 1)
        self.assert_all_stopped(parts)
        self.assertEqual(
            playcheck.problem(parts[0]), "did not finish its steps; it was at step 2 (line 12: wait phase lobby)"
        )
        self.assertEqual(playcheck.problem(parts[1]), "")
        self.assertIn("3s passed, stopping", self.out.getvalue())

    def test_an_engine_error_line_fails_the_run(self) -> None:
        code, parts = self.run_scenario({"window 1": "error"})
        self.assertEqual(code, 1)
        self.assertEqual(playcheck.problem(parts[0]), "exited 0 but printed 1 engine error line")
        self.assertIn("-> ERROR: Parent node is busy", self.out.getvalue())

    def test_a_failed_bot_fails_the_run(self) -> None:
        code, parts = self.run_scenario({"bots": "botfail"})
        self.assertEqual(code, 1)
        self.assert_all_stopped(parts)
        self.assertIn("a target it cannot know", playcheck.problem(parts[2]))

    def test_a_missing_png_fails_the_run(self) -> None:
        code, _parts = self.run_scenario({"window 2": "noshot"})
        self.assertEqual(code, 1)
        self.assertIn("no PNG for the shots: spectating", self.out.getvalue())

    def test_a_new_run_starts_with_an_empty_folder(self) -> None:
        old = self.tmp / "out" / "probe" / "old.png"
        old.parent.mkdir(parents=True)
        old.write_bytes(shot.PNG_MAGIC)
        self.run_scenario({})
        self.assertFalse(old.exists())

    def test_logs_of_an_earlier_run_with_more_windows_go(self) -> None:
        old = self.tmp / "logs" / "probe" / "window-3.log"
        old.parent.mkdir(parents=True)
        old.write_text("an earlier run\n", encoding="utf-8")
        self.run_scenario({})
        self.assertFalse(old.exists())
        self.assertTrue((self.tmp / "logs" / "probe" / "window-1.log").is_file())

    def test_a_folder_it_cannot_clear_fails_before_anything_starts(self) -> None:
        old = self.tmp / "out" / "probe" / "old.png"
        old.parent.mkdir(parents=True)
        old.write_bytes(shot.PNG_MAGIC)
        with mock.patch.object(playcheck.shutil, "rmtree"), mock.patch.object(hostjoin, "supervise") as supervise:
            with self.assertRaises(Failure) as caught:
                self.run_scenario({})
        self.assertIn("cannot clear", str(caught.exception))
        self.assertIn("close any program holding its files", str(caught.exception))
        supervise.assert_not_called()
        self.assertTrue(old.exists())


if __name__ == "__main__":
    unittest.main()
