---
name: new-mechanic
description: 'The designer''s front door for a game-mechanic idea (role, ability, item, sabotage, task, information tool) - interview, a mechanic issue and engine-request issues after the designer''s OK, then a GDD section with open questions; never invented content. Use for "нова механіка: …", "new mechanic: …" or when the designer describes a mechanic idea.'
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(gh issue list *)
  - PowerShell(gh issue list *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh issue create *)
  - PowerShell(gh issue create *)
  - Bash(gh issue edit *)
  - PowerShell(gh issue edit *)
---

# New mechanic (docs/AGENT_WORKFLOW.md §6 and §12; designer-owned)

The designer decides the game's content. You interview, structure, record and file; you never invent names, numbers
or rules. Anything the designer has not decided is written down as an open question. Talk in the designer's
language; the repo and the issues are English.

1. **Read first:** `content/CLAUDE.md`, the relevant parts of `docs/GDD.md`, and the content-API section of
   `docs/ARCHITECTURE.md` (§9: the parts the engine offers). Look for an existing issue on the same idea:
   `gh issue list --state all --label area:content --search "<keywords>"`. Found one: show it and ask whether to
   continue there.
2. **Interview,** at most three questions per message, following `.github/ISSUE_TEMPLATE/mechanic.md`:
   - intent: what it should feel like, and why the game needs it;
   - rules, step by step: when it can happen, what it does, how it ends;
   - hidden information: who knows what, and when (the actor, the target, a team, everyone, nobody until a reveal);
   - edge cases: dead players, meetings, two players at once, the host's own player, a disconnect;
   - numbers to tune (cooldowns, ranges, counts): only values the designer gives.
   When asked for ideas, offer two or three options with their trade-offs and let the designer pick.
3. **Map it to engine parts** from §9: a rule (trigger → conditions and costs → effects) and its owner (an item
   kind, a role or the game mode), a task type with its station kind, or a win condition. Note for each part the
   events it emits, who sees them, and what a refusal tells the sender. For each part that does not exist, draft
   an `engine-request` from `.github/ISSUE_TEMPLATE/engine-request.md` with the spec `content/CLAUDE.md` asks for. If the idea would change how the engine works rather than add a part, say so in
   the request: the engineer decides.
4. **Stop for OK.** Show the designer the exact texts: the `mechanic` issue and each `engine-request`. Change them
   until the designer says yes. Only then create them, in this order, with bodies from scratchpad files:
   - `gh issue create --title "<mechanic>" --label area:content --body-file <file>`;
   - each request: `gh issue create --title "Engine: <part>" --label needs-engine --body-file <file>`, with
     "Needed by #<mechanic issue>";
   - `gh issue edit <mechanic> --body-file <file>` so its "Engine parts" section links every request.
5. **Start the work** only if the designer wants to go on now: skill `start-task` with the mechanic issue.
6. **GDD section** in `docs/GDD.md`, in the section where it belongs: intent, rules, hidden information, edge cases,
   numbers, engine parts (with issue links) and **open questions**. Only what the designer said, in their meaning.
7. **Content data** (`.tres` in `content/`) only when §9 lists every part the mechanic needs (from M2). Then follow
   `.claude/rules/godot-resources.md`, run `tools\run.cmd normalize <files>` and `tools\run.cmd check`. Each mechanic
   gets a bot scenario in `content/scenarios/` (§9.7) once the bot harness exists (M3).
8. **Finish** with `finish-task`. In the PR, say what the designer should check in a playtest.
