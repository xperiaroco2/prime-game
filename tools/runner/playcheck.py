"""`playcheck [scenario ...]`: scripted runs of the real game in off-screen windows, screenshots at named steps.

#186, the AI productivity design's P9 (docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item
8); usage in docs/AGENT_WORKFLOW.md §11. It catches what only a playtest saw before (#168, #169).

A scenario, tools/playcheck/scenarios/<name>.txt, names its players: the first `windows` are the game,
client/app/game.tscn, each in a real window at `shot`'s off-screen position (never headless or minimized: Godot then
draws nothing), started by tools/playcheck/playcheck_window.gd with the command line `host` gives a host (window 1:
--host --local) and its local clients (--join=127.0.0.1); the players after them are bots, one headless process of
tests/harness/playcheck/playcheck_bots_main.gd that plays the scripts of a BotScenario over ENet. Each window runs
its own steps. A wait reads only that window's own client: its ClientSession and ClientModel (the host's own client
included), its Esc menu and its pointer, and what its Ui and current camera draw (#275); never HostSession, the match
or core/ (invariant 2), so a window that draws before its filtered event arrived is not hidden by a wait on the
host's state. PNGs go to
tools/out/playcheck/<scenario>/<shot>.png; logs to tools/out/logs/playcheck/<scenario>/.

The scenario file: one line each, `#` starts a comment. The header comes first:
    players <n>             every player, 1 to MAX_PLAYERS: the windows, then the bots
    windows <n>             1 to MAX_WINDOWS: window 1 hosts, the others join it
    bots <file.tres>        a BotScenario (repo-relative or res://) whose scripts play the players after the windows;
                            required when players > windows. Its `bots` counts every player, so it equals
                            `players`; its own roles, settings and clock stay empty
    role <player> <id>      ForceRole, sent by window 1 once every player is in its roster (debug builds, E17)
    setting <id> <int>      ChangeSettings, sent by window 1 then
    clock <seconds>         ForceClock (the match clock's length), sent by window 1 then
    timeout <seconds>       how long a wait may take (default DEFAULT_TIMEOUT); with bots, window 1's setup, and in
                            every other window the first wait after its first `press ready`, waits
                            BOTS_START_SECONDS longer, for their process to start
Then a section per window, `window <n>`, and its steps, run in order:
    wait phase <id>                      its model's phase (lobby, countdown, loading, round, end)
    wait screen <screen>                 the screen it shows (SCREENS)
    wait life [<player>] <life>          its own, or that player's, life as its model knows it (LIVES)
    wait ready [<player>] on|off         a roster member's ready flag (its own without a player)
    wait players <n>                     at least n players in its roster
    wait event <Event> [field=value ...] an event it received since the last one a wait matched; a field
                                         that names a player (peer, raiser, target) holds the player's number
    wait esc open|closed                 its Esc menu
    wait pointer free|captured           its pointer as the game asked for it (playcheck never captures the mouse)
    wait text <field> is|has|lacks <text ...>
                                         what the window draws in a field (FIELDS): `is` the whole text, `has` a
                                         part of it, `lacks` not a part of it. Runs of whitespace (the roster's
                                         two spaces, a line break) count as one space on both sides, and a hidden
                                         field reads as ""
    wait shown <field> on|off            whether the field's Control is visible in the tree (hand.item: an item in
                                         the first-person hand)
    frames <n>                           n rendered frames, 1 to MAX_FRAMES
    press <action>                       the action's key pressed, released the next frame
                                         (Input.parse_input_event); keys only, never a mouse button
    hold <action> / release <action>     Input.action_press until the release (each hold needs one)
    button <text ...>                    the one visible, enabled Button in the window's Ui whose text is <text>
                                         (whitespace as in `wait text`): it takes the focus (grab_focus) and gets
                                         ui_accept's key as `press` gives it; no mouse event, so nothing captures
                                         the mouse. None, or more than one, fails the step
    aim item <kind> / aim off            from `aim item` until `aim off` (each aim needs one), every frame the
                                         window turns its own local player (PlayerController.look) to face the
                                         middle of the nearest item of <kind> resting in its own ClientModel
                                         (no holder; item positions are public); with none, it turns nothing.
                                         The mouse is never captured, so this is the only way to face something
    shot <name>                          the window's viewport as <name>.png ([a-z0-9_], unique in the scenario)
A wait takes `timeout=<seconds>` as its last word to override the default. A `#` in a line starts its comment, so
a text to wait for or a button's text holds none.

The fields are read from the window's own Ui (GameUi) and current camera only, never HostSession, the match or core/
(invariant 2); playcheck_window.gd's GameView has the same keys as FIELDS (a test holds them equal). Assert short,
stable parts with `has`/`lacks`: the HUD's wording is greybox (#150) and will change. A hidden field reads as "", so
`lacks` (and `wait shown <field> off`) holds at once while the field is hidden: put a `has` or `wait shown <field> on`
on the same field before it.

A run fails on a step that times out or cannot run (its window prints the step's line and what it saw, saves
failed-window-<n>.png and exits 1), an engine error line or a non-zero exit of any process, a window that did not
finish its steps within --seconds, or a missing PNG. Every process it started stops through hostjoin's stop file (a
killed runner: the alive file) and is killed if it still runs WINDOW_GRACE_SECONDS later (a window; the bots:
hostjoin's GRACE_SECONDS), so no host is left holding the port; the report gives each one's time from the stop to its
exit. It needs a desktop session: CI never runs it, and verify does not.
"""

