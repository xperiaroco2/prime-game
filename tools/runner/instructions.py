"""Instruction files for Claude Code: line budgets, frontmatter and skills' links (docs/AGENT_WORKFLOW.md §3 and §5).

Budgets count the lines Claude Code loads: frontmatter and block-level HTML comments are removed before
injection (code.claude.com/docs/en/memory), so `<!-- see docs/interventions/... -->` notes are free.
Frontmatter is checked strictly: when a rule's YAML does not parse, Claude Code silently ignores its
`paths:` and loads the rule at every launch.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

ROOT_BUDGET = 150  # root CLAUDE.md plus every rule without paths: (all of them load at launch)
NESTED_BUDGET = 100  # each CLAUDE.md below the root (loads when a file in its folder is read)
RULE_BUDGET = 60  # each .claude/rules/**/*.md
AGENT_MODELS = ("opus", "sonnet", "haiku")  # docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md
READ_ONLY = ("Edit", "Write", "NotebookEdit", "Agent")  # every project subagent but the lean writers is read-only (§5)
# The lean workflow agent types: exactly these names, each within its own tools allowlist, Skill disallowed, no
# effort (docs/decisions/2026-10-04-lean-workflow-agent-types.md; the reader and lean-writer:
# docs/decisions/2026-10-06-lean-reader-and-writer-types.md). The writers are the only writable subagents; a fourth
# writer needs a new ADR. The reader stays read-only.
_LEAN_TOOLS = (
    "Bash", "PowerShell", "Read", "Edit", "Write", "Grep", "Glob", "Monitor", "TaskStop", "WebFetch", "WebSearch",
)  # fmt: skip
_READER_TOOLS = ("Read", "Grep", "Glob", "Bash", "PowerShell", "WebFetch", "WebSearch")
WRITERS = {
    "task-implementer": _LEAN_TOOLS,
    "task-publisher": (*_LEAN_TOOLS, "SendUserFile"),
    "lean-writer": (*_READER_TOOLS, "Edit", "Write"),
}
READERS = {"lean-reader": _READER_TOOLS}
LEAN = {**WRITERS, **READERS}
WRITER_DISALLOWED = ("NotebookEdit", "Agent", "Skill")
# Skills (§6), against the frontmatter reference at code.claude.com/docs/en/skills (checked 2026-09-29). Claude Code
# ignores an unknown field without a word, so a misspelled `allowed_tools` would silently grant nothing.
SKILL_FIELDS = {
    "name", "description", "when_to_use", "argument-hint", "arguments", "disable-model-invocation",
    "user-invocable", "allowed-tools", "disallowed-tools", "model", "effort", "context", "agent", "background",
    "hooks", "paths", "shell", "metadata", "license", "compatibility",
}  # fmt: skip
# Would replace bundled commands (§6); workflow-authoring is the bundled skill a manager loads for a script (#557).
SKILL_RESERVED = ("doctor", "verify", "run", "workflow-authoring")
SKILL_NO_FORK = ("start-task", "finish-task")  # they need the conversation (§6)
SKILL_LISTING_CAP = 1536  # description + when_to_use are cut here in the skill listing
SKILL_BUDGET = 500  # lines of SKILL.md body; the docs advise moving detail to supporting files beyond this
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
# The skill listing (#562): `skillOverrides` in .claude/settings.json hides the bundled skills no agent of ours uses.
# Values from code.claude.com/docs/en/skills, "Override skill visibility from settings" (read 2026-10-08, Claude Code
# 2.1.293). Our skills and workflows stay listed (dictation, the manager's launches), and so do the bundled skills our
# instructions send the model to (SKILL_KEPT). `disableBundledSkills` would remove those with the rest, and an "on"
# entry cannot bring them back (seen in the 2.1.293 binary), so it stays unset.
SKILL_OVERRIDE_VALUES = ("on", "name-only", "user-invocable-only", "off")
SKILL_KEPT = {
    "workflow-authoring": "a manager loads it to write a workflow script (#557)",
    "code-review": "finish-task step 2 and AGENT_WORKFLOW §4.2 route a docs-only or content-data diff to it",
}
# A Markdown link's target (inline links only); a scheme (https:, mailto:) or a bare #anchor is not a file.
LINK_RE = re.compile(r"\]\(([^)\s]+)\)")
CODE_SPAN_RE = re.compile(r"`[^`]*`")
EXTERNAL_RE = re.compile(r"^(?:[A-Za-z][A-Za-z0-9+.-]*:|#)")
# A repo path a lean agent's body names in backticks (#557): docs/ or .claude/, no placeholder, glob or space.
BODY_PATH_RE = re.compile(r"`((?:docs|\.claude)/[^`<>*\s]+)`")
FALSE = ("false", "no", "off", "0")
TRUE = ("true", "yes", "on", "1")
SKIP = {".git", ".godot", "addons", "tools/out", "docs/history", ".claude/worktrees"}
OVER_BUDGET_FIX = (
    "Scope a rule to paths:, move it into a skill, or retire it; the intervention entry says which "
    "(docs/AGENT_WORKFLOW.md §3)."
)

KEY_RE = re.compile(r"^([A-Za-z][\w-]*):(?:\s+(.*))?$")
ITEM_RE = re.compile(r"^\s+-\s+(.*)$")
# A plain (unquoted) YAML scalar cannot start with these, and cannot contain ": " or " #".
YAML_INDICATORS = tuple("*&!%@`|>{[,?")


@dataclass
class Frontmatter:
    fields: dict[str, str | list[str]]
    body: list[str]
    error: str | None = None


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def _scalar(raw: str) -> tuple[str, str | None]:
    """The value of a one-line YAML scalar, or an error when real YAML would reject or reinterpret it."""
    value = raw.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1], None
    if value.startswith(("'", '"')):
        return value, "unbalanced quote"
    if value.startswith(YAML_INDICATORS) or ": " in value or " #" in value:
        return value, f"quote this value: {value!r}"
    return value, None


def parse(text: str) -> Frontmatter:
    """Split `---` frontmatter (a strict subset: `key: value` and `key:` with `  - item` lines) from the body."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return Frontmatter({}, lines)
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return Frontmatter({}, lines, "frontmatter has no closing ---")
    fields: dict[str, str | list[str]] = {}
    key = ""
    for number, line in enumerate(lines[1:end], start=2):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if match := KEY_RE.match(line):
            key = match.group(1)
            if match.group(2):
                value, problem = _scalar(match.group(2))
                if problem:
                    return Frontmatter(fields, lines[end + 1 :], f"line {number}: {problem}")
                fields[key] = value
            else:
                fields[key] = []
            continue
        item = ITEM_RE.match(line)
        current = fields.get(key)
        if item and isinstance(current, list):
            value, problem = _scalar(item.group(1))
            if problem:
                return Frontmatter(fields, lines[end + 1 :], f"line {number}: {problem}")
            current.append(value)
            continue
        return Frontmatter(fields, lines[end + 1 :], f"line {number}: cannot parse {line.strip()!r}")
    return Frontmatter(fields, lines[end + 1 :])


