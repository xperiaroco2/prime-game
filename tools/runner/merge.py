"""`merge-check` and `merge`: merge safety for open PRs (docs/AGENT_WORKFLOW.md §7.1; P4 of
docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md, item 3).

`merge-check [--base B] [<pr>...]` checks the open PRs (default: every one, grouped by base) before a merge, with no
Godot: each PR onto its base tip, and each pair of PRs into the same base.
- Textual: `git merge-tree --write-tree` of the two commits; a conflict names its files.
- Semantic: the symbols one side removes, renames or changes, matched against what the other side's added lines use.
  GDScript (`class_name`, `class`, `func`, `const`, `var` and `signal` members, enums and their values) and the
  runner's Python (`def`, `class`, module and class attributes): a member removed (not declared again in the same
  file and class), or a `func` / `signal` / `def` whose parameters changed (names, types, which have defaults, the
  return type, `static`). Wire rows (a `net/messages/*schema*.gd`): a row whose lines changed, with the field names
  added or removed, and rows added or removed. A `.tres` field renamed in a section that stays. A file deleted or
  renamed, by its path. Test fixtures are GDScript and count the same way. The M4 failures it is built from: #153
  renamed `PlayerRules.ghost_speed_factor`, which #154 read; #156 added the flag `invulnerable` to the `Snapshot`
  row, whose test avatar #154 built by hand.
  Uses are the identifiers in the other side's added lines of code and data (`.gd`, `.py`, `.tres`, `.tscn`,
  `.godot`, `.cfg`, `.gdshader`; comments stripped) and their string literals without spaces (`&"Snapshot"`,
  `"downed"`, `mock.patch.object(m, "name")`). A wire row or field matches only a string literal (fields travel as
  dictionary keys, and `position` is everywhere as an identifier); a name starting with `_` matches only in its own
  file; a line that declares the name is no use. A symbol match is a lead, not a proof: `--trial` settles it.
  A `func` / `def` that only appended parameters with defaults (every old call still binds: `gdunit.main` gaining
  `shards=None` in #210, which #200 called) is a note, not an overlap; a parameter removed, renamed, retyped or
  reordered, or a new one without a default, stays an overlap (#207), and so does one a .py use patches by name
  (`mock.patch.object(gdunit, "main", ...)`: a stand-in with the old arguments breaks once callers pass the new one).
- The "onto base" check compares the PR with what its base gained since the PR's fork (another PR merged meanwhile).
- Across bases (#207): each checked PR with every open PR that finally lands in another base (`main`,
  `release/m<k>`; a PR stacked on one of its own track lands in that one's), compared only when both change one
  shared file (`tools/`, `.claude/`, `.github/`, `docs/AGENT_WORKFLOW.md`: every track may change them, and a
  milestone takes `main` in at its next wave boundary): the textual conflicts in the files both change, and the same
  symbol check, each PR measured from its fork with its own base. The other cross-base pairs are named as not
  compared. `--base B` checks B's PRs within B and against every other base.
It prints one Markdown table per base and one across bases (paste them into a wave comment or a PR), each overlap
with the symbol and file:line on both sides, and the notes; exit 1 on any conflict or overlap, or a PR it could not
check (its base is gone from origin).

`merge-check --trial <pr>... [--base B]`: the base (default: the first PR's) plus the PRs merged in order with
`--no-ff` in a scratch detached worktree under `tools/out/merge/`, then that tree's own `verify`; it reports and
removes the worktree. For what no symbol match sees (behaviour, test expectations).

`merge <pr> --base release/<x>`: a milestone manager's merge of a task PR into its release branch
(docs/decisions/2026-10-01-release-branch-per-milestone.md). It refuses any base but `release/*` (only humans merge
into `main`) and a task checkout (a `.claude/worktrees/<n>` worktree or a task branch, here or in the current
folder); fetches only when a human already merged the PR; requires green CI (`gh pr checks`) on a ready, open PR
into that base whose head origin has; then merges `--no-ff` with GitHub's message in a scratch detached worktree at
`origin/<base>`, runs `verify` on the merged tree (always: the release-branch gate; no tree-equality shortcut), pushes
the merge commit by its hash (`git push origin <sha>:refs/heads/<base>`, a fast-forward the pre-push hook allows),
removes the worktree, confirms that GitHub shows the PR merged and prints one line for the wave comment. A red
`verify` or a conflict pushes nothing and leaves nothing to undo. `merge --sync-main --base release/<x>` takes
`origin/main` into the release branch the same way (the wave-boundary sync of the engineer's N2 answer). The fresh
reviews' gate (no open blocker or major) stays the manager's call.

The git commands run inside the runner's process, so neither the permission rules nor the guard see them: a session
types only `tools\\run.cmd merge ...`, which `PowerShell(tools\\run.cmd *)` allows and the guard passes from the main
checkout and from any worktree (test_merge.py). Typed by hand, `git worktree remove` of the scratch worktree would ask
(the guard treats everything inside the project as another checkout for git).
"""

from __future__ import annotations

import itertools
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

from .common import OUT, ROOT, Failure, Result, bad, ensure_out, ok, run, say, warn

REMOTE = "origin"
# The checkout the commands work in, and where scratch worktrees go (tests point both at temporary folders).
REPO = ROOT
SCRATCH = OUT / "merge"
TIMEOUT = 300
VERIFY_TIMEOUT = 3600
# Deleting a worktree's ignored .godot/ import cache can take minutes on Windows (start.py).
REMOVE_TIMEOUT = 600
# After the push, how long to wait for GitHub to show the PR merged.
CONFIRM_TRIES, CONFIRM_WAIT = 12, 5.0
TASK_BRANCH_RE = re.compile(r"^[a-z][a-z0-9]*/[0-9]+-[a-z0-9][a-z0-9._-]*$")
TASK_WORKTREE_RE = re.compile(r"[\\/]\.claude[\\/]worktrees[\\/][0-9]+$")
PR_FIELDS = "number,title,state,baseRefName,headRefName,headRefOid,isDraft,headRepositoryOwner"
# Files whose added lines count as uses, and whose declarations the semantic check reads.
USE_SUFFIXES = (".gd", ".py", ".tres", ".tscn", ".godot", ".cfg", ".gdshader")
# A deleted or renamed file counts as a removed path, unless nothing refers to it by path.
PATHLESS_SUFFIXES = (".md", ".uid", ".import")


# --- GitHub and git ---------------------------------------------------------------------------------------------------


@dataclass
class PullRequest:
    number: int
    title: str
    base: str
    head: str
    oid: str
    owner: str = ""
    draft: bool = False
    state: str = "OPEN"

    @classmethod
    def of(cls, data: dict[str, Any]) -> PullRequest:
        owner = data.get("headRepositoryOwner") or {}
        return cls(
            int(data["number"]), str(data.get("title", "")), str(data["baseRefName"]), str(data["headRefName"]),
            str(data["headRefOid"]), str(owner.get("login", "")), bool(data.get("isDraft")),
            str(data.get("state", "OPEN")),
        )  # fmt: skip

    @property
    def label(self) -> str:
        return f"#{self.number}"


def gh(*args: str) -> Result:
    """One gh call in the checkout (tests replace it)."""
    exe = shutil.which("gh")
    if not exe:
        raise Failure("GitHub CLI (gh) not found: winget install --id GitHub.cli")
    return run([exe, *args], timeout=120, cwd=REPO)


def gh_json(*args: str) -> Any:
    res = gh(*args)
    try:
        return json.loads(res.out)
    except ValueError:
        raise Failure(f"gh {' '.join(args[:3])} failed: {res.out.strip()[-400:]}") from None


def open_prs() -> list[PullRequest]:
    data = gh_json("pr", "list", "--state", "open", "--limit", "200", "--json", PR_FIELDS)
    return sorted((PullRequest.of(d) for d in data), key=lambda p: p.number)


