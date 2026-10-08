"""`ui-sync` (#288): pin the UI track's pack (xperiaroco2/prime-game-ui, `dist/pack/` at a tag `ui-<semver>`).

The pack's text files (JSON and SVG) land byte for byte in client/ui/theme/pack/, under a `.gdignore` so Godot
imports none of them, and client/ui/theme/pack.lock.json records where they came from and the sha256 of each:

    {"repo": "xperiaroco2/prime-game-ui", "tag": "ui-0.4.0", "commit": "<40 hex>",
     "files": {"toy.pack.json": "<64 hex>", "icons/check.svg": "<64 hex>", ...},
     "deferred": {"cards/delivery-1.png": "<64 hex>", ...}}

Binaries (the card art PNGs, a font) are not landed here: they reach the game through the imported folders of #519
and #520, and the lock lists them under `deferred` with the sha256 the pack records for them, so that work knows
what to import and can check it under the same lock.

The tag is fetched with a `--no-checkout` clone and read with `git cat-file`, so no working tree, no line-ending
conversion and no credentials are involved (the repository is public). Everything is read and checked in memory
before anything is written, so a bad pack leaves the pinned copy as it was. With no tag (or `--check`) it only
verifies the pinned copy, offline; with the tag already pinned and intact it does not touch the network either.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .common import ROOT, Failure, bad, force_rmtree, ok, say

REPO = "xperiaroco2/prime-game-ui"
URL = f"https://github.com/{REPO}.git"
PACK_DIR = "dist/pack/"
DEST = Path("client") / "ui" / "theme" / "pack"
LOCK = Path("client") / "ui" / "theme" / "pack.lock.json"
PACK_FILE = "toy.pack.json"
FORMAT = "prime-game-ui/pack"
SCHEMAS = (1,)
TAG_RE = re.compile(r"^ui-\d+\.\d+\.\d+$")
TEXT_SUFFIXES = (".json", ".svg")
LOCK_KEYS = ("repo", "tag", "commit", "files", "deferred")
HEX_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
GDIGNORE = ".gdignore"


@dataclass
class Fetched:
    """The pack at a tag, read from git: the commit and every file under dist/pack/ (path relative to it)."""

    commit: str
    files: dict[str, bytes] = field(default_factory=dict)


Fetch = Callable[[str, str, Path], Fetched]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _git(args: list[str], cwd: Path | None = None) -> bytes:
    """Run git and return its raw stdout (blobs stay bytes; common.git decodes text)."""
    try:
        res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Failure(f"git {args[0]}: {exc}") from exc
    if res.returncode != 0:
        err = res.stderr.decode("utf-8", "replace").strip().splitlines()
        raise Failure(f"git {args[0]} exited {res.returncode}: {err[-1] if err else 'no output'}")
    return res.stdout


def _source_url(source: str) -> str:
    """A local folder becomes a file:// URL, so --depth applies to it too; anything else is used as given."""
    path = Path(source)
    return path.resolve().as_uri() if path.is_dir() else source


def fetch(tag: str, source: str, work: Path) -> Fetched:
    """Clone the tag without a checkout into work/clone and read dist/pack/ from its commit."""
    clone = work / "clone"
    if clone.exists():
        force_rmtree(clone)
    work.mkdir(parents=True, exist_ok=True)
    try:
        url = _source_url(source)
        _git(["clone", "--quiet", "--no-checkout", "--depth", "1", "--branch", tag, url, str(clone)])
        commit = _git(["rev-parse", "--verify", "HEAD^{commit}"], cwd=clone).decode("ascii").strip()
        names = _git(["ls-tree", "-r", "-z", "--name-only", commit, "--", PACK_DIR], cwd=clone)
        fetched = Fetched(commit=commit)
        for name in sorted(n for n in names.decode("utf-8").split("\0") if n):
            fetched.files[name[len(PACK_DIR) :]] = _git(["cat-file", "blob", f"{commit}:{name}"], cwd=clone)
        return fetched
    finally:
        if clone.exists():
            force_rmtree(clone)


def check_tag(tag: str) -> None:
    if not TAG_RE.match(tag):
        raise Failure(f"'{tag}' is not a UI pack tag: it must look like ui-<major>.<minor>.<patch> (ui-0.4.0)")


