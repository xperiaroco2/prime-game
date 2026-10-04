"""`export [--version V] [--rev R]`: the friends' Windows builds (#369; M6 ADR E59, D20; AGENT_WORKFLOW §11 "Exported
builds"). CI's release workflow runs it on a tag; it runs on Linux (and needs `curl`).

1. The pinned export templates: the release's .tpz is downloaded once into ~/godot-download (where tools/cloud/setup.sh
   keeps the editor zip) and checked against pins.GODOT_TEMPLATES_SHA512 on every run. Its Windows x86_64 templates go
   into an app-data folder of the export's own (tools/out/export/data), which Godot reads through XDG_DATA_HOME or
   APPDATA (common.app_data_var), so the human's editor folder is never touched.
2. A clean tree of the commit (`git archive`), not the working tree: untracked files never reach a build, and the
   TwoVoIP extension, which a cloud session's sparse checkout leaves out, is in it. On Linux Godot prints `ERROR:`
   lines for that extension (it has Windows libraries only); those are expected, any other fails the export.
3. Both presets exported (`--export-release` / `--export-debug`) and zipped into tools/out/export/.
4. The release check: the published zip holds the release template's .exe byte for byte (not the debug one), the
   release library of TwoVoIP and no console wrapper. OS.is_debug_build() is false only in a release template, and
   the F3 overlay, the dev tools and the debug wire kinds exist only when it is true (invariant 8).
5. The content hash in an export (M6 ADR §2.5): tools/export/export_probe.gd runs against the release pack. Every
   level and every file it reaches is found; a second tree of the same commit exported again gives the same hash;
   one byte changed in each level gives another.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from . import pins
from .common import IS_LINUX, OUT, ROOT, Failure, app_data_var, git, ok, require_godot, run, say

EXPORT = OUT / "export"
DOWNLOADS = Path.home() / "godot-download"
GAME = "PrimeGame"
RELEASE = "Windows Release"
DEBUG = "Windows Debug"
TEMPLATES = (
    "windows_release_x86_64.exe",
    "windows_release_x86_64_console.exe",
    "windows_debug_x86_64.exe",
    "windows_debug_x86_64_console.exe",
)
RELEASE_FILES = {f"{GAME}.exe", f"{GAME}.pck", "libtwovoip.windows.template_release.x86_64.dll"}
PROBE = ROOT / "tools" / "export" / "export_probe.gd"
EXPORT_TIMEOUT = 600
PROBE_TIMEOUT = 120
LFS_POINTER = b"version https://git-lfs.github.com/spec/v1"
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
NODE_NAME = re.compile(rb'\[node name="([A-Za-z])')


def sha512_of(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def templates_dir(data: Path) -> Path:
    """Where Godot looks for the pinned templates when its app-data folder is `data` (OS::get_godot_dir_name: "godot"
    on Linux, "Godot" elsewhere)."""
    return data / ("godot" if IS_LINUX else "Godot") / "export_templates" / pins.GODOT_TEMPLATES_VERSION


def data_env(data: Path) -> dict[str, str]:
    """Godot's app-data folder for one process (common.app_data_var): the templates and user:// go to `data`."""
    return {app_data_var() or "XDG_DATA_HOME": str(data)}


def install_templates(data: Path) -> Path:
    """Download the pinned .tpz unless a copy with the right checksum is there, check it, and unpack the Windows x86_64
    templates for an app-data folder `data`. Returns the templates folder."""
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    tpz = DOWNLOADS / pins.GODOT_TEMPLATES_TPZ
    if not tpz.is_file() or sha512_of(tpz) != pins.GODOT_TEMPLATES_SHA512:
        say(f"        downloading {pins.GODOT_TEMPLATES_URL}")
        part = tpz.with_name(tpz.name + ".part")
        res = run(["curl", "-fsSL", "--retry", "3", "-o", str(part), pins.GODOT_TEMPLATES_URL], timeout=1800)
        if res.rc != 0:
            raise Failure(f"downloading the export templates failed: {res.out.strip()}")
        part.replace(tpz)
    have = sha512_of(tpz)
    if have != pins.GODOT_TEMPLATES_SHA512:
        raise Failure(f"{tpz.name}: SHA-512 {have} is not the pinned {pins.GODOT_TEMPLATES_SHA512}")
    ok(f"export templates {tpz.name} (SHA-512 checked)")
    folder = templates_dir(data)
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(tpz) as archive:
        version = archive.read("templates/version.txt").decode("utf-8").strip()
        if version != pins.GODOT_TEMPLATES_VERSION:
            raise Failure(f"{tpz.name} holds templates {version}, not {pins.GODOT_TEMPLATES_VERSION}")
        for name in (*TEMPLATES, "version.txt"):
            (folder / name).write_bytes(archive.read(f"templates/{name}"))
    return folder