def pr_view(number: int) -> PullRequest:
    return PullRequest.of(gh_json("pr", "view", str(number), "--json", PR_FIELDS))


def ci_problems(number: int) -> list[str]:
    """What keeps the PR's CI from being green: failing or pending checks, or none reported. Empty: green."""
    res = gh("pr", "checks", str(number), "--json", "name,state,bucket")
    try:
        checks = json.loads(res.out)
    except ValueError:
        return [res.out.strip()[-300:] or "gh pr checks gave no answer"]
    if not checks:
        return ["no checks reported"]
    return [f"{c.get('name')}: {c.get('state')}" for c in checks if c.get("bucket") not in ("pass", "skipping")]


def _git(*args: str, cwd: Path | None = None, timeout: float = TIMEOUT, env: dict[str, str] | None = None) -> Result:
    return run(["git", *args], timeout=timeout, cwd=cwd or REPO, env=env)


def _out(*args: str, cwd: Path | None = None) -> str:
    """stdout of a git command that must succeed (stderr apart: warnings never reach the parsed text)."""
    res = subprocess.run(
        ["git", *args], cwd=cwd or REPO, capture_output=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL
    )
    if res.returncode != 0:
        err = res.stderr.decode("utf-8", "replace").strip()
        raise Failure(f"git {' '.join(args[:3])} failed: {err[-600:]}")
    return res.stdout.decode("utf-8", "replace").replace("\r\n", "\n")


def _must(res: Result, what: str) -> str:
    if res.timed_out or res.rc != 0:
        raise Failure(f"{what} failed: {res.out.strip()[-600:]}")
    return res.out.strip()


def _sha(ref: str) -> str:
    res = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"], cwd=REPO, capture_output=True,
        timeout=TIMEOUT, stdin=subprocess.DEVNULL,
    )  # fmt: skip
    return res.stdout.decode().strip() if res.returncode == 0 else ""


def _is_ancestor(commit: str, of: str) -> bool:
    return _git("merge-base", "--is-ancestor", commit, of).rc == 0


def fetch() -> None:
    _must(_git("fetch", REMOTE), f"git fetch {REMOTE}")
    ok(f"fetched {REMOTE}")


def ensure_head(pr: PullRequest) -> None:
    """The PR's head commit is here: from the branch on origin, else from GitHub's pull/<n>/head."""
    if _sha(pr.oid):
        return
    _git("fetch", REMOTE, f"refs/pull/{pr.number}/head")
    if not _sha(pr.oid):
        raise Failure(f"{pr.label}'s head {pr.oid[:10]} is not on {REMOTE}; run merge-check again in a minute")


def merge_message(pr: PullRequest) -> str:
    """GitHub's own merge commit message."""
    who = f"{pr.owner}/{pr.head}" if pr.owner else pr.head
    return f"Merge pull request #{pr.number} from {who}\n\n{pr.title}".rstrip()


# --- textual check ----------------------------------------------------------------------------------------------------


def textual(ours: str, theirs: str) -> list[str]:
    """The files `git merge-tree --write-tree` finds in conflict between two commits; empty when they merge."""
    res = subprocess.run(
        ["git", "merge-tree", "--write-tree", "--name-only", "--no-messages", ours, theirs], cwd=REPO,
        capture_output=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL,
    )  # fmt: skip
    lines = res.stdout.decode("utf-8", "replace").splitlines()
    if res.returncode == 0:
        return []
    if res.returncode == 1:
        return sorted({line for line in lines[1:] if line.strip()})
    raise Failure(f"git merge-tree {ours[:10]} {theirs[:10]} failed: {res.stderr.decode('utf-8', 'replace')[-400:]}")


# --- reading code: one lexer for GDScript and Python ------------------------------------------------------------------


@dataclass
class Lexed:
    """Per line (index 0 is line 1): the code with comments removed and string literals blanked to `""`; the string
    literals that end on it as (prefix, text), the prefix `&` for a StringName; whether it continues an earlier line
    (inside brackets or a triple-quoted string, or after a backslash). Bracket pairs as (open line, close line)."""

    code: list[str] = field(default_factory=list)
    strings: list[list[tuple[str, str]]] = field(default_factory=list)
    cont: list[bool] = field(default_factory=list)
    groups: list[tuple[int, int]] = field(default_factory=list)


def lex(text: str) -> Lexed:
    out = Lexed()
    quote, prefix, content = "", "", []  # an open string literal (only a triple-quoted one spans lines)
    stack: list[int] = []
    backslash = False
    for number, row in enumerate(text.replace("\r\n", "\n").split("\n"), 1):
        code: list[str] = []
        found: list[tuple[str, str]] = []
        out.cont.append(bool(quote) or bool(stack) or backslash)
        i = 0
        while i < len(row):
            ch = row[i]
            if quote:
                if ch == "\\":
                    content.append(row[i : i + 2])
                    i += 2
                    continue
                if row.startswith(quote, i):
                    if len(quote) == 1:
                        found.append((prefix, "".join(content)))
                    code.append('""')
                    i += len(quote)
                    quote = ""
                    continue
                content.append(ch)
            elif ch == "#":
                break
            elif ch in "\"'":
                quote = row[i : i + 3] if row[i : i + 3] in ('"""', "'''") else ch
                prefix, content = (row[i - 1] if i and row[i - 1] in "&^" else ""), []
                i += len(quote)
                continue
            else:
                if ch in "([{":
                    stack.append(number)
                elif ch in ")]}" and stack:
                    out.groups.append((stack.pop(), number))
                code.append(ch)
            i += 1
        if len(quote) == 1:
            quote = ""  # an unterminated one-line string ends with its line
        line = "".join(code)
        backslash = line.rstrip().endswith("\\")
        out.code.append(line)
        out.strings.append(found)
    return out


def _indent(row: str) -> int:
    width = 0
    for ch in row:
        if ch == "\t":
            width += 4
        elif ch == " ":
            width += 1
        else:
            break
    return width


def _statement_end(lexed: Lexed, index: int) -> int:
    end = index
    while end + 1 < len(lexed.cont) and lexed.cont[end + 1]:
        end += 1
    return end


def _split_top(text: str, sep: str = ",") -> list[str]:
    """text split at sep outside brackets (string literals are already blanked)."""
    parts, depth, start = [], 0, 0
    for i, ch in enumerate(text):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == sep and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return [p.strip() for p in parts if p.strip()]


def _signature(header: str, name: str) -> str:
    """What a caller depends on: each parameter's name, type and whether it has a default (not the default's value),
    the return type and `static`."""
    at = header.find("(", header.find(name) + len(name))
    if at < 0:
        return "()"
    depth, end = 0, len(header)
    for i in range(at, len(header)):
        depth += {"(": 1, ")": -1}.get(header[i], 0)
        if depth == 0:
            end = i
            break
    params = []
    for param in _split_top(header[at + 1 : end]):
        head = re.split(r":?=", param, maxsplit=1)[0]
        pname, _, ptype = head.partition(":")
        params.append(pname.strip() + ":" + re.sub(r"\s+", "", ptype) + ("=" if "=" in param else ""))
    returns = re.match(r"\s*->\s*([^:]+)", header[end + 1 :])
    static = "static " if re.match(r"^\s*static\b", header) else ""
    return f"{static}({', '.join(params)})" + ("->" + re.sub(r"\s+", "", returns.group(1)) if returns else "")


SIGNATURE_RE = re.compile(r"^(static )?\((.*)\)(->.*)?$")