from __future__ import annotations

import json
import re
import shutil
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from . import hostjoin, launch, shot
from .common import IS_CI, LOGS, OUT, ROOT, Failure, bad, ensure_out, ok, rel, require_godot, say

SCENARIOS = ROOT / "tools" / "playcheck" / "scenarios"
SUFFIX = ".txt"
WINDOW_SCRIPT = "res://tools/playcheck/playcheck_window.gd"
BOTS_SCRIPT = "res://tests/harness/playcheck/playcheck_bots_main.gd"
OUT_DIR = OUT / "playcheck"
LOG_DIR = LOGS / "playcheck"
# Every line the runner reads from a window or the bots starts with this (playcheck_window.gd's PREFIX).
PREFIX = "PLAYCHECK "
STEP = PREFIX + "at "
DONE = PREFIX + "done"
FAIL = PREFIX + "fail "
# A host and one or two clients in windows (#186); the base mode takes up to ten players.
MAX_WINDOWS = 3
MAX_PLAYERS = 10
DEFAULT_TIMEOUT = 30.0
MAX_TIMEOUT = 600.0
MAX_FRAMES = 600
MAX_CLOCK = 3600
# The whole run of one scenario: joining, the lobby's countdown, loading and the steps.
DEFAULT_SECONDS = 300
MAX_SECONDS = 1800
# How long a window gets from the stop to its exit before it is killed (hostjoin's GRACE_SECONDS for the bots). A
# window's renderer teardown waits for the GPU driver's idle-priority threads, which a PC whose cores are all busy runs
# only when Windows lifts a starved thread, about every 4 s: windows that printed `session: stopped` at once took up
# to 9.5 s to exit beside 32 busy loops on 16 cores, and #318 saw over 10 s (#354).
WINDOW_GRACE_SECONDS = 30
# What window 1's setup wait adds to the scenario's timeout when bots play: their headless process starts only once
# window 1 hosts, and beside 32 busy loops on 16 cores it joined so late that 5 of #354's runs failed the setup after
# 30 s with 2 of 3 players (#406). As long as hostjoin gives a host's process to start listening.
BOTS_START_SECONDS = hostjoin.HOST_READY_SECONDS
SIZE = "1280x720"
NAME_RE = re.compile(r"[a-z0-9_]+")
ID_RE = re.compile(r"[a-z_][a-z0-9_]*")
EVENT_RE = re.compile(r"[A-Z][A-Za-z0-9]*")
INT_RE = re.compile(r"-?[0-9]+")
FLOAT_RE = re.compile(r"-?[0-9]+\.[0-9]+")
LIVES = ("alive", "downed", "dead", "left")
# GameFlow.Screen in client/app/game_flow.gd, lower case.
SCREENS = ("menu", "connecting", "lobby", "loading", "round", "end")
# The event fields that name a player (ScenarioPlay.PLAYER_FIELDS): the scenario writes the player's number.
PLAYER_FIELDS = ("peer", "raiser", "target")
ACTIONS = ("press", "hold", "release")
# What `wait text` and `wait shown` read, the keys of playcheck_window.gd's GameView: the round's Hud labels, the
# LifePanel (title_label, lines_label, bar_label: its bar's visibility), the LobbyHud, the EndScreen, the visible Esc
# tabs' texts joined with ", ", and the kind of the item in the FirstPersonHand under the current camera.
FIELDS = (
    "hud.role",
    "hud.teammates",
    "hud.clock",
    "hud.progress",
    "hud.health",
    "hud.stamina",
    "hud.hand",
    "hud.belt",
    "hud.spectating",
    "hud.destination",
    "hud.hint",
    "hud.crosshair",
    "life.title",
    "life.lines",
    "life.bar",
    "lobby.hint",
    "lobby.roster",
    "lobby.countdown",
    "end.winner",
    "end.countdown",
    "esc.tabs",
    "hand.item",
)
TEXT_OPS = ("is", "has", "lacks")
FIELDS_ARE = f"; the fields are {', '.join(FIELDS)}"


