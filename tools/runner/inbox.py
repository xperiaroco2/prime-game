"""`inbox [--since T] [--repo OWNER/NAME ...]`: the GitHub half of the secretary's digest (#485), read-only.

The secretary session (.claude/skills/secretary/SKILL.md, docs/AGENT_WORKFLOW.md §7.2) runs it once a digest and
reads the sessions' half itself. Per repo (default REPOS: the game's, the UI's and the art's), two gh calls:
- `gh pr list --state open` with bodies and files: each open PR's "Needs the engineer" items without "Answered: <GitHub
  link>" (merge.open_needs, the gate's own reading), and, in GATED only (the repo whose gate is merge.py's), the gate's
  exceptions of a ready PR into main by the engineer's account (merge.exception_reasons over gh's file list: a merge
  only the engineer makes). gh lists at most 100 files a PR; a rename counts as a change of its new path.
- `gh api repos/<repo>/issues/comments?since=T` (newest first, COMMENT_LIMIT a page, a further page only while the
  last was full, at most COMMENT_PAGES; past that a "Truncated:" line names the oldest comment read; issues and PRs
  alike): the last "For you:" (or "Для вас:") block of each thread's latest comment by the engineer's account that
  has one, its items as written, and how many comments came after it in the window (a later one may have answered it).
A "For you:" block (orchestrate-stage §8): the heading on a line of its own (bold or a Markdown heading allowed), then
numbered items "1. ..." at the line's start (a "- " item is read too), each item's indented lines and fenced blocks with
it; "For you: nothing." when empty. Text after the label's colon is read as the first item. A block ends at the next
heading or label, or after a blank line at a line that is not an item, not indented and not fenced. A comment's blocks
are read together (a wave comment has the manager's in its notes and housekeeping's own line further down).
A source that fails prints "Unavailable: <error>" in its section and a warn line; the rest is still printed, and the
exit code is 1. Writes nothing; posts, edits and merges nothing.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from . import merge
from .common import Failure, warn

REPOS = ("xperiaroco2/prime-game", "xperiaroco2/prime-game-ui", "xperiaroco2/prime-game-art")
# The repo whose merges into main go through merge.py's gate (the UI and art repos keep their own flow).
GATED = "xperiaroco2/prime-game"
DEFAULT_HOURS = 72
COMMENT_LIMIT = 100
COMMENT_PAGES = 5
PR_LIMIT = 100
PR_JSON = "number,title,url,body,isDraft,baseRefName,headRefName,author,files,latestReviews"
# "For you" (or "Для вас") at a line's start, maybe as a heading or bold; label_rest decides whether it is a label.
LABEL_RE = re.compile(r"^\s*(#{1,6}\s+)?(\*\*|__)?\s*(?:For you|Для вас)\b\s*(.*)$", re.I)
ITEM_RE = re.compile(r"^(?:\d+[.)]|[-*+])\s+")
HEADING_RE = re.compile(r"^#{1,6}\s")
NOTHING_RE = re.compile(r"(?i)^\W*(?:nothing|none|нічого)\W*$")
CHANGE_CODES = {"ADDED": "A", "DELETED": "D"}

# One gh call returning parsed JSON (tests replace it).
GH: Callable[..., Any] = merge.gh_json


@dataclass
class ForYou:
    thread: int
    url: str
    created: str
    items: list[list[str]]
    later: int = 0


@dataclass
class RepoInbox:
    repo: str
    needs: list[str] | str = field(default_factory=list)  # a str: the source failed
    exceptions: list[str] | str = field(default_factory=list)
    for_you: list[ForYou] | str = field(default_factory=list)
    truncated: str = ""  # the oldest comment read when the window held more than COMMENT_PAGES full pages


def iso(seconds: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(seconds))


def label_rest(line: str) -> str | None:
    """The text after a "For you:" label on its line ("" for none), or None when the line is no label: the label needs
    its colon, or stands alone as a heading or a bold line ("For you to decide" is prose)."""
    match = LABEL_RE.match(line)
    if not match:
        return None
    heading, bold, rest = match.group(1), match.group(2), match.group(3).strip()

    def unbold(text: str) -> str:
        return text[2:].strip() if bold and text[:2] in ("**", "__") else text

    rest = unbold(rest)
    if rest.startswith(":"):
        return unbold(rest[1:].strip())
    return "" if not rest and (heading or bold) else None


def for_you_block(body: str) -> list[list[str]] | None:
    """The items of the body's "For you:" blocks, all of them in order (a wave comment has the manager's block in its
    notes and housekeeping's line further down), each item as its lines with its own first; [] when every block says
    "nothing"; None when the body has no block."""
    lines = merge.strip_comments(body).split("\n")
    found: list[list[str]] | None = None
    i = 0
    while i < len(lines):
        rest = label_rest(lines[i])
        i += 1
        if rest is None:
            continue
        items: list[list[str]] = [[rest]] if rest and not NOTHING_RE.match(rest) else []
        fenced = blank = False
        while i < len(lines):
            line = lines[i]
            fence = line.strip().startswith("```")
            if fenced or fence:
                if items:
                    items[-1].append(line)
                fenced = fenced != fence
            elif HEADING_RE.match(line) or label_rest(line) is not None:
                break
            elif ITEM_RE.match(line):
                items.append([line.strip()])
            elif not line.strip():
                blank = True
                i += 1
                continue
            elif line[:1].isspace() and items:
                items[-1].append(line)
            elif blank or not items:
                break
            else:
                items[-1].append(line)
            blank = False
            i += 1
        found = (found or []) + items
    return found


def needs_of(prs: list[dict[str, Any]]) -> list[str]:
    found = []
    for pr in prs:
        problems = merge.open_needs(str(pr.get("body") or ""))
        draft = ", draft" if pr.get("isDraft") else ""
        for problem in problems:
            found.append(f"PR #{pr.get('number')} (into {pr.get('baseRefName')}{draft}) \"{pr.get('title')}\": "
                         f"{problem}. {pr.get('url')}")  # fmt: skip
    return found


def exceptions_of(prs: list[dict[str, Any]]) -> list[str]:
    found = []
    for pr in prs:
        author = (pr.get("author") or {}).get("login")
        if pr.get("baseRefName") != "main" or pr.get("isDraft") or author != merge.ENGINEER_LOGIN:
            continue
        paths = [(CHANGE_CODES.get(str(f.get("changeType")), "M"), str(f.get("path"))) for f in pr.get("files") or []]
        designer = any(
            (r.get("author") or {}).get("login") == merge.DESIGNER_LOGIN and r.get("state") == "APPROVED"
            for r in pr.get("latestReviews") or []
        )
        for reason in merge.exception_reasons(paths, str(pr.get("body") or ""), str(pr.get("headRefName")), designer):
            found.append(f"PR #{pr.get('number')} \"{pr.get('title')}\": {reason}. {pr.get('url')}")
    return found


def for_you_of(comments: list[dict[str, Any]]) -> list[ForYou]:
    """Each thread's latest comment by the engineer's account with a block, newest thread first."""
    ordered = sorted(comments, key=lambda c: str(c.get("created_at")), reverse=True)
    latest: dict[int, ForYou] = {}
    seen: dict[int, int] = {}
    for c in ordered:
        thread = int(str(c.get("issue_url", "")).rstrip("/").rsplit("/", 1)[-1] or 0)
        seen[thread] = seen.get(thread, 0) + 1
        if thread in latest or (c.get("user") or {}).get("login") != merge.ENGINEER_LOGIN:
            continue
        items = for_you_block(str(c.get("body") or ""))
        if items is not None:
            latest[thread] = ForYou(thread, str(c.get("html_url")), str(c.get("created_at")), items, seen[thread] - 1)
    return sorted(latest.values(), key=lambda f: f.created, reverse=True)


def comments_since(repo: str, since: str) -> list[dict[str, Any]]:
    """The window's comments, newest first: page after page while a page comes back full, at most COMMENT_PAGES."""
    found: list[dict[str, Any]] = []
    for page in range(1, COMMENT_PAGES + 1):
        query = f"since={since}&sort=created&direction=desc&per_page={COMMENT_LIMIT}"
        query += f"&page={page}" if page > 1 else ""
        batch = GH("api", f"repos/{repo}/issues/comments?{query}")
        found += batch
        if len(batch) < COMMENT_LIMIT:
            break
    return found