def appends_defaults(old: str, new: str) -> bool:
    """Whether the `_signature` new keeps old's parameters (names, types, defaults), `static` and return type, and
    only appends parameters with a default (or Python's `*args`, `**kwargs`, a bare `*`): every call that bound
    before still binds. A parameter removed, renamed, retyped or reordered, or a new one without a default, is not."""
    before, after = SIGNATURE_RE.match(old), SIGNATURE_RE.match(new)
    if not before or not after or before.group(1, 3) != after.group(1, 3):
        return False
    old_params = before.group(2).split(", ") if before.group(2) else []
    new_params = after.group(2).split(", ") if after.group(2) else []
    added = new_params[len(old_params) :]
    return (
        bool(added)
        and new_params[: len(old_params)] == old_params
        and all(p.endswith("=") or p.startswith("*") for p in added)
    )


@dataclass(frozen=True)
class Decl:
    name: str
    kind: str
    scope: str  # the inner class (dotted) or enum it belongs to; "" for the script or module
    line: int
    end: int
    signature: str = ""


GD_ANNOTATIONS = re.compile(r"^(?:@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?\s*)+")
GD_KINDS = (
    ("class_name", re.compile(r"^class_name\s+([A-Za-z_]\w*)")),
    ("signal", re.compile(r"^signal\s+([A-Za-z_]\w*)")),
    ("func", re.compile(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)")),
    ("const", re.compile(r"^const\s+([A-Za-z_]\w*)")),
    ("var", re.compile(r"^(?:static\s+)?var\s+([A-Za-z_]\w*)")),
    ("class", re.compile(r"^class\s+([A-Za-z_]\w*)")),
    ("enum", re.compile(r"^enum(?:\s+([A-Za-z_]\w*))?\s*\{")),
)
PY_KINDS = (
    ("def", re.compile(r"^(?:async\s+)?def\s+([A-Za-z_]\w*)")),
    ("class", re.compile(r"^class\s+([A-Za-z_]\w*)")),
    ("var", re.compile(r"^([A-Za-z_]\w*)\s*(?::[^=]*)?=(?!=)")),
    ("var", re.compile(r"^([A-Za-z_]\w*)\s*:\s*[^=\s][^=]*$")),
)


def declarations(text: str, python: bool = False) -> list[Decl]:
    """The members a script or module declares (not the locals of a function body), with their lines."""
    lexed = lex(text)
    rows = text.replace("\r\n", "\n").split("\n")
    found: list[Decl] = []
    blocks: list[tuple[int, str, str]] = []  # (indent, "class" or "body", name)
    for index, code in enumerate(lexed.code):
        if lexed.cont[index] or not code.strip():
            continue
        indent = _indent(rows[index])
        while blocks and indent <= blocks[-1][0]:
            blocks.pop()
        body = any(kind == "body" for _, kind, _ in blocks)
        end = _statement_end(lexed, index)
        header = " ".join(lexed.code[index : end + 1]).strip()
        stripped = header if python else GD_ANNOTATIONS.sub("", header)
        kind, name = "", ""
        for each, pattern in PY_KINDS if python else GD_KINDS:
            match = pattern.match(stripped)
            if match:
                kind, name = each, match.group(1) or ""
                break
        scope = ".".join(n for _, k, n in blocks if k == "class")
        if kind and not body and not (kind == "class_name" and blocks):
            if kind == "enum":
                found += _enum(lexed, index, end, name, scope)
            else:
                signature = _signature(stripped, name) if kind in ("func", "signal", "def") else ""
                if python and kind == "var" and name.isupper():
                    kind = "const"
                found.append(Decl(name, kind, scope, index + 1, end + 1, signature))
        opens = header.endswith(":")
        if python:
            if kind in ("def", "class"):
                blocks.append((indent, "body" if kind == "def" or body else "class", name))
        elif opens:
            blocks.append((indent, "class" if kind == "class" and not body else "body", name))
    return found


def _enum(lexed: Lexed, index: int, end: int, name: str, scope: str) -> list[Decl]:
    found = [Decl(name, "enum", scope, index + 1, end + 1)] if name else []
    inner = scope + ("." if scope and name else "") + name
    text = " ".join(lexed.code[index : end + 1])
    body = text[text.find("{") + 1 : text.rfind("}")]
    for item in _split_top(body):
        value = re.match(r"([A-Za-z_]\w*)", item)
        if not value:
            continue
        line = next(
            (n for n in range(index, end + 1) if re.search(rf"\b{value.group(1)}\b", lexed.code[n].split("{")[-1])),
            index,
        )
        found.append(Decl(value.group(1), "enum value", inner, line + 1, line + 1))
    return found


# --- wire rows --------------------------------------------------------------------------------------------------------

ROW_NAME = re.compile(r"^[A-Z]\w*$")
FIELD_NAME = re.compile(r"^[a-z_][a-z0-9_]*$")


class WireRows:
    """Which rows of a wire schema each line belongs to: the row names (`&"Snapshot"`) on the line itself, else those
    in the smallest bracket pair around it that holds any, else, for a line of a `var` statement, the rows of the
    lines below that use the variable (the Snapshot's avatar record is `var avatar`, which `var avatars` takes, which
    the row `&"Snapshot"` takes), else those of its function."""

    def __init__(self, text: str) -> None:
        self.lexed = lex(text)
        self.names = [{s for p, s in found if p == "&" and ROW_NAME.match(s)} for found in self.lexed.strings]
        rows = text.replace("\r\n", "\n").split("\n")
        self.funcs: list[tuple[int, int]] = []
        start = 0
        for index, code in enumerate(self.lexed.code):
            top = code.strip() and not self.lexed.cont[index] and _indent(rows[index]) == 0
            if top and start:
                self.funcs.append((start, index))
                start = 0
            if top and re.match(r"^(?:static\s+)?func\b", code):
                start = index + 1
        if start:
            self.funcs.append((start, len(rows)))

    def _in(self, first: int, last: int) -> set[str]:
        return set().union(*self.names[first - 1 : last]) if last >= first else set()

    def rows_of(self, line: int, depth: int = 0) -> set[str]:
        if self.names[line - 1]:
            return set(self.names[line - 1])
        for first, last in sorted((g for g in self.lexed.groups if g[0] <= line <= g[1]), key=lambda g: g[1] - g[0]):
            names = self._in(first, last)
            if names:
                return names
        func = next(((first, last) for first, last in self.funcs if first <= line <= last), None)
        if func is None:
            return set()
        start = line
        while start > 1 and self.lexed.cont[start - 1]:
            start -= 1
        variable = re.match(r"^\s*var\s+([A-Za-z_]\w*)", self.lexed.code[start - 1])
        if variable and depth < 4:
            end = _statement_end(self.lexed, start - 1) + 1
            used = re.compile(rf"\b{variable.group(1)}\b")
            names = set().union(
                *(self.rows_of(n, depth + 1) for n in range(end + 1, func[1] + 1) if used.search(self.lexed.code[n - 1]))
            )
            if names:
                return names
        return self._in(*func)

    def fields(self, line: int) -> set[str]:
        return {s for p, s in self.lexed.strings[line - 1] if p == "" and FIELD_NAME.match(s)}

    def code(self, line: int) -> bool:
        return bool(self.lexed.code[line - 1].strip())


# --- one side of a check: a PR, or what its base gained since the PR's fork --------------------------------------------


@dataclass(frozen=True)
class Symbol:
    name: str
    kind: str  # func, var, const, signal, class_name, class, enum, enum value, def, wire row, wire field, ...
    change: str  # removed, changed, added, or the fields a wire row changed
    path: str
    line: int
    own: str = ""  # a private name (`_x`) matches only in this path (its path after the change)
    # A module-level Python name: its module's stem and paths. Another .py file uses it only as `<module>.<name>`
    # (or `<module>, "<name>"` in a patch) or after `from ...<module> import <name>`; a .gd file never does.
    module: str = ""
    home: tuple[str, ...] = ()
    # A `func` / `def` that only gained parameters with defaults after its old ones: every old call still binds, so a
    # use of it is a note, not an overlap (#207: `gdunit.main` gained `shards=None` in #210; #200 called it).
    compatible: bool = False

    def describe(self) -> str:
        return f"`{self.name}` ({self.kind}, {self.change}{'; old calls still bind' if self.compatible else ''})"


@dataclass(frozen=True)
class Use:
    path: str
    line: int


@dataclass
class Change:
    label: str
    symbols: list[Symbol] = field(default_factory=list)
    idents: dict[str, list[Use]] = field(default_factory=dict)  # identifiers in added lines
    literals: dict[str, list[Use]] = field(default_factory=dict)  # string literals without spaces in added lines
    texts: list[tuple[Use, str]] = field(default_factory=list)  # added code lines, for removed paths
    py_idents: dict[Use, frozenset[str]] = field(default_factory=dict)  # identifiers of each added .py line
    py_imports: dict[str, set[tuple[str, str]]] = field(default_factory=dict)  # .py path -> (module stem, name)

    def add_use(self, table: dict[str, list[Use]], name: str, use: Use) -> None:
        table.setdefault(name, []).append(use)


@dataclass
class FileDiff:
    old: str | None = None
    new: str | None = None
    removed: list[int] = field(default_factory=list)
    added: list[int] = field(default_factory=list)
    hunks: list[tuple[list[int], list[int]]] = field(default_factory=list)


HUNK_RE = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def parse_diff(text: str) -> list[FileDiff]:
    """`git diff -U0 -M` output as files with their removed (old) and added (new) line numbers."""
    files: list[FileDiff] = []
    cur: FileDiff | None = None
    old_no = new_no = 0
    for line in text.split("\n"):
        if line.startswith("diff --git "):
            cur = FileDiff()
            files.append(cur)
            rest = line[len("diff --git ") :]
            half = (len(rest) - 5) // 2
            if rest.startswith("a/") and rest[half + 2 : half + 5] == " b/" and rest[2 : half + 2] == rest[half + 5 :]:
                cur.old = cur.new = rest[2 : half + 2]
        elif cur is None:
            continue
        elif not cur.hunks:
            if line.startswith("--- "):
                cur.old = None if line == "--- /dev/null" else line[6:]
            elif line.startswith("+++ "):
                cur.new = None if line == "+++ /dev/null" else line[6:]
            elif line.startswith("rename from "):
                cur.old = line[len("rename from ") :]
            elif line.startswith("rename to "):
                cur.new = line[len("rename to ") :]
            elif line.startswith("deleted file mode"):
                cur.new = None
            elif line.startswith("new file mode"):
                cur.old = None
            elif match := HUNK_RE.match(line):
                old_no, new_no = int(match.group(1)), int(match.group(2))
                cur.hunks.append(([], []))
        elif match := HUNK_RE.match(line):
            old_no, new_no = int(match.group(1)), int(match.group(2))
            cur.hunks.append(([], []))
        elif line.startswith("-"):
            cur.removed.append(old_no)
            cur.hunks[-1][0].append(old_no)
            old_no += 1
        elif line.startswith("+"):
            cur.added.append(new_no)
            cur.hunks[-1][1].append(new_no)
            new_no += 1
    return files


def read_blobs(specs: list[str]) -> dict[str, str]:
    """`<rev>:<path>` -> text, through one `git cat-file --batch`; a missing one is left out."""
    if not specs:
        return {}
    res = subprocess.run(
        ["git", "cat-file", "--batch"], cwd=REPO, input="\n".join(specs).encode() + b"\n", capture_output=True,
        timeout=TIMEOUT,
    )  # fmt: skip
    data, at, found = res.stdout, 0, {}
    for spec in specs:
        newline = data.find(b"\n", at)
        if newline < 0:
            break
        header = data[at:newline].decode("utf-8", "replace").split()
        at = newline + 1
        if len(header) == 3 and header[1] == "blob":
            size = int(header[2])
            found[spec] = data[at : at + size].decode("utf-8", "replace")
            at += size + 1
        elif len(header) == 3:
            at += int(header[2]) + 1
    return found


def build_change(label: str, before: str, after: str) -> Change:
    """The symbols that `before..after` removes, renames or changes, and what its added lines use."""
    change = Change(label)
    if before == after:
        return change
    files = parse_diff(
        _out(
            "-c", "core.quotePath=false", "diff", "-U0", "-M", "--no-color", "--no-ext-diff", "--no-textconv",
            "--src-prefix=a/", "--dst-prefix=b/", before, after, "--",
        )  # fmt: skip
    )
    wanted = [f"{before}:{f.old}" for f in files if f.old and f.old.endswith(USE_SUFFIXES)]
    wanted += [f"{after}:{f.new}" for f in files if f.new and f.new.endswith(USE_SUFFIXES)]
    blobs = read_blobs(wanted)
    old_text = {f.old: blobs.get(f"{before}:{f.old}", "") for f in files if f.old}
    new_text = {f.new: blobs.get(f"{after}:{f.new}", "") for f in files if f.new}
    new_decls = {
        f.new: declarations(new_text[f.new], python=f.new.endswith(".py"))
        for f in files
        if f.new and f.new.endswith((".gd", ".py"))
    }
    classes = {d.name for decls in new_decls.values() for d in decls if d.kind == "class_name"}
    for f in files:
        if f.old and f.old != f.new and not f.old.endswith(PATHLESS_SUFFIXES):
            change.symbols.append(Symbol(f.old, "file", "removed" if f.new is None else f"renamed to {f.new}", f.old, 0))
        if f.old and f.old.endswith((".gd", ".py")):
            change.symbols += _code_symbols(f, old_text[f.old], new_decls.get(f.new or "", []), classes)
        if f.old and f.new and "net/messages/" in f.new and "schema" in f.new.rsplit("/", 1)[-1]:
            change.symbols += _wire_symbols(f, old_text[f.old], new_text[f.new])
        if f.old and f.new and f.new.endswith(".tres"):
            change.symbols += _resource_symbols(f, old_text[f.old], new_text[f.new])
        if f.new and f.new.endswith(USE_SUFFIXES) and f.added:
            _uses(change, f.new, new_text[f.new], f.added, new_decls.get(f.new, []))
    # A field renamed in its class and in a .tres is one symbol: the class's member.
    members = {s.name for s in change.symbols if s.kind in ("var", "const")}
    change.symbols = [s for s in change.symbols if not (s.kind == "resource field" and s.name in members)]
    return change


def _code_symbols(f: FileDiff, old: str, new_decls: list[Decl], classes: set[str]) -> list[Symbol]:
    python = (f.old or "").endswith(".py")
    removed = set(f.removed)
    by_key = {(d.scope, d.name): d for d in new_decls}
    found: list[Symbol] = []
    home = tuple(p for p in dict.fromkeys([f.old, f.new]) if p)
    module = (f.old or "").rsplit("/", 1)[-1].removesuffix(".py")
    for d in declarations(old, python=python):
        if not removed.intersection(range(d.line, d.end + 1)) or d.name.startswith("__"):
            continue
        # A private name, or a member of a private class (`_Quiet.write`), matches only in its own file.
        private = d.name.startswith("_") or any(part.startswith("_") for part in d.scope.split("."))
        own = (f.new or f.old or "") if private else ""
        count = len(found)
        if f.new is None:
            # A deleted file: what others name it by (a class, a class_name); its path is a symbol of its own.
            if d.kind in ("class_name", "class") and not d.scope and d.name not in classes:
                found.append(Symbol(d.name, d.kind, "removed", f.old or "", d.line, own))
            if python and len(found) > count:
                found[-1] = replace(found[-1], module=module, home=home)
            continue
        now = by_key.get((d.scope, d.name))
        if d.kind == "class_name":
            if d.name not in classes:
                found.append(Symbol(d.name, d.kind, "removed", f.old or "", d.line, own))
        elif now is None:
            found.append(Symbol(d.name, d.kind, "removed", f.old or "", d.line, own))
        elif d.signature != now.signature and d.kind in ("func", "signal", "def"):
            compatible = d.kind != "signal" and appends_defaults(d.signature, now.signature)
            what = f"changed {d.signature} -> {now.signature}"
            found.append(Symbol(d.name, d.kind, what, f.new, now.line, own, compatible=compatible))
        if python and not d.scope and len(found) > count:
            found[-1] = replace(found[-1], module=module, home=home)
    return found


def _wire_symbols(f: FileDiff, old: str, new: str) -> list[Symbol]:
    before, after = WireRows(old), WireRows(new)
    found: list[Symbol] = []
    for gone_lines, new_lines in f.hunks:
        gone = [n for n in gone_lines if before.code(n)]
        came = [n for n in new_lines if after.code(n)]
        named_gone = set().union(*(before.names[n - 1] for n in gone)) if gone else set()
        named_came = set().union(*(after.names[n - 1] for n in came)) if came else set()
        line = came[0] if came else (gone[0] if gone else 0)
        for row in sorted(named_came - named_gone):
            found.append(Symbol(row, "wire row", "added", f.new or "", line))
        for row in sorted(named_gone - named_came):
            found.append(Symbol(row, "wire row", "removed", f.new or "", line))
        gone = [n for n in gone if not before.names[n - 1] & (named_gone - named_came)]
        came = [n for n in came if not after.names[n - 1] & (named_came - named_gone)]
        if not gone and not came:
            continue
        old_fields = set().union(*(before.fields(n) for n in gone)) if gone else set()
        new_fields = set().union(*(after.fields(n) for n in came)) if came else set()
        rows = set().union(*(before.rows_of(n) for n in gone), *(after.rows_of(n) for n in came))
        rows -= named_came ^ named_gone
        moved = sorted(f"+{x}" for x in new_fields - old_fields) + sorted(f"-{x}" for x in old_fields - new_fields)
        for row in sorted(rows):
            what = f"changed: fields {' '.join(moved)}" if moved else "changed"
            found.append(Symbol(row, "wire row", what, f.new or "", line))
        for name in sorted(new_fields ^ old_fields):
            found.append(Symbol(name, "wire field", "added" if name in new_fields else "removed", f.new or "", line))
    return found


TRES_SECTION = re.compile(r"^\[(?:sub_resource\b.*\bid=\"([^\"]+)\"|(resource))")
TRES_KEY = re.compile(r"^([A-Za-z_][\w/]*)\s*=")


def _tres_keys(text: str) -> tuple[dict[int, tuple[str, str]], set[tuple[str, str]], set[str]]:
    """line -> (section, key), every (section, key), and the sections of a .tres."""
    at, keys, every, sections = "", {}, set(), set()
    for number, row in enumerate(text.replace("\r\n", "\n").split("\n"), 1):
        if row.startswith("["):
            match = TRES_SECTION.match(row)
            at = (match.group(1) or match.group(2)) if match else ""
            if at:
                sections.add(at)
        elif at and (key := TRES_KEY.match(row)):
            keys[number] = (at, key.group(1))
            every.add((at, key.group(1)))
    return keys, every, sections


def _resource_symbols(f: FileDiff, old: str, new: str) -> list[Symbol]:
    """A field renamed in a resource section that stays: a key gone while another key came into that section. A key
    gone alone is not one: Godot leaves out a field set back to its default."""
    old_keys, _, _ = _tres_keys(old)
    new_keys, new_every, new_sections = _tres_keys(new)
    old_every = set(old_keys.values())
    found = []
    for gone_lines, came_lines in f.hunks:
        came = {new_keys[n] for n in came_lines if n in new_keys} - old_every
        for n in gone_lines:
            section, key = old_keys.get(n, ("", ""))
            if section in new_sections and (section, key) not in new_every and any(s == section for s, _ in came):
                found.append(Symbol(key, "resource field", "removed", f.old or "", n))
    return found


PY_FROM_IMPORT = re.compile(r"^[ \t]*from[ \t]+([.\w]+)[ \t]+import[ \t]+(\([^)]*\)|[^\n]*)", re.M)


def _python_use(symbol: Symbol, use: Use, b: Change) -> bool:
    """Whether a use of a module-level Python name can mean that module's name (see Symbol.module)."""
    if use.path in symbol.home:
        return True
    if not use.path.endswith(".py"):
        return False
    return symbol.module in b.py_idents.get(use, ()) or (symbol.module, symbol.name) in b.py_imports.get(use.path, ())


def _uses(change: Change, path: str, text: str, added: list[int], decls: list[Decl]) -> None:
    lexed = lex(text)
    declared = {(d.line, d.name) for d in decls}
    python = path.endswith(".py")
    if python:
        imports = change.py_imports.setdefault(path, set())
        for match in PY_FROM_IMPORT.finditer("\n".join(lexed.code)):
            stem = match.group(1).rsplit(".", 1)[-1]
            imports.update((stem, name) for name in re.findall(r"[A-Za-z_]\w*", match.group(2)) if name != "as")
    for number in added:
        if number > len(lexed.code):
            continue
        code = lexed.code[number - 1]
        use = Use(path, number)
        idents = set(re.findall(r"[A-Za-z_]\w*", code))
        if python:
            change.py_idents[use] = frozenset(idents)
        for name in idents:
            if (number, name) not in declared:
                change.add_use(change.idents, name, use)
        for _, literal in lexed.strings[number - 1]:
            if literal and not any(c.isspace() for c in literal):
                for name in {literal, *re.findall(r"[A-Za-z_]\w*", literal)}:
                    change.add_use(change.literals, name, use)
        change.texts.append((use, code + " " + " ".join(s for _, s in lexed.strings[number - 1])))


@dataclass
class Overlap:
    symbol: Symbol
    owner: str  # the side that removed or changed it
    user: str  # the side whose added lines use it
    uses: list[Use]
    # The .py uses that name the symbol in a string (`mock.patch.object(gdunit, "main", ...)`): a stand-in that
    # asserts the exact arguments or takes the old ones breaks once the owner's callers pass the new parameter.
    named: list[Use] = field(default_factory=list)

    @property
    def note(self) -> bool:
        """A compatible signature change (Symbol.compatible) that no use patches by name: reported, but no overlap."""
        return self.symbol.compatible and not self.named


def overlaps(a: Change, b: Change) -> list[Overlap]:
    """a's symbols that b's added lines use."""
    found = []
    for symbol in a.symbols:
        if symbol.kind == "file":
            uses = [use for use, text in b.texts if symbol.path in text]
        elif symbol.kind.startswith("wire"):
            uses = list(b.literals.get(symbol.name, []))
        else:
            uses = b.idents.get(symbol.name, []) + b.literals.get(symbol.name, [])
        if symbol.own:
            uses = [u for u in uses if u.path == symbol.own]
        if symbol.module:
            uses = [u for u in uses if _python_use(symbol, u, b)]
        uses = sorted(set(uses), key=lambda u: (u.path, u.line))
        if uses:
            strings = set(b.literals.get(symbol.name, [])) if symbol.compatible else set()
            named = [u for u in uses if u in strings and u.path.endswith(".py")]
            found.append(Overlap(symbol, a.label, b.label, uses, named))
    return found


def both_ways(a: Change, b: Change) -> list[Overlap]:
    return overlaps(a, b) + overlaps(b, a)


def describe(overlap: Overlap, limit: int = 3) -> str:
    s = overlap.symbol
    where = f"{s.path}:{s.line}" if s.line else s.path
    shown = ", ".join(f"{u.path}:{u.line}" for u in overlap.uses[:limit])
    more = f" (+{len(overlap.uses) - limit} more)" if len(overlap.uses) > limit else ""
    patched = ""
    if overlap.named:
        patched = f"; patched by name at {', '.join(f'{u.path}:{u.line}' for u in overlap.named[:limit])}"
    return f"{s.describe()} by {overlap.owner} at {where}; used by {overlap.user} at {shown}{more}{patched}"


# --- merge-check ------------------------------------------------------------------------------------------------------


def _names(found: list[Overlap]) -> str:
    names = sorted({f"`{o.symbol.name}`" for o in found})
    return ", ".join(names[:6]) + (" ..." if len(names) > 6 else "")


@dataclass
class Row:
    check: str
    conflicts: list[str]
    overlaps: list[Overlap]
    notes: list[Overlap] = field(default_factory=list)
    shared: list[str] = field(default_factory=list)  # a pair across bases: the shared files both change

    @classmethod
    def of(cls, check: str, conflicts: list[str], found: list[Overlap], shared: list[str] | None = None) -> Row:
        """A row from both_ways' result: compatible signature changes go to notes, the rest are overlaps."""
        overlaps = [o for o in found if not o.note]
        return cls(check, conflicts, overlaps, [o for o in found if o.note], shared or [])

    def cells(self) -> tuple[str, str]:
        text = f"conflict: {', '.join(self.conflicts[:6])}" + (" ..." if len(self.conflicts) > 6 else "")
        sem = f"overlap: {_names(self.overlaps)}" if self.overlaps else "clean"
        if self.notes:
            sem += f"; note: {_names(self.notes)}"
        return (text if self.conflicts else "clean"), sem


class Sides:
    """Each PR measured from its fork with its own base (`origin/<base>`), each computed once: the fork, the paths it
    changes (both names of a rename) and its Change. The per-base check and the check across bases share them."""

    def __init__(self) -> None:
        self.forks: dict[int, str] = {}
        self.paths: dict[int, set[str]] = {}
        self.changes: dict[int, Change] = {}

    def fork(self, pr: PullRequest) -> str:
        if pr.number not in self.forks:
            tip = _sha(f"refs/remotes/{REMOTE}/{pr.base}")
            if not tip:
                raise Failure(f"{REMOTE}/{pr.base} not found after the fetch")
            self.forks[pr.number] = _out("merge-base", tip, pr.oid).strip()
        return self.forks[pr.number]

    def touched(self, pr: PullRequest) -> set[str]:
        if pr.number not in self.paths:
            out = _out("-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", self.fork(pr), pr.oid, "--")
            self.paths[pr.number] = {line for line in out.split("\n") if line}
        return self.paths[pr.number]

    def change(self, pr: PullRequest) -> Change:
        if pr.number not in self.changes:
            self.changes[pr.number] = build_change(pr.label, self.fork(pr), pr.oid)
        return self.changes[pr.number]


def check_group(base: str, prs: list[PullRequest], sides: Sides | None = None) -> list[Row]:
    """Each PR onto the tip of origin/<base>, then each pair, textually and semantically."""
    sides = sides or Sides()
    tip = _sha(f"refs/remotes/{REMOTE}/{base}")
    if not tip:
        raise Failure(f"{REMOTE}/{base} not found after the fetch")
    since: dict[str, Change] = {}
    rows = []
    for pr in prs:
        fork = sides.fork(pr)
        if fork not in since:
            since[fork] = build_change(base, fork, tip)
        behind = ""
        if fork != tip:
            behind = f" ({_out('rev-list', '--count', fork + '..' + tip).strip()} commits since its fork)"
        semantic = both_ways(sides.change(pr), since[fork])
        rows.append(Row.of(f"{pr.label} onto {base}{behind}", textual(tip, pr.oid), semantic))
    for a, b in itertools.combinations(prs, 2):
        semantic = both_ways(sides.change(a), sides.change(b))
        rows.append(Row.of(f"{a.label} + {b.label}", textual(a.oid, b.oid), semantic))
    return rows


# --- across bases (#207) ----------------------------------------------------------------------------------------------

# The files every track may change (AGENT_WORKFLOW §7.1 "Parallel tracks"): a milestone takes `main` in at its next
# wave boundary (`merge --sync-main`), so a PR into `main` and one into `release/m<k>` that change the same shared file
# meet there although merge-check never paired them within one base.
SHARED_DIRS = ("tools/", ".claude/", ".github/")
SHARED_FILES = ("docs/AGENT_WORKFLOW.md",)


def shared(paths: set[str]) -> list[str]:
    return sorted(p for p in paths if p.startswith(SHARED_DIRS) or p in SHARED_FILES)


def long_lived(branch: str) -> bool:
    return branch == "main" or branch.startswith("release/")


def stacked_on(pr: PullRequest, by_head: dict[str, PullRequest]) -> list[str]:
    """The bases a PR is stacked through: its base, then the base of the open PR whose head that is, and so on."""
    seen, chain = {pr.number}, [pr.base]
    while chain[-1] in by_head and by_head[chain[-1]].number not in seen:
        seen.add(by_head[chain[-1]].number)
        chain.append(by_head[chain[-1]].base)
    return chain


def root_base(pr: PullRequest, by_head: dict[str, PullRequest]) -> str:
    """The base a PR finally lands in: through the open PRs it is stacked on (a base that is another open PR's head)
    to the first long-lived branch (`main`, `release/m<k>`). A stage's own PR (`release/m<k>` into `main`, open while
    the human reviews it) is no stack: a fix-up PR into `release/m<k>` still lands in `release/m<k>`."""
    chain = stacked_on(pr, by_head)
    return next((base for base in chain if long_lived(base)), chain[-1])


def cross_pairs(prs: list[PullRequest], everyone: list[PullRequest]) -> list[tuple[PullRequest, PullRequest]]:
    """Each checked PR with every open PR that finally lands in another base, each pair once, by PR number. A PR
    stacked on another one (a task PR on its parent, a fix-up into `release/m<k>` on the stage's PR) is no partner of
    it: the one contains the other's base."""
    by_head = {p.head: p for p in everyone}
    roots = {p.number: root_base(p, by_head) for p in [*everyone, *prs]}
    chains = {p.number: set(stacked_on(p, by_head)) for p in [*everyone, *prs]}
    pairs: dict[tuple[int, int], tuple[PullRequest, PullRequest]] = {}
    for a in prs:
        for b in everyone:
            if a.head in chains[b.number] or b.head in chains[a.number]:
                continue
            if roots[a.number] != roots[b.number]:
                first, second = sorted((a, b), key=lambda p: p.number)
                pairs[(first.number, second.number)] = (first, second)
    return [pairs[key] for key in sorted(pairs)]


def lands_in(pr: PullRequest, by_head: dict[str, PullRequest]) -> str:
    """`release/m1`, or `release/m1 via core/302-task` for a PR stacked on another one."""
    root = root_base(pr, by_head)
    return root if pr.base == root else f"{root} via {pr.base}"


def check_cross(
    pairs: list[tuple[PullRequest, PullRequest]], sides: Sides, by_head: dict[str, PullRequest]
) -> tuple[list[Row], list[str]]:
    """The pairs that change the same shared files, textually (the conflicts in files both change) and with the same
    symbol check as within a base; and the labels of the pairs with no shared file in common."""
    rows, apart = [], []
    for a, b in pairs:
        label = f"{a.label} ({lands_in(a, by_head)}) + {b.label} ({lands_in(b, by_head)})"
        common = sides.touched(a) & sides.touched(b)
        files = shared(common)
        if not files:
            apart.append(label)
            continue
        conflicts = [path for path in textual(a.oid, b.oid) if path in common]
        rows.append(Row.of(label, conflicts, both_ways(sides.change(a), sides.change(b)), files))
    return rows, apart


def _details(rows: list[Row]) -> None:
    for row in rows:
        if row.overlaps or row.notes:
            say()
            say(f"{row.check}:")
            for each in row.overlaps:
                say(f"- {describe(each)}")
            for each in row.notes:
                say(f"- note: {describe(each)}")


def report(base: str, prs: list[PullRequest], rows: list[Row]) -> None:
    tip = _sha(f"refs/remotes/{REMOTE}/{base}")
    say()
    say(f"### {base} ({REMOTE}/{base} at {tip[:10]}): {', '.join(p.label for p in prs)}")
    say()
    say("| check | textual | semantic |")
    say("|---|---|---|")
    for row in rows:
        textual_cell, semantic_cell = row.cells()
        say(f"| {row.check} | {textual_cell} | {semantic_cell} |")
    _details(rows)


def report_cross(bases: list[str], rows: list[Row], apart: list[str]) -> None:
    say()
    say(f"### across bases ({', '.join(bases)}): pairs that change the same files under "
        f"{', '.join(SHARED_DIRS)} or {', '.join(SHARED_FILES)}")  # fmt: skip
    if rows:
        say()
        say("| check | shared files | textual | semantic |")
        say("|---|---|---|---|")
        for row in rows:
            files = ", ".join(row.shared[:4]) + (f" (+{len(row.shared) - 4} more)" if len(row.shared) > 4 else "")
            textual_cell, semantic_cell = row.cells()
            say(f"| {row.check} | {files} | {textual_cell} | {semantic_cell} |")
    if apart:
        say()
        say(f"no shared file in common, not compared: {'; '.join(apart)}")
    _details(rows)


def check(numbers: list[int], base: str | None = None, trial: bool = False) -> int:
    say("merge-check" + (" --trial" if trial else ""))
    if trial:
        return run_trial(numbers, base)
    fetch()
    found = everyone = open_prs()
    if numbers:
        known = {pr.number: pr for pr in found}
        missing = [n for n in numbers if n not in known]
        if missing:
            raise Failure(f"not open PRs: {', '.join(f'#{n}' for n in missing)}")
        found = [known[n] for n in numbers]
        elsewhere = [f"{pr.label} targets {pr.base}" for pr in found if base and pr.base != base]
        if elsewhere:
            raise Failure(f"{', '.join(elsewhere)}, not {base}: leave out --base or name only PRs into {base}")
    if base:
        found = [pr for pr in found if pr.base == base]
    if not found:
        ok("no open PRs to check" + (f" into {base}" if base else ""))
        return 0
    groups: dict[str, list[PullRequest]] = {}
    for pr in found:
        ensure_head(pr)
        groups.setdefault(pr.base, []).append(pr)
    ok(f"{len(found)} open PRs: " + ", ".join(f"{b} ({len(p)})" for b, p in groups.items()))
    sides = Sides()
    conflicts = overlapping = total = 0
    unchecked: list[str] = []
    for name, prs in groups.items():
        if not _sha(f"refs/remotes/{REMOTE}/{name}"):
            unchecked += [p.label for p in prs]
            warn(f"{REMOTE}/{name} is gone (a merged parent?): {', '.join(p.label for p in prs)} not checked; "
                 f"retarget them (gh pr edit <pr> --base <its base>) and run merge-check again")  # fmt: skip
            continue
        rows = check_group(name, prs, sides)
        report(name, prs, rows)
        total += len(rows)
        conflicts += sum(1 for r in rows if r.conflicts)
        overlapping += sum(1 for r in rows if r.overlaps)
    # Across bases: the checked PRs whose base is on origin, with every open PR into another base that is.
    present = {name for name in {pr.base for pr in everyone} if _sha(f"refs/remotes/{REMOTE}/{name}")}
    pairs = cross_pairs([pr for pr in found if pr.base in present], [pr for pr in everyone if pr.base in present])
    crossed = False
    if pairs:
        checked = {pr.number for pr in found}
        for pr in {p.number: p for pair in pairs for p in pair if p.number not in checked}.values():
            ensure_head(pr)
        by_head = {pr.head: pr for pr in everyone}
        rows, apart = check_cross(pairs, sides, by_head)
        report_cross(sorted({root_base(pr, by_head) for pair in pairs for pr in pair}), rows, apart)
        total += len(rows)
        conflicts += sum(1 for r in rows if r.conflicts)
        overlapping += sum(1 for r in rows if r.overlaps)
        crossed = any(r.conflicts or r.overlaps for r in rows)
    say()
    verdict = f"{conflicts} textual conflicts and {overlapping} overlaps in {total} checks"
    if unchecked:
        verdict += f"; not checked: {', '.join(unchecked)}"
    if conflicts or overlapping or unchecked:
        say(f"merge-check: {verdict}. Order the merges so the side that removes or changes a symbol goes first and "
            "the other is rebased on it, or run merge-check --trial <pr>... to see whether verify stays green.")
        if crossed:
            say("Across bases: name the pair on both tracks' plan issues; the PR into main merges first, the milestone "
                "takes main in (merge --sync-main) and its PR is rebased on that before it merges.")  # fmt: skip
        return 1
    say(f"merge-check: clean ({verdict})")
    return 0


# --- scratch worktrees, verify, trial ---------------------------------------------------------------------------------


def _remove(path: Path) -> None:
    res = _git("worktree", "remove", "--force", str(path), timeout=REMOVE_TIMEOUT)
    if res.rc != 0 or res.timed_out:
        shutil.rmtree(path, ignore_errors=True)
        _git("worktree", "prune")
    if path.exists():
        warn(f"could not remove the scratch worktree {path} (a program still has it open): delete it, then "
             "git worktree prune")  # fmt: skip
    else:
        ok(f"removed the scratch worktree {path.name}")


@contextmanager
def scratch_worktree(commit: str, label: str) -> Iterator[Path]:
    """A detached worktree at commit under tools/out/merge/ (gitignored; tools/out/.gdignore keeps the editor of this
    checkout from importing it), removed afterwards whatever happened in it."""
    if SCRATCH.parent == OUT:
        ensure_out()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    path = Path(tempfile.mkdtemp(prefix=f"{label}-", dir=SCRATCH))
    res = _git("worktree", "add", "--detach", str(path), commit, timeout=REMOVE_TIMEOUT)
    if res.rc != 0 or res.timed_out:
        shutil.rmtree(path, ignore_errors=True)
        raise Failure(f"git worktree add failed: {res.out.strip()[-600:]}")
    ok(f"scratch worktree {path.relative_to(SCRATCH.parent).as_posix()} at {commit[:10]}")
    try:
        yield path
    finally:
        _remove(path)


def verify_in(path: Path, log: str) -> Result:
    """The merged tree's own `verify` (its runner, its tests), as CI would run it on the merge."""
    say(f"verify on the merged tree (log: tools/out/logs/{log}.log)")
    return run(
        [sys.executable, str(path / "tools" / "run.py"), "verify"], cwd=path, timeout=VERIFY_TIMEOUT, log=log, echo=True
    )


def keep_reports(path: Path, log: str) -> str:
    """Copies the merged tree's logs and GdUnit reports out of the scratch worktree before it is removed, so a red
    verify can be read afterwards; the kept folder, relative to the checkout."""
    kept = SCRATCH.parent / "merge-logs" / log
    shutil.rmtree(kept, ignore_errors=True)
    for name in ("logs", "gdunit"):
        source = path / "tools" / "out" / name
        if source.is_dir():
            shutil.copytree(source, kept / name, dirs_exist_ok=True, ignore_dangling_symlinks=True)
    where = (kept.relative_to(ROOT) if kept.is_relative_to(ROOT) else kept).as_posix()
    say(f"kept the merged tree's logs and reports in {where}")
    return where


def _merge_into(path: Path, commit: str, message: str, what: str) -> str:
    """merge --no-ff in the scratch worktree; the merge commit's hash, or a Failure naming the conflicts."""
    res = _git("merge", "--no-ff", "-m", message, commit, cwd=path)
    if res.rc != 0 or res.timed_out:
        conflicts = _git("diff", "--name-only", "--diff-filter=U", cwd=path).out.split()
        raise Failure(
            f"{what} does not merge cleanly: "
            + (", ".join(conflicts) if conflicts else res.out.strip()[-400:])
            + ". Nothing was pushed."
        )
    sha = _out("rev-parse", "HEAD", cwd=path).strip()
    ok(f"merged {what} -> {sha[:10]}")
    return sha


def run_trial(numbers: list[int], base: str | None) -> int:
    if not numbers:
        raise Failure("--trial needs the PRs to merge, in order: merge-check --trial 153 154")
    prs = [pr_view(n) for n in numbers]
    closed = [pr.label for pr in prs if pr.state != "OPEN"]
    if closed:
        raise Failure(f"not open: {', '.join(closed)}")
    base = base or prs[0].base
    fetch()
    for pr in prs:
        ensure_head(pr)
        if pr.base != base:
            warn(f"{pr.label} targets {pr.base}, not {base}; merged onto {base} anyway")
    tip = _sha(f"refs/remotes/{REMOTE}/{base}")
    if not tip:
        raise Failure(f"{REMOTE}/{base} not found after the fetch")
    order = " + ".join(pr.label for pr in prs)
    started = time.monotonic()
    try:
        with scratch_worktree(tip, "trial") as path:
            for pr in prs:
                _merge_into(path, pr.oid, merge_message(pr), pr.label)
            result = verify_in(path, "merge-trial")
            if result.rc != 0 or result.timed_out:
                keep_reports(path, "merge-trial")
    except Failure as exc:
        bad(str(exc))
        say(f"trial: {base} + {order}: does not merge")
        return 1
    seconds = time.monotonic() - started
    passed = result.rc == 0 and not result.timed_out
    say(f"trial: {base} + {order}: verify {'passed' if passed else 'FAILED'} in {seconds:.0f} s")
    return 0 if passed else 1


# --- merge into a release branch --------------------------------------------------------------------------------------


def _cwd() -> Path:
    return Path.cwd()


def refuse_task_checkout() -> None:
    """merge runs from the main checkout or the release worktree, never from a task's checkout."""
    for where in dict.fromkeys([Path(REPO), _cwd()]):
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=where, capture_output=True, timeout=60, stdin=subprocess.DEVNULL
        )
        if res.returncode != 0:
            continue
        top = res.stdout.decode().strip()
        branch = subprocess.run(
            ["git", "symbolic-ref", "--quiet", "--short", "HEAD"], cwd=top, capture_output=True, timeout=60,
            stdin=subprocess.DEVNULL,
        ).stdout.decode().strip()  # fmt: skip
        if TASK_WORKTREE_RE.search(top) or TASK_BRANCH_RE.match(branch):
            raise Failure(
                f"{top} is a task's checkout ({branch or 'its worktree'}): run merge from the main checkout or your "
                "release worktree. Nothing was changed."
            )


