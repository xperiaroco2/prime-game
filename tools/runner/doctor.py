"""`doctor`: check the environment and print a fix for every problem."""

from __future__ import annotations

import configparser
import json
import os
import shutil
import socket
import sys
from pathlib import Path

from . import machine_env, metrics, pins
from .common import (
    IS_CI,
    IS_CLOUD,
    IS_LINUX,
    IS_WINDOWS,
    OUT,
    ROOT,
    Failure,
    bad,
    cloud_session,
    ensure_out,
    gdtoolkit_exe,
    git_bash,
    node_bin,
    godot_bin,
    ok,
    require_godot,
    run,
    say,
    skip,
    version_tuple,
    warn,
)

USER_SETTINGS = "~/.claude/settings.json"
HOOKS_PATH = ".claude/githooks"
# The stall step's backlog (tests/integration/net/enet_stall.gd, BACKLOG_POSES: ENET_RECEIVES_PER_SERVICE + 64) is one
# small datagram per pose, and it must all wait in the host's socket: Godot's ENet keeps the kernel's default UDP
# receive buffer (net.core.rmem_default on Linux). Some kernels charge more per datagram than others (#159).
# test_doctor checks this against the two GDScript constants.
STALL_BACKLOG_DATAGRAMS = 256 + 64
UDP_PROBE_BYTES = 32
# Twice Linux's 208 KB default: room for 512 such datagrams here. tools/cloud/setup.sh raises the default to it.
RMEM_DEFAULT_FIX = 425984
# Windows libraries only (the M5 voice ADR §2): CI deletes both, tools/cloud/setup.sh leaves both out of a cloud clone.
TWOVOIP_EXTENSION = "addons/twovoip/twovoip.gdextension"
TWOVOIP_FILES = (TWOVOIP_EXTENSION, TWOVOIP_EXTENSION + ".uid")
# #385: a session started in the main checkout (the manager and its workflow agents) loads main's root CLAUDE.md at
# launch, and a Read under .claude/worktrees/<n>/ would load that worktree's copy too. The exclude goes only into the
# main checkout's untracked settings.local.json: on Windows a session started inside a worktree reads its own
# .claude/settings.local.json, never main's, so it keeps its only root CLAUDE.md (docs/AGENT_WORKFLOW.md §3).
# #406: the same holds for the rules. Such a Read loads main's copy and the worktree's copy of each matching rule;
# with the second pattern only main's (probed: a worktree-started session still loads the worktree's rules).
CLAUDE_MD_EXCLUDES = ("**/.claude/worktrees/*/CLAUDE.md", "**/.claude/worktrees/*/.claude/rules/**")
EXCLUDES_KEY = "claudeMdExcludes"
PRESENT, ADDED, MISSING = "present", "added", "missing"


def _dotted(parts: tuple[int, ...]) -> str:
    return ".".join(map(str, parts))


