# MVP content built by the engineer's agent

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** the engineer (in chat with the M2 manager session on 2026-09-29); recorded from #31

## Context
`content/` and `levels/` belong to the designer ([ownership ADR](2026-09-28-ownership-by-codeowners-and-convention.md)),
and the engineer's agent does not touch the other owner's area without asking. The
[MVP rules](2026-09-29-mvp-rules.md) are provisional and were decided by the engineer; the MVP still needs its data
(roles, the Delivery task, the knife) and scenes (a lobby, a greybox map) before the designer reviews them in #38.

## Decision
- **MVP content and levels:** the engineer's agent builds the MVP's `content/` data and `levels/` scenes (the lobby,
  a greybox map) where they will live. Each such PR needs the engineer's explicit approval and is marked
  provisional; the designer may replace it.
- **Content API v0** is designed and built now (#33) and reviewed by the engineer. The designer reviews it before v1,
  before M7, and may change it (#38).
- **The M2 design** runs as two sequential sessions at xhigh effort, #32 (phases, intents, events and who may see what)
  and then #33 (content API v0 and the bot-scenario format). Each ends with a fresh adversarial reviewer. No workflow.

## Alternatives
None recorded in the chat.

## Consequences
- An exception to the ownership rule for the MVP only: outside it, `content/` and `levels/` stay the designer's, and
  the engineer's agent still stops and asks before touching them. `docs/AGENT_WORKFLOW.md` §9 points here.
- The scene rule is unchanged: never edit a scene someone else has an open PR on.