def refuse_base(base: str) -> None:
    if base == "main" or not base.startswith("release/") or base == "release/":
        raise Failure(
            f"merge goes only into a release branch (release/<x>), not {base}: only humans merge into main "
            "(docs/decisions/2026-09-28-humans-merge-prs.md). Nothing was changed."
        )


def _push(sha: str, base: str) -> None:
    res = _git("push", REMOTE, f"{sha}:refs/heads/{base}")
    for line in res.lines:
        if line.strip():
            say(f"        {line.rstrip()}")
    if res.rc != 0 or res.timed_out:
        raise Failure(
            f"the push of {sha[:10]} to {base} was rejected, usually because {REMOTE}/{base} moved since the fetch "
            "(another merge): nothing changed there; run merge again."
        )
    ok(f"pushed {sha[:10]} to {REMOTE}/{base}")


def _confirm(number: int) -> bool:
    """Whether GitHub shows the PR merged after the push. A failed `gh pr view` (a network blip, a rate limit) counts
    as "not yet": the push already happened, so merge must not exit 1, which means nothing was pushed."""
    for attempt in range(CONFIRM_TRIES):
        try:
            if pr_view(number).state == "MERGED":
                return True
        except Failure:
            pass
        if attempt + 1 < CONFIRM_TRIES:
            time.sleep(CONFIRM_WAIT)
    return False