@dataclass
class Step:
    """One step of a window, as the window's plan carries it."""

    line: int
    text: str
    do: str
    args: dict[str, object] = field(default_factory=dict)

    def plan(self) -> dict[str, object]:
        return {"line": self.line, "text": self.text, "do": self.do, **self.args}


@dataclass
class Scenario:
    name: str
    players: int = 0
    windows: int = 0
    # The BotScenario's res:// path; "" without bots.
    bots: str = ""
    roles: dict[int, str] = field(default_factory=dict)
    settings: dict[str, int] = field(default_factory=dict)
    clock: int = 0
    timeout: float = DEFAULT_TIMEOUT
    steps: dict[int, list[Step]] = field(default_factory=dict)

    def shots(self) -> list[str]:
        ordered = [step for window in sorted(self.steps) for step in self.steps[window]]
        return [str(step.args["name"]) for step in ordered if step.do == "shot"]

    def labels(self) -> list[str]:
        """The process labels, in start order: the windows, then the bots."""
        return [window_label(n) for n in range(1, self.windows + 1)] + (["bots"] if self.bots else [])


def window_label(number: int) -> str:
    return f"window {number}"


# --- the scenario file -----------------------------------------------------------------------------


class _Parser:
    def __init__(self, name: str) -> None:
        self.scenario = Scenario(name)
        self.window = 0
        self.line = 0
        # Per-step player numbers to check once `players` is known: (line, number).
        self.player_refs: list[tuple[int, int]] = []
        # The line of each `window <n>`.
        self.sections: dict[int, int] = {}
        # The line of `bots <file.tres>`, and that BotScenario's `bots`.
        self.bots_line = 0
        self.bots_count = 0

    def fail(self, why: str, line: int | None = None) -> Failure:
        return Failure(f"{self.scenario.name}{SUFFIX}:{line or self.line}: {why}")

    def number(self, text: str, what: str, low: int, high: int) -> int:
        if not INT_RE.fullmatch(text) or not low <= int(text) <= high:
            raise self.fail(f"{what} must be a whole number from {low} to {high}, not {text!r}")
        return int(text)

    def seconds(self, text: str, what: str) -> float:
        try:
            value = float(text)
        except ValueError:
            value = -1.0
        if not 0 < value <= MAX_TIMEOUT:
            raise self.fail(f"{what} must be seconds above 0 and at most {MAX_TIMEOUT:g}, not {text!r}")
        return value

    def player(self, text: str) -> int:
        number = self.number(text, "a player", 1, MAX_PLAYERS)
        self.player_refs.append((self.line, number))
        return number

    def parse(self, text: str) -> Scenario:
        for self.line, raw in enumerate(text.splitlines(), start=1):
            words = raw.split("#", 1)[0].split()
            if not words:
                continue
            if words[0] == "window":
                self.section(words)
            elif self.window == 0:
                self.header(words)
            else:
                self.step(words, " ".join(words))
        return self.finish()

    def header(self, words: list[str]) -> None:
        key, args = words[0], words[1:]
        s = self.scenario
        if key == "players" and len(args) == 1:
            s.players = self.number(args[0], "players", 1, MAX_PLAYERS)
        elif key == "windows" and len(args) == 1:
            s.windows = self.number(args[0], "windows", 1, MAX_WINDOWS)
        elif key == "bots" and len(args) == 1:
            s.bots = bots_res(args[0], self.fail)
            self.bots_line, self.bots_count = self.line, bots_count(s.bots)
        elif key == "role" and len(args) == 2:
            player = self.player(args[0])
            if not ID_RE.fullmatch(args[1]):
                raise self.fail(f"a role id looks like dissident, not {args[1]!r}")
            if player in s.roles:
                raise self.fail(f"player {player} already has a role")
            s.roles[player] = args[1]
        elif key == "setting" and len(args) == 2:
            if not ID_RE.fullmatch(args[0]) or not INT_RE.fullmatch(args[1]):
                raise self.fail("a setting is `setting <id> <whole number>`, such as `setting match_duration 5`")
            s.settings[args[0]] = int(args[1])
        elif key == "clock" and len(args) == 1:
            s.clock = self.number(args[0], "clock", 1, MAX_CLOCK)
        elif key == "timeout" and len(args) == 1:
            s.timeout = self.seconds(args[0], "timeout")
        elif key in ("players", "windows", "bots", "role", "setting", "clock", "timeout"):
            raise self.fail(f"wrong number of words for `{key}`")
        else:
            raise self.fail(f"unknown header line `{key}` (steps go under a `window <n>` line)")

    def section(self, words: list[str]) -> None:
        if len(words) != 2:
            raise self.fail("a section is `window <n>`")
        number = self.number(words[1], "a window", 1, MAX_WINDOWS)
        if number in self.scenario.steps:
            raise self.fail(f"window {number} has two sections")
        self.window = number
        self.sections[number] = self.line
        self.scenario.steps[number] = []

    def step(self, words: list[str], text: str) -> None:
        verb, args = words[0], words[1:]
        options: dict[str, object] = {}
        if args and args[-1].startswith("timeout="):
            if verb != "wait":
                raise self.fail("only a wait takes timeout=")
            options["timeout_s"] = self.seconds(args.pop().removeprefix("timeout="), "timeout=")
        if verb == "wait":
            made = self.wait(args)
            made.setdefault("timeout_s", options.get("timeout_s"))
        elif verb == "frames" and len(args) == 1:
            made = {"count": self.number(args[0], "frames", 1, MAX_FRAMES)}
        elif verb in ACTIONS and len(args) == 1:
            if not ID_RE.fullmatch(args[0]):
                raise self.fail(f"an input action looks like ui_cancel, not {args[0]!r}")
            made = {"action": args[0]}
        elif verb == "shot" and len(args) == 1:
            if not NAME_RE.fullmatch(args[0]):
                raise self.fail(f"a shot's name is [a-z0-9_], not {args[0]!r}")
            made = {"name": args[0]}
        elif verb == "button":
            if not args:
                raise self.fail("`button` needs the button's text, such as `button Resume`")
            # Not "text": the plan's step has the line's text under that key.
            made = {"label": " ".join(args)}
        elif verb == "aim":
            made = {"kind": self.aim(args)}
        elif verb in ("frames", "shot", *ACTIONS):
            raise self.fail(f"`{verb}` takes one word")
        else:
            raise self.fail(f"unknown step `{verb}` (wait, frames, press, hold, release, button, aim, shot)")
        self.scenario.steps[self.window].append(Step(self.line, text, verb, made))

    def wait(self, args: list[str]) -> dict[str, object]:
        if not args:
            raise self.fail("`wait` needs what to wait for")
        what, rest = args[0], args[1:]
        made: dict[str, object] = {"what": what}
        if what == "phase" and len(rest) == 1 and ID_RE.fullmatch(rest[0]):
            made["value"] = rest[0]
        elif what == "screen" and len(rest) == 1 and rest[0] in SCREENS:
            made["value"] = rest[0]
        elif what == "life" and 1 <= len(rest) <= 2 and rest[-1] in LIVES:
            made.update(player=self.player(rest[0]) if len(rest) == 2 else 0, value=rest[-1])
        elif what == "ready" and 1 <= len(rest) <= 2 and rest[-1] in ("on", "off"):
            made.update(player=self.player(rest[0]) if len(rest) == 2 else 0, value=rest[-1] == "on")
        elif what == "players" and len(rest) == 1:
            made["value"] = self.number(rest[0], "players", 1, MAX_PLAYERS)
        elif what == "event" and rest and EVENT_RE.fullmatch(rest[0]):
            made.update(event=rest[0], fields=self.fields(rest[1:]))
        elif what == "esc" and len(rest) == 1 and rest[0] in ("open", "closed"):
            made["value"] = rest[0] == "open"
        elif what == "pointer" and len(rest) == 1 and rest[0] in ("free", "captured"):
            made["value"] = rest[0] == "captured"
        elif what == "text":
            made.update(field=self.field(rest, "text"))
            if len(rest) < 2 or rest[1] not in TEXT_OPS:
                raise self.fail(f"a text wait is `wait text <field> is|has|lacks <text ...>`{FIELDS_ARE}")
            if len(rest) < 3:
                raise self.fail(f"`wait text {rest[0]} {rest[1]}` needs the text to look for{FIELDS_ARE}")
            made.update(op=rest[1], value=" ".join(rest[2:]))
        elif what == "shown":
            made.update(field=self.field(rest, "shown"))
            if len(rest) != 2 or rest[1] not in ("on", "off"):
                raise self.fail(f"a shown wait is `wait shown <field> on|off`{FIELDS_ARE}")
            made["value"] = rest[1] == "on"
        else:
            raise self.fail(
                "a wait is `wait phase <id>`, `wait screen <" + "|".join(SCREENS) + ">`, `wait life [<player>] <"
                + "|".join(LIVES) + ">`, `wait ready [<player>] on|off`, `wait players <n>`, "
                "`wait event <Event> [field=value ...]`, `wait esc open|closed`, `wait pointer free|captured`, "
                "`wait text <field> is|has|lacks <text ...>` or `wait shown <field> on|off`"
            )
        return made

    def aim(self, args: list[str]) -> str:
        """The item kind of `aim item <kind>`, or "" for `aim off`."""
        if args == ["off"]:
            return ""
        if len(args) == 2 and args[0] == "item" and ID_RE.fullmatch(args[1]):
            return args[1]
        raise self.fail("an aim is `aim item <kind>` (an item kind's id, such as `aim item knife`) or `aim off`")

    def field(self, rest: list[str], what: str) -> str:
        """The field a `wait text` or `wait shown` names; a mistake lists the fields there are."""
        if not rest or rest[0] not in FIELDS:
            named = f"no field {rest[0]!r}" if rest else "no field"
            raise self.fail(f"`wait {what}` has {named}{FIELDS_ARE}")
        return rest[0]

    def fields(self, words: list[str]) -> dict[str, object]:
        found: dict[str, object] = {}
        for word in words:
            key, sep, value = word.partition("=")
            if not sep or not ID_RE.fullmatch(key) or not value or key in found:
                raise self.fail(f"an event field is `name=value`, each name once, not {word!r}")
            if key in PLAYER_FIELDS:
                found[key] = self.player(value)
            elif INT_RE.fullmatch(value):
                found[key] = int(value)
            elif FLOAT_RE.fullmatch(value):
                found[key] = float(value)
            else:
                found[key] = value
        return found

    def finish(self) -> Scenario:
        s = self.scenario
        if s.players == 0 or s.windows == 0:
            raise self.fail("the header needs `players <n>` and `windows <n>`", 1)
        if s.windows > s.players:
            raise self.fail(f"windows {s.windows} is more than players {s.players}", 1)
        if s.players > s.windows and not s.bots:
            raise self.fail(f"players {s.windows + 1} to {s.players} need `bots <file.tres>`", 1)
        if s.players == s.windows and s.bots:
            raise self.fail("`bots` plays the players after the windows, and there are none", 1)
        if s.bots and self.bots_count != s.players:
            raise self.fail(
                f"bots: {s.bots.removeprefix('res://')} has bots = {self.bots_count}, but players is {s.players} "
                "(a BotScenario's bots counts every player, the windows too)",
                self.bots_line,
            )
        for line, number in self.player_refs:
            if number > s.players:
                raise self.fail(f"player {number}: the scenario has {s.players}", line)
        for number, line in self.sections.items():
            if number > s.windows:
                raise self.fail(f"window {number}: the scenario has {s.windows}", line)
        has_setup = bool(s.roles or s.settings or s.clock)
        for number, steps in s.steps.items():
            held: dict[str, int] = {}
            # The line of the `aim item` in force; 0 while the window aims at nothing.
            aiming = 0
            # With bots, a window without the setup (which waits for every player) gives its first wait after its
            # first `press ready` the bots' start time too: the round needs the bots in and ready (#406).
            late_bots = bool(s.bots) and not (number == 1 and has_setup)
            after_ready = False
            for step in steps:
                if step.args.get("timeout_s") is None and step.do == "wait":
                    step.args["timeout_s"] = s.timeout
                if late_bots and after_ready and step.do == "wait":
                    step.args["timeout_s"] = float(step.args["timeout_s"]) + BOTS_START_SECONDS
                    late_bots = False
                if step.do == "press" and step.args.get("action") == "ready":
                    after_ready = True
                if step.do == "aim" and step.args["kind"]:
                    if aiming:
                        raise self.fail(f"window {number} aims again before `aim off` (line {aiming})", step.line)
                    aiming = step.line
                elif step.do == "aim":
                    if not aiming:
                        raise self.fail(f"window {number} has `aim off` without an `aim item` before it", step.line)
                    aiming = 0
                action = str(step.args.get("action", ""))
                if step.do == "hold":
                    if action in held:
                        raise self.fail(f"window {number} holds {action} twice", step.line)
                    held[action] = step.line
                elif step.do == "release":
                    if held.pop(action, None) is None:
                        raise self.fail(f"window {number} releases {action}, which it does not hold", step.line)
            for action, line in held.items():
                raise self.fail(f"window {number} holds {action} and never releases it", line)
            if aiming:
                raise self.fail(f"window {number} aims and never stops: `aim off` ends an `aim item`", aiming)
        names = s.shots()
        if not names:
            raise self.fail("a scenario saves at least one `shot`", 1)
        repeated = sorted({name for name in names if names.count(name) > 1})
        if repeated:
            raise self.fail(f"shot names must be unique: {', '.join(repeated)}", 1)
        if has_setup:
            setup = {"roles": {str(k): v for k, v in s.roles.items()}, "settings": s.settings, "clock": s.clock}
            setup.update(players=s.players, timeout_s=s.timeout + (BOTS_START_SECONDS if s.bots else 0))
            text = "setup (ForceRole, ForceClock, ChangeSettings)"
            s.steps.setdefault(1, []).insert(0, Step(0, text, "setup", setup))
        return s