def loaded_lines(body: list[str]) -> int:
    """Lines Claude Code injects: block-level HTML comments outside code fences are stripped."""
    count, in_comment, in_code = 0, False, False
    for line in body:
        text = line.strip()
        if in_comment:
            in_comment = "-->" not in text
            continue
        if text.startswith("```"):
            in_code = not in_code
        elif not in_code and text.startswith("<!--"):
            if "-->" not in text:
                in_comment = True
                continue
            if text.endswith("-->"):
                continue
        count += 1
    return count


def _as_list(value: str | list[str] | None) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [v for v in value if v]
    return [part.strip() for part in value.split(",") if part.strip()]


def _nested_claude_files(root: Path) -> list[Path]:
    found: list[Path] = []
    for folder, dirs, files in os.walk(root):
        rel = Path(folder).relative_to(root).as_posix()
        dirs[:] = sorted(d for d in dirs if (f"{rel}/{d}" if rel != "." else d) not in SKIP)
        if rel != "." and "CLAUDE.md" in files:
            found.append(Path(folder) / "CLAUDE.md")
    return [p for p in found if p != root / ".claude" / "CLAUDE.md"]


def check(root: Path) -> Report:
    report = Report()

    def rel(path: Path) -> str:
        return path.relative_to(root).as_posix()

    # Launch-time files: root CLAUDE.md, .claude/CLAUDE.md and unscoped rules share one budget.
    launch: list[tuple[str, int]] = []
    for path in (root / "CLAUDE.md", root / ".claude" / "CLAUDE.md"):
        if path.is_file():
            launch.append((rel(path), loaded_lines(path.read_text(encoding="utf-8").splitlines())))
    if not (root / "CLAUDE.md").is_file():
        report.errors.append("CLAUDE.md is missing at the repo root")

    rules = sorted((root / ".claude" / "rules").rglob("*.md")) if (root / ".claude" / "rules").is_dir() else []
    largest_rule = ("", 0)
    for path in rules:
        fm = parse(path.read_text(encoding="utf-8"))
        lines = loaded_lines(fm.body)
        largest_rule = max(largest_rule, (rel(path), lines), key=lambda item: item[1])
        if fm.error:
            report.errors.append(
                f"{rel(path)}: {fm.error}. Claude Code would ignore paths: and load this rule at every launch"
            )
            continue
        if lines > RULE_BUDGET:
            report.errors.append(f"{rel(path)}: {lines} lines, budget {RULE_BUDGET}")
        if "paths" in fm.fields and not _as_list(fm.fields["paths"]):
            report.errors.append(f"{rel(path)}: paths: is empty")
        elif "paths" not in fm.fields:
            launch.append((rel(path), lines))
            report.notes.append(f"{rel(path)} has no paths: and loads at every launch")

    if rules:
        report.notes.append(f"{len(rules)} rules, largest {largest_rule[0]} {largest_rule[1]}/{RULE_BUDGET} lines")
    total = sum(n for _, n in launch)
    detail = " + ".join(f"{name} {n}" for name, n in launch)
    if total > ROOT_BUDGET:
        report.errors.append(f"launch-time instructions: {total} lines ({detail}), budget {ROOT_BUDGET}")
    else:
        report.notes.append(f"launch-time instructions {total}/{ROOT_BUDGET} lines ({detail})")

    nested = [(rel(p), loaded_lines(parse(p.read_text(encoding="utf-8")).body)) for p in _nested_claude_files(root)]
    for name, lines in nested:
        if lines > NESTED_BUDGET:
            report.errors.append(f"{name}: {lines} lines, budget {NESTED_BUDGET}")
    if nested:
        name, lines = max(nested, key=lambda item: item[1])
        report.notes.append(f"{len(nested)} nested CLAUDE.md, largest {name} {lines}/{NESTED_BUDGET} lines")

    report.errors += control_characters(root)

    agents_dir = root / ".claude" / "agents"
    agents = sorted(agents_dir.glob("*.md")) if agents_dir.is_dir() else []
    for path in agents:
        report.errors += [f"{rel(path)}: {problem}" for problem in agent_problems(path)]
    if agents:
        report.notes.append(f"{len(agents)} subagents: frontmatter, model guard, read-only or a lean writer")

    skills_dir = root / ".claude" / "skills"
    skills = sorted(p for p in skills_dir.iterdir() if p.is_dir()) if skills_dir.is_dir() else []
    for folder in skills:
        report.errors += [f"{rel(folder)}/SKILL.md: {problem}" for problem in skill_problems(folder)]
        report.errors += skill_links(root, folder)
    if skills:
        report.notes.append(f"{len(skills)} skills: frontmatter, model-invocable, Bash and PowerShell twins, links")
    report.errors += skill_override_problems(root, report)
    return report


