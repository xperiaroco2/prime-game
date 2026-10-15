# The humans' active win condition and the pacing of a 10-minute match

Tags: **[V]** checked against the cited page. **[S]** taken only from a search-result summary, because the page itself refused the fetch (403, 402 or 429). **[P]** a player's, critic's or designer's opinion. **[A]** my analysis. Every number in a proposal is a **placeholder**. This report builds on Round 1's [outed traitor report](2026-10-15-outed-traitor.md), which covered Project Winter exile, the GGD hunts, the BotC succession roles, Avalon ratios and the DbD regression cap. Those are cited, not repeated.

## 1. Short answer

1. **"Run out the clock" is a fallback, not a goal.** The games that rely on it add something that forces the hidden side to act. TTT's Haste Mode exists to "put pressure on traitors to keep things moving, which is more interesting for the innocent players" [V] ([TTT settings](https://www.troubleinterroristtown.com/config/settings/)).
2. **The goal shape that fits identical roles best is a tug-of-war over one shared, visible meter.** Examples are Dale & Dawson's slackers "outperforming" the specialists and Secret Hitler's two policy tracks. A meter does not care who is outed. It turns every sabotage into visible progress, so playing the villain openly is a real way to win [A].
3. **That meter also answers the engineer's point-abuse worry, if the sabotage point and the meter are the same act.** An alien who sabotages for a point then pushes his own team toward losing. The abuse punishes itself, and no separate anti-farming rule is needed [A].
4. **Short matches get their shape from one scheduled midpoint and one telegraphed finale, plus a rule that a contest in progress at 0:00 is not cut off.** The evidence is Two Rooms' 3-2-1 minute rounds, DbD's 2-minute Endgame Collapse, Among Us Hide n Seek's Final Hide and TF2's overtime [V]. Behind it is the Konno and Fall Guys principle: "everyone in it until the end" [V].
5. **Side ratios cluster at about 1 in 4 to 1 in 3.** Host-set counts are best balanced by scaling the goal (thresholds, timer, number of sabotages), not the role. This fits the identical-roles rule [A].

## 2. Active goals for a minority side: a catalogue of goal shapes

Each shape below gets four parts: how it works in other games, why it works, what goes wrong, and how it maps to our game. The mapping always checks three of our constraints: identical roles, a human who may be outed early, and "play the villain openly" being fun.

### 2.1 Baseline: run out the clock (our current rule)