class Doctor:
    def __init__(self) -> None:
        self.failures = 0

    def fail(self, text: str, fix: str) -> None:
        self.failures += 1
        bad(text, fix)

    # --- individual checks ------------------------------------------------------------------------

    def python(self) -> None:
        current = sys.version_info[:3]
        if current >= pins.PYTHON_MIN:
            ok(f"Python {_dotted(current)} ({sys.executable})")
        else:
            self.fail(
                f"Python {_dotted(current)} is older than {_dotted(pins.PYTHON_MIN)}",
                f"Install Python {_dotted(pins.PYTHON_MIN)}+ and set PYTHON_BIN in {USER_SETTINGS} env.",
            )

    def machine_paths(self) -> None:
        """Say where each machine path came from: the process environment or a Claude settings file (#55)."""
        report = machine_env.apply()
        for problem in report.problems:
            warn(problem)
        for var in machine_env.MACHINE_VARS:
            source = report.sources.get(var)
            if source:
                ok(f"{var} from {source}: {os.environ.get(var, '')}")
            elif IS_CI or IS_CLOUD:
                skip(f"{var} (not set; {'CI' if IS_CI else 'a cloud session'} finds its tools on PATH)")
            elif var in machine_env.OPTIONAL_VARS:
                skip(f"{var} (not set; the tool on PATH is used)")
            else:
                warn(
                    f"{var} is not set: neither " + ", ".join(report.searched[:-1]) + f" nor {report.searched[-1]} "
                    f"has it; add it to the env of {report.searched[-1]}"
                )

    def godot(self) -> None:
        path = godot_bin()
        try:
            require_godot()
        except Failure as exc:
            self.fail(str(exc), f"GODOT_BIN is currently: {os.environ.get('GODOT_BIN', '(not set)')}")
            return
        ok(f"Godot {pins.GODOT_VERSION_PREFIX} ({path})")
        if IS_WINDOWS and path and not Path(path).name.lower().endswith("_console.exe"):
            warn("GODOT_BIN is not the *_console.exe build; its output may not reach the runner")
        gui = os.environ.get("GODOT_GUI_BIN")
        if IS_CI or IS_CLOUD:
            skip(f"GODOT_GUI_BIN (not needed in {'CI' if IS_CI else 'a cloud session'})")
        elif gui and Path(gui).is_file():
            ok(f"GODOT_GUI_BIN ({gui})")
        elif gui:
            warn(f"GODOT_GUI_BIN points to a missing file: {gui}; a windowed `run` uses it")
        # Not set at all: machine_paths() has already warned about it.

    def git(self) -> None:
        res = run(["git", "--version"], timeout=30)
        if res.rc != 0:
            self.fail("git not found", "Install Git for Windows: https://git-scm.com/download/win")
            return
        ok(res.out.strip())
        lfs = run(["git", "lfs", "version"], timeout=30)
        if lfs.rc == 0:
            ok(lfs.out.strip().split(" (")[0])
        else:
            self.fail("Git LFS not found", "Install Git LFS (bundled with Git for Windows), then run: git lfs install")

    def githooks(self) -> None:
        """Point git at the committed hooks. Only the runner sets this: the agent's own `git config *hooksPath*` is
        denied (docs/AGENT_WORKFLOW.md §8.3)."""
        if IS_CI:
            skip("core.hooksPath (not needed in CI)")
            return
        if not (ROOT / HOOKS_PATH / "pre-push").is_file():
            self.fail(f"{HOOKS_PATH}/pre-push is missing", "Restore it from git: it is committed in the repo.")
            return
        current = run(["git", "config", "--local", "--get", "core.hooksPath"], timeout=30).out.strip()
        if current == HOOKS_PATH:
            ok(f"git hooks: core.hooksPath = {HOOKS_PATH}")
            return
        res = run(["git", "config", "--local", "core.hooksPath", HOOKS_PATH], timeout=30)
        if res.rc == 0:
            ok(f"git hooks: set core.hooksPath to {HOOKS_PATH}" + (f" (it was {current})" if current else ""))
        else:
            self.fail("could not set core.hooksPath", res.out.strip())

    def claude_md_exclude(self, quick: bool) -> None:
        """The main checkout's `.claude/settings.local.json` excludes the worktrees' root CLAUDE.md (#385) and rules
        (#406). The full doctor adds them, merged into what the file holds; the quick one (verify's first step) only
        reads and warns."""
        if IS_CI:
            skip(f"{EXCLUDES_KEY} (not needed in CI)")
            return
        if not IS_WINDOWS:
            skip(
                f"{EXCLUDES_KEY} (Windows only: elsewhere a session started in a worktree reads the main checkout's "
                "settings.local.json, so the exclude would take its only root CLAUDE.md)"
            )
            return
        main = metrics.main_checkout(ROOT)
        if in_worktrees_folder(main):
            # git could not name the main checkout: a worktree's own file is the one a session started there reads on
            # Windows, so the exclude would take that session's only root CLAUDE.md.
            text = f"cannot find the main checkout from {ROOT}, so {EXCLUDES_KEY} is left alone"
            fix = "Run the full doctor from the main checkout: tools\\run.cmd doctor"
            if quick:
                warn(f"{text}. {fix}")
            else:
                self.fail(text, fix)
            return
        target = main / machine_env.LOCAL_SETTINGS
        try:
            missing = ", ".join(missing_claude_md_excludes(target))
            state = add_claude_md_exclude(target, write=not quick)
        except (OSError, UnicodeDecodeError, ValueError) as exc:
            text = f"cannot add {EXCLUDES_KEY} to {target}: {exc}"
            fix = "Fix the file by hand (Claude Code reads it too), then run: tools\\run.cmd doctor"
            if quick:
                warn(f"{text}. {fix}")
            else:
                self.fail(text, fix)
            return
        if state == PRESENT:
            ok(f"{EXCLUDES_KEY} has {', '.join(CLAUDE_MD_EXCLUDES)} ({target})")
        elif state == ADDED:
            ok(f"{EXCLUDES_KEY}: added {missing} to {target}")
        else:
            warn(
                f"{target} lacks {EXCLUDES_KEY} {missing}, so a workflow agent that reads a worktree file loads root "
                "CLAUDE.md or a rule twice; run the full doctor once to add them: tools\\run.cmd doctor"
            )

    def bash(self) -> None:
        path = git_bash()
        if path:
            ok(f"Git Bash ({path})")
        else:
            self.fail(
                "Git Bash not found",
                "Install Git for Windows. Claude Code hooks run in Git Bash; without it they fail open.",
            )

    def gh(self) -> None:
        if IS_CI:
            skip("gh (not needed in CI)")
            return
        if IS_CLOUD:
            skip("gh (a cloud session uses its own GitHub tools; `start` and `board` need an authenticated gh)")
            return
        exe = shutil.which("gh")
        if not exe:
            self.fail("GitHub CLI (gh) not found", "Install it: winget install --id GitHub.cli")
            return
        version = version_tuple(run([exe, "--version"], timeout=30).out)
        if version < pins.GH_MIN:
            self.fail(f"gh {_dotted(version)} is older than {_dotted(pins.GH_MIN)}", "Upgrade: winget upgrade --id GitHub.cli")
        else:
            ok(f"gh {_dotted(version)}")
        res = run([exe, "auth", "status", "--active", "--json", "hosts"], timeout=30)
        try:
            hosts = json.loads(res.out)["hosts"]["github.com"]
            account = next(h for h in hosts if h.get("active"))
        except (ValueError, KeyError, StopIteration, TypeError):
            self.fail("gh is not logged in to github.com", "Run: gh auth login")
            return
        scopes = {s.strip() for s in account.get("scopes", "").split(",")}
        if account.get("state") != "success":
            self.fail(f"gh auth for {account.get('login')} is not valid", "Run: gh auth login")
        elif "project" not in scopes:
            self.fail(f"gh token of {account.get('login')} lacks the 'project' scope", "Run: gh auth refresh -s project")
        else:
            ok(f"gh logged in as {account.get('login')} (scopes include project)")

    def gdtoolkit(self) -> None:
        for name in ("gdformat", "gdlint"):
            exe = gdtoolkit_exe(name)
            if not exe:
                self.fail(
                    f"{name} not found",
                    f"Run: python -m pip install gdtoolkit=={pins.GDTOOLKIT}\n"
                    f"and set GDTOOLKIT_DIR in {USER_SETTINGS} env to the folder holding {name}.",
                )
                continue
            version = run([exe, "--version"], timeout=60).out.strip()
            if version.endswith(pins.GDTOOLKIT):
                ok(f"{version}")
            else:
                self.fail(
                    f"{name} reports '{version}', pinned {pins.GDTOOLKIT}",
                    f"Run: python -m pip install gdtoolkit=={pins.GDTOOLKIT}",
                )

    def node(self) -> None:
        """Node.js for `signal`, a verify step (the toolchain-pins ADR)."""
        exe = node_bin()
        fix = (
            f"Install Node.js {pins.NODE} (Windows: winget install OpenJS.NodeJS.LTS --version {pins.NODE}; a cloud "
            f"session: bash tools/cloud/setup.sh), or set NODE_BIN to its node executable in {USER_SETTINGS} env."
        )
        if not exe:
            self.fail("node not found", fix)
            return
        result = run([exe, "--version"], timeout=60)
        version = version_tuple(result.out)
        if version[:1] == (pins.NODE_MAJOR,):
            ok(f"Node.js {_dotted(version)} ({exe})")
        else:
            self.fail(f"node reports '{result.out.strip()}', pinned {pins.NODE_MAJOR}.x ({pins.NODE} in CI)", fix)

    def addons(self) -> None:
        cfg_path = ROOT / "addons" / "gdUnit4" / "plugin.cfg"
        if not cfg_path.is_file():
            self.fail("GdUnit4 addon missing (addons/gdUnit4)", "Restore it from git: it is committed in the repo.")
            return
        cfg = configparser.ConfigParser()
        cfg.read(cfg_path, encoding="utf-8")
        version = cfg.get("plugin", "version", fallback="?").strip('"')
        if version == pins.GDUNIT4:
            ok(f"GdUnit4 {version}")
        else:
            self.fail(f"GdUnit4 is {version}, pinned {pins.GDUNIT4}", "See docs/decisions/2026-09-28-toolchain-pins.md")

    def claude(self) -> None:
        if IS_CI:
            skip("Claude Code (not needed in CI)")
            return
        exe = shutil.which("claude")
        if not exe:
            ok("no `claude` on PATH (the desktop app bundles its own)")
            return
        version = version_tuple(run([exe, "--version"], timeout=60).out)
        if version >= pins.CLAUDE_CODE_MIN:
            ok(f"Claude Code CLI {_dotted(version)} ({exe})")
        else:
            self.fail(
                f"`claude` on PATH is {_dotted(version)}, older than {_dotted(pins.CLAUDE_CODE_MIN)}",
                "Update it (claude update) or remove it from PATH, so Rider cannot start an old build.",
            )

    def disk(self) -> None:
        """Temp files of every tool (pip, Godot, Claude Code) go to the TEMP drive, often C:."""
        folders = {"project": ROOT, "temp": Path(os.environ.get("TEMP") or os.environ.get("TMPDIR") or "/tmp")}
        seen: set[str] = set()
        for label, folder in folders.items():
            anchor = folder.anchor or "/"
            if anchor in seen or not folder.exists():
                continue
            seen.add(anchor)
            free_gb = shutil.disk_usage(folder).free / 1024**3
            text = f"{free_gb:.1f} GB free on {anchor} ({label})"
            if free_gb < 1:
                self.fail(text, "Free some space: tools fail with 'No space left on device' below about 1 GB.")
            elif free_gb < 5:
                warn(text + "; below 5 GB, clean up soon")
            else:
                ok(text)

    def cloud_twovoip(self) -> None:
        """A cloud session runs without the Windows-only TwoVoIP extension, as CI does (#345): on Linux Godot prints
        an `ERROR:` line for its .gdextension, which fails verify's Godot steps minutes later."""
        if not cloud_session(IS_CLOUD, IS_CI):
            return
        fix = (
            "Run: tools/cloud/setup.sh, or only its last step: git sparse-checkout set --no-cone '/*' "
            + " ".join(f"'!/{path}'" for path in TWOVOIP_FILES)
            + " (git still tracks them; git status stays clean)"
        )
        if (ROOT / TWOVOIP_EXTENSION).exists():
            self.fail(
                f"{TWOVOIP_EXTENSION} is in the working tree: it has no Linux library, so Godot prints an ERROR: "
                "line for it and verify fails",
                fix,
            )
            return
        # `git ls-files -t` tags a file the sparse checkout leaves out "S"; one deleted by hand, as CI does, is still
        # "H", and `git add -A` would commit its deletion. A checkout from before M5 tracks neither: nothing to do.
        listing = run(["git", "ls-files", "-t", "--", *TWOVOIP_FILES], timeout=30, cwd=ROOT)
        tags = listing.out.split()[0::2] if listing.rc == 0 else ["?"]
        if not tags:
            ok("no TwoVoIP extension in this checkout")
        elif set(tags) == {"S"}:
            ok("TwoVoIP extension left out (a cloud session runs without it, as CI does)")
        else:
            self.fail(
                "the TwoVoIP extension is deleted, not left out by the sparse checkout: a commit could take the "
                "deletion",
                fix,
            )

    def udp_backlog(self) -> None:
        """Warn early when a default UDP socket on 127.0.0.1 cannot hold the stall step's backlog (Linux only)."""
        if not IS_LINUX:
            return
        try:
            held = loopback_datagrams_held(STALL_BACKLOG_DATAGRAMS)
        except OSError as exc:
            warn(f"could not probe UDP on 127.0.0.1 for the stall step's backlog: {exc}")
            return
        if held >= STALL_BACKLOG_DATAGRAMS:
            ok(f"a default UDP socket holds the stall backlog ({STALL_BACKLOG_DATAGRAMS} datagrams)")
            return
        warn(
            f"a default UDP socket on 127.0.0.1 holds only {held} of the stall step's {STALL_BACKLOG_DATAGRAMS} "
            f"datagrams, so verify's stall step will fail; raise the default: "
            f"sudo sysctl -w net.core.rmem_default={RMEM_DEFAULT_FIX} (tools/cloud/setup.sh does it)"
        )

    def api_dump(self) -> None:
        target = OUT / "godot-api" / pins.GODOT / "extension_api.json"
        if target.is_file():
            ok(f"engine API dump ({target.relative_to(ROOT).as_posix()})")
            return
        exe = godot_bin()
        if not exe:
            return  # already reported by godot()
        ensure_out()
        target.parent.mkdir(parents=True, exist_ok=True)
        res = run([exe, "--headless", "--no-header", "--dump-extension-api-with-docs"], timeout=180, cwd=target.parent, log="doctor-api-dump")
        if res.rc == 0 and target.is_file():
            ok(f"engine API dump generated ({target.relative_to(ROOT).as_posix()})")
        else:
            self.fail("could not generate the engine API dump", "See tools/out/logs/doctor-api-dump.log")


