# Sabotage design and a point economy that can't be farmed when roles are identical

## 0. Scope, tags and verification

This report builds on round 1's [in-match economy report](2026-10-15-in-match-economy.md). It does not repeat that report's shooter, MOBA, bounty or "wallhack" material. Round 1 left this question open (its §9 risk 3 and §11 question 1): if anyone may sabotage, how do you stop "sabotage, then complete" farming? This report answers it with mechanisms and models of how players would exploit each rule.

**Tags:**
- **[V]** verified on a page I fetched on 2026-10-15.
- **[V-s]** taken only from a search-engine summary. Fandom, among-us, Phasmophobia, Project Winter, Goose Goose Duck and Barotrauma wiki pages returned 402, 403 or 401, and Steam news pages render empty.
- **[P]** a player's or critic's opinion.
- **[A]** my analysis.

All numbers in the proposals are **placeholders**.

**What I could not verify:**
- Goose Goose Duck sabotage timers and cooldowns.
- Lockdown Protocol's exact dissident actions (official notes list none, see §1.4).
- Dread Hunger's live values (the game is delisted).
- Overcooked's fire-spread timer.
- The current Among Us sabotage cooldowns. Sources conflict between 10 s and 30 s.

**Terminology in the repo.** `docs/GDD.md` §10 still says "Engineers win only by finishing every task before the timer ends; the dissidents win when the timer ends with a task left". I read engineers as the aliens and dissidents as the humans. The GDD's per-task sabotage notes (Delivery "the dissidents sabotage by hiding items"; Cooking "a dissident may take a box and hide it") are what I map against below.

---

## 1. A taxonomy of sabotage

### 1.1 Per-task sabotage: a station, an item or a step

