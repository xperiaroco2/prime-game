# content/: mechanics as data (designer)

Loaded when a file in `content/` is read. This folder belongs to the **designer**. Roles, abilities, items,
sabotages and task types live here as Godot `Resource` files (`.tres`), composed from parts the engine provides.
Read the root `CLAUDE.md`, `docs/GDD.md` and the **content API** section of `docs/ARCHITECTURE.md` first.

## The contract
- A mechanic is built from content-API parts: a **trigger** (when), **conditions** (only if) and **effects** (what
  happens), plus interactables and task stations for things in the world. The content-API section of
  `docs/ARCHITECTURE.md` lists every part that exists and its settings. Use only those.
- Until the content API exists (pre-M2 design), there is no content data yet. Work goes into `docs/GDD.md` and
  `mechanic` issues instead.

## Never edit engine code
- The designer's agent edits only `content/`, `levels/`, `docs/GDD.md`, `docs/design/`, and the skills
  `new-mechanic` and `new-level-piece`. Everything else is engine code or shared tooling: `core/ server/ net/
  client/ voice/ tools/ tests/ addons/ .github/ .claude/ project.godot`. Do not edit those, not even "one line".
- When a mechanic needs a part that does not exist, open an `engine-request` issue with a precise spec, then
  continue with whatever can be done in data. The spec says:
  - what the part does, in one sentence, and which kind it is (trigger, condition, effect, interactable, station);
  - its settings (name, type, allowed values) and what it produces;
  - who may see its result (everyone, the actor, the target, a team, nobody until a reveal);
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
- Hand-written `.tres` files follow `.claude/rules/godot-resources.md`.
- Done means `verify` is green. Each mechanic gets a bot scenario once the bot harness exists (M3).
- The designer reviews results through screenshots and playtests, not code: put both in the PR where they apply.