- **Evidence.**
  - Project Winter gives survivors 30 minutes to repair two objectives and call for help, so traitors win if that fails [V] ([Wikipedia](https://en.wikipedia.org/wiki/Project_Winter)).
  - Meccha Chameleon (released 9 June 2026) is a pure clock game: "The Seekers win if they find everyone within the time limit." Steam shows 90% positive of 43,927 reviews [V] ([Steam](https://store.steampowered.com/app/4704690/_/)).
  - TTT's default round is 10 minutes. Haste Mode replaces it with a 5-minute start, and every death adds 0.5 minutes [V] ([TTT settings](https://www.troubleinterroristtown.com/config/settings/)).
- **Why it works.** It is easy to explain, and it gives the majority side a reason to hurry [A].
- **What goes wrong.** The minority's best play is to hide and stall. TTT's own documentation calls Haste Mode the fix for this [V]. Fortnite reportedly cut endgame wait times in a July 2026 trial to stop players "stalling their way into the final circles" [S] ([Pocket Tactics](https://www.pockettactics.com/fortnite/storm-update), fetch refused). Meccha Chameleon works only because hiding is itself the skill, and in our game it is not [A].
- **Our game.** A timer win alone gives an outed human nothing to do except grief. Keep the timer as the backstop and add one shape below that is active [A].

### 2.2 The critical countdown: a crisis that wins if left unfixed

- **Evidence.**
  - In Among Us, the Impostors win by "sabotaging a critical system on the map (provided the Crewmates do not resolve it in time)". During a critical sabotage the emergency button is disabled [V] ([Wikipedia](https://en.wikipedia.org/wiki/Among_Us)).
  - Timers: Reactor and O2 on the Skeld are 30 s, both on MIRA HQ are 45 s, and the Polus seismic sabotage is 60 s. O2 needs two PIN pads in different rooms, and reporting a body resolves a critical sabotage [S] ([Among Us wiki](https://among-us.fandom.com/wiki/Guide:Sabotage), fetch refused).
  - Guides describe calling Reactor and waiting at the fix site to "double kill" whoever comes. They also say it fails against a long kill cooldown [S] (same page).
- **Why it works.** It is a telegraphed emergency that pulls the whole map toward one or two places. It is a short, loud moment of action, and the villain gets a real threat without needing cover [A].
- **What goes wrong.** An instant loss can feel cheap. Among Us softens it with a fix that needs two people and a body report that clears the crisis [S]. We have no meetings, so we would need another way out [A].
- **Our game.**
  - It works with identical roles if anyone can trigger a crisis but the payoff matches the win conditions: an unfixed crisis helps the humans' goal, so an alien who triggers one hurts his own side [A].
  - It works for an outed human, because triggering is fast and the crisis is fixed elsewhere, so being known does not stop him [A].
  - Prefer "a large hit to the shared meter" (2.3) over "instant win", so one missed crisis does not end a 10-minute match [A].

### 2.3 The tug-of-war meter or threshold (best fit)

- **Evidence.**
  - **Dale & Dawson Stationery Supplies** (30 August 2024). "Specialists perform positive tasks, while slackers perform negative tasks." Slackers win "if enough specialists are fired, or if they perform enough tasks to outperform the specialists" [V] ([Wikipedia](https://en.wikipedia.org/wiki/Dale_%26_Dawson_Stationery_Supplies)). Steam shows 88% positive of 4,596 reviews [V] ([Steam](https://store.steampowered.com/app/2920570/)). One player says hosts can tune slacker difficulty [P] ([thread](https://steamcommunity.com/app/2920570/discussions/0/4756452548787744731)).
  - **Secret Hitler.** Liberals win at 5 Liberal policies and Fascists at 6 Fascist policies, on two tracks fed by the same draws. Powers unlock as the Fascist track fills, and a veto unlocks after five [V] ([Wikipedia](https://en.wikipedia.org/wiki/Secret_Hitler)). Optional rebalancing for 6, 7 and 9 players changes the starting track or the deck [S] ([rules](https://secrethitler.io/rules)).
  - **GGD Pigeon:** wins by infecting every player [S] ([Twinfinite](https://twinfinite.net/guides/all-roles-goose-goose-duck/)). **Among Shadows** (unreleased): hidden players raise an "Infection Score" (Round 1).
- **Why it works.**
  - Both sides act on the same object, so the minority's work is as visible and as measurable as the majority's [A].
  - Exposure barely matters. A known slacker still moves the bar, and the majority must physically out-work him [A].
  - Secret Hitler adds escalation: each point on the villain's track makes the next one more dangerous [V].
- **What goes wrong.**
  - If one push and one pull are equal, a stalemate drags on [A].
  - If the meter is hidden, nobody feels the swing [A].
  - Dale & Dawson needs a firing mechanic on top, and our pillars reject voting [A].
- **Our game.**
  - We already have task progress shown per task ([GDD](../../GDD.md), lines 556-561). A party meter would add one total that both sides move [A].
  - **Self-correcting points.** Each sabotage earns its player one point, as decided. The same act also pushes the meter toward "party ruined", so an alien buying a mutation with a sabotage point is spending his team's lead [A]. This gives the engineer his balance against abuse without a special rule.
  - Placeholder rule: a sabotage moves the meter more than a completion does, so a "sabotage then let a friend complete it" combo nets the aliens negative progress [A]. Completed tasks are locked and each player earns only one point per task, as decided, so the combo cannot be repeated on the same task [A].
  - **The outed human.** Being known means more aliens guard tasks. But every task he sabotages still counts, and the meter shows all players he is winning. That is "play the villain openly" with a score [A].
  - It conflicts with one shipped rule: the GDD says "There is no shared total of every task's subtasks" (#738), so a visible total is a reversal for the engineer to decide [V] ([GDD](../../GDD.md), line 560).

### 2.4 Destroy the objective

- **Evidence.**
  - In Dread Hunger, an exposed Thrall is advised to switch to sabotaging the ship and shooting the nitroglycerin convoy (Round 1, [TheGamer](https://www.thegamer.com/dread-hunger-thrall-play-guide-winning-tips/)).
  - In DbD's current 2v8 mode there are 13 generators and 8 must be repaired. Killers damage generators so they regress at 200%, and repair speed *drops* by a stacking 5% per completed generator [V] ([DbD wiki](https://deadbydaylight.wiki.gg/wiki/2v8)). The DbD regression cap is in Round 1.
- **Why it works.** One physical target is easy to read ("defend that thing"). It makes standing guard a real choice for the majority, at the cost of their own task speed [A].
- **What goes wrong.** Camping a single objective: DbD needed caps against excessively long matches (Round 1) [V].
- **Our game.**
  - A destroy goal suits a known human, because a guarded target creates a rush scene [A].
  - Any damage needs a cap per object, plus a visible repair, so it cannot be farmed for points or griefed forever [A].
  - DbD's falling repair speed is worth noting as a pacing tool: the majority's last steps get slower, which keeps the end close [A].

### 2.5 Steal and escape (carry and positioning)

- **Evidence.**
  - Two Rooms and a Boom: Red wins "if the Bomber and the President are in the same room at the end" [V] ([rulebook](https://rulespal.com/two-rooms-and-a-boom/rulebook)).
  - First Class Trouble: residents must find the Personoids and "make it to the center of the ship". Personoids can win by "convinc[ing] the other Residents that they are part of the group long enough to reach the center" [S] ([Common Sense Media](https://www.commonsensemedia.org/game-reviews/first-class-trouble)).
  - R.E.P.O. (co-op, 2025): the team must fill a quota at each extraction point in turn before escaping to the truck [S] ([Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.)).
- **Why it works.** Positioning and carrying are macro skills, not aiming. A carrier is visible, slow and chaseable, which creates a comic chase [A].
- **What goes wrong.** If the carrier is known and the exit is fixed, a crowd blocks the exit [A].
- **Our game.**
  - We already have hand-held items, throwing, busy hands and a knockdown. A human could win part of the match by getting N party items out through known exits [A].
  - It works when outed (the chase is the fun), and throwing turns a pass between humans into a crazy moment [A].
  - Risk: it competes with the delivery chains for the same items and players. It also needs content (which items, which exits), which only the engineer can approve [A].

### 2.6 A ritual or build of their own

- **Evidence.**
  - GGD's Cuckoo plants eggs, and enough hatchlings start a hunt. Deceit 2's Terrors activate weak points, then transform in the In-Between (Round 1).
  - A Deceit 2 patch cut the weak-point activation delay from 5 s to 3 s [S] ([mp1st](https://mp1st.com/news/deceit-2-update-1-072-delivers-year-8-season-1/)).
  - One critic called Deceit 2's powers "lack lustre" (Round 1, [P]).
- **Why it works.** The villain has a progress bar of his own, and the majority can counter it by finding and smashing the parts [A].
- **What goes wrong.** It is a second task system to teach. If the payoff phase is weak, the whole build feels pointless (Deceit 2 [P]) [A].
- **Our game.** It overlaps with 2.3, which needs no new system. Keep it as a later map variant [A].

### 2.7 A contest over one shared object

- **Evidence.** In Halo Oddball, a player must hold the skull for two minutes in total across the match. The carrier cannot use weapons but has a strong melee [S] ([Halopedia](https://www.halopedia.org/Team_Oddball)).
- **Why it works.** One object makes the whole map readable, and the carrier gives up power for points [A].
- **What goes wrong.** With identical roles and hidden sides, a shared-object contest needs both sides to want the object for different ends. Otherwise it is just a team brawl [A].
- **Our game.** It could appear as a finale event: one object both sides race for, the aliens to place it and the humans to hide or destroy it. Better as a randomized event (2.8) than as the main win [A].

### 2.8 The last-chance flip and the mid-match twist

- **Evidence.**
  - Spyfall: at the deadline "the spy has one shot to guess the location" [S] ([MDA: Spyfall](https://mechanicsofmagic.com/2022/04/11/mda-spyfall/)).
  - The Chameleon: if the vote catches the Chameleon, it still wins by guessing the secret word [S] ([Wikipedia](https://en.wikipedia.org/wiki/The_Chameleon_(party_game))).
  - The Traitors TV end game: the game continues until everyone votes to end it, and any remaining Traitor takes the whole pot [S] ([Traitors wiki](https://thetraitors.fandom.com/wiki/End_Game)).
  - Mid-match twists: Overcooked 2's "dynamic levels" change the recipes halfway through [S] ([Push Square](https://pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games)). Mario Party's last-five-turns event lets the last-place player spin to add a rule (Mario Party 5) or gives him coins or a Star (DS) [S] ([MarioWiki](https://www.mariowiki.com/Mario_Party_5)).
- **Why it works.** A caught villain still has a real way to win, so "you found me" becomes a dramatic moment, not an ending [A].
- **What goes wrong.** If the flip is cheap, the majority's win feels stolen. If it is hard, nobody remembers it [A].
- **Our game.** A late flip suits a timer win: if the aliens finish their goal in the last stretch, the humans get a short counter-window. This is Round 1's Option D, so I do not repeat it [A].

### 2.9 What makes "play the villain openly" fun (across shapes)

- **Telegraph the threat.** Hide n Seek's danger meter fills as the seeker nears, "the louder the music gets!" [V] ([Innersloth](https://www.innersloth.com/new-game-mode-hide-n-seek-is-here-emergency-meeting-35/)).
- **Pay the open villain in progress, not cover.** Examples are the meter, the countdown and the carried item [A].
- **Give the victims a counter-window**, as the GGD hunts do (Round 1) [V].
- **An early design note from Among Us.** Innersloth's first concept had the ship "always in crisis while the crewmates attempted to hold it together", with Impostors who "could do tasks wrong". They cut it as "too stressful and didn't leave much time for detective work" [V] ([Nintendo](https://nintendo.com/whatsnew/among-us-dev-recounts-how-the-game-took-flight)). Our pillars drop deduction, so this rejected concept is close to what we want. Its stress risk is real, and the fix is pacing (§3) [A].

## 3. Pacing a short match

### 3.1 Evidence from short-round games

| Game | Length and structure | Pacing mechanism | Tag |
|---|---|---|---|
| Two Rooms and a Boom | Rounds of 3, 2, then 1 minute | A clock that shortens per round. Hostage counts scale with players (1 per round at 6 to 10) | [V] [rulebook](https://rulespal.com/two-rooms-and-a-boom/rulebook) |
| TTT Haste | 5 min start, +30 s per death (the non-haste default is 10 min) | The clock is driven by the action, and stalling shortens the round | [V] [settings](https://www.troubleinterroristtown.com/config/settings/) |
| DbD Endgame Collapse | 2 min, half speed while a survivor is dying, hooked or caged, so at most 4 min. A bell at each quarter | A telegraphed finale clock that bends with the action | [V] [wiki](https://deadbydaylight.wiki.gg/wiki/Endgame_Collapse) |
| Among Us Hide n Seek | Tasks make the timer go down faster. Final Hide: the Impostor gets "a power boost, special Seek map, and a directional ping" | The majority speeds up the clock, and the end has a power spike | [V] [Innersloth](https://www.innersloth.com/new-game-mode-hide-n-seek-is-here-emergency-meeting-35/) |
| LOCKDOWN Protocol | 8-minute round, "balanced for 5-8 players" | The length is fixed. Out of Early Access since 18 Nov 2025, 82% positive of 9,504 reviews | [V] Round 1, [Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/) |
| Splatoon Turf War | 3 min, and the last minute switches to its own track ("Now or Never!") | An audio phase change. Only the final ink counts | [S] [Splatoon wiki](https://splatoonwiki.org/wiki/Clickbait) |
| Overcooked | A timer replaced the lives system "to make sure there was panic there". More tasks than people. Levels "disrupt the players" | Panic by design, plus mid-level disruption | [V] [MCV postmortem](https://mcvuk.com/the-develop-post-mortem-overcooked/) |
| Lethal Company | A day of about 11 min (08:00 to midnight). Danger rises at about 15:00. The ship leaves at midnight | Rising danger plus a hard leave time | [S] [Orbis](https://orbispatches.com/gaming-faq/how-long-is-a-day-in-lethal-company), [P] [Steam thread](https://steamcommunity.com/app/1966720/discussions/0/3978428732561802183) |
| PEAK | Biomes separated by campfires. Fog creeps in on higher Ascents if the team is slow | Checkpoints plus a pursuing threat | [S] [PEAK wiki](https://peak.wiki.gg/wiki/Peak_(game)) |
| R.E.P.O. | Quota per extraction point, filled one after another, with no level timer | Sub-goals mark the match's progress | [S] [Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.) |
| MIMESIS | A June 2026 update replaced its three-day cycle with "a more flexible structure" to "reduce predictability" | Fixed schedules get stale on repeat play | [V] [Game Developer](https://www.gamedeveloper.com/press-release/mimesis-major-update-makes-its-ai-driven-monster-more-unpredictable) |
| Jackbox | 15 to 20 min sessions. Comebacks come from "increasing the point value ... as the game progresses" or "penalizing the current leader". Quiplash's last round reportedly triples points | Late rounds weigh more | [V] [Jason Shen](https://www.jasonshen.com/2020/the-product-genius-behind-jackbox-games/), [S] [Giant Bomb](https://www.giantbomb.com/quiplash/3030-50183/) |
| TF2 overtime | The match continues while a point is partly captured or the cart is not rolling back. It gives "a brief window to win or extend the game with a last-second push" | A contest in progress at 0:00 is not cut off | [V] [TF2 wiki](https://wiki.teamfortress.com/wiki/Overtime) |
| Overwatch overtime | No limit to how often overtime triggers. In 2016 the fuse was set to deplete much faster after 20 s | An overtime that cannot be stretched forever | [S] [Icy Veins](https://www.icy-veins.com/overwatch/overwatch-payload-escort-game-mode-guide) |
| Rocket League | 5 min, then the next goal wins. Reportedly the clock does not end while the ball is in the air | Sudden death | [S] [ExpertBeacon](https://expertbeacon.com/how-long-do-rocket-league-games-last/) |

### 3.2 Designer principles that apply

- **Fall Guys** (Max Boyle): "80% skill and 20% chaos". The pillar "It's Only Over When It's Over" is about "am I going to make it?!" moments. "Qualification should always feel like it's within reach!" and "Failure should feel fair and deserved." [V] ([Mediatonic](https://mediatonicgames.com/blog/behind-the-beans-the-story-of-snowball-survival))
- **Mario Kart** (Hideki Konno): "We wanted to create a race where everyone was in it until the end." [V] ([Kotaku](https://kotaku.com/the-maker-of-mario-kart-justifies-the-blue-shell-5780082))
- **Left 4 Dead.** Booth's GDC 2009 slides list "Generate Dramatic Game Pacing" as an AI goal, and the Director creates highs and lows of drama [S] ([slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf), not machine-readable here). I could not verify the commonly cited phase names (build-up, sustain peak, peak fade, relax) [A].

### 3.3 Mapping to a 10-minute match (placeholders)

| Window | Purpose | Mechanism |
|---|---|---|
| 0:00 to 0:20 | "Fun from the first second" | No setup phase. The first task is a few steps from every spawn |
| 0:20 to about 4:30 | Opening | Points flow and the first mutations get bought. The meter swings |
| About 4:30 to 5:30 | Midpoint event | One event, announced and drawn at random from a small deck (randomness pillar). Both sides can use it |
| About 8:00 to 10:00 | Finale | Music and HUD change. Both sides get a power spike, for example meter swings ×1.5. Respawns get shorter |
| 10:00 | Overtime | If a task or a crisis is mid-progress, play continues while someone keeps working it, up to a hard cap (for example +30 s) |

- **The cost of the 30 s respawn changes over the match [A].** 30 s is 5% of a 10-minute match but 25% of a 2-minute finale. A death at 9:31 removes the player from the result, which breaks "never boring". DbD bends the clock while a survivor is down [V]. We could instead shorten the respawn wait in the finale (placeholder 15 s). That modifies the decided 30 s rule, so it is an engineer decision. It stays within "no wait that grows per death".
- **A fixed schedule gets stale with repetition** (MIMESIS [V]). Randomize the *content* of the midpoint event, not its existence or its time [A].

## 4. Side ratios per player count (4 to 10) and host-set counts

| Players | Among Us minimum to allow N impostors [S] | TTT 25%, rounded down [V] | Secret Hitler fascists incl. Hitler [V] | BotC evil, where verified [S] | Project Winter [S] |
|---|---|---|---|---|---|
| 4 | 1 | 1 | – | – | – |
| 5 | 1 | 1 | 2 | – | 1 |
| 6 | 1 | 1 | 2 | – | 2 |
| 7 | 2 allowed | 1 | 3 | 2 | 2 |
| 8 | 2 | 2 | 3 | – | 2 |
| 9 | 3 allowed | 2 | 4 | – | 2 |
| 10 | 3 | 2 | 4 | 3 | 2 |

Sources:
- Among Us: the wiki's "outdated" screenshot page, with 1 impostor needing at least 4 players, 2 needing 7 and 3 needing 9 ([wiki](https://among-us.fandom.com/wiki/File:Options_screenshot_outdated.png)).
- TTT: [settings](https://www.troubleinterroristtown.com/config/settings/). The detective role starts at 10 players.
- Secret Hitler: [strategy guide table](https://secrethitler.tartanllama.xyz/).
- BotC rows: [forum game](https://forum.quartertothree.com/t/blood-on-the-clocktower-game-2-complete/148371). The official setup page does not print the table [V] ([BotC Setup](https://wiki.bloodontheclocktower.com/Setup)).
- Project Winter: [forum post](https://steamcommunity.com/app/774861/discussions/0/1640915206445238977).
- Avalon and Mafia ratios: see Round 1.

**Balance data and levers:**
- **Among Us.** Early opt-in data had Impostors winning 8,011 of 15,057 games (about 53%). 4- and 5-player games were about 61% of games [V] ([Innersloth](https://www.innersloth.com/the-data-among-us/)). These are early 2018 numbers. Small lobbies dominated, so the 4-player balance matters most [A].
- **Werwölfe** (the German Werewolf edition) gives every role a value: werewolf −6, seer +7, villager +1. The values should sum to about 0, with −1 to −3 for experienced groups and +1 to +3 for new ones [V] ([rulebook](https://rulespal.com/werwolfe/rulebook)). A lobby could show such a "balance hint" for the host's chosen count [A].
- **Secret Hitler** offers optional handicaps for 6, 7 and 9 players: a pre-placed policy or a smaller deck [S].
- **TTT** combines a percentage with a cap (`ttt_traitor_max`) [V].
- **DbD 2v8** scales the objective, not the killers: 13 generators with 8 needed, and auras shown only within 64 m [V] ([wiki](https://deadbydaylight.wiki.gg/wiki/2v8)).
- **Overcooked** reportedly scales its star thresholds with player count [S] ([Steam thread](https://steamcommunity.com/app/728880/discussions/0/1696049513785405064)).

**Our game [A].** Roles are identical, so a human is no stronger than an alien. His power is only his goal. Scale the goal to the humans' share h / N: the meter's ruin threshold, the number of crises allowed, and possibly the timer. The host's exact count then stays meaningful without turning extreme counts into broken matches. Placeholder default counts: 4→1, 5→1, 6→2, 7→2, 8→2, 9→3, 10→3, close to the 1-in-4 to 1-in-3 band.

## 5. Cross-game patterns

1. **The minority needs a progress bar of its own, or a shared one it can push.** This appears in Dale & Dawson, Secret Hitler, the GGD Pigeon and Among Shadows [V/S]. A timer-only win invites stalling (TTT, Fortnite) [V/S].
2. **Emergencies pull everyone together and are short.** Critical sabotages last 30 to 60 s [S], and DbD's finale is 2 min, bending to at most 4 [V].
3. **Matches have a named last phase:** Final Hide, Endgame Collapse, a last-minute music track, the 1-minute round [V/S].
4. **A contest in progress at 0:00 is honored but capped.** Examples are TF2, Overwatch's faster fuse and Rocket League [V/S].
5. **Comebacks come from late weighting** (Jackbox, Mario Party) **or from slowing the leader's last steps** (DbD 2v8's −5% per generator) [V/S].
6. **The design goal is to keep everyone in it until the end** (Konno, Fall Guys) [V].
7. **Balance by player count is done on the objective or on the counts table, rarely on role power** (DbD 2v8, Secret Hitler, TTT) [V].

## 6. Risks for our design

1. **Point farming (the engineer's concern).** If sabotage points are free for aliens, aliens will sabotage just to buy mutations. Fix: tie the point and the meter to the same act, so farming costs the farmer's own team (2.3) [A].
2. **An outed human in a respawn loop.** Our 30 s respawn into random capsules does not stop a crowd guarding every task he approaches. The goal must have reach he can use while known: crises, remote acts, carried items [A].
3. **Instant-win crises feel cheap in a 10-minute match.** Among Us's protections (a two-person fix, a body report) do not exist here. Prefer a meter hit [A].
4. **The finale and respawns.** A late death decides more than an early one. Without an adjusted respawn, the finale is when players sit out [A].
5. **Stress.** Innersloth cut "always in crisis" as too stressful [V]. A meter that swings constantly with every action may feel the same. Calm opening minutes and one peak per phase help [A].
6. **The finale's strength.** Too weak and it is the Deceit 2 problem [P]. Too strong and it erases the first 8 minutes [A].
7. **Scaling to 4 players.** At 4 players with 1 human, every alien death matters, and the human may win by one crisis. Thresholds must be checked at 4 and at 10 separately [A].
8. **Complexity versus "fun from the first second."** Stacking a meter, crises, carries and events is too much for a first map. One active goal plus pacing is enough [A].
9. **Conflict with a shipped rule.** A visible total reverses #738 [V] ([GDD](../../GDD.md), line 560).
10. **Mutation snowball.** Points buy power, power wins more points. The meter's "sabotage costs more than completion" weighting interacts with this, and it needs a playtest [A].

## 7. Options for the engineer to decide

All numbers are placeholders. These are options, not decisions.

**Option 1: a shared party meter (tug-of-war).**
- Mechanism:
  - One visible meter. Every completed subtask pushes it up, every sabotage pushes it down by more (placeholder: sabotage −2, completion +1).
  - The aliens win by finishing their goal. The humans win if the meter falls to a floor (the party is ruined) or when the timer ends with the goal unfinished, as now.
  - One point per task, either for completing or for sabotaging, as decided.
- Trade-offs:
  - For: an active human goal that works when he is outed; self-correcting against point farming; open knowledge.
  - Against: reverses #738 (no shared total); risk of constant swings; the weights need playtests at 4 and 10 players.

**Option 2: crises (a short countdown at one or two known places).**
- Mechanism:
  - Any player may trigger a crisis at a fixed station, a limited number of times per match (placeholder: humans + 1).
  - Two players at two places must fix it within a countdown (placeholder 40 s). Unfixed, it is a large meter hit, not an instant win.
  - The trigger earns no point, so it cannot be farmed.
- Trade-offs:
  - For: loud, short action moments, and reach for an outed human.
  - Against: new stations are content (the engineer's word is needed); a crisis triggered by an alien must cost the aliens, or it becomes griefing.
- Works best on top of Option 1.

**Option 3: a finale phase plus a capped overtime.**
- Mechanism:
  - From 8:00 (placeholder) the finale starts: a music change and both sides' meter actions ×1.5. Respawn shortens to 15 s, which modifies the decided 30 s.
  - At 0:00, if a task or a crisis is in progress, play continues while someone keeps working it, up to +30 s.
- Trade-offs:
  - For: a climax every match; fixes the late-death problem; "only over when it's over".
  - Against: changes a decided number; overtime makes 10 minutes a soft target.

**Option 4: a midpoint event from a small random deck.**
- Mechanism: at about 5:00 (placeholder), one announced event drawn from 3 to 5 options. Each changes one rule for the rest of the match and helps either side.
- Trade-offs:
  - For: the randomness pillar; replay variety (the MIMESIS lesson).
  - Against: each event is content (names and rules come from the engineer); the deck needs balance per event.

**Option 5: smuggle-out goal (per map, later).**
- Mechanism: humans earn meter damage or a win by carrying party items through known exits. Uses the existing items, throwing and knockdown.
- Trade-offs:
  - For: macro skill and comic chases.
  - Against: competes with delivery chains; content-heavy.
- Better as a second map's twist.

**Option 6: goal scaling for host-set counts.**
- Mechanism: the ruin floor, the number of crises and the finale's multiplier scale with h / N. The lobby shows the recommended band and a neutral "balance hint" for the chosen count, like the Werwölfe sum.
- Trade-offs:
  - For: keeps the host's exact choice meaningful.
  - Against: the formulas need playtests; hidden scaling may feel opaque, so show it.

**Recommendation.** Prototype Options 1 + 3 + 6 together. Option 1 is the only one that is an active human goal, fits identical roles and an early outing, and answers the point-abuse worry by its own structure. Option 3 gives every 10 minutes a shape and protects "never boring" at the end. Option 6 is needed as soon as the host sets the counts. Add Option 2 once the meter works. Hold Options 4 and 5 for content work after the first playtest.

## 8. Open questions for the engineer

1. Is a visible shared total acceptable, reversing #738, or should the meter show only a coarse mood, for example three states?
2. Should a sabotage cost the meter more than a completion adds, and if so, by how much (as a first playtest value)?
3. Is the humans' active win a meter floor, a crisis, a carry goal, or the timer only plus pacing?
4. May the 30 s respawn shorten in a finale, or is 30 s fixed for the whole match?
5. Is "10 minutes" a hard length, or may a capped overtime extend it?
6. Should the meter be fed per subtask or only per completed task (the point rule is per task)?
7. Can an alien trigger a crisis at all, and if yes, what does it cost him?
8. What are the default human counts for 4 to 10 players, and may the host go outside the recommended band?
9. Should the goal scale with the humans' share automatically, and should the lobby show the scaling?
10. Does a midpoint event belong to this map, or to later party maps?

## 9. What I could not verify

- The exact Among Us critical sabotage timers and the Airship crash timer (the wiki refused the fetch).
- The exact win rules and day structure of LOCKDOWN Protocol and Cursed Companions.
- The L4D Director's phase names (the PDF was not readable).
- The Fortnite July 2026 storm change (the page refused the fetch).
- Lethal Company's day length and danger time (guides and players only).
- PEAK's fog rule (wiki via search only).
- Project Winter's traitor airdrop timer and its current traitor counts.
- Quiplash's final-round multiplier.
- BotC's full counts table (only some rows found).
- Meccha Chameleon's round timers and what happens to found hiders.
- Dale & Dawson's exact slacker thresholds.