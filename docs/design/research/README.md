# Design research

Web research behind the game's design decisions, kept as written so later sessions build on it instead of searching
again (the engineer, 2026-10-15, #1078). These are **research, not decisions**: each report ends with options and a
recommendation for the engineer, and only what he chose is a rule (in `docs/GDD.md`, an ADR or the issue named
below). Never copy names, designs or plots from the games studied into the game.

## Round 1, 2026-10-15 (M8: aliens vs humans)
Four web researchers in parallel, one topic each, from the M8 plan (#1039) and the engineer's answers of the same day.

| Report | Covers | Fed |
|---|---|---|
| [The outed traitor](2026-10-15-outed-traitor.md) | How hidden-role games keep a revealed traitor a threat: soft exile, redundancy, spendable reach, open-hunt phases, caps on the villain | #1031, #1040 |
| [Death and respawn](2026-10-15-death-respawn.md) | Dead time, respawn costs (timers, pools, trips, items), knockdown and revive, spawn camping, what the dead may share | #1032 |
| [In-match economy](2026-10-15-in-match-economy.md) | Earning and spending inside a match, catch-up and bounties, information powers ("see through walls") and their six fairness levers | #1040 |
| [Meta-progression and the voice chaos co-op wave](2026-10-15-meta-and-voice-chaos.md) | Progression without power creep; why the 2023-2026 proximity-voice co-op hits spread and what brings friends back | #1041, #1038 |

**Trust.** Each claim is tagged verified, opinion or analysis, with its URL. Many wikis refused the fetch (HTTP 402,
403, 429), so some facts come from search-result summaries and are marked so; sales and player counts are third-party
estimates, right in order of magnitude only. Each report lists what it could not verify.

**What the engineer decided from it (2026-10-15):** being outed is a disadvantage, never a loss; roles mechanically
identical; points per completed task and per task sabotage (#1031, #1040); many capsules, a random one, a perk to
choose, a few seconds of invulnerability, a 30 s wait and no wait that grows per death (#1032); the pillars "never
boring" and "randomness is part of the fun" (`docs/GDD.md` §1).