def parse_pack(data: bytes) -> dict:
    try:
        pack = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Failure(f"{PACK_FILE} is not JSON: {exc}") from exc
    if not isinstance(pack, dict):
        raise Failure(f"{PACK_FILE} is not a JSON object")
    return pack


def pack_problems(pack: dict, tag: str) -> list[str]:
    """What makes a pack unusable at this tag: its format, an unknown schema, a version that is not the tag's."""
    problems = []
    if pack.get("format") != FORMAT:
        problems.append(f"{PACK_FILE}: format is {pack.get('format')!r}, not {FORMAT!r}")
    if pack.get("schema") not in SCHEMAS:
        problems.append(
            f"{PACK_FILE}: schema {pack.get('schema')!r} is unknown (known: {', '.join(map(str, SCHEMAS))}); "
            "update the generator (tools/theme/) and ui_sync.SCHEMAS for it first"
        )
    if f"ui-{pack.get('version')}" != tag:
        problems.append(f"{PACK_FILE}: version {pack.get('version')!r} does not match the tag {tag}")
    return problems


def asset_hashes(pack: dict) -> dict[str, str]:
    """The pack's own record of its assets: path -> sha256."""
    assets = pack.get("assets")
    if not isinstance(assets, list):
        return {}
    return {
        str(a.get("path")): str(a.get("sha256"))
        for a in assets
        if isinstance(a, dict) and isinstance(a.get("path"), str)
    }


def plan(tag: str, fetched: Fetched) -> tuple[dict[str, bytes], dict]:
    """Check the fetched pack in memory and return (the files to land, the lock); a problem raises Failure."""
    if PACK_FILE not in fetched.files:
        raise Failure(f"{PACK_DIR}{PACK_FILE} is missing at {tag}")
    pack = parse_pack(fetched.files[PACK_FILE])
    problems = pack_problems(pack, tag)
    assets = asset_hashes(pack)
    landed: dict[str, bytes] = {}
    deferred: dict[str, str] = {}
    for name, data in sorted(fetched.files.items()):
        digest = sha256(data)
        if name.lower().endswith(TEXT_SUFFIXES):
            if name in assets and assets[name] != digest:
                problems.append(f"{name}: sha256 {digest} differs from the pack's assets record {assets[name]}")
            landed[name] = data
        else:
            deferred[name] = assets.get(name, digest)
    if problems:
        raise Failure(f"the pack at {tag} cannot be used:\n" + "\n".join(problems))
    lock = {
        "repo": REPO,
        "tag": tag,
        "commit": fetched.commit,
        "files": {name: sha256(data) for name, data in landed.items()},
        "deferred": deferred,
    }
    return landed, lock


def lock_text(lock: dict) -> str:
    return json.dumps(lock, indent=2, sort_keys=True) + "\n"


def sync(tag: str, source: str = URL, root: Path = ROOT, fetcher: Fetch = fetch) -> dict:
    """Fetch the pack at tag and replace the pinned copy under root with it; return the new lock."""
    check_tag(tag)
    try:
        fetched = fetcher(tag, source, root / "tools" / "out" / "ui-sync")
    except Failure as exc:
        raise Failure(
            f"could not fetch {tag} from {source}: {exc}\nThe pinned copy is untouched; "
            "`tools\\run.cmd ui-sync --check` verifies it offline."
        ) from exc
    landed, lock = plan(tag, fetched)
    dest = root / DEST
    dest.mkdir(parents=True, exist_ok=True)
    for path in sorted(dest.rglob("*"), reverse=True):
        rel = path.relative_to(dest).as_posix()
        if path.is_file() and rel not in landed and rel != GDIGNORE:
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    for name, data in landed.items():
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (dest / GDIGNORE).write_bytes(b"")
    (root / LOCK).write_bytes(lock_text(lock).encode("utf-8"))
    return lock


def read_lock(root: Path = ROOT) -> dict | None:
    path = root / LOCK
    if not path.is_file():
        return None
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return lock if isinstance(lock, dict) else None