def skill_override_problems(root: Path, report: Report) -> list[str]:
    """`skillOverrides` and `disableBundledSkills` in .claude/settings.json (#562; SKILL_OVERRIDE_VALUES)."""
    path = root / ".claude" / "settings.json"
    if not path.is_file():
        return []
    where = ".claude/settings.json"
    try:
        settings = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        return [f"{where}: not JSON ({exc})"]
    if not isinstance(settings, dict):
        return [f"{where}: not a JSON object"]
    problems = []
    if settings.get("disableBundledSkills") is True:
        problems.append(
            f"{where}: disableBundledSkills removes {' and '.join(SKILL_KEPT)} with the other bundled skills; hide "
            "them one by one in skillOverrides (docs/AGENT_WORKFLOW.md §6)"
        )
    overrides = settings.get("skillOverrides", {})
    if not isinstance(overrides, dict):
        return [*problems, f"{where}: skillOverrides must be an object of skill name to value"]
    skills_dir, workflows_dir = root / ".claude" / "skills", root / ".claude" / "workflows"
    ours = {p.name for p in skills_dir.iterdir() if p.is_dir()} if skills_dir.is_dir() else set()
    ours |= {p.stem for p in workflows_dir.glob("*.js")} if workflows_dir.is_dir() else set()
    hidden = 0
    for name, value in sorted(overrides.items()):
        if value not in SKILL_OVERRIDE_VALUES:
            allowed = ", ".join(SKILL_OVERRIDE_VALUES)
            problems.append(f"{where}: skillOverrides {name!r}: {value!r} is not one of {allowed}")
        elif value != "on" and name in ours:
            problems.append(
                f"{where}: skillOverrides hides the project's own {name!r}; our skills and workflows stay listed (§6)"
            )
        elif value != "on" and name in SKILL_KEPT:
            problems.append(f"{where}: skillOverrides hides {name!r}; {SKILL_KEPT[name]}")
        elif value != "on":
            hidden += 1
    if hidden:
        report.notes.append(f"skillOverrides: {hidden} bundled skills kept out of the listing")
    return problems