def bots_res(text: str, fail: Callable[[str], Failure]) -> str:
    """A BotScenario's file (repo-relative or res://) -> its checked res:// path."""
    rel_path = text.replace("\\", "/").removeprefix("res://").removeprefix("./")
    if not rel_path.endswith(".tres") or ".." in Path(rel_path).parts or Path(rel_path).is_absolute():
        raise fail(f"bots: give a .tres inside the project, not {text!r}")
    if not (ROOT / rel_path).is_file():
        raise fail(f"bots: {rel_path} not found")
    return f"res://{rel_path}"


def bots_count(res: str) -> int:
    """The `bots` of a BotScenario .tres (its [resource] section; BotScenario's default 1 when the line is absent)."""
    text = (ROOT / res.removeprefix("res://")).read_text(encoding="utf-8")
    found = re.search(r"^\[resource\]\s*$(.*)", text, re.MULTILINE | re.DOTALL)
    count = re.search(r"^bots = ([0-9]+)\s*$", found.group(1) if found else "", re.MULTILINE)
    return int(count.group(1)) if count else 1


def parse(text: str, name: str) -> Scenario:
    """The scenario `name` from its file's text; a Failure names the line and what is wrong."""
    return _Parser(name).parse(text)


def available() -> list[str]:
    return sorted(path.stem for path in SCENARIOS.glob(f"*{SUFFIX}"))


