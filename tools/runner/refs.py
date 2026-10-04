"""lint's check of § references (#338; the instruction-diet ADR's issue B).

It fails a duplicate § in a doc, and a § reference to ARCHITECTURE or AGENT_WORKFLOW in a tracked file (docs/history/
and addons/ excepted) that resolves to no heading. Which doc a § belongs to follows the ADR's scope rules, in the
order `references` gives. Where they were ambiguous, the choice keeps the docs' own references quiet: a doc named in
an earlier sentence of the same line does not take a § (in ARCHITECTURE, "(`docs/AGENT_WORKFLOW.md` §12), ... (§9.3)"
is its own §9.3), and a list item or a table row is a paragraph of its own. A § with no doc in scope, or with another
doc (an ADR's own sections, a skill's, the KICKOFF's), is counted, not failed: `section --refs` lists the first kind.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from .common import ROOT, Failure, say
from .section import headings

# The docs whose § references lint resolves; any other doc's § is only counted.
CHECKED = {"ARCHITECTURE": "docs/ARCHITECTURE.md", "AGENT_WORKFLOW": "docs/AGENT_WORKFLOW.md"}
# Tracked paths whose references are not checked: the archive (it describes the past), third-party addons.
SKIP_PREFIXES = ("docs/history/", "addons/")
# This check's own examples: its docstring and its tests name sections on purpose that do not exist.
SKIP_FILES = ("tools/runner/refs.py", "tools/runner/tests/test_refs.py")
REF_RE = re.compile(r"§\s?(\d+(?:\.\d+)*)")
# A doc named in text. The two checked docs by name (`docs/ARCHITECTURE.md`, `ARCHITECTURE.md`, `ARCHITECTURE`);
# any other Markdown file, the KICKOFF, GDD and ROADMAP, and an ADR ("the M5 ADR's §3") name another doc.
DOC_RE = re.compile(
    r"(?<![\w/.-])(?:[\w./-]*/)?(ARCHITECTURE|AGENT_WORKFLOW)(?:\.md)?(?![\w-])"
    r"|(?<![\w/-])([\w./-]*[\w-]\.md)\b"
    r"|\b(KICKOFF|GDD|ROADMAP|ADRs?)\b"
)
# Markdown files without numbered sections: naming one takes no § ("the rest is in `server/CLAUDE.md` (§4.5)" in
# ARCHITECTURE is its own §4.5), so the § falls through to the next scope rule.
NO_SECTIONS = ("CLAUDE.md", "README.md", "CREDITS.md")
DOC_LINK_RE = re.compile(r"\bdocs/[\w./-]+\.md\b")
COMMENT_RE = re.compile(r"^\s*(#|//|/\*|\*|<!--|--)")


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    resolved: int = 0
    unscoped: list[str] = field(default_factory=list)  # `path:line: §n`: no doc in scope
    other: int = 0  # § of a doc other than the checked two (ADRs, skills, KICKOFF, the GDD): not checked

    @property
    def notes(self) -> list[str]:
        return [
            f"§ references: {self.resolved} to ARCHITECTURE and AGENT_WORKFLOW resolve; {self.other} name another "
            f"doc and {len(self.unscoped)} have no doc in scope (not checked; `section --refs` lists those)"
        ]


def doc_key(match: re.Match[str]) -> str:
    """The doc a DOC_RE match names: ARCHITECTURE, AGENT_WORKFLOW, or `other`."""
    return match.group(1) or "other"


def own_doc(path: str, text: str) -> str | None:
    """A Markdown file with numbered headings (the two docs, a skill) owns its unnamed §, and so does an ADR (its §
    are its own sections or the KICKOFF's): ARCHITECTURE, AGENT_WORKFLOW or `other`."""
    for key, doc in CHECKED.items():
        if path == doc:
            return key
    if path.startswith("docs/decisions/") and path.endswith(".md"):
        return "other"
    if path.endswith(".md") and any(h.number for h in headings(text)):
        return "other"
    return None


def declared_doc(path: str, texts: dict[str, str]) -> str | None:
    """The design doc of a file without sections of its own: an area `CLAUDE.md`'s first link to a doc under docs/;
    any other file has its nearest `CLAUDE.md`'s, in its folder or above (the root's excepted: it routes, it is no
    area's design doc)."""
    folder = path.rpartition("/")[0]
    candidate = path if path.endswith("/CLAUDE.md") else ""
    while not candidate:
        if not folder:
            return None
        if f"{folder}/CLAUDE.md" in texts:
            candidate = f"{folder}/CLAUDE.md"
        folder = folder.rpartition("/")[0]
    link = DOC_LINK_RE.search(texts.get(candidate, ""))
    if not link:
        return None
    named = DOC_RE.search(link.group(0))
    return doc_key(named) if named else "other"


LIST_ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s|^\s*\||^#{1,6}\s")
# "§4.5 of ARCHITECTURE", "§11 in `docs/AGENT_WORKFLOW.md`", "§3 of the M5 ADR": the doc named right after the §.
OF_DOC_RE = re.compile(r"^[\s`'\"]*(?:of|in)\s+(?:the\s+(?:[\w-]+\s+)?)?[`'\"]?$")
# "§2.4 in `ARCHITECTURE.md` §4": a doc followed by a § of its own takes that §, not the one before it.
OWN_REF_RE = re.compile(r"[`'\")]*\s?§")
SENTENCE_END_RE = re.compile(r"[.!?][`'\")*]*\s")


def _blocks(lines: list[str], markdown: bool) -> list[int]:
    """The block of each line, as an id: in Markdown a paragraph, list item, table row or heading; in code a comment
    block (a switch between comment and code lines ends it). A blank line ends any block."""
    ids, current, previous = [], 0, None
    for line in lines:
        if not line.strip():
            current += 1
            previous = None
            ids.append(current)
            continue
        if markdown:
            starts = bool(LIST_ITEM_RE.match(line))
            kind = True
        else:
            starts = False
            kind = bool(COMMENT_RE.match(line))
        if previous is not None and (starts or kind != previous):
            current += 1
        previous = kind
        ids.append(current)
    return ids


def references(path: str, text: str, own: str | None, declared: str | None) -> list[tuple[int, str, str | None]]:
    """Each § reference in a file: (line, number, doc key or None). Its doc, the first that applies:
    1. the doc named right after it ("§4.5 of ARCHITECTURE"), unless a § of its own follows it ("§2.4 in
       ARCHITECTURE §4": that doc takes only the §4);
    2. the doc named nearest before it in the same sentence;
    3. the file's own sections (`own_doc`);
    4. the doc named nearest before it in its block (paragraph, list item, table row, comment block);
    5. the file's declared design doc (`declared_doc`)."""
    lines = text.splitlines()
    blocks = _blocks(lines, path.endswith(".md"))
    # Each block as one string, with the offset of each of its lines, so a sentence can cross a line break.
    joined: dict[int, list[str]] = {}
    offsets: list[int] = []
    for index, line in enumerate(lines):
        parts = joined.setdefault(blocks[index], [])
        offsets.append(sum(len(p) + 1 for p in parts))
        parts.append(line)
    found = []
    for index, line in enumerate(lines):
        if "§" not in line:
            continue
        block = "\n".join(joined[blocks[index]])
        mentions = [
            (m.start(), m.end(), doc_key(m))
            for m in DOC_RE.finditer(block)
            if not (m.group(2) and m.group(2).rpartition("/")[2] in NO_SECTIONS)
        ]
        for match in REF_RE.finditer(line):
            at = offsets[index] + match.start()
            end = offsets[index] + match.end()
            after = next((m for m in mentions if m[0] >= end), None)
            before = [m for m in mentions if m[1] <= at]
            if after and OF_DOC_RE.match(block[end : after[0]]) and not OWN_REF_RE.match(block, after[1]):
                doc: str | None = after[2]
            elif before and not SENTENCE_END_RE.search(block[before[-1][1] : at]):
                doc = before[-1][2]
            elif own:
                doc = own
            elif before:
                doc = before[-1][2]
            else:
                doc = declared
            found.append((index + 1, match.group(1), doc))
    return found


def numbers_of(text: str) -> tuple[set[str], list[str]]:
    """A doc's § numbers, and each one that more than one heading carries."""
    seen: set[str] = set()
    twice: list[str] = []
    for heading in headings(text):
        if heading.number is None:
            continue
        if heading.number in seen and heading.number not in twice:
            twice.append(heading.number)
        seen.add(heading.number)
    return seen, twice


def tracked_texts(root: Path) -> dict[str, str]:
    """Every tracked text file outside SKIP_PREFIXES and SKIP_FILES, by repo-relative path (binary files skipped)."""
    res = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=False)
    if res.returncode != 0:
        raise Failure(f"git ls-files failed: {res.stderr.decode(errors='replace').strip()}")
    texts: dict[str, str] = {}
    for name in res.stdout.decode("utf-8").split("\0"):
        if not name or name.startswith(SKIP_PREFIXES) or name in SKIP_FILES:
            continue
        try:
            data = (root / name).read_bytes()
        except OSError:
            continue  # deleted in the working tree
        if b"\0" in data[:8192]:
            continue
        texts[name] = data.decode("utf-8", errors="replace")
    return texts


