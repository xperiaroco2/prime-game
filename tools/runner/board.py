"""`board move <issue> <status>`: put an issue on the project board and set its Status column.

Agents set only "In progress" (start-task) and "In review" (finish-task). The board's built-in workflows set
Backlog when an item is added and Done when it is closed or merged (docs/AGENT_WORKFLOW.md §10).
"""

from __future__ import annotations

import json
import shutil

from .common import Failure, ok, run, say

OWNER = "xperiaroco2"
PROJECT_NUMBER = 1
STATUS_FIELD = "Status"
# Command-line name -> the board column it sets.
MOVES = {"in-progress": "In progress", "in-review": "In review"}
TIMEOUT = 60


def status_option(fields: dict[str, object], column: str) -> tuple[str, str]:
    """(field id, option id) of `column` in the Status field of `gh project field-list --format json` output."""
    for field in fields.get("fields", []):  # type: ignore[union-attr]
        if field.get("name") != STATUS_FIELD:
            continue
        for option in field.get("options", []):
            if option.get("name") == column:
                return field["id"], option["id"]
        names = ", ".join(o.get("name", "?") for o in field.get("options", []))
        raise Failure(f"the board has no '{column}' column (it has: {names}). Fix the Status field on the board.")
    raise Failure(f"the board has no '{STATUS_FIELD}' field")


def _gh(*args: str) -> dict[str, object]:
    exe = shutil.which("gh")
    if not exe:
        raise Failure("GitHub CLI (gh) not found: winget install --id GitHub.cli")
    res = run([exe, *args], timeout=TIMEOUT)
    if res.timed_out:
        raise Failure(f"gh {args[0]} {args[1]} timed out after {TIMEOUT}s")
    if res.rc != 0:
        hint = " Run: gh auth refresh -s project" if "scope" in res.out.lower() else ""
        raise Failure(f"gh {' '.join(args[:2])} failed: {res.out.strip()[-400:]}{hint}")
    try:
        data = json.loads(res.out)
    except ValueError as exc:
        raise Failure(f"gh {' '.join(args[:2])} returned no JSON: {res.out.strip()[-200:]}") from exc
    return data if isinstance(data, dict) else {"items": data}


def move(issue: int, where: str) -> int:
    column = MOVES[where]
    say(f"board move #{issue} -> {column}")
    info = _gh("issue", "view", str(issue), "--json", "url,state,title")
    if "/pull/" in str(info.get("url")):
        raise Failure(f"#{issue} is a pull request; move the issue it closes instead")
    if info.get("state") != "OPEN":
        raise Failure(f"issue #{issue} is {info.get('state')}; only open issues move on the board")
    number, owner = str(PROJECT_NUMBER), OWNER
    project = _gh("project", "view", number, "--owner", owner, "--format", "json")
    field_id, option_id = status_option(_gh("project", "field-list", number, "--owner", owner, "--format", "json"), column)
    # Adding an issue that is already on the board returns its existing item.
    item = _gh("project", "item-add", number, "--owner", owner, "--url", str(info["url"]), "--format", "json")
    _gh(
        "project", "item-edit",
        "--id", str(item["id"]),
        "--project-id", str(project["id"]),
        "--field-id", field_id,
        "--single-select-option-id", option_id,
        "--format", "json",
    )
    ok(f"#{issue} '{info.get('title')}' is in '{column}' on {project.get('url')}")
    return 0
