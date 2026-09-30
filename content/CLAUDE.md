# content/: mechanics as data (designer)

Loaded when a file in `content/` is read. This folder belongs to the **designer**. Roles, abilities, items,
sabotages and task types live here as Godot `Resource` files (`.tres`), composed from parts the engine provides.
Read the root `CLAUDE.md`, `docs/GDD.md` and the **content API** section of `docs/ARCHITECTURE.md` first.

## The contract
- A mechanic is built from content-API parts (`docs/ARCHITECTURE.md` §9, content API v0): **rules** of a
  **trigger** (an intent such as `Use`, or a fact such as `item_rested`), **conditions** (only if; a **cost** is a
  condition that is also paid) and **effects** (what happens). A rule's owner decides whom it applies to: an item
  kind (while held), a role (its players) or the game mode (everyone). Task types (with their station kinds), win
  conditions and the game mode's phases are parts too. §9 lists every part, its settings, the events it emits and
  what its refusal reveals; a part is usable once its entry names the PR that built it. Use only those.
- Where the data lives (§9.6): `modes/`, `roles/`, `items/`, `tasks/`, `win_conditions/`, and `scenarios/` for
  bot scenarios (§9.7). The MVP's first data is provisional: the engineer's agent builds it in M2 under the MVP
  content ADR, and the designer reviews it in #38.

## Never edit engine code
- The designer's agent edits only its own paths (`content/`, `levels/`, `docs/GDD.md`, `docs/design/`, the skills
  `new-mechanic` and `new-level-piece`) and the shared logs (a new file in `docs/interventions/`, `docs/credits/`
  or `docs/decisions/`). Everything else is engine code or shared tooling: `core/ server/ net/ client/ voice/
  tools/ tests/ addons/ .github/ .claude/ project.godot`. Do not edit those, not even "one line".
- When a mechanic needs a part that does not exist, open an `engine-request` issue with a precise spec, then
  continue with whatever can be done in data. The spec says:
  - what the part does, in one sentence, and which kind it is (condition or cost, effect, tick system, voice rule,
    task type, station kind; §9.3);
  - its settings (name, type, allowed values) and what it produces;
  - who may see its result (everyone, the actor, the target, a team, nobody until a reveal), and what a refusal
    tells the sender;
  - edge cases (dead players, meetings, two players at once, the host's own player);
  - the mechanic that needs it, with a link to the `mechanic` issue.
- If a request would change how the engine works rather than add a part, say so in the issue: the engineer decides.

## Designing with the human
- The designer decides the game's content. Propose options with trade-offs and let the designer pick; never invent
  final content (names, numbers, rules) on your own.
- Every mechanic states what is hidden and from whom. Hidden information is the core of this game, and the
  engine enforces it only if the design says it.
- Numbers (cooldowns, ranges, counts) live in the data, where the designer can tune them. The engineer's agent does
  not rebalance them without the designer's approval.

## How work flows
- A new idea ("нова механіка: …"): skill `new-mechanic` (a `mechanic` issue, a GDD section with open questions,
  `engine-request` issues for missing parts, then data once the parts exist).
- Existing work: "start task 42" (skill `start-task`).
- Hand-written `.tres` files follow `.claude/rules/godot-resources.md`. The designer may have them open in the
  Godot editor: remind them of the save-first convention in `levels/CLAUDE.md`.
- Done means `verify` is green. Each mechanic gets a bot scenario once the bot harness exists (M3).
- The designer reviews results through screenshots and playtests, not code: put both in the PR where they apply.
