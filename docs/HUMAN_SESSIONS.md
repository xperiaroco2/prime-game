# Sessions with a human

Read this before your first reply in a chat with a human (the engineer or the designer): a task session, a manager, the
director, the meta session; read it again after a compaction (root `CLAUDE.md` is re-injected then, this file is
not). A workflow agent runs unattended and does not need it; root `CLAUDE.md` points here instead of carrying it
(#836; the instruction-diet ADR's Context, "Which sections are used": every workflow agent paid for these lines on
every call).

## Talking to the humans
- Ask the engineer only taste questions: art, visuals, game design, level design (and a milestone's goal or go/no-go).
  A technical choice (code, engine, netcode, tooling, meta, docs, process) takes your recommended option without a
  question; say it in your report with the option taken, so he can reverse it (the trust ADR's tiers). Still asked:
  how the humans work, a new dependency (its ADR), anything destructive, anything costing money, the gate's
  exceptions.
<!-- see docs/interventions/2026-10-29-engineer-asks-only-taste.md -->
- Voice dictation: infer the meaning, read the file name back before editing, ask a question only if a misreading
  changes what gets built; read back a design answer with two readings (AGENT_WORKFLOW §13).
<!-- see docs/interventions/2026-09-30-engineer-ghosts-look-not-flight.md -->
- Explain from a concrete scenario of what goes wrong, plainly; options, then jargon (AGENT_WORKFLOW §13).
<!-- see docs/interventions/2026-09-28-engineer-plain-explanations.md -->
- A command for a human goes in the chat itself, one fenced PowerShell block each (a PR or issue may add it, never
  instead), starting with `cd` to its absolute folder (your worktree, not the main checkout). Run or preview it first.
<!-- see docs/interventions/2026-09-29-engineer-commands-say-where.md -->
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->

## Launching a workflow
Costs money, so it is a stop-and-ask item of root `CLAUDE.md`: state the agent count (fewer than 5) and rough cost, wait
for a yes (a manager: none within its track's weekly budget, else 15% of the weekly limit, trust ADR); its prompt
states its bounds (AGENT_WORKFLOW §7);
"ultracode" alone never exceeds the size guideline. A manager's estimate and checks: `docs/MANAGERS.md`.
<!-- see docs/interventions/2026-09-28-engineer-phase-a-workflow-unbounded.md -->

## Memory
Auto memory is personal: no shared rules or task state. "запам'ятай", "remember" or a correction: ask "для проєкту
(PR) чи тільки для вас?"; project → skill `log-intervention`, personal → `~/.claude/CLAUDE.md` after the human approves.

## Dictation glossary
Add a row per real misrecognition you resolved, in this table (not in root `CLAUDE.md`); never guess.

| Heard | Meant |
|---|---|
| "посеред науки" | "посеред двору" (in the middle of the yard) |
| "хаоса" | "House" (the map: "немає хаоса" = "the House is not there") |
| "поїзд" | "пояс" (the belt: "траву можна на поїзд" = a herb may go on the belt, #682 CD3) |
| "старілка" | "тарілка" (the plate: "старілка не може прийняти сиру котлету", #682 CD8) |
| "кішки" | "кишки" (guts: "не буде там кішки, розчленьонка" = no guts, no dismemberment, #1076) |
| "лігаві" | "легаві" (slang for the cops: "завітали лігаві" = the cops dropped in, #1090) |
| "топ-кін ефіцієнції" | "token efficiency" (the meta track's name: "AI продуктивіті топ-кін ефіцієнції" = AI productivity and token efficiency, #170 and #302) |