def skill_links(root: Path, folder: Path) -> list[str]:
    """Each relative link in a skill's Markdown files (SKILL.md and its supporting files, which SKILL.md points to and
    the agent reads on demand: orchestrate-stage's budget.md, #415) must name a file or folder that exists, so a
    renamed supporting file or ADR cannot leave a pointer to nothing. Links inside code fences (``` or ~~~) and inline
    code spans are examples."""
    problems = []
    for path in sorted(folder.rglob("*.md")):
        in_code = False
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.strip().startswith(("```", "~~~")):
                in_code = not in_code
                continue
            if in_code:
                continue
            for target in LINK_RE.findall(CODE_SPAN_RE.sub("", line)):
                if EXTERNAL_RE.match(target):
                    continue
                if not (path.parent / target.split("#", 1)[0]).exists():
                    problems.append(f"{path.relative_to(root).as_posix()}:{number}: link {target} names no file")
    return problems


def control_characters(root: Path) -> list[str]:
    """A lone CR or another control character (except tab) in Markdown is always a mistake, such as an escape
    sequence that leaked out of a script (`\\r` in `tools\\run.cmd`). CRLF line ends are fine: git normalizes them."""
    problems = []
    for folder, dirs, files in os.walk(root):
        rel = Path(folder).relative_to(root).as_posix()
        dirs[:] = sorted(d for d in dirs if (f"{rel}/{d}" if rel != "." else d) not in SKIP)
        for name in sorted(f for f in files if f.endswith(".md")):
            path = Path(folder) / name
            for number, line in enumerate(path.read_bytes().split(b"\n"), start=1):
                bad = sorted({b for b in line.removesuffix(b"\r") if b < 32 and b != 9})
                if bad:
                    codes = ", ".join(f"0x{b:02X}" for b in bad)
                    problems.append(f"{path.relative_to(root).as_posix()}:{number}: control character {codes}")
    return problems


def tool_rules(value: str | list[str] | None) -> list[str]:
    """allowed-tools as a YAML list, or a string separated by spaces or commas outside parentheses."""
    if value is None:
        return []
    if isinstance(value, list):
        return [v.strip() for v in value if v.strip()]
    rules, depth, current = [], 0, ""
    for char in value:
        depth += (char == "(") - (char == ")")
        if depth == 0 and (char.isspace() or char == ","):
            if current:
                rules.append(current)
            current = ""
        else:
            current += char
    return rules + ([current] if current else [])


def _runner_neutral(rule: str) -> str:
    """The shell-independent text of a Bash(...) or PowerShell(...) rule: both runner wrappers read the same."""
    inner = rule[rule.index("(") + 1 : -1]
    for wrapper in ("./tools/run.sh", ".\\tools\\run.cmd", "tools/run.sh", "tools\\run.cmd"):
        inner = inner.replace(wrapper, "<runner>")
    return inner


