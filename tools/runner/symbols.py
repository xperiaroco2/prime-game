"""`section` for code (#468): a .py, .gd or .js file's top-level symbols with line ranges, or one symbol whole.

#468 extends the docs-by-section rule (#339) to code: an agent reads a big code file by its outline first, then only
the symbol it needs. A symbol is a top-level class, function, named constant or variable; a Python class's methods
and a GDScript inner class's funcs are listed one level down (JS stays top level: the workflow scripts have no
classes). Any other top-level statement longer than BLOCK_MIN_LINES - 1 lines shows as an unnamed `block`, so the
outline also shows the big `if (...) {` blocks of the workflow scripts. A symbol's range takes in its decorators or
annotations and the comment lines directly above it, and ends at its last code line.

Python is parsed with `ast`. GDScript and JS go through a line scanner that knows strings, template literals, comments
and bracket depth: a top-level unit ends before the next line that starts at column 0 in code at depth 0. The outline
is best effort and never raises; only a Python file that does not parse fails, with a `grep -n` hint.
"""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass
from pathlib import Path

from .common import ROOT, Failure
from .section import CHARS_PER_TOKEN, _shown, tokens

CODE_SUFFIXES = (".py", ".gd", ".js")
BLOCK_MIN_LINES = 6  # an unnamed top-level statement of this many lines or more shows as a `block`
BLOCK_NAME_CHARS = 60


@dataclass
class Symbol:
    level: int  # 1: top level; 2: a method of a class
    kind: str
    name: str
    start: int  # 1-based, its leading comments and decorators included
    end: int  # inclusive
    parent: str | None = None

    @property
    def qualified(self) -> str:
        return f"{self.parent}.{self.name}" if self.parent else self.name


def is_code(path: Path) -> bool:
    return path.suffix.lower() in CODE_SUFFIXES


def symbols(text: str, suffix: str) -> list[Symbol]:
    """Every symbol of a file in file order, a class's methods right after it."""
    lines = text.splitlines()
    suffix = suffix.lower()
    if suffix == ".py":
        return _python(text, lines)
    if suffix == ".gd":
        return _scanned(lines, "gd")
    if suffix == ".js":
        return _scanned(lines, "js")
    raise Failure(f"{suffix}: not a code file ({', '.join(CODE_SUFFIXES)})")


def _block_name(line: str) -> str:
    text = line.strip()
    return text if len(text) <= BLOCK_NAME_CHARS else text[: BLOCK_NAME_CHARS - 3] + "..."


def _lead(lines: list[str], start: int, lang: str) -> int:
    """`start` moved up over the lines directly above it (no blank between) at the same indentation that are comments
    or, in GDScript, annotations alone on their line; a JS `/** */` comment's ` * ` lines at any indentation."""
    indent = _indent(lines[start - 1])
    while start > 1:
        above = lines[start - 2]
        text = above.strip()
        if lang == "js" and text.startswith("*"):
            start -= 1
            continue
        if not text or _indent(above) != indent:
            break
        if not (
            text.startswith("#")
            or (lang == "gd" and GD_BARE_ANNOTATION_RE.match(text))
            or (lang == "js" and text.startswith(("//", "/*")))
        ):
            break
        start -= 1
    return start


# --- Python ---------------------------------------------------------------------------------------------------


def _python(text: str, lines: list[str]) -> list[Symbol]:
    try:
        tree = ast.parse(text)
    except SyntaxError as error:
        raise Failure(f"does not parse (line {error.lineno}): {error.msg}; use grep -n") from None
    found: list[Symbol] = []
    for node in tree.body:
        start = min([node.lineno] + [d.lineno for d in getattr(node, "decorator_list", [])])
        end = node.end_lineno or node.lineno
        named = _python_name(node)
        if named is None:
            if isinstance(node, (ast.Import, ast.ImportFrom)) or end - node.lineno + 1 < BLOCK_MIN_LINES:
                continue
            found.append(Symbol(1, "block", _block_name(lines[node.lineno - 1]), start, end))
            continue
        kind, name = named
        found.append(Symbol(1, kind, name, _lead(lines, start, "py"), end))
        if isinstance(node, ast.ClassDef):
            for child in node.body:
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    first = min([child.lineno] + [d.lineno for d in child.decorator_list])
                    kind = "async def" if isinstance(child, ast.AsyncFunctionDef) else "def"
                    lead = _lead(lines, first, "py")
                    found.append(Symbol(2, kind, child.name, lead, child.end_lineno or child.lineno, name))
    return found


def _python_name(node: ast.stmt) -> tuple[str, str] | None:
    if isinstance(node, ast.ClassDef):
        return "class", node.name
    if isinstance(node, ast.AsyncFunctionDef):
        return "async def", node.name
    if isinstance(node, ast.FunctionDef):
        return "def", node.name
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
        return "assign", node.targets[0].id
    if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        return "assign", node.target.id
    return None


# --- GDScript and JS: a line scanner --------------------------------------------------------------------------