def load(name: str) -> Scenario:
    # A name, or its file in SCENARIOS.
    stem = name.replace("\\", "/").removeprefix("./").removeprefix(rel(SCENARIOS) + "/").removesuffix(SUFFIX)
    path = SCENARIOS / f"{stem}{SUFFIX}"
    if not NAME_RE.fullmatch(stem) or not path.is_file():
        raise Failure(f"{name}: no such scenario in {rel(SCENARIOS)}; there are: {', '.join(available()) or 'none'}")
    return parse(path.read_text(encoding="utf-8"), stem)


def plan(scenario: Scenario, out: Path) -> dict[str, object]:
    """What every window reads (--plan=): its steps, the players and where the PNGs and the peer files go."""
    steps: dict[str, list[dict[str, object]]] = {}
    for number in range(1, scenario.windows + 1):
        made = []
        for step in scenario.steps.get(number, []):
            entry = step.plan()
            if step.do == "shot":
                entry["path"] = str(out / f"{step.args['name']}.png")
            made.append(entry)
        steps[str(number)] = made
    return {
        "scenario": scenario.name,
        "players": scenario.players,
        "windows": scenario.windows,
        "peers": str(out / "peers"),
        "out": str(out),
        "steps": steps,
    }


# --- the processes ---------------------------------------------------------------------------------


