"""A per-file cache of parsed transcripts (#1014), for `metrics` and `wave` (metrics.read_agent).

The transcripts are over a gigabyte (every session, subagent and workflow agent of the project folders), and a report
parses most of them again on every run, though only the live ones changed. So each transcript's parsed summary (what
metrics.read_agent returns, from which every report is built: never a report itself) is kept in one pickle file per
transcript under the folder `enable` names (the CLI's: shared_store, tools/out/cache/transcripts/ of the main checkout,
gitignored, which every worktree shares, so a fresh worktree starts warm, #1256), and served only while the
transcript is unchanged:
- an entry holds the transcript's path, size and mtime (ns) as `os.stat` gave them before the parse, the format
  VERSION, and the parser's own source (`salt`: a hash of metrics.py), and one summary per window (since, until) read;
- an entry whose path, size, mtime, VERSION or salt differs from now, or that cannot be read or unpickled (corrupt,
  cut short, another format), is a miss: the file is parsed again and the entry rewritten;
- a file that changed while it was parsed (the live session's transcript, appended to as it is read) is parsed but
  not stored, and an append changes its size, so a growing file is never served stale;
- `until` beyond the file's newest timestamp cuts nothing, so such a window is stored and looked up as `until` None:
  a report run "until now" hits the entry of an earlier "until now";
- each entry keeps at most WINDOWS windows, the newest last.
Pickle, not JSON, so a hit returns the very types a parse does (Counter, tuples, sets), and every report is
byte-identical with and without the cache. Writes go to a temporary file first, then `os.replace`; a write that fails
(another process holds the file) leaves the cache as it was; the temporary file's name holds the writer's pid, so
two worktrees' runs at once never share one. Without `enable` or `enabled` (library calls, the
tests), nothing is cached.
"""

from __future__ import annotations

import hashlib
import os
import pickle
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

from .common import ROOT, TRANSCRIPT_CACHE, git

# Bump it when an entry's layout changes; a change of metrics.py (the parser) is caught by the salt.
VERSION = 1
# The windows kept per transcript: a report and its --since variants, and the stage window of `wave --stage-since`.
WINDOWS = 8

Window = tuple[float | None, float | None]
Parse = Callable[[Path, float | None, float | None], tuple[dict, float | None]]

_folder: Path | None = None


def enable(folder: Path | None) -> None:
    """Cache the parsed transcripts in `folder` from now on (None: stop caching)."""
    global _folder
    _folder = folder


def folder() -> Path | None:
    return _folder


def shared_store() -> Path:
    """The CLI's cache folder (#1256): TRANSCRIPT_CACHE's place under the main checkout (the parent of git's common
    dir, the same from every worktree), so no worktree parses the transcripts cold; else this checkout's."""
    res = git("rev-parse", "--path-format=absolute", "--git-common-dir", timeout=30)
    lines = [line.strip() for line in res.lines if line.strip()]
    if res.rc == 0 and lines:
        return Path(lines[-1]).parent / TRANSCRIPT_CACHE.relative_to(ROOT)
    return TRANSCRIPT_CACHE


@contextmanager
def enabled(store: Path) -> Iterator[None]:
    """Cache in `store` for the block's length (the CLI's metrics and wave), then as before."""
    before = _folder
    enable(store)
    try:
        yield
    finally:
        enable(before)


def entry_path(store: Path, path: Path) -> Path:
    """One entry per transcript, named by a hash of its absolute path."""
    key = os.path.normcase(os.path.abspath(path))
    return store / (hashlib.sha256(key.encode("utf-8", "surrogatepass")).hexdigest()[:32] + ".pickle")


def signature(path: Path) -> tuple[str, int, int]:
    st = os.stat(path)
    return os.path.normcase(os.path.abspath(path)), st.st_size, st.st_mtime_ns


def load(file: Path) -> dict | None:
    """An entry, or None when there is none or it cannot be read whole (a corrupt entry is a miss)."""
    try:
        value = pickle.loads(file.read_bytes())
    except Exception:  # noqa: BLE001 - any broken entry (truncated, garbage, another format) is a miss
        return None
    return value if isinstance(value, dict) else None


def store(file: Path, entry: dict) -> None:
    """Write `entry` whole or not at all; a failure leaves the cache as it was (the report does not depend on it)."""
    tmp = file.with_name(f"{file.name}.{os.getpid()}.tmp")
    try:
        file.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_bytes(pickle.dumps(entry, protocol=pickle.HIGHEST_PROTOCOL))
        os.replace(tmp, file)
    except OSError:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass


def window(since: float | None, until: float | None, latest: float | None) -> Window:
    """An entry's key for a window: an `until` after every timestamp of the file cuts nothing, so it is None."""
    return since, None if until is None or latest is None or until > latest else until


def read(path: Path, since: float | None, until: float | None, parse: Parse, salt: str) -> dict:
    """`parse(path, since, until)`'s summary, from the cache when the transcript is unchanged since it was stored.

    `parse` returns (the summary, the file's newest timestamp or None)."""
    if _folder is None:
        return parse(path, since, until)[0]
    try:
        sig = signature(path)
    except OSError:
        return parse(path, since, until)[0]  # parse raises what a missing file raises, as without the cache
    file = entry_path(_folder, path)
    entry = load(file)
    if entry is not None and (
        (entry.get("version"), entry.get("salt"), entry.get("sig")) != (VERSION, salt, sig)
        or not isinstance(entry.get("windows"), dict)
    ):
        entry = None
    if entry is not None:
        blob = entry["windows"].get(window(since, until, entry.get("latest")))
        if isinstance(blob, bytes):
            try:
                data = pickle.loads(blob)
            except Exception:  # noqa: BLE001 - a corrupt window is a miss like a corrupt entry
                data = None
            if isinstance(data, dict):
                return data
    data, latest = parse(path, since, until)
    try:
        after = signature(path)
    except OSError:
        return data
    if after != sig:
        return data  # written to while it was read: the next read parses it again
    if entry is None or entry.get("latest") != latest:
        entry = {"version": VERSION, "salt": salt, "sig": sig, "latest": latest, "windows": {}}
    key = window(since, until, latest)
    windows = entry["windows"]
    windows.pop(key, None)
    windows[key] = pickle.dumps(data, protocol=pickle.HIGHEST_PROTOCOL)  # before a caller changes `data`
    while len(windows) > WINDOWS:
        del windows[next(iter(windows))]
    store(file, entry)
    return data