def in_worktrees_folder(path: Path) -> bool:
    """`path` is inside a `.claude/worktrees/` folder: an agent's worktree, never the main checkout."""
    parts = [part.lower() for part in path.parts]
    return any(parts[i : i + 2] == [".claude", "worktrees"] for i in range(len(parts) - 1))


def _local_settings(path: Path) -> tuple[dict, list]:
    """The settings file at `path` (empty when missing) and its claudeMdExcludes. ValueError when the file is not a
    JSON object or its claudeMdExcludes is not a list."""
    data: dict = {}
    if path.is_file():
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(data, dict):
            raise ValueError("the file is not a JSON object")
    patterns = data.get(EXCLUDES_KEY, [])
    if not isinstance(patterns, list):
        raise ValueError(f"`{EXCLUDES_KEY}` is not a list")
    return data, patterns


def missing_claude_md_excludes(path: Path) -> list[str]:
    """The CLAUDE_MD_EXCLUDES the settings file at `path` does not list, in their order."""
    _data, patterns = _local_settings(path)
    return [pattern for pattern in CLAUDE_MD_EXCLUDES if pattern not in patterns]


def add_claude_md_exclude(path: Path, write: bool = True) -> str:
    """Make the settings file at `path` list every CLAUDE_MD_EXCLUDES pattern in its claudeMdExcludes. PRESENT: it
    already does; ADDED: the missing ones appended and written (a missing file is created; every other key and pattern
    is kept, in its order); MISSING: some are missing and `write` is False. ValueError when the file is not a JSON
    object or its claudeMdExcludes is not a list: nothing is written then."""
    data, patterns = _local_settings(path)
    missing = [pattern for pattern in CLAUDE_MD_EXCLUDES if pattern not in patterns]
    if not missing:
        return PRESENT
    if not write:
        return MISSING
    data[EXCLUDES_KEY] = [*patterns, *missing]
    path.parent.mkdir(parents=True, exist_ok=True)
    # Through a temporary file beside it, so a Claude Code session reading the file never sees half of it.
    scratch = path.with_name(path.name + ".doctor.tmp")
    try:
        scratch.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
        os.replace(scratch, path)
    except BaseException:
        # A failed replace (a sharing violation while Claude Code holds the file) leaves no stray untracked file.
        scratch.unlink(missing_ok=True)
        raise
    return ADDED


