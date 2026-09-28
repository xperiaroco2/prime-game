"""`normalize <files>`: re-save hand-written .tscn/.tres files the way the Godot editor would (docs/AGENT_WORKFLOW.md §11).

Runs tools/normalize/normalize.gd in headless editor context (`--headless -e -s`). Only the editor's file system
hands out uids: a plain `-s` run saves files without them, and the designer's editor would then rewrite them. The
`-e -s` combination is not a documented workflow; it works on 4.7.2 and is smoke-tested after each Godot upgrade.
"""

from __future__ import annotations

import re
from pathlib import Path

from .common import ROOT, Failure, bad, git_status, godot, ok, say
from .lint import strip_cr

SCRIPT = "res://tools/normalize/normalize.gd"
EXTENSIONS = (".tscn", ".tres")
TIMEOUT = 300


def to_res(name: str) -> str:
    """A repo-relative path or res:// path -> a checked res:// path."""
    text = name.replace("\\", "/")
    rel = text.removeprefix("res://").removeprefix("./")
    if Path(rel).is_absolute() or ".." in Path(rel).parts:
        raise Failure(f"{name}: give a path inside the project (repo-relative or res://)")
    if not rel.endswith(EXTENSIONS):
        raise Failure(f"{name}: normalize handles only {' and '.join(EXTENSIONS)} files")
    if rel.startswith(("addons/", "tools/out/", ".godot/")):
        raise Failure(f"{name}: third-party and generated files are never normalized")
    if not (ROOT / rel).is_file():
        raise Failure(f"{name}: file not found")
    return f"res://{rel}"


HEADER_RE = re.compile(r"^\[(\w+)(.*)\]\s*$")
ATTR_RE = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|[^\s\]]+)')
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_/:.-]*)\s*=")


def property_keys(text: str) -> set[str]:
    """'<section>: <key>' for every property line. Sections are named by id or node path, which a re-save keeps
    (it adds uid= and unique_id=, so whole header lines cannot be compared)."""
    keys, section = set(), ""
    for line in text.splitlines():
        header = HEADER_RE.match(line)
        if header:
            attrs = {k: v.strip('"') for k, v in ATTR_RE.findall(header.group(2))}
            ident = attrs.get("id") or "/".join(filter(None, (attrs.get("parent"), attrs.get("name"))))
            section = f"[{header.group(1)} {ident}]".replace(" ]", "]")
            continue
        key = KEY_RE.match(line)
        if key and section:
            keys.add(f"{section}: {key.group(1)}")
    return keys


def _rel(res_path: str) -> str:
    return res_path.removeprefix("res://")


def _file(res_path: str) -> Path:
    return ROOT / _rel(res_path)


def command(paths: list[str]) -> list[str]:
    return ["--headless", "-e", "-s", SCRIPT, "--", *paths]


def parse(lines: list[str], paths: list[str]) -> tuple[list[str], list[str]]:
    """(saved paths, problems) from the script's NORMALIZE lines."""
    saved = [line.split(" ", 2)[2].strip() for line in lines if line.startswith("NORMALIZE saved ")]
    problems = [line.removeprefix("NORMALIZE error ").strip() for line in lines if line.startswith("NORMALIZE error ")]
    if not any(line.startswith("NORMALIZE done") for line in lines):
        problems.append("the normalize script did not finish (see tools/out/logs/normalize.log)")
    problems += [f"{p}: not saved" for p in paths if p not in saved and not any(x.startswith(p) for x in problems)]
    return saved, problems


def main(files: list[str]) -> int:
    say("normalize")
    paths = [to_res(name) for name in files]
    before = git_status()
    contents = {p: _file(p).read_bytes() for p in paths}
    res = godot(command(paths), timeout=TIMEOUT, log="normalize")
    if res.timed_out:
        raise Failure(f"normalize timed out after {TIMEOUT}s (log: tools/out/logs/normalize.log)")
    saved, problems = parse(res.lines, paths)
    for path in saved[:]:
        strip_cr(_file(path))  # the repo is LF (.gitattributes)
        dropped = property_keys(contents[path].decode("utf-8")) - property_keys(_file(path).read_text("utf-8"))
        if dropped:
            # Godot drops a property it does not know (a typo) or one set to its default: never lose it silently.
            _file(path).write_bytes(contents[path])
            saved.remove(path)
            problems.append(
                f"{path}: the re-save dropped {', '.join(sorted(dropped))}. A misspelled property, or one set to its "
                "default value. The file is restored unchanged: fix or remove those lines, then normalize again."
            )
    for line in problems:
        bad(line)
    for path in saved:
        ok(f"re-saved {path}" + ("" if _file(path).read_bytes() != contents[path] else " (unchanged: already normalized)"))
    # Other files the editor context wrote, such as the .uid sidecar of a new script: commit them too.
    others = sorted(line for line in git_status() - before if not any(line.endswith(_rel(p)) for p in paths))
    if others:
        say("        the editor also created or changed (commit them with your change):")
        for line in others:
            say(f"          {line}")
    say("normalize: FAILED" if problems else "normalize: done")
    return 1 if problems else 0
