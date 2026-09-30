# 2026-09-30: Read back a design answer that has two readings

- **Who intervened:** the engineer.
- **Session:** the M2 manager session (the engineer's Claude session, Desktop, Opus 5.5), during the M2 rules
  questions (#31) and the tasks built on them (#32, #46).

**What happened.**
- 2026-09-29 the manager session asked how ghosts move (Q6 on #31). The engineer answered, in Ukrainian, that ghosts
  "fly" but do not pass through walls, their collider is like a player's, and instead of a body they are a small
  sphere like a head.
- The manager recorded "Ghosts fly, faster than the living, but do not pass through walls" (#31 Q6). That became
  physical flight without gravity in `docs/decisions/2026-09-29-mvp-rules.md`, in `docs/ARCHITECTURE.md` §7.1 (#32)
  and in the controller of #46 (PR #52, with a Ctrl fly-down key).
- 2026-09-30 the engineer corrected it: a ghost moves exactly like a player (same collider, walks on the floor,
  jumps, sprints with unlimited stamina, 30% faster) and cannot reach anything a player cannot. "Flying" was only the
  look: a head without legs. The fix is in PR #52 (comments on #46).

**Why it happened.**
- "Fly" could describe the look or the mechanics. The manager picked the mechanics without saying so, and the rest
  of the answer (a collider like a player's) did not make it stop and ask.
- The recorded sentence then read as a settled rule, so the ADR, the architecture doc and the controller task each
  built on it without going back to the human's words.

**Rule adopted.**
1. When a human's answer to a design question has two readings that would build different things (for example the
   look or the mechanics), read the chosen reading back in one sentence before recording it in an issue, an ADR or a
   design document.
2. Record it only after the human confirms that reading.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Talking to the humans" (the explanation bullet was shortened to keep the budget).
- `docs/AGENT_WORKFLOW.md` §13.