def loopback_datagrams_held(count: int, rcvbuf: int | None = None) -> int:
    """Send `count` small datagrams to a fresh, never-read UDP socket on 127.0.0.1 with the default receive buffer
    (or `rcvbuf` bytes); return how many it holds. The kernel drops the rest (RcvbufErrors in /proc/net/snmp)."""
    with (
        socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver,
        socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender,
    ):
        if rcvbuf is not None:
            receiver.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcvbuf)
        receiver.bind(("127.0.0.1", 0))
        address = receiver.getsockname()
        for _ in range(count):
            sender.sendto(bytes(UDP_PROBE_BYTES), address)
        receiver.settimeout(0.2)  # loopback delivery is fast but not synchronous
        held = 0
        try:
            while held < count:
                receiver.recv(UDP_PROBE_BYTES)
                held += 1
        except TimeoutError:
            pass
        return held


def main(quick: bool) -> int:
    say("doctor" + (" --quick" if quick else ""))
    doc = Doctor()
    doc.python()
    doc.machine_paths()
    doc.disk()
    doc.godot()
    doc.gdtoolkit()
    doc.node()
    doc.addons()
    doc.githooks()  # also in --quick: start-task runs the quick doctor
    doc.claude_md_exclude(quick)  # --quick only reads it: verify's doctor step never writes Claude Code's settings
    doc.udp_backlog()  # also in --quick: verify's doctor step then warns minutes before its stall step fails
    doc.cloud_twovoip()  # also in --quick: verify stops at its doctor step instead of failing its Godot steps
    if not quick:
        doc.git()
        doc.bash()
        doc.gh()
        doc.claude()
        doc.api_dump()
    if doc.failures:
        say(f"doctor: {doc.failures} problem(s). Fix them before working on a task.")
        return 1
    say("doctor: all good")
    return 0