GD_ANNOTATION_RE = re.compile(r"^(?:@\w+(?:\([^()]*\))?\s+)*")
GD_SYMBOL_RE = re.compile(
    r"^(?P<kind>static\s+func|func|class|signal|const|var|static\s+var|enum)\s+(?P<name>[A-Za-z_]\w*)"
)
GD_BARE_ANNOTATION_RE = re.compile(r"^@\w+(?:\(.*\))?\s*$")
JS_SYMBOL_RE = re.compile(
    r"^(?:export\s+(?:default\s+)?)?(?P<kind>(?:async\s+)?function\s*\*?|class|const|let|var)\s+"
    r"(?P<name>[A-Za-z_$][\w$]*)"
)
JS_REGEX_AFTER = set("(,=:[!&|?{};+-*%<>~^")
JS_REGEX_WORDS = {
    "return", "typeof", "case", "in", "of", "new", "delete", "void", "throw", "else", "do", "yield", "await"
}
OPEN, CLOSE = "([{", ")]}"


Scan = list[tuple[str, int]]


def _code_starts(lines: list[str], lang: str) -> Scan:
    """For each line: the mode it starts in (`code`, or inside a `block` comment, a `triple`-quoted string or a JS
    `template` literal) and the bracket depth there."""
    out: Scan = []
    depth = 0
    mode = "code"  # code, block (a /* */ comment), triple (a GDScript triple-quoted string), template (a JS `...`)
    triple = ""
    stack: list[int] = []  # JS: for each open `${`, the depth to return to the template at
    for line in lines:
        out.append((mode, depth))
        i, n = 0, len(line)
        last = ""  # the last significant code character, for a JS regex
        word = ""
        while i < n:
            ch = line[i]
            if mode == "block":
                end = line.find("*/", i)
                if end < 0:
                    break
                mode, i = "code", end + 2
                continue
            if mode == "triple":
                end = line.find(triple, i)
                if end < 0:
                    break
                mode, i = "code", end + 3
                continue
            if mode == "template":
                if ch == "\\":
                    i += 2
                elif ch == "`":
                    mode, i, last = "code", i + 1, "`"
                elif line.startswith("${", i):
                    stack.append(depth)
                    depth += 1
                    mode, i, last = "code", i + 2, "{"
                else:
                    i += 1
                continue
            # code
            if ch.isspace():
                i += 1
                continue
            if lang == "gd" and ch == "#":
                break
            if lang == "js" and line.startswith("//", i):
                break
            if lang == "js" and line.startswith("/*", i):
                mode, i = "block", i + 2
                continue
            if lang == "gd" and (line.startswith('"""', i) or line.startswith("'''", i)):
                triple, mode, i = line[i : i + 3], "triple", i + 3
                continue
            if ch in "'\"":
                i = _skip_quoted(line, i, ch)
                last, word = ch, ""
                continue
            if lang == "js" and ch == "`":
                mode, i = "template", i + 1
                continue
            if lang == "js" and ch == "/" and (last == "" or last in JS_REGEX_AFTER or word in JS_REGEX_WORDS):
                i = _skip_regex(line, i)
                last, word = "/", ""
                continue
            if ch in OPEN:
                depth += 1
            elif ch in CLOSE:
                if lang == "js" and ch == "}" and stack and depth - 1 == stack[-1]:
                    stack.pop()
                    depth -= 1
                    mode, i = "template", i + 1
                    continue
                depth = max(0, depth - 1)
            if ch.isalnum() or ch in "_$":
                word = word + ch if last and (last.isalnum() or last in "_$") else ch
            else:
                word = ""
            last = ch
            i += 1
    return out


def _skip_quoted(line: str, i: int, quote: str) -> int:
    """The index after a one-line string that opens at i (to the line's end if it does not close)."""
    i += 1
    while i < len(line):
        if line[i] == "\\":
            i += 2
            continue
        if line[i] == quote:
            return i + 1
        i += 1
    return len(line)


def _skip_regex(line: str, i: int) -> int:
    i += 1
    in_class = False
    while i < len(line):
        ch = line[i]
        if ch == "\\":
            i += 2
            continue
        if ch == "[":
            in_class = True
        elif ch == "]":
            in_class = False
        elif ch == "/" and not in_class:
            return i + 1
        i += 1
    return len(line)


def _trivial(line: str, lang: str, mode: str) -> bool:
    """Blank, a comment line, a line that starts inside a comment, or a GDScript annotation alone on its line (it
    belongs to the symbol below it)."""
    text = line.strip()
    if not text or mode == "block":
        return True
    if mode != "code":
        return False
    if lang == "gd":
        return text.startswith("#") or bool(GD_BARE_ANNOTATION_RE.match(text))
    return text.startswith(("//", "/*"))


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _units(lines: list[str], scan: Scan, lang: str, lo: int, hi: int, indent: int) -> list[int]:
    """The 1-based start lines of the units in lines lo..hi at this indentation: a line that starts in code at depth
    0 (relative to lo), not blank, not a comment, not a bare annotation."""
    base = scan[lo - 1][1]
    starts = []
    for number in range(lo, hi + 1):
        line = lines[number - 1]
        mode, depth = scan[number - 1]
        if mode == "code" and depth == base and not _trivial(line, lang, mode) and _indent(line) == indent:
            starts.append(number)
    return starts


def _end(lines: list[str], scan: Scan, lang: str, start: int, stop: int) -> int:
    """The last line before `stop` that is code, not blank or a comment."""
    end = stop - 1
    while end > start and _trivial(lines[end - 1], lang, scan[end - 1][0]):
        end -= 1
    return end


def _scanned(lines: list[str], lang: str) -> list[Symbol]:
    scan = _code_starts(lines, lang)
    found: list[Symbol] = []
    starts = _units(lines, scan, lang, 1, len(lines), 0) if lines else []
    for position, start in enumerate(starts):
        stop = starts[position + 1] if position + 1 < len(starts) else len(lines) + 1
        end = _end(lines, scan, lang, start, stop)
        named = _scanned_name(lines[start - 1], lang)
        if named is None:
            if end - start + 1 >= BLOCK_MIN_LINES:
                found.append(Symbol(1, "block", _block_name(lines[start - 1]), start, end))
            continue
        kind, name = named
        found.append(Symbol(1, kind, name, _lead(lines, start, lang), end))
        if lang == "gd" and kind == "class" and end > start:
            found += _gd_members(lines, scan, start, end, name)
    return found


def _scanned_name(line: str, lang: str) -> tuple[str, str] | None:
    if lang == "gd":
        rest = line[GD_ANNOTATION_RE.match(line).end() :]
        match = GD_SYMBOL_RE.match(rest)
    else:
        match = JS_SYMBOL_RE.match(line)
    if not match:
        return None
    return " ".join(match.group("kind").replace("*", "").split()), match.group("name")


def _gd_members(lines: list[str], scan: Scan, start: int, end: int, parent: str) -> list[Symbol]:
    body = [
        n for n in range(start + 1, end + 1) if scan[n - 1][0] == "code" and not _trivial(lines[n - 1], "gd", "code")
    ]
    if not body:
        return []
    indent = _indent(lines[body[0] - 1])
    starts = _units(lines, scan, "gd", start + 1, end, indent)
    members = []
    for position, first in enumerate(starts):
        stop = starts[position + 1] if position + 1 < len(starts) else end + 1
        named = _scanned_name(lines[first - 1].strip(), "gd")
        if named and named[0] in ("func", "static func"):
            last = _end(lines, scan, "gd", first, stop)
            members.append(Symbol(2, named[0], named[1], _lead(lines, first, "gd"), last, parent))
    return members


# --- the command ------------------------------------------------------------------------------------------------


def _read(path: Path) -> tuple[list[str], list[Symbol]]:
    text = path.read_text(encoding="utf-8")
    try:
        return text.splitlines(), symbols(text, path.suffix)
    except Failure as error:
        raise Failure(f"{path.as_posix()}: {error}") from None


def outline(path: Path, root: Path | None = None) -> list[str]:
    """A header (lines, tokens), then one row per symbol: indent by level, kind, name, line range, tokens."""
    lines, found = _read(path)
    estimate = f"{tokens(lines)} tokens (characters / {CHARS_PER_TOKEN})"
    rows = [f"{_shown(path, root or ROOT)}: {len(lines)} lines, {estimate}"]
    for symbol in found:
        indent = "  " * (symbol.level - 1)
        size = tokens(lines[symbol.start - 1 : symbol.end])
        rows.append(f"{indent}{symbol.kind} {symbol.name}  [lines {symbol.start}-{symbol.end}, {size} tokens]")
    return rows


def find(found: list[Symbol], key: str) -> Symbol:
    """A symbol by `Class.method`, then its exact name, a case-insensitive name, a unique prefix. A block has no name
    to find."""
    named = [s for s in found if s.kind != "block"]
    wanted = key.strip()
    folded = wanted.casefold()
    tests = (
        lambda s: s.qualified == wanted,
        lambda s: s.name == wanted,
        lambda s: folded in (s.name.casefold(), s.qualified.casefold()),
        lambda s: s.name.casefold().startswith(folded) or s.qualified.casefold().startswith(folded),
    )
    for test in tests:
        hits = [s for s in named if test(s)]
        if len(hits) == 1:
            return hits[0]
        if len(hits) > 1:
            names = "; ".join(f"line {s.start}: {s.kind} {s.qualified}" for s in hits[:8])
            raise Failure(f"{key}: {len(hits)} symbols match ({names}); give Class.method or the whole name")
    raise Failure(f"{key}: no such symbol (run `section <file>` for the outline)")


def extract(path: Path, keys: list[str], root: Path | None = None) -> list[str]:
    """Each symbol asked for, whole: a `--- <path>:<start>-<end> <kind> <qualified>` line, then its lines unchanged."""
    lines, found = _read(path)
    shown = _shown(path, root or ROOT)
    out: list[str] = []
    for key in keys:
        symbol = find(found, key)
        out.append(f"--- {shown}:{symbol.start}-{symbol.end} {symbol.kind} {symbol.qualified}")
        out += lines[symbol.start - 1 : symbol.end]
    return out