**Dead by Daylight's generator regression is the clearest numeric model.**
- A generator needs 90 charges, about 90 s for one survivor. Each extra survivor on it cuts every repairer's speed by 15%. A regressing generator loses 0.25 c/s [V] ([wiki.gg](https://deadbydaylight.wiki.gg/wiki/Generators)).
- A kick takes 1.8 s and removes 5% at once. Survivors must repair at least 5% to stop regression [V] (same page).
- Patch 7.5.0 (January 2024) capped each generator at **8 regression events**, an event being any killer-caused instant loss of at least 2.5%. The patch named the reason: "The 3-gen strategy (identifying the closest 3 Generators and defending only them) has become very strong." It also added "increasing VFX after 3 or more regression events" and removed "gen tapping" (a one-second touch to stop regression) by requiring the 5% repair [V] ([EIP](https://eip.gg/dbd/news/patch-7-5-0-alan-wake-available/)).
- Failed skill checks still regress generators and do not count toward the cap [V] (wiki.gg).

**Why it works [A].**
- Sabotage removes real, visible progress, so the repairer feels the loss.
- The cap bounds the stall, so "defend one objective forever" stops working.
- The VFX telegraphs how close an objective is to being safe.
- The 5% minimum kills token play from both sides.

**What went wrong [V].** Before the cap, a stalling strategy produced "very long games and frustration". This is our biggest structural risk (§3): the humans win by the clock, so stalling one task wins the match.

**Among Us began as all per-task sabotage.** Forest Willard: "Originally, the ship was always in crisis while the crewmates attempted to hold it together," and "Impostors could do tasks wrong to hinder players." It was dropped because "this was too stressful and didn't leave much time for detective work" [V] ([Nintendo](https://nintendo.com/whatsnew/among-us-dev-recounts-how-the-game-took-flight)).

[A] Our pillars invert theirs. We do not need room for detective work, so a constant low-level crisis is closer to what we want, as long as it is not stressful in a bad way. The fix is short and comedic, not rare.

**Project Winter pays sabotage as power, not points.**
- Traitors "gain physical Stat Buffs from trapping objects or objectives and sabotaging objectives" [V] ([Power Balance Vol 2](https://nintendoeverything.com/project-winter-power-balance-vol-2-update-out-now-patch-notes/)).
- A later patch added a buff "when sabotaging the objective with a delay". The same patch let the cabin radio be sabotaged at any time, because the late-only rule "often does not leave enough time for Traitors to make a move" [V] ([Up To Snow Good](https://nintendoeverything.com/project-winter-up-to-snow-good-update-out-now-patch-notes/)).
- [A] The delayed sabotage is the interesting part. It splits the act from the effect, which lets the saboteur walk away from the scene.

**Dread Hunger.**
- Thralls win if every explorer dies or the ship sinks. Sabotage includes stealing and dumping coal, crafting gunpowder (two per coal), and a Bomb Ship spell that makes 3, 6 or 9 hull holes by tier, each repaired with planks and nails [V-s] ([wiki](https://dread-hunger.fandom.com/wiki/Beginner_Thrall_Guide_by_Raven)).
- Its totems (1 bone and 3 wood) have diminishing returns from about the sixth [V-s] (same).
- [A] Sabotage here creates repair work in many places, a "chores" cost that the crew pays with time and materials.

### 1.2 Global sabotage: the whole map

**Among Us** is the reference implementation:
- **Critical sabotages kill unless fixed** [V-s] ([wiki via search](https://among-us.fandom.com/wiki/Reactor_Meltdown)):
  - Reactor: 30 s on the Skeld, 45 s on MIRA HQ, 60 s on the Fungle.
  - Seismic stabilizers on Polus: 60 s, two players at opposite stations.
  - Crash course on the Airship: 90 s.
- **Lights.** The panel flips 1 to 5 of its 5 switches off. Any living player can fix it, toggles from different players stack, Impostors can flip switches back off, and Impostor vision is unaffected [V-s] ([search of wiki and guides](https://among-us.fandom.com/wiki/Fix_Lights)).
- **Cooldowns.** About 30 s for the majors. A major sabotage puts all sabotages on cooldown, doors included, and the cooldown starts only after the problem is fixed. Doors lock for about 10 s and can be chained individually [V-s] ([GameWith via search](https://gamewith.net/among-us-wiki/article/show/22107)). One guide gives 10 s for the majors, which conflicts with this, so treat the number as unverified.
- **The Fungle's Mushroom Mixup** cannot be repaired and simply expires. Fan wikis say about 10 s; Innersloth says only "a limited amount of time" [V-s] ([Innersloth](https://innersloth.com/new-map-the-fungle-out-now-emergency-meeting-38)).
- [A] Four useful patterns:
  1. A shared cooldown that starts after the fix, so sabotages cannot be chained.
  2. Repair at known, fixed places, which is open knowledge.
  3. Two-person repairs at stations far apart, which forces the crew to split.
  4. A purely comedic sabotage that just expires (Mixup). It needs no repair loop at all.

**Goose Goose Duck.** A 2021 map guide lists Lights, Reactor, Doors, Communications and Life Support, each tied to a room [V-s] ([steamah](https://steamah.com/goose-goose-duck-maps-guide/)). The goose Engineer role "can temporarily see in the mini-map where living ducks called sabotages come from" [V-s] ([Prima](https://primagames.com/gaming/goose-goose-duck-roles-explained)). [A] That is a trace on the saboteur sold as a role power. Our roles are identical, so it could be a mutation instead.

**Phasmophobia: an AI's global events, telegraphed and on a cooldown.**
- A hunt has a minimum 25 s cooldown before the next (20 s for the Demon). A smudge delays hunts for 90 s (180 s for one ghost type) [V-s] ([wiki via search](https://phasmophobia.fandom.com/wiki/Hunt)).
- During a hunt, lights flicker within 10 m and electronics fail within 10 m [V-s] (same).
- A Steam post lists a hunt-start grace of 5, 4, 3 and 2 s by difficulty [P] ([thread](https://steamcommunity.com/app/739630/discussions/0/3767859448794495193)).
- [A] The players get a warning (flicker), a counter-item (smudge), a hiding window (grace) and a guaranteed rest (cooldown). That is "randomness with a chance to react" in its purest form.

**Deceit (2017).** Three power-outage phases follow 90 s intermissions. Players carry fuses to fuse boxes to restore light and unlock the next area, and the infected can transform only in the dark [V] ([Game Developer](https://www.gamedeveloper.com/design/deceit-core-systems-analysis)). [A] Here the global sabotage is a scheduled phase, not a player action. That fits "fun from the first second" better than waiting for someone to trigger it.

**Lethal Company: a greedy act that is a global sabotage.** Pulling the Apparatus, worth 80 credits, cuts the facility's power, opens the secure doors for good, and by some accounts spawns enemies [V-s] ([Prima](https://primagames.com/tips/how-much-is-the-apparatus-worth-in-lethal-company-answered), [Dot Esports](https://dotesports.com/general/news/should-you-remove-the-apparatus-in-lethal-company-answered)). [A] One player's reward costs the whole team. The comedy is the panic run in the dark.

### 1.3 Chaos without a saboteur: Overcooked

- Ghost Town Games built Overcooked 2's levels around a single element (separation, a pinch point), with recipes that change mid-level, moving ingredients and rats stealing food. They talk about "the balance between freedom and restriction" [V] ([Red Bull](https://www.redbull.com/int-en/overcooked-2-ghost-town-games-interview), [Push Square](https://pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games)).
- Fire spreads from food left on heat, and the fix is the extinguisher [V-s] ([TrueAchievements](https://www.trueachievements.com/game/Overcooked/walkthrough/2)).
- Tips multiply on combos, capped at 4x per a 2018 player post [P] ([Steam](https://steamcommunity.com/app/728880/discussions/0/1745594817440770927)).
- [A] Overcooked's sabotage is the environment plus your own fumbles. Our Cooking chain is already "in the spirit of Overcooked" (GDD §8), so the House can generate sabotage-like accidents that pay nobody.

### 1.4 Games from 2024 to 2026, checked live

- **LOCKDOWN Protocol** (early access 2024-07-22, 1.0 on 2025-11-18, 82% of 9,504 reviews positive) [V] ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)). I read the official news feed through 1.5.0 (2026-05-31) [V] ([Steam API](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=2780980&count=40&maxlength=4000)):
  - It contains **no global sabotage at all**. It lists "Added alarms", "Alarms can now be disabled, with 2 fuses" (0.13.0), defibrillators, "locked door, that need access card", and fragile items that "break on impact" (1.3.0).
  - Its one revealing fix: "Fixed the unintended ability to make 'dummy' samples from rice containers in the sample machine" (1.0.0). [A] A fake-progress item is exactly the token-sabotage and fake-completion loophole we must close.
  - Third-party summaries say dissidents "sabotage equipment" and remove key items [V-s] ([vaporlens](https://vaporlens.app/app/2780980/lockdown_protocol.md)). Players asked for "a perceived need for more distinct sabotage mechanics" [P] (same).
  - A fan mod adds a blackout that ends when one player dies or two batteries go into the defibrillator [V] ([Nexus](https://www.nexusmods.com/lockdownprotocol/mods/67)).
- **Dale & Dawson Stationery Supplies** (2024-08-30, 88% of 4,596 reviews positive) [V] ([Steam](https://store.steampowered.com/app/2920570/)).
  - Slackers win "by completing enough tasks to outpace the specialists", so there are two parallel tallies, not a veto [V] ([Wikipedia](https://en.wikipedia.org/wiki/Dale_%26_Dawson_Stationery_Supplies)).
  - A fan guide says the "Slacking tasks" go to both roles, which gives everyone cover [V-s] ([grindnstrat](https://grindnstrat.com/?p=660)).
- **The Outlast Trials, Invasion** (2025-10-21) [V] ([TheSixthAxis](https://www.thesixthaxis.com/2025/10/21/the-outlast-trials-pvp-invasion-mode-is-out-now-just-in-time-for-halloween/)):
  - Imposters invade for a limited time and must return to a gate or be electrocuted.
  - Dying brings "a time penalty on the next spawn".
  - Players waiting for their turn ping targets as the Imposters' "eyes and ears".
  - [A] Waiting players get a job, which is our "never boring" rule.
- **Hide and Sheep** (March 2026). Everyone is a hidden hunter among AI sheep, with no tasks [V] ([Game Rant](https://gamerant.com/steam-games-like-among-us-hide-and-sheep/)). [A] This is evidence that the genre is moving away from meetings toward physical play.
- **Among Us 17.0.0** (September 2025) added Detective and Viper and no new sabotage [V-s] ([Nintendo Life](https://www.nintendolife.com/news/2025/09/among-us-latest-update-adds-two-new-roles)).

---

## 2. Scoring that cannot be farmed

### 2.1 How games attribute credit

| Mechanism | Example | Evidence |
|---|---|---|
| Credit at a progress threshold, not the full act | Battlefield 2142 1.20: "Heal and repair points awarded after a 50% heal / repair instead of 100%" | [V] [SweClockers](https://www.sweclockers.com/forum/post/7187535) |
| A named fix for farming | Battlefield 2 1.03: "game will stop Support/Medic/Engineer point farming exploits" | [V] [Shacknews](https://www.shacknews.com/article/37897/battlefield-2-patch-plans) |
| A server-level cut | Battlefield 6 (October 2025): "XP farm" servers earn almost nothing; normal completion XP raised 10% | [V] [GosuGamers](https://www.gosugamers.net/entertainment/news/77501-battlefield-6-cracks-down-on-xp-farming-servers-ahead-of-season-1-launch) |
| Diminishing returns on repeats | WoW Classic: honor falls 10% per repeated kill of the same player | [V-s] [Engadget](https://www.engadget.com/2006-08-08-doing-the-math-on-the-new-honor-kill-decay-rate.html) |
| A cap per category | Dead by Daylight: each of 4 score categories capped at 10,000 per trial | [V] [wiki.gg](https://deadbydaylight.wiki.gg/wiki/Bloodpoints) |
| Holder attribution with a grace window | R.E.P.O. host mod: damage goes to the current holder or the holder within 3.0 s; unowned loss ignored | [V] [Thunderstore](https://thunderstore.io/c/repo/p/REPO_JP/AntiValuableGrief/) |
| A team-wide award at a team threshold | TTT: every living traitor gets a credit when 35% of innocents have died | [V] (round 1 report, TTT source) |
| A penalty scaled to harm | TTT karma: hurting your own side costs `victim_karma × dmg × 0.001`; low karma scales damage down; a clean round pays +30 | [V] [karma.lua](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/terrortown/gamemode/karma.lua) |
| Credit only on success | Barotrauma traitors "steal" a share (for example 10%) of mission XP, only if not correctly accused. A wrong accusation fines the crew. Players who haven't been traitor recently are picked more often | [V-s] [wiki](https://barotraumagame.com/wiki/Traitors) |
| A finisher bonus plus a shared payout | Saboteur: the player who completes the path picks first; each miner keeps one card | [V-s] [Wikipedia](https://en.wikipedia.org/wiki/Saboteur_(card_game)) |
| Payout scaled by minority size | Saboteur: one saboteur takes 4 gold, 2 or 3 take 3 each, 4 take 2 each | [V-s] (same, via search) |

### 2.2 Board games: sabotage as hidden contributions

- **Battlestar Galactica.** Players add skill cards face down. Off-colour cards subtract, and two random Destiny cards join the pile, so "it's possible that a random card... caused the check to fail" [V-s] ([Uppsala analysis](https://babel.speldesign.uu.se/?p=6179)).
- **Dead of Winter.** Crisis contributions are face down and shuffled. A non-matching card subtracts 1 [V-s] ([rules](https://media.plaidhatgames.com/old_images/games/dead-of-winter/rules.pdf)).
- **The Resistance.** One Fail card sinks a mission, but mission 4 in games of 7 or more needs two [V-s] ([Wikipedia](https://en.wikipedia.org/wiki/The_Resistance_(game))).
- **Secret Hitler.** An 11-to-6 deck means a bad outcome is often just luck [V-s] ([rules](https://secrethitler.io/rules)).
- **Semi-cooperative games.** A player who cannot win has a reason to sink the table, the "kingmaker" and threat problem [P] ([Man O' Kent](https://www.manokentgames.com/single-post/the-philosophy-of-game-design-the-ontology-of-victory), [There Will Be Games](https://www.therewillbe.games/component/tags/tag/articles?start=60)).

[A] The board-game lessons:
1. **Random noise** makes a fail funny instead of an accusation (the randomness pillar).
2. **Thresholds that rise with player count** stop one saboteur dominating a large table and keep a small table winnable.
3. **Payouts scaled to minority size** fit our host-set human count.
4. **Do not let a capped-out player's best move become sinking the game.**

### 2.3 Modelling the exploits against our rule

The rule as given: per task, each player earns one point, for completing or for sabotaging it, never both; aliens may sabotage. Three things are still undefined:
- **(i) What "task" means:** the whole chain (Cooking) or one subtask (one burger).
- **(ii) Who "completes":** the finisher only, or every contributor.
- **(iii) What counts as "a sabotage".**

The exploits hinge on these three.

**[A] Key result.** The per-player cap already stops unbounded farming. Each player can hold at most *T* points, where *T* is the number of tasks (or subtasks). The risk is not infinite points. The real risks are:
- **(a)** free points from token sabotage;
- **(b)** a sabotage incentive created by narrow completion credit;
- **(c)** unlimited stalling, which wins outright for the humans and has nothing to do with points.

**Exploit E1: token sabotage (both sides).** An alien flips a Generator switch off and on in one second. The GDD says a switch toggles "as often as anyone likes, with no cooldown" (§8 Generator). If that pays, every player banks a point per task at zero cost. The same goes for putting a wrong ingredient on a plate: it turns red and can be taken back (Cooking). This is Lockdown's "dummy samples" and DbD's "gen tapping".
- **Fix:** credit a sabotage only after it has cost the other side real time (Option A).

**Exploit E2: narrow completion credit pushes everyone to sabotage.** Suppose only the player who presses the last E gets the completion point:
- The Generator has 2 to 4 switch-flippers plus a button-presser.
- Photo needs a sitter and a shooter.
- Car repair needs a holder and a fitter.

All but one contributor earn nothing, so their only route to that task's point is to sabotage it. Self-interest then sabotages every chain, aliens included.
- **Fix:** broad completion credit (Option B).

**Exploit E3: the pair swap (aliens).** Alien A sabotages, alien B repairs and completes; on the next task they swap. Under broad credit plus "never both", A gave up his completion point to take a sabotage point. His net is zero, and the team lost time. The swap only pays an alien who could not have earned the completion anyway.
- [A] Broad credit makes alien sabotage profitable only for latecomers. That cost is real, so the dilemma stays a real choice. Whether a latecomer can still join late steps is a tuning question.

**Exploit E4: the early harvest (humans).** At 0:30 a human "sabotages" all five chains while there is nothing to break: switches start off, no film is shot, no patty is on the grill. That is 5 points and a mutation spree by minute two.
- **Fix:** a sabotage pays only if it removes existing progress or blocks a ready step (Option A).

**Exploit E5: the stall (humans).** The aliens must finish every task, so humans need one chain unfinished at the bell. That is DbD's 3-gen problem: one human, or a guard, re-sabotaging one task forever.
- **Fix:** a per-task cap (Option C) plus diminishing harm.

**Exploit E6: a global sabotage as a point pump.** If global sabotages are bought with points and repairing them pays points, a human's purchase becomes alien income, and aliens may even trigger global sabotages to farm repairs.
- **Fix:** global sabotages are bought, pay nobody, and their repair pays nobody (Option D).

**Exploit E7: accidents as credit.** A burnt patty, a car dropped because the holder was clumsy, a film full of empty frames. If accidents pay, the clumsy are paid for being clumsy, and "accidents" become deniable farming.
- **Fix:** accidents pay nothing. Only deliberate acts that cross Option A's threshold pay. Under the cap, the residual risk is small.

**Exploit E8: the outed human is starved.** Aliens body-block stations and refuse to fit the car with him.
- **Fix:** trust-free sabotages that work alone or at a distance, and that stay creditable (§2.4). Stations spread so that guarding everything is impossible.

### 2.4 The House's five chains: what counts as a sabotage

The rules are from GDD §8. Every threshold below is a placeholder.

| Chain | Trust-free sabotage the GDD already allows | Token version to exclude | A cost-based credit test (placeholder) | The outed human's angle |
|---|---|---|---|---|
| **Deliveries** | Hide an item (GDD: "the dissidents sabotage by hiding items") | Pick it up and drop it a metre away | The item ends at least *D* m from storage and from its drop-off, and stays undelivered for at least *T* s (for example 20 s) | Works alone. Items take two hands, so carrying one is slow and visible, which invites a comic chase |
| **Generator** | Switch an active switch off; GDD: "a switch going off stops the charge" | Off, then on within a second | Credit when a switch-off has stopped a running charge, or kept the bars from being complete, for at least *T* s | The best trust-free lever. Switches stand 20 to 39 m apart and out of earshot, so one alien cannot guard them all |
| **Cooking** | Hide a box (GDD); burn a patty; put a wrong ingredient | A wrong ingredient (red, take back); burning a patty you put on yourself | Box: away from storage and kitchen for at least *T* s. Burnt patty: counts for nobody (an accident, E7) | Works alone. Herb beds and boxes are unlimited, so only hiding a box costs real time |
| **Photo** | Hide a shot film or a printed photo; waste frames by shooting no one | Shooting empty frames: films are unlimited, so the cost is tiny | A shot film or printed photo removed from its path (camera, study printer, darkroom board) and missing for at least *T* s | Works alone. The path crosses three floors, so a theft costs a long trip |
| **Car repair** | Let go of the lift, or knock down the holder: the car drops and kills the fitter (GDD decision 9) | Dropping it with nobody under it | Credit to the one who released it, or to the knocker who downed the holder, only when a fitter was under the car or a fit was in progress | Knocking the holder down needs no trust. An outed human will never be given the lift, but he can still ambush it. This is the map's built-in comic moment |

[A] The House already has a trust-free lever in every chain. What is missing is (1) a rule that decides which acts pay and (2) a cap on how often a chain can be hit.

---

## 3. Cross-game patterns

1. **Sabotage removes real, visible progress or blocks a ready step.** DbD's 5% regression and 5% repair minimum, Dread Hunger's holes, Among Us's switches. Games that let a token touch count got patched: gen tapping, dummy samples, Battlefield 2 and 2142 farming.
2. **Every stall is bounded.** DbD's 8-event cap, Among Us's critical countdowns and shared cooldown, Phasmophobia's 25 s hunt cooldown and 90 s smudge. Without a bound, the side that wins by the clock wins by stalling.
3. **Global sabotage is telegraphed and repaired at a known place.** Alarms and countdowns, Phasmophobia's flicker, the DbD VFX, Deceit's fuse boxes.
4. **Sabotage pays in power or on success, not in raw score.** Project Winter's stat buffs, Barotrauma's XP share on success, TTT's team credit at a threshold.
5. **Credit thresholds and caps beat bans.** Battlefield 2142's 50%, DbD's category caps, WoW's 10% per repeat, the R.E.P.O. holder window.
6. **Noise makes sabotage funny and deniable.** BSG's Destiny cards, Secret Hitler's deck, Overcooked's rats and fires, the Lethal Company blackout.
7. **The minority's reward scales with its size,** and the rise in difficulty is tuned for large tables. Saboteur's payout scale, The Resistance's two-fail mission.
8. **Waiting players get jobs.** Outlast Trials pings, Among Us ghosts finishing tasks.

## 4. Risks for our design

1. **The stall is a win condition [A].** Humans need one chain unfinished. With unlimited re-sabotage, one human camping the Generator's farthest switch, or the car lift, wins 10-minute matches. This is DbD's 3-gen problem.
2. **Sabotage becomes the default for everyone** if completion credit is narrow (E2). Then the aliens' race against the clock fails, and humans win by alien self-interest instead of by play.
3. **Token sabotage inflates the economy** (E1, E4). Every player buys everything early, so mutations stop being choices.
4. **Free repairs are boring [A].** If a sabotage is undone in a second, nobody chases anybody. If it takes a minute, someone waits, which breaks "never boring". The repair should be a short errand: travel plus a few seconds.
5. **Global sabotage as a hard lock [A].** Lights out on a map with knockdowns and a one-shot car could feel like dead time. Among Us lights pair darkness with kills, a different tone from comic chaos.
6. **Voice-based sabotage could punish the wrong people [A].** Proximity voice is the core. Muting everyone for 30 s is "boring", but a shorter range near a noise source makes a game of it.
7. **Attribution disputes [A].** Who "hid" an item that three players carried? Without a holder rule (the R.E.P.O. pattern), the host must arbitrate, and players see points appear for the wrong person.
8. **Credit visibility leaks roles [A].** A "+1 sabotage" pop-up seen by others outs the player. Round 1 risk 10 applies. Credit must reach only the earner (architecture invariant 2, per-peer filtering).
9. **Accidents get credited and the clumsy farm points** (E7). Or the reverse: humans feel cheated when their clean sabotage is ruled an accident.
10. **The outed human's spiral.** Without trust-free creditable levers he cannot earn points, cannot buy, and stops mattering (round 1's outed-traitor report, risk 3).

---

## 5. Options for the engineer

These are original proposals, framed for the engineer to decide. Every value is a placeholder.

### Option A: Cost-gated sabotage credit
**How it works.**
- A sabotage pays only once the sabotaged state has cost the other side real time: the switch has stayed off past *T* s while the charge could run, or the item has been missing past *T* s (placeholder 15 to 20 s).
- It must also undo existing progress or block a ready step.
- The point is paid when the threshold is crossed, not at the act, so a quick fix pays nothing.
- Each chain has a short definition (the §2.4 table).

**For.**
- It closes E1 and E4.
- It needs no knowledge of roles, so it fits identical roles.
- It mirrors DbD's 5%, Battlefield 2142's 50% and the delay in Project Winter's delayed sabotage.
- The delay also lets the saboteur walk away, which fits "action over discussion".

**Against.**
- One more rule to explain.
- A repair just before *T* both denies the point and teaches players to camp stations.
- It needs per-chain thresholds and a playtest.

### Option B: Broad completion credit, paid when the task locks
**How it works.**
- Every player who did a counted step of a task gets its one point when the task locks: a switch on at full charge, the button, a delivered item, a green ingredient, a hung photo's shooter or sitter, a fitted part or the lift hold.
- "Never both" is resolved by **the first credited act claims the slot**. A player holding a pending completion credit who then sabotages that task loses the pending point and takes the sabotage point.

**For.**
- It removes E2.
- It makes the alien pair swap (E3) break even at best.
- Sabotage becomes mostly the humans' tool, and an alien's sabotage stays a real, costly choice.
- Saboteur and the Battlefield thresholds credit helpers. Escrow until lock also means a task the humans stall pays its contributors nothing, so aliens fight to finish.

**Against.**
- Alien income arrives in lumps, late in the match. Humans' sabotage income arrives sooner, which may be a feature for the minority or may be too strong.
- "Counted step" needs care for chains like Delivery, where many players touch many items.

**Recommendation:** adopt A and B together. Each one alone leaves a hole.

### Option C: A sabotage budget per task with visible wear
**How it works.**
- Each task tolerates at most *N* credited sabotages (placeholder 3) in total, from anyone.
- The station visibly wears with each one, comic plasticine damage such as tape, dents and smoke, so the count is open knowledge.
- After *N*, the station is tamper-proof until it locks.
- After each repair, a short protection window (placeholder 10 s) blocks another credited sabotage, like Among Us's cooldown that starts after the fix.

**For.**
- It bounds the stall (E5) the way DbD's 8-event cap with VFX did.
- It turns "which chain do we hit?" into a real choice.
- It makes the last hit on a worn station a funny "now or never" moment.

**Against.**
- It caps humans' total reach. With three humans and five chains, the budget may run out too early. *N* may need to scale with the human count, as The Resistance's two-fail mission does.
- A tamper-proof station may feel arbitrary unless the wear is very readable.

### Option D: Global sabotages that are bought, pay nobody, and are repaired by anyone
**How it works.**
- Anyone can buy a map-wide sabotage at the apparatus with points.
- It is telegraphed with a few seconds' warning, like Phasmophobia's flicker, and has one map-wide cooldown that starts after the repair.
- One player can repair it at a fixed known place, in a few seconds plus travel.
- It never earns points, and neither does its repair (closes E6).

**Placeholder event kinds for the House (content needs the engineer's word):**
- a power cut, fixed at a known panel;
- a deafening noise source that shrinks voice range around it, fixed by reaching it (voice routing as game logic, invariant 6);
- a jammed exterior door;
- one event that cannot be repaired and simply expires, Mushroom-Mixup-style.

**For.**
- This is the outed human's reach without trust (round 1's outed-traitor Option B) and a spending sink for points.
- The voice event is unique to our game.
- Nothing to farm.

**Against.**
- It needs tuning per player count.
- It risks dead time if the effect is long.
- Aliens buying events purely for laughs spend points on nothing. That may be fine.

**Recommendation:** adopt with one or two events first. Keep the effect under about 20 s and the repair under about 10 s plus travel (placeholders).

### Option E: A trace on the saboteur instead of a meeting
**How it works.**
- Each credited sabotage plays a sound at the station.
- It leaves a short visible trace on the actor (placeholder: a coloured smear for 10 s), seen by everyone nearby.
- Counterplay is to chase and knock him down. Respawn is the existing 30 s.

**For.**
- It turns sabotage into a chase, not a debate (pillars: action, deduction not central).
- It gives the hidden human a risk to weigh.
- An outed human loses nothing, so the trace does not punish him twice.
- It follows the Goose Goose Duck Engineer's sabotage-origin view and Hunt's bounty visibility (round 1).

**Against.**
- It may out humans too fast and make hiding pointless.
- It needs a filtered event so only nearby peers see it (invariant 2).
- It could become a mutation (seeing traces) rather than a default.

### Option F: House accidents that pay nobody
**How it works.**
- The host draws a few telegraphed random mishaps per match (placeholders: a fuse trips, a box tips over, the grill flares).
- Each has a warning and a quick fix. None credits anyone (closes E7). They can hit any chain, so a fail is funny before it is suspicious.

**For.**
- It delivers the randomness pillar with a chance to react: Overcooked's hazards, BSG's Destiny noise, Phasmophobia's telegraphed events.
- It gives humans plausible cover without anyone having to play detective.

**Against.**
- It costs the aliens time with nobody to blame. Over-tuned, it decides matches.
- It must be counted inside Option C's budget, or kept outside it, which is one more rule.

**Overall recommendation.** Make **A + B + C** the core economy rules, since they close E1 to E5 between them. Add **D** with one or two events as the outed human's reach. Prototype **E** and **F** after the first playtest. Separately, round 1's apparatus pricing (its Options A and B) still applies on the spending side.

---

## 6. Open questions for the engineer

1. **What is a "task" for the one-point rule:** the whole chain (5 tasks, so at most 5 points per player) or each subtask (a burger, a switch, an item)? Every number below depends on it.
2. **Who completes a task:** only the finisher, or every contributor (Option B)? And if both a pending completion and a sabotage exist, which act claims the slot?
3. **When is a point paid:** at the act, at a cost threshold (Option A), or when the task locks?
4. **May one chain be sabotaged forever?** If not, how many times, and is the count visible (Option C)?
5. **Do accidents count:** a burnt patty, an empty photo, a dropped car with nobody holding it?
6. **Does a car drop that kills a fitter pay its releaser or the knocker who downed the holder?** It is the House's signature moment, and the one lever an outed human can use without trust.
7. **Global sabotages: yes or no, bought with points or free on a cooldown, and may they touch voice range?**
8. **Who sees a credit:** only the earner, or does a sabotage leave a public trace (Option E)?
9. **Should humans' reach (a sabotage budget, a global cooldown) scale with the host's human count,** the way Saboteur scales gold and The Resistance scales fails?
10. **Random House accidents (Option F): wanted, and inside or outside the sabotage budget?**