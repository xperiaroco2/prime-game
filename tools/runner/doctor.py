"""`doctor`: check the environment and print a fix for every problem."""

from __future__ import annotations

import configparser
import json
import os
import shutil
import sys
from pathlib import Path

from . import machine_env, pins
from .common import (
    IS_CI,
    IS_WINDOWS,
    OUT,
    ROOT,
    Failure,
    bad,
    ensure_out,
    gdtoolkit_exe,
    git_bash,
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
            elif IS_CI:
                skip(f"{var} (not set; CI finds its tools on PATH)")
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
        if IS_CI:
            skip("GODOT_GUI_BIN (not needed in CI)")
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


def main(quick: bool) -> int:
    say("doctor" + (" --quick" if quick else ""))
    doc = Doctor()
    doc.python()
    doc.machine_paths()
    doc.disk()
    doc.godot()
    doc.gdtoolkit()
    doc.addons()
    doc.githooks()  # also in --quick: start-task runs the quick doctor
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