def gather(repo: str, since: str) -> RepoInbox:
    box = RepoInbox(repo)
    try:
        prs = GH("pr", "list", "--repo", repo, "--state", "open", "--limit", str(PR_LIMIT), "--json", PR_JSON)
        box.needs = needs_of(prs)
        box.exceptions = exceptions_of(prs) if repo == GATED else []
    except (Failure, OSError, ValueError, TypeError, AttributeError) as exc:
        box.needs = box.exceptions = f"gh pr list: {exc}"
    try:
        comments = comments_since(repo, since)
        box.for_you = for_you_of(comments)
        if len(comments) >= COMMENT_LIMIT * COMMENT_PAGES:
            box.truncated = min(str(c.get("created_at")) for c in comments)
    except (Failure, OSError, ValueError, TypeError, AttributeError) as exc:
        box.for_you = f"gh api issues/comments: {exc}"
    return box


def render(boxes: list[RepoInbox], since: str, now: str) -> str:
    md = [f"# Inbox: GitHub since {since}", "", f"Written {now}; repos: {', '.join(b.repo for b in boxes)}.", ""]
    for box in boxes:
        md += [f"## {box.repo}", ""]
        sections: list[tuple[str, list[str] | str]] = [("Needs the engineer (open PRs)", box.needs)]
        if box.repo == GATED:
            sections.append(("Merges only the engineer makes (the gate's exceptions)", box.exceptions))
        for title, rows in sections:
            md += [f"### {title}", ""]
            if isinstance(rows, str):
                md += [f"Unavailable: {rows}", ""]
            else:
                md += [f"{k}. {row}" for k, row in enumerate(rows, 1)] or ["Nothing."]
                md.append("")
        md += [f"### For you (each thread's latest, by {merge.ENGINEER_LOGIN})", ""]
        if isinstance(box.for_you, str):
            md += [f"Unavailable: {box.for_you}", ""]
            continue
        if box.truncated:
            md += [f"Truncated: the newest {COMMENT_LIMIT * COMMENT_PAGES} comments only, back to {box.truncated}; "
                   "an older thread's block may be missing.", ""]  # fmt: skip
        if not box.for_you:
            md.append("Nothing.")
        for k, f in enumerate(box.for_you, 1):
            later = f" ({f.later} later comment{'s' if f.later != 1 else ''})" if f.later else ""
            md.append(f"{k}. #{f.thread}, {f.created}{later}: {f.url}")
            md += [f"   {line}" if line.strip() else "" for item in f.items for line in item] or ["   nothing."]
        md.append("")
    return "\n".join(md).rstrip("\n") + "\n"


def main(since: str | None = None, repos: list[str] | None = None, now: float | None = None) -> int:
    now = time.time() if now is None else now
    since = since or iso(now - DEFAULT_HOURS * 3600)
    boxes = [gather(repo, since) for repo in repos or REPOS]
    print(render(boxes, since, iso(now)), end="", flush=True)
    failed = [b.repo for b in boxes for v in (b.needs, b.for_you) if isinstance(v, str)]
    for repo in dict.fromkeys(failed):
        warn(f"inbox: a source of {repo} could not be read (see its Unavailable line)")
    return 1 if failed else 0