def clean_tree(rev: str, dest: Path) -> Path:
    """The commit's files in `dest` (`git archive`), without the working tree's untracked or sparse-checkout state."""
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    archive = dest.with_name(dest.name + ".zip")
    res = git("archive", "--format=zip", "-o", str(archive), rev, timeout=300)
    if res.rc != 0:
        raise Failure(f"git archive {rev} failed: {res.out.strip()}")
    with zipfile.ZipFile(archive) as files:
        files.extractall(dest)
    archive.unlink()
    pointers = lfs_pointers(dest)
    if pointers:
        raise Failure(f"{len(pointers)} Git LFS pointers instead of content, e.g. {pointers[0]}: CI checks out no LFS")
    return dest


def lfs_pointers(tree: Path) -> list[str]:
    found = []
    for path in sorted(tree.rglob("*")):
        if path.is_file() and path.stat().st_size < 1024:
            with path.open("rb") as stream:
                if stream.read(len(LFS_POINTER)) == LFS_POINTER:
                    found.append(path.relative_to(tree).as_posix())
    return found


def unexpected_errors(lines: list[str]) -> list[str]:
    """The `ERROR:` lines of a Godot run, minus those about the TwoVoIP extension, which has no Linux library."""
    errors = []
    for i, line in enumerate(lines):
        if not line.startswith("ERROR:"):
            continue
        if "twovoip" in line.lower():
            continue
        errors.append(line + (f" {lines[i + 1].strip()}" if i + 1 < len(lines) else ""))
    return errors


def export(tree: Path, data: Path, mode: str, preset: str, target: Path, log: str) -> None:
    """One headless export of `tree` (`mode`: --export-release, --export-debug or --export-pack) into `target`."""
    target.parent.mkdir(parents=True, exist_ok=True)
    cmd = [require_godot(), "--headless", "--path", str(tree), mode, preset, str(target)]
    res = run(cmd, timeout=EXPORT_TIMEOUT, log=log, env=data_env(data))
    if res.timed_out:
        raise Failure(f"{preset} export timed out after {EXPORT_TIMEOUT}s (log: tools/out/logs/{log}.log)")
    errors = unexpected_errors(res.lines)
    if res.rc != 0 or errors or not target.is_file():
        reason = "; ".join(errors) or f"exit {res.rc}"
        raise Failure(f"{preset} export failed: {reason} (log: tools/out/logs/{log}.log)")
    say(f"        {preset} {mode}: {res.seconds:.0f}s")


@dataclass
class Probe:
    """What tools/export/export_probe.gd printed for one pack: each mode's fingerprint, text lines and missing files."""

    fingerprints: dict[str, int] = field(default_factory=dict)
    texts: dict[str, list[str]] = field(default_factory=dict)
    missing: list[str] = field(default_factory=list)

    def levels(self) -> list[str]:
        """The level files the modes name, in order, each once."""
        found: list[str] = []
        for lines in self.texts.values():
            for line in lines:
                parts = line.split(" ")
                if parts[0] == "level" and parts[1] not in found:
                    found.append(parts[1])
        return found

    def missing_digests(self) -> list[str]:
        return [line for lines in self.texts.values() for line in lines if line.endswith(" missing")]


def parse_probe(lines: list[str]) -> Probe:
    probe = Probe()
    done = False
    for line in lines:
        parts = line.split(" ", 3)
        if parts[0] != "EXPORT" or len(parts) < 3:
            continue
        if parts[1] == "mode" and len(parts) == 4:
            probe.fingerprints[parts[2]] = int(parts[3])
        elif parts[1] == "text" and len(parts) == 4:
            probe.texts.setdefault(parts[2], []).append(parts[3])
        elif parts[1] == "missing" and len(parts) == 4:
            probe.missing.append(f"{parts[2]}: {parts[3]}")
        elif parts[1] == "done":
            done = True
    if not done or not probe.fingerprints:
        raise Failure("the export probe printed no modes (log: tools/out/logs/export-probe.log)")
    return probe


def probe(pack: Path, data: Path) -> Probe:
    """The content hash as the exported pack computes it, run from an empty folder so nothing but the pack is res://."""
    cwd = EXPORT / "probe-cwd"
    cwd.mkdir(parents=True, exist_ok=True)
    cmd = [require_godot(), "--headless", "--main-pack", str(pack), "--script", str(PROBE)]
    res = run(cmd, timeout=PROBE_TIMEOUT, cwd=cwd, log="export-probe", env=data_env(data))
    errors = unexpected_errors(res.lines)
    if res.rc != 0 or res.timed_out or errors:
        reason = "; ".join(errors) or f"exit {res.rc}"
        raise Failure(f"the export probe failed: {reason} (log: tools/out/logs/export-probe.log)")
    return parse_probe(res.lines)


def changed_byte(text: bytes) -> bytes:
    """`text` with one byte changed that an export keeps: the first letter of the first node's name, A to B, any other
    letter to A (a scene has a root node; a converted scene stores its names)."""
    match = NODE_NAME.search(text)
    if match is None:
        raise Failure("no [node name=...] to change in the level")
    at = match.start(1)
    letter = b"B" if text[at : at + 1] == b"A" else b"A"
    return text[:at] + letter + text[at + 1 :]