def check(root: Path, texts: dict[str, str] | None = None) -> Report:
    """Duplicate § in the docs, and § references to ARCHITECTURE and AGENT_WORKFLOW that resolve to no heading."""
    texts = tracked_texts(root) if texts is None else texts
    report = Report()
    numbers: dict[str, set[str]] = {}
    for name, text in sorted(texts.items()):
        if name.endswith(".md"):
            seen, twice = numbers_of(text)
            for number in twice:
                report.errors.append(f"{name}: §{number} is the number of more than one heading")
            if name in CHECKED.values():
                numbers[name] = seen
    for name, text in sorted(texts.items()):
        if "§" not in text:
            continue
        own = own_doc(name, text)
        declared = None if own else declared_doc(name, texts)
        for line, number, doc in references(name, text, own, declared):
            if doc is None:
                report.unscoped.append(f"{name}:{line}: §{number}")
            elif doc not in CHECKED:
                report.other += 1
            elif CHECKED[doc] not in numbers:
                continue  # a fixture without the doc
            elif number in numbers[CHECKED[doc]]:
                report.resolved += 1
            else:
                report.errors.append(f"{name}:{line}: §{number} is not a section of {CHECKED[doc]}")
    return report


def main() -> int:
    """`section --refs`: lint's § check, listing each reference that has no doc in scope."""
    report = check(ROOT)
    for line in report.errors:
        say(f"  FAIL  {line}")
    for line in report.unscoped:
        say(f"  note  {line}: no doc in scope")
    for line in report.notes:
        say(f"  ok    {line}")
    return 1 if report.errors else 0
