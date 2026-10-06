"""`section`: a doc's outline, or exactly the sections asked for (#338).

The instruction-diet ADR's N1 (a) (docs/decisions/2026-10-04-instruction-diet.md): agents read ARCHITECTURE and
AGENT_WORKFLOW by section. A section runs from its heading up to the next heading of the same or a higher level, so
`section docs/ARCHITECTURE.md 4.5` returns all of §4.5 (its subsections included) and nothing of §4.6. Headings in
fenced code blocks are text, not headings. A heading's § is its leading number (`### 4.5 The host session`,
`## 6. Skills`); an ADR's headings have none and are picked by title.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .common import ROOT, Failure, say

# The outline's token estimate: characters / 2.35, the ratio the instruction-diet ADR measured on ARCHITECTURE
# (386k characters, about 164k tokens): Markdown, code spans and non-ASCII text cost more than the usual 4.
CHARS_PER_TOKEN = 2.35

HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
NUMBER_RE = re.compile(r"^(\d+(?:\.\d+)*)\.?\s+(.*)$")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
SECTION_KEY_RE = re.compile(r"^\d+(?:\.\d+)*$")


@dataclass
class Heading:
    level: int
    title: str  # without the § number
    number: str | None
    start: int  # 1-based line of the heading
    end: int = 0  # last line of the section, inclusive

    @property
    def label(self) -> str:
        return f"§{self.number}" if self.number else ""


def headings(text: str) -> list[Heading]:
    """Every Markdown heading outside fenced code, with the line range of its section."""
    lines = text.splitlines()
    found: list[Heading] = []
    fence = ""
    for index, line in enumerate(lines, 1):
        match = FENCE_RE.match(line)
        if match:
            if not fence:
                fence = match.group(1)
            elif match.group(1) == fence:
                fence = ""
            continue
        if fence:
            continue
        match = HEADING_RE.match(line)
        if not match:
            continue
        title = match.group(2)
        number = NUMBER_RE.match(title)
        found.append(
            Heading(
                len(match.group(1)),
                number.group(2) if number else title,
                number.group(1) if number else None,
                index,
            )
        )
    for position, heading in enumerate(found):
        later = (h.start for h in found[position + 1 :] if h.level <= heading.level)
        heading.end = next(later, len(lines) + 1) - 1
    return found


def tokens(lines: list[str]) -> str:
    """The estimate as the outline shows it: `~840`, `~16.8k`."""
    count = round(sum(len(line) + 1 for line in lines) / CHARS_PER_TOKEN)
    return f"~{count / 1000:.1f}k" if count >= 1000 else f"~{count}"


def doc_path(name: str, root: Path | None = None) -> Path:
    """A doc from a path (repo-relative or absolute), a name (ARCHITECTURE, AGENT_WORKFLOW, GDD) or part of an ADR's
    file name (`instruction-diet`)."""
    base = root or ROOT
    for candidate in (Path(name), base / name):
        if candidate.is_file():
            return candidate
    stem = name.removesuffix(".md")
    for candidate in (base / "docs" / f"{stem.upper()}.md", base / "docs" / f"{stem}.md"):
        if candidate.is_file():
            return candidate
    adrs = sorted(p for p in (base / "docs" / "decisions").glob("*.md") if stem.lower() in p.name.lower())
    if len(adrs) == 1:
        return adrs[0]
    if adrs:
        names = ", ".join(p.name for p in adrs[:8])
        raise Failure(f"{name}: matches {len(adrs)} ADRs ({names}{', ...' if len(adrs) > 8 else ''}); name one")
    raise Failure(f"{name}: no such doc (a path, ARCHITECTURE, AGENT_WORKFLOW, or part of an ADR's file name)")


def _shown(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def outline(path: Path, root: Path | None = None) -> list[str]:
    """One line per heading: indent by level, §, title, line range, tokens."""
    lines = path.read_text(encoding="utf-8").splitlines()
    estimate = f"{tokens(lines)} tokens (characters / {CHARS_PER_TOKEN})"
    rows = [f"{_shown(path, root or ROOT)}: {len(lines)} lines, {estimate}"]
    for heading in headings("\n".join(lines)):
        indent = "  " * (heading.level - 1)
        name = f"{heading.label} {heading.title}" if heading.number else heading.title
        size = tokens(lines[heading.start - 1 : heading.end])
        rows.append(f"{indent}{name}  [lines {heading.start}-{heading.end}, {size} tokens]")
    return rows


def find(found: list[Heading], key: str) -> Heading:
    """A heading by § (`4.5`, `§4.5`, `4.5.`) or, for any other key, by title: exact, then a unique prefix or part
    (case-insensitive)."""
    wanted = key.strip().removeprefix("§").strip().rstrip(".")
    if SECTION_KEY_RE.match(wanted):
        for heading in found:
            if heading.number == wanted:
                return heading
        raise Failure(f"§{wanted}: no such section (run `section <doc>` for the outline)")
    folded = key.strip().casefold()
    for test in (str.__eq__, str.startswith, str.__contains__):
        hits = [h for h in found if test(h.title.casefold(), folded)]
        if len(hits) == 1:
            return hits[0]
        if len(hits) > 1:
            names = "; ".join(f"line {h.start}: {h.title}" for h in hits[:6])
            raise Failure(f"{key}: {len(hits)} headings match ({names}); give a § or more of the title")
    raise Failure(f"{key}: no such section (run `section <doc>` for the outline)")


def extract(path: Path, keys: list[str], root: Path | None = None) -> list[str]:
    """Each section asked for, whole: a `--- <path>:<start>-<end> <§ title>` line, then its lines unchanged."""
    lines = path.read_text(encoding="utf-8").splitlines()
    found = headings("\n".join(lines))
    shown = _shown(path, root or ROOT)
    out: list[str] = []
    for key in keys:
        heading = find(found, key)
        name = f"{heading.label} {heading.title}" if heading.number else heading.title
        out.append(f"--- {shown}:{heading.start}-{heading.end} {name}")
        out += lines[heading.start - 1 : heading.end]
    return out


def main(doc: str, keys: list[str]) -> int:
    path = doc_path(doc)
    for line in extract(path, keys) if keys else outline(path):
        say(line)
    return 0