def make_parts(scenario: Scenario, plan_path: Path, port: int, stop: Path) -> list[hostjoin.Part]:
    """The windows (window 1 hosts on 127.0.0.1, the others join it), then the bots, with their arguments."""
    parts = hostjoin.host_parts(port, scenario.windows - 1, local=True, stop=stop)
    for number, part in enumerate(parts, start=1):
        part.label = window_label(number)
        part.user_args = [f"--plan={plan_path}", f"--window={number}", *part.user_args]
        part.grace = WINDOW_GRACE_SECONDS
        if number == 1:
            part.user_args.append(hostjoin.NO_REPLAY)
    if scenario.bots:
        tail = [f"--port={port}", f"--stop-file={stop}", f"--alive-file={hostjoin.alive_file(stop)}"]
        peers = plan_path.parent / "peers"
        args = [f"--scenario={scenario.bots}", f"--first={scenario.windows + 1}", f"--peers={peers}", *tail]
        parts.append(hostjoin.Part("bots", args))
    return parts


def set_commands(parts: list[hostjoin.Part], exe: str) -> None:
    """Windows: the window script in a real window at shot's off-screen position with the dummy audio driver. The
    console exe opens them too, and relays the lines the runner reads. The bots: their script headless."""
    for part in parts:
        bots = part.label == "bots"
        part.cmd = launch.command(
            exe,
            ROOT,
            BOTS_SCRIPT if bots else WINDOW_SCRIPT,
            headless=bots,
            offscreen=not bots,
            audio="dummy",
            user_args=part.user_args,
            window=None if bots else ["--resolution", SIZE],
        )