def skill_problems(folder: Path) -> list[str]:
    path = folder / "SKILL.md"
    if not path.is_file():
        return ["missing (every folder in .claude/skills/ is one skill)"]
    fm = parse(path.read_text(encoding="utf-8"))
    if fm.error:
        return [f"{fm.error}; Claude Code would load the skill with no frontmatter at all"]
    if not fm.fields:
        return ["no frontmatter"]
    problems = []
    name = fm.fields.get("name")
    if name != folder.name:
        problems.append(f"name: must be {folder.name!r} (the folder name)")
    if not SKILL_NAME_RE.match(folder.name):
        problems.append("the folder name must be lowercase words joined by '-'")
    if folder.name in SKILL_RESERVED:
        problems.append(f"'{folder.name}' would replace the bundled /{folder.name} (§6)")
    unknown = sorted(set(fm.fields) - SKILL_FIELDS)
    if unknown:
        problems.append(f"unknown field(s) {', '.join(unknown)}: Claude Code ignores them silently")
    description = fm.fields.get("description")
    if not isinstance(description, str) or not description:
        problems.append("description: is empty")
    else:
        listing = len(description) + len(str(fm.fields.get("when_to_use") or ""))
        if listing > SKILL_LISTING_CAP:
            problems.append(f"description + when_to_use is {listing} characters; the listing cuts at {SKILL_LISTING_CAP}")
    if str(fm.fields.get("disable-model-invocation", "")).lower() in TRUE:
        problems.append("disable-model-invocation: every skill stays model-invocable, so dictation works (§6)")
    if str(fm.fields.get("user-invocable", "")).lower() in FALSE:
        problems.append("user-invocable: false hides it from the / menu; humans invoke skills too (§6)")
    if folder.name in SKILL_NO_FORK and fm.fields.get("context") == "fork":
        problems.append("context: fork loses the conversation; start-task and finish-task run inline (§6)")
    shell = fm.fields.get("shell")
    if shell is not None and shell not in ("bash", "powershell"):
        problems.append("shell: must be bash or powershell")
    rules = tool_rules(fm.fields.get("allowed-tools"))
    for bare in sorted({r for r in rules if r in ("Bash", "PowerShell")}):
        problems.append(f"allowed-tools: a bare {bare} pre-approves every command; name the commands")
    for rule in rules:
        if rule.startswith("Bash(") and "run.cmd" in rule or rule.startswith("PowerShell(") and "run.sh" in rule:
            problems.append(f"allowed-tools: {rule} uses the other shell's runner (Bash: tools/run.sh, PowerShell: tools\\run.cmd)")
    bash = {_runner_neutral(r) for r in rules if r.startswith("Bash(") and r.endswith(")")}
    pwsh = {_runner_neutral(r) for r in rules if r.startswith("PowerShell(") and r.endswith(")")}
    for missing in sorted(bash - pwsh):
        problems.append(f"allowed-tools: Bash({missing}) has no PowerShell twin")
    for missing in sorted(pwsh - bash):
        problems.append(f"allowed-tools: PowerShell({missing}) has no Bash twin")
    lines = loaded_lines(fm.body)
    if lines > SKILL_BUDGET:
        problems.append(f"{lines} lines, budget {SKILL_BUDGET}: move detail into a supporting file")
    return problems


def agent_problems(path: Path) -> list[str]:
    fm = parse(path.read_text(encoding="utf-8"))
    if fm.error:
        return [fm.error]
    if not fm.fields:
        return ["no frontmatter"]
    problems = []
    if fm.fields.get("name") != path.stem:
        problems.append(f"name: must be {path.stem!r} (the file name)")
    if not fm.fields.get("description"):
        problems.append("description: is empty")
    if fm.fields.get("model") not in AGENT_MODELS:
        problems.append(f"model: must be one of {', '.join(AGENT_MODELS)} (model guard ADR)")
    tools = _as_list(fm.fields.get("tools"))
    if not tools:
        problems.append("tools: is empty (list the minimal tools)")
    disallowed = _as_list(fm.fields.get("disallowedTools"))
    if path.stem in LEAN:
        for tool in tools:
            if tool not in LEAN[path.stem]:
                problems.append(f"tools: {tool} is outside the lean allowlist (lean agent types ADR)")
    if path.stem not in WRITERS:
        missing = [t for t in READ_ONLY if t not in disallowed]
        if missing:
            problems.append(f"disallowedTools: must include {', '.join(missing)} (subagents are read-only)")
    if path.stem in LEAN:
        # A reader's NotebookEdit and Agent are already in the read-only line above.
        required = WRITER_DISALLOWED if path.stem in WRITERS else [t for t in WRITER_DISALLOWED if t not in READ_ONLY]
        missing = [t for t in required if t not in disallowed]
        if missing:
            problems.append(f"disallowedTools: must include {', '.join(missing)} (lean agent types ADR)")
        if "effort" in fm.fields:
            problems.append("effort: is set by the workflow per role (lean agent types ADR)")
        if "skills" in fm.fields:
            # #557's probe: a preloaded skill's whole text is in every call of every task of the type.
            problems.append("skills: a lean type preloads no skill (its text is in every call; #557)")
        # #557: the body sent agents to a SKILL.md that does not exist; a named path must (the root is the agents'
        # .claude/agents/ two levels up).
        root = path.resolve().parents[2]
        for rel in dict.fromkeys(BODY_PATH_RE.findall("\n".join(fm.body))):
            if not (root / rel).exists():
                problems.append(f"body names {rel}, which does not exist")
    if "permissionMode" in fm.fields:
        problems.append("permissionMode: project subagents inherit the session's mode (lean agent types ADR)")
    if "memory" in fm.fields:
        problems.append("memory: is not used by project subagents")
    return problems
