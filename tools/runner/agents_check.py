"""`agents-check`: assert that each subagent was served by the model family it asked for (docs/AGENT_WORKFLOW.md §5).

Claude Code writes each subagent's transcript to
~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl, with agent-<id>.meta.json next to it. The meta file
holds `agentType` and, when the caller asked for one, `model`; every assistant line of the transcript holds the model
that actually answered. The expected family is the caller's `model`, else the `model:` of the project agent in
.claude/agents/<agentType>.md; a subagent with neither inherits the session's model and is only listed. Families, not
exact IDs, are compared.

`availableModels` is the shared list (.claude/settings.json) plus the user-scope one (settings.json in the config
folder: ~/.claude, or CLAUDE_CONFIG_DIR), merged as Claude Code merges lists across non-managed scopes
(code.claude.com/docs/en/settings, "Lists merge instead of overriding", read 2026-10-02). Not modelled: managed
settings, whose list replaces the merged one (none on the engineer's PC, checked 2026-10-02), and
.claude/settings.local.json. A requested model from the shared list must be what served it. A model only in the user
list (amendment A of docs/decisions/2026-09-28-model-guard-no-fable-in-shared-config.md: the engineer's per-launch
opt-in) is ok when it served; when another family served it, it fell back and is listed, not judged (its transcripts
from before the user list held it would otherwise keep `--all` red). A requested model in neither list must NOT be
what served it (the model guard); a broken user settings file is a failure that names it.

The folders read are the main checkout's and its .claude/worktrees/* sessions' (the main checkout is found as `metrics`
finds it, from git's common dir), so a run from a worktree reads what a run from the main checkout reads. Workflow
agents' transcripts (<session>/subagents/workflows/wf_*/) are not read.
"""

from __future__ import annotations

import json
import os
import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from . import instructions
from .common import ROOT, Failure, bad, ok, say, skip

FAMILY_RE = re.compile(r"^claude-([a-z]+)-")
FAMILIES = ("opus", "sonnet", "haiku", "fable")


@dataclass
class Transcript:
    session: str
    agent_id: str
    agent_type: str
    requested: str | None
    served: set[str]


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or str(Path.home() / ".claude"))


def project_dirs(root: Path = ROOT, base: Path | None = None) -> list[Path]:
    """A checkout's transcript folders: the checkout itself and its .claude/worktrees/* sessions (`base`: the config
    folder)."""
    name = re.sub(r"[^A-Za-z0-9]", "-", str(root))
    projects = (base or config_dir()) / "projects"
    if not projects.is_dir():
        return []
    return sorted(
        p for p in projects.iterdir() if p.is_dir() and (p.name == name or p.name.startswith(f"{name}--claude-worktrees-"))
    )


def family(model: str) -> str | None:
    """'claude-opus-5-5' -> 'opus'; an alias ('sonnet') is its own family; '<synthetic>' and unknowns -> None."""
    model = model.lower()
    if model in FAMILIES:
        return model
    match = FAMILY_RE.match(model)
    return match.group(1) if match and match.group(1) in FAMILIES else None


def read(folder: Path, session: str | None) -> list[Transcript]:
    found = []
    pattern = f"{session}/subagents/agent-*.jsonl" if session else "*/subagents/agent-*.jsonl"
    for path in sorted(folder.glob(pattern)):
        meta_path = path.with_name(path.name.removesuffix(".jsonl") + ".meta.json")
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.is_file() else {}
        except ValueError:
            meta = {}
        served = set()
        with path.open(encoding="utf-8") as lines:
            for line in lines:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                message = entry.get("message")
                if entry.get("type") == "assistant" and isinstance(message, dict) and message.get("model"):
                    served.add(str(message["model"]))
        found.append(
            Transcript(
                session=path.parent.parent.name,
                agent_id=path.stem.removeprefix("agent-"),
                agent_type=str(meta.get("agentType", "?")),
                requested=meta.get("model"),
                served=served,
            )
        )
    return found


def agent_models(root: Path = ROOT) -> dict[str, str]:
    models = {}
    for path in sorted((root / ".claude" / "agents").glob("*.md")):
        value = instructions.parse(path.read_text(encoding="utf-8")).fields.get("model")
        if isinstance(value, str) and value:
            models[path.stem] = value
    return models