def failed_line(part: hostjoin.Part) -> str:
    return next((line for line in part.lines if line.startswith(FAIL)), "")


def done(part: hostjoin.Part) -> bool:
    return any(line.startswith(DONE) for line in part.lines)


def last_step(part: hostjoin.Part) -> str:
    return next((line.removeprefix(STEP) for line in reversed(part.lines) if line.startswith(STEP)), "")


def finished(parts: list[hostjoin.Part]) -> bool:
    """supervise's end: a process failed or ended, or every window finished its steps."""
    for part in parts:
        if failed_line(part) or (part.proc is not None and not part.running):
            return True
    return all(done(part) for part in parts if part.label != "bots")


def problem(part: hostjoin.Part, *, others_failed: bool = False) -> str:
    """Why this process failed the run, or ''. `others_failed`: another process failed first, and the stop that
    followed cut this window's steps short."""
    line = failed_line(part)
    if line:
        return line.removeprefix(FAIL)
    if part.problem:
        return part.problem
    if part.label != "bots" and not done(part):
        where = last_step(part)
        why = "stopped before its steps were done, since another process failed" if others_failed else (
            "did not finish its steps"
        )
        return why + (f"; it was at {where}" if where else "; it started none")
    return ""


def missing_shots(scenario: Scenario, out: Path) -> list[str]:
    return [
        name
        for name in scenario.shots()
        if not (out / f"{name}.png").is_file() or not (out / f"{name}.png").read_bytes().startswith(shot.PNG_MAGIC)
    ]