def check_release(archive: Path, templates: Path) -> list[str]:
    """What makes the zip not a release build: files, the .exe against the templates, the TwoVoIP library."""
    problems = []
    with zipfile.ZipFile(archive) as files:
        names = {Path(name).name: name for name in files.namelist() if not name.endswith("/")}
        if set(names) != RELEASE_FILES:
            problems.append(f"files {sorted(names)}, not {sorted(RELEASE_FILES)}")
        exe = files.read(names[f"{GAME}.exe"]) if f"{GAME}.exe" in names else b""
    if exe != (templates / "windows_release_x86_64.exe").read_bytes():
        problems.append(f"{GAME}.exe is not the release template windows_release_x86_64.exe")
    if exe == (templates / "windows_debug_x86_64.exe").read_bytes():
        problems.append(f"{GAME}.exe is the debug template")
    return problems


def write_zip(folder: Path, archive: Path, top: str) -> None:
    """The files of `folder` under `top/`, sorted, with one fixed date: the same files give the same zip."""
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as out:
        for path in sorted(p for p in folder.iterdir() if p.is_file()):
            info = zipfile.ZipInfo(f"{top}/{path.name}", ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            out.writestr(info, path.read_bytes())


def version_of(rev: str, given: str | None) -> str:
    name = given or git("describe", "--tags", "--always", rev).out.strip() or rev
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
        raise Failure(f"--version {name!r}: use letters, digits, '.', '_' and '-' only")
    return name


def prove_hash(rev: str, data: Path, release: Probe) -> None:
    """The content hash criteria of #369 on a second clean tree of `rev`; raises Failure on any miss."""
    if release.missing or release.missing_digests():
        raise Failure("in the export the hash misses files: " + "; ".join(release.missing + release.missing_digests()))
    ok(f"every level file and what it reaches is found in the export ({len(release.levels())} levels)")
    tree = clean_tree(rev, EXPORT / "trees" / "again")
    proof = EXPORT / "proof"
    if proof.exists():
        shutil.rmtree(proof)
    export(tree, data, "--export-pack", RELEASE, proof / "again" / f"{GAME}.pck", "export-again")
    again = probe(proof / "again" / f"{GAME}.pck", data)
    if again.fingerprints != release.fingerprints or again.texts != release.texts:
        raise Failure(f"two exports of {rev} disagree: {release.fingerprints} and {again.fingerprints}")
    ok(f"two exports of one commit give one hash: {release.fingerprints}")
    for n, level in enumerate(release.levels()):
        path = tree / level.removeprefix("res://")
        before = path.read_bytes()
        path.write_bytes(changed_byte(before))
        try:
            export(tree, data, "--export-pack", RELEASE, proof / f"level-{n}" / f"{GAME}.pck", f"export-level-{n}")
            changed = probe(proof / f"level-{n}" / f"{GAME}.pck", data)
        finally:
            path.write_bytes(before)
        same = [mode for mode, value in changed.fingerprints.items() if value == release.fingerprints.get(mode)]
        if same:
            raise Failure(f"one byte changed in {level} left the hash of {', '.join(same)} unchanged")
        ok(f"one byte changed in {level} changes the hash: {changed.fingerprints}")


def main(version: str | None = None, rev: str = "HEAD") -> int:
    say("export")
    commit = git("rev-parse", "--verify", f"{rev}^{{commit}}").out.strip()
    if not commit:
        raise Failure(f"{rev}: not a commit")
    name = version_of(commit, version)
    EXPORT.mkdir(parents=True, exist_ok=True)
    data = EXPORT / "data"
    templates = install_templates(data)
    tree = clean_tree(commit, EXPORT / "trees" / "build")
    builds = EXPORT / "build"
    if builds.exists():
        shutil.rmtree(builds)
    export(tree, data, "--export-release", RELEASE, builds / "release" / f"{GAME}.exe", "export-release")
    export(tree, data, "--export-debug", DEBUG, builds / "debug" / f"{GAME}.exe", "export-debug")
    release_zip = EXPORT / f"{GAME}-{name}-windows-x86_64.zip"
    debug_zip = EXPORT / f"{GAME}-{name}-windows-x86_64-debug.zip"
    for stale in EXPORT.glob(f"{GAME}-*.zip"):
        stale.unlink()
    write_zip(builds / "release", release_zip, GAME)
    write_zip(builds / "debug", debug_zip, f"{GAME}-debug")
    problems = check_release(release_zip, templates)
    if problems:
        raise Failure(f"{release_zip.name} is not a release build: " + "; ".join(problems))
    ok(f"{release_zip.name} is a release build (the release template's .exe, the release TwoVoIP library)")
    prove_hash(commit, data, probe(builds / "release" / f"{GAME}.pck", data))
    for archive in (release_zip, debug_zip):
        say(f"EXPORT {archive.relative_to(ROOT).as_posix()} {archive.stat().st_size // (1 << 20)} MB")
    say(f"export: done ({commit[:9]})")
    return 0