def verify(root: Path = ROOT) -> list[str]:
    """Problems of the pinned copy under root, read-only and offline; [] when the copy matches its lock."""
    lock = read_lock(root)
    if lock is None:
        return [f"{LOCK.as_posix()} is missing or not a JSON object: run `tools\\run.cmd ui-sync <tag>`"]
    problems = []
    if sorted(lock) != sorted(LOCK_KEYS):
        problems.append(f"{LOCK.as_posix()}: keys {sorted(lock)}, expected {sorted(LOCK_KEYS)}")
    files = lock.get("files") if isinstance(lock.get("files"), dict) else {}
    deferred = lock.get("deferred") if isinstance(lock.get("deferred"), dict) else {}
    tag = str(lock.get("tag"))
    if lock.get("repo") != REPO:
        problems.append(f"lock: repo {lock.get('repo')!r} is not {REPO}")
    if not TAG_RE.match(tag):
        problems.append(f"lock: tag {tag!r} is not ui-<semver>")
    if not COMMIT_RE.match(str(lock.get("commit"))):
        problems.append(f"lock: commit {lock.get('commit')!r} is not a 40-hex commit")
    dest = root / DEST
    for name, digest in sorted(files.items()):
        path = dest / name
        if not path.is_file():
            problems.append(f"{name}: in the lock but missing from {DEST.as_posix()}")
        elif sha256(path.read_bytes()) != digest:
            problems.append(f"{name}: sha256 differs from the lock (edited by hand? run ui-sync {tag} --force)")
    if not (dest / GDIGNORE).is_file():
        problems.append(f"{DEST.as_posix()}/{GDIGNORE} is missing (Godot would import the pack)")
    if dest.is_dir():
        for path in sorted(dest.rglob("*")):
            rel = path.relative_to(dest).as_posix()
            if path.is_file() and rel not in files and rel != GDIGNORE:
                problems.append(f"{rel}: under {DEST.as_posix()} but not in the lock")
    if PACK_FILE not in files:
        problems.append(f"lock: {PACK_FILE} is not listed")
        return problems
    if not (dest / PACK_FILE).is_file():
        return problems
    try:
        pack = parse_pack((dest / PACK_FILE).read_bytes())
    except Failure as exc:
        return problems + [str(exc)]
    problems += pack_problems(pack, tag)
    assets = asset_hashes(pack)
    for name, digest in sorted(assets.items()):
        if name in files and files[name] != digest:
            problems.append(f"{name}: the lock's sha256 differs from the pack's assets record")
        if not name.lower().endswith(TEXT_SUFFIXES) and name not in deferred:
            problems.append(f"{name}: a pack asset neither landed nor listed under deferred")
    for name, digest in sorted(deferred.items()):
        if name in assets and assets[name] != digest:
            problems.append(f"{name}: deferred with a sha256 that differs from the pack's assets record")
        if (dest / name).exists():
            problems.append(f"{name}: deferred (a binary) but present under {DEST.as_posix()}")
    return problems


def main(
    tag: str | None, source: str | None = None, check: bool = False, force: bool = False, root: Path = ROOT,
    fetcher: Fetch = fetch,
) -> int:  # fmt: skip
    say("ui-sync")
    if tag:
        check_tag(tag)
    lock = read_lock(root)
    pinned = lock.get("tag") if lock else None
    if check or not tag:
        problems = verify(root)
        if tag and pinned != tag:
            problems.insert(0, f"the pinned tag is {pinned}, not {tag}")
        return _report(problems, f"pinned copy of {pinned} matches its lock (offline)")
    if pinned == tag and not force and not verify(root):
        ok(f"{tag} is already pinned and intact; nothing fetched (--force fetches it again)")
        return 0
    lock = sync(tag, source or URL, root=root, fetcher=fetcher)
    problems = verify(root)
    landed = len(lock["files"])
    return _report(
        problems,
        f"{tag} ({lock['commit'][:10]}): {landed} text files in {DEST.as_posix()}, "
        f"{len(lock['deferred'])} binaries deferred (#520); now run `tools\\run.cmd run tools/theme/build_theme.gd "
        "--headless`",
    )


def _report(problems: list[str], success: str) -> int:
    if problems:
        for problem in problems:
            bad(problem)
        bad(f"{len(problems)} problem(s) in the pinned UI pack", "tools\\run.cmd ui-sync <tag> --force refetches it")
        return 1
    ok(success)
    return 0