def shown(path: Path) -> str:
    return rel(path) if path.is_relative_to(ROOT) else str(path)


def report(scenario: Scenario, parts: list[hostjoin.Part], out: Path) -> int:
    failed = 0
    first = any(failed_line(part) or part.problem for part in parts)
    for part in parts:
        where = f" (log: {shown(part.log)})" if part.log is not None else ""
        why = problem(part, others_failed=first and not (failed_line(part) or part.problem))
        if why:
            failed += 1
            bad(f"{part.label}: {why}{where}", "\n".join(launch.error_lines(part.lines)[1]))
        else:
            stopped = hostjoin.stop_time(part)
            stopped = f", stopped{stopped}" if stopped else ""
            ok(f"{part.label}: {'its steps done' if part.label != 'bots' else 'played'}{stopped}{where}")
    if not failed:
        missing = missing_shots(scenario, out)
        if missing:
            failed += 1
            bad(f"no PNG for the shots: {', '.join(missing)} (in {shown(out)})")
    for png in sorted(out.glob("*.png")):
        say(f"PLAYCHECK {shown(png)}")
    say(f"playcheck {scenario.name}: FAILED" if failed else f"playcheck {scenario.name}: passed")
    return 1 if failed else 0


def clear(folder: Path) -> None:
    """Removes `folder` of an earlier run, so none of its files passes for this run's."""
    shutil.rmtree(folder, ignore_errors=True)
    if folder.exists():
        raise Failure(f"cannot clear {shown(folder)}: close any program holding its files (a PNG viewer), then rerun")


def run_one(scenario: Scenario, exe: str, seconds: int, port: int) -> int:
    say(f"playcheck {scenario.name}: {scenario.windows} window(s) and {scenario.players - scenario.windows} bot(s)")
    out = OUT_DIR / scenario.name
    clear(out)
    # hostjoin.write_logs clears old logs only for a first part labelled host: a log of an earlier run with more
    # windows or bots would stay beside this run's.
    clear(LOG_DIR / scenario.name)
    (out / "peers").mkdir(parents=True)
    plan_path = out / "plan.json"
    plan_path.write_text(json.dumps(plan(scenario, out), indent=2) + "\n", encoding="utf-8")
    stop = hostjoin.stop_file()
    parts = make_parts(scenario, plan_path, port, stop)
    set_commands(parts, exe)
    say(f"        {' '.join(parts[0].cmd[1:])}")
    hostjoin.supervise(parts, seconds=seconds, stop=stop, until=finished)
    hostjoin.write_logs(parts, LOG_DIR / scenario.name)
    return report(scenario, parts, out)


def main(names: list[str] | None = None, seconds: int | None = None) -> int:
    say("playcheck")
    seconds = DEFAULT_SECONDS if seconds is None else seconds
    if IS_CI or not shot.has_display():
        raise Failure("playcheck needs a desktop session with a GPU (real windows, like shot); CI never runs it")
    if not 1 <= seconds <= MAX_SECONDS:
        raise Failure(f"--seconds must be between 1 and {MAX_SECONDS}")
    scenarios = [load(name) for name in (names or available())]
    if not scenarios:
        raise Failure(f"no scenarios in {rel(SCENARIOS)}")
    exe = require_godot()
    ensure_out()
    launch.ensure_import()
    from .verify import free_udp_port

    failed = sum(run_one(scenario, exe, seconds, free_udp_port()) for scenario in scenarios)
    say(f"playcheck: FAILED ({failed} of {len(scenarios)})" if failed else "playcheck: passed")
    if not failed:
        say("playcheck: done. Read the PNGs to check them; a PR lists their paths for the human to drag in.")
    return 1 if failed else 0