def merge(number: int | None, base: str, sync_main: bool = False) -> int:
    say(f"merge {'--sync-main' if sync_main else f'#{number}'} --base {base}")
    if (number is None) == (not sync_main):
        raise Failure("name one PR (merge 154 --base release/m5) or --sync-main, not both or neither")
    refuse_base(base)
    refuse_task_checkout()
    if sync_main:
        return _sync_main(base)
    assert number is not None
    pr = pr_view(number)
    if pr.state == "MERGED":
        fetch()
        say(f"wave: #{number} ({pr.head}) was already merged into {pr.base}; fetched only")
        return 0
    if pr.state != "OPEN":
        raise Failure(f"#{number} is {pr.state.lower()}, not open. Nothing was changed.")
    if pr.base != base:
        raise Failure(f"#{number} targets {pr.base}, not {base}. Nothing was changed.")
    if pr.draft:
        raise Failure(f"#{number} is a draft. Nothing was changed.")
    problems = ci_problems(number)
    if problems:
        raise Failure(f"#{number}'s CI is not green: {'; '.join(problems)}. Nothing was changed.")
    ok(f"#{number}: open into {base}, CI green")
    fetch()
    if _sha(f"refs/remotes/{REMOTE}/{pr.head}") != pr.oid:
        raise Failure(f"{REMOTE}/{pr.head} is not at the PR's head {pr.oid[:10]} (it moved): run merge again")
    tip = _sha(f"refs/remotes/{REMOTE}/{base}")
    if not tip:
        raise Failure(f"{REMOTE}/{base} not found after the fetch")
    if _is_ancestor(pr.oid, tip):
        raise Failure(f"{REMOTE}/{base} already has #{number}'s head {pr.oid[:10]}; check gh pr view {number}")
    sha, seconds = _merge_verify_push(tip, pr.oid, merge_message(pr), pr.label, base, f"merge-{number}")
    confirmed = _confirm(number)
    if not confirmed:
        warn(f"GitHub does not show #{number} merged yet: check gh pr view {number} --json state")
    say(
        f"wave: merged #{number} ({pr.head}) into {base} as {sha[:12]}; verify on the merged tree passed in "
        f"{seconds:.0f} s" + ("" if confirmed else "; GitHub did not show it merged yet")
    )
    return 0


