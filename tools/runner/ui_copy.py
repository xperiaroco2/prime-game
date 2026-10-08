"""`ui-copy [tag] [--from DIR]`: the UI track's copy deck into the game, pinned (#208, part a).

xperiaroco2/prime-game-ui keeps every player-facing string of the screens in `copy/strings.csv`, Godot's CSV
translation format (`keys,en,uk,?plural,?context`). The game imports that file as it is at a tag `ui-<semver>`:
`client/i18n/strings.csv`, byte for byte, and `client/i18n/strings.lock.json` with the repo, the tag, its commit and
the file's sha256 (the lock of #288's `ui-sync` has the same shape; `ui-sync` copies the theme pack, not the deck).
Godot's import turns the CSV into `strings.en.translation` and `strings.uk.translation` next to it, which
project.godot's `[internationalization]` lists. The deck is read from GitHub (`gh api`) or, with `--from`, from a
local checkout of prime-game-ui (its tags fetched). `tests/unit/client/i18n/` checks the file against the lock.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import subprocess
from pathlib import Path

from .common import ROOT, Failure, ok, say

REPO = "xperiaroco2/prime-game-ui"
SOURCE = "copy/strings.csv"
FOLDER = "client/i18n"
DECK = "strings.csv"
LOCK = "strings.lock.json"
HEADER = "keys,en,uk,?plural,?context"
TAG_RE = re.compile(r"ui-\d+\.\d+\.\d+")
TIMEOUT = 60.0


def _output(cmd: list[str], what: str) -> bytes:
    try:
        done = subprocess.run(cmd, capture_output=True, timeout=TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Failure(f"{what}: {exc}") from exc
    if done.returncode != 0:
        detail = done.stderr.decode("utf-8", "replace").strip() or f"exit {done.returncode}"
        raise Failure(f"{what}: {detail}")
    return done.stdout


def fetch(tag: str, source: Path | None = None) -> tuple[str, bytes]:
    """The commit of `tag` and the deck's bytes at it: from a local checkout `source`, else from GitHub."""
    if source is not None:
        where = str(source)
        commit = _output(
            ["git", "-C", where, "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}"],
            f"no tag {tag} in {where} (git -C {where} fetch --tags)",
        ).decode().strip()
        return commit, _output(["git", "-C", where, "show", f"{commit}:{SOURCE}"], f"no {SOURCE} at {tag}")
    commit = _output(
        ["gh", "api", f"repos/{REPO}/commits/{tag}", "--jq", ".sha"], f"no tag {tag} in {REPO}"
    ).decode().strip()
    data = _output(
        ["gh", "api", "-H", "Accept: application/vnd.github.raw", f"repos/{REPO}/contents/{SOURCE}?ref={commit}"],
        f"no {SOURCE} at {tag}",
    )
    return commit, data


def key_count(data: bytes) -> int:
    """The deck's keys: the rows with a key (a plural's extra forms are rows without one). Fails on a deck the
    game's import cannot take: not UTF-8, CR line ends, a byte-order mark or another header."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise Failure(f"{SOURCE} is not UTF-8: {exc}") from exc
    if text.startswith("﻿"):
        raise Failure(f"{SOURCE} starts with a byte-order mark")
    if "\r" in text:
        raise Failure(f"{SOURCE} has CR line ends; the deck is LF")
    first = text.split("\n", 1)[0]
    if first != HEADER:
        raise Failure(f"{SOURCE}'s header is {first!r}, not {HEADER!r}")
    rows = list(csv.reader(io.StringIO(text, newline="")))[1:]
    return sum(1 for row in rows if row and row[0])


def lock_text(tag: str, commit: str, data: bytes) -> str:
    lock = {"repo": REPO, "tag": tag, "commit": commit, "files": {DECK: hashlib.sha256(data).hexdigest()}}
    return json.dumps(lock, indent=2) + "\n"


def main(tag: str, source: Path | None = None, root: Path = ROOT) -> int:
    if not TAG_RE.fullmatch(tag):
        raise Failure(f"{tag!r} is not a UI release tag (ui-<major>.<minor>.<patch>)")
    commit, data = fetch(tag, source)
    keys = key_count(data)
    folder = root / FOLDER
    folder.mkdir(parents=True, exist_ok=True)
    (folder / DECK).write_bytes(data)
    (folder / LOCK).write_bytes(lock_text(tag, commit, data).encode("utf-8"))
    ok(f"{FOLDER}/{DECK}: {keys} keys at {tag} ({commit[:12]}), locked in {FOLDER}/{LOCK}")
    say("  next  the next import (check, test, verify) turns it into the translations; commit both files")
    return 0