def allowed_models(root: Path = ROOT) -> list[str]:
    settings = json.loads((root / ".claude" / "settings.json").read_text(encoding="utf-8"))
    return list(settings.get("availableModels", []))


def user_models(config: Path | None = None) -> list[str]:
    """The user-scope `availableModels` (settings.json in the config folder); [] when the file or the key is missing."""
    path = (config or config_dir()) / "settings.json"
    if not path.is_file():
        return []
    try:
        settings = json.loads(path.read_text(encoding="utf-8-sig"))
    except ValueError as exc:
        raise Failure(f"{path}: not valid JSON ({exc})") from exc
    if not isinstance(settings, dict):
        raise Failure(f"{path}: not a JSON object")
    value = settings.get("availableModels", [])
    if not isinstance(value, list) or not all(isinstance(m, str) for m in value):
        raise Failure(f"{path}: availableModels must be a list of model names, not {value!r}")
    return value


def judge(t: Transcript, agents: dict[str, str], allowed: list[str], user: Sequence[str] = ()) -> tuple[str, str]:
    """('ok' | 'FAIL' | 'skip', explanation). `allowed`: the shared availableModels; `user`: the user-scope one."""
    families = {family(m) for m in t.served} - {None}
    served = ", ".join(sorted(t.served)) or "nothing"
    if not families:
        return "skip", f"no model answered ({served})"
    source = "requested"
    expected = t.requested if t.requested and t.requested != "inherit" else None
    if expected is None and t.agent_type in agents and agents[t.agent_type] != "inherit":
        expected, source = agents[t.agent_type], f".claude/agents/{t.agent_type}.md"
    if expected is None:
        return "skip", f"inherits the session model; served {served}"
    want = family(expected)
    if want is None:
        return "FAIL", f"{source} model {expected!r} is not a known family"
    # By family, so a full ID such as claude-sonnet-5-5 counts as the allowed alias sonnet.
    if want not in {family(a) for a in allowed}:
        if want in {family(u) for u in user}:
            scope = f"{source} {expected} (user-scope availableModels), served {served}"
            if families == {want}:
                return "ok", scope
            return "skip", f"{scope}: it fell back (the user list did not hold it then, or the model was unavailable)"
        if want in families:
            return "FAIL", (
                f"{source} {expected}, outside availableModels (shared and user scope), yet served {served}: "
                "the model guard failed"
            )
        return "ok", f"{source} {expected} is outside availableModels; the guard served {served} instead"
    if families == {want}:
        return "ok", f"{source} {expected}, served {served}"
    return "FAIL", f"{source} {expected}, served {served}"


def main(
    session: str | None = None, all_sessions: bool = False, *, root: Path = ROOT, config: Path | None = None
) -> int:
    """`root`: the checkout whose agent files and shared settings apply; `config`: the Claude config folder."""
    from . import metrics  # here, not at the top: metrics imports this module

    if not session and not all_sessions:
        session = os.environ.get("CLAUDE_CODE_SESSION_ID") or None
    scope = "all sessions" if all_sessions or not session else f"session {session}"
    say(f"agents-check ({scope})")
    agents, allowed, user = agent_models(root), allowed_models(root), user_models(config)
    say(f"availableModels: shared {', '.join(allowed) or 'none'}; user scope {', '.join(user) or 'none'}")
    # The main checkout's folders and its worktrees' sessions, from any worktree, as metrics reads them (#178).
    folders = project_dirs(metrics.main_checkout(root), config)
    transcripts = [t for folder in folders for t in read(folder, None if all_sessions else session)]
    judged = failed = 0
    for t in transcripts:
        verdict, why = judge(t, agents, allowed, user)
        label = f"{t.agent_type} (agent {t.agent_id[:10]}, session {t.session[:8]}): {why}"
        if verdict == "ok":
            ok(label)
            judged += 1
        elif verdict == "FAIL":
            bad(label)
            judged += 1
            failed += 1
        else:
            skip(label)
    if judged == 0:
        raise Failure(
            f"no subagent transcript with an expected model in {scope}. Run a project subagent (for example "
            "test-runner) first, or pass --all."
        )
    say(f"agents-check: {'FAILED' if failed else 'passed'} ({judged} checked, {failed} wrong)")
    return 1 if failed else 0