def _sync_main(base: str) -> int:
    fetch()
    tip, main = _sha(f"refs/remotes/{REMOTE}/{base}"), _sha(f"refs/remotes/{REMOTE}/main")
    if not tip or not main:
        raise Failure(f"{REMOTE}/{base} or {REMOTE}/main not found after the fetch")
    if _is_ancestor(main, tip):
        say(f"wave: {base} already has main at {main[:12]}; nothing to merge")
        return 0
    message = f"Merge branch 'main' into {base}"
    sha, seconds = _merge_verify_push(tip, main, message, f"main ({main[:10]})", base, "merge-sync-main")
    say(f"wave: merged main ({main[:12]}) into {base} as {sha[:12]}; verify on the merged tree passed in {seconds:.0f} s")
    return 0


def _merge_verify_push(tip: str, commit: str, message: str, what: str, base: str, log: str) -> tuple[str, float]:
    started = time.monotonic()
    with scratch_worktree(tip, log) as path:
        sha = _merge_into(path, commit, message, what)
        result = verify_in(path, log)
        if result.rc != 0 or result.timed_out:
            kept = keep_reports(path, log)
            raise Failure(
                f"verify is red on the merged tree of {what}: nothing was pushed (log tools/out/logs/{log}.log; "
                f"the merged tree's logs and reports: {kept})"
            )
        _push(sha, base)
    return sha, time.monotonic() - started
