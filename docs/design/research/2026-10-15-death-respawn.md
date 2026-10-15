# Death, respawn and the cost of dying: research for the House (alien/human) design

## 0. Method and confidence

I did about 90 searches and fetches on 2026-10-15. Many wiki hosts (Fandom, Steam guides, some news sites) refused fetches with HTTP 402, 403 or 429. Facts marked **[snippet]** come from search-result summaries I could not open, so treat them as lower confidence.

Not verified:
- **Dread Hunger:** the store page, Wikipedia and previews say nothing about dead players ([store](https://store.steampowered.com/app/1418630/)). It was delisted, with servers ending 2024-01-01.
- **Original Deceit:** its servers shut on 2025-11-06 [snippet](https://en.wikipedia.org/wiki/Deceit_(video_game)). I found nothing on how its dead players behave.
- **Goose Goose Duck ghost rules:** only conflicting community guides.
- **Lockdown Protocol dead-player rules:** only one Steam reply, "you turn into a ghost to spectate" ([thread](https://steamcommunity.com/app/2780980/discussions/0/4635988522932715980)). The store page carries a "Perma Death" tag ([store](https://store.steampowered.com/app/2780980/)).
- **Lethal Company's vanilla credit penalty:** one guide claims 20% of funds per death, but I could not confirm it.
- **Darktide's respawn rules:** not found.

I found **no verified 2024–2026 game with documented clone, vat or capsule respawns**. Do not assume precedent for the capsule idea. The nearest cases:
- Void Crew's player characters are cloned astronauts ("ectypes"), but its respawn rules are undocumented and a Steam thread conflicts ([Wikipedia](https://en.wikipedia.org/wiki/Void_Crew), [thread](https://steamcommunity.com/app/1063420/discussions/1/6892266032685010270)).
- Project Winter's Scientist uses a cloning machine (§1.4).
- Borderlands' New-U stations are older (§2.7).
- Helldivers 2's orbital pod is a respawn delivered from outside (§2.1).

## 1. The dead who stay: ghost roles and ghosts with a job

### 1.1 Among Us
**Verified.**
- Killed or ejected players become ghosts. Crewmate ghosts keep doing tasks, impostor ghosts keep sabotaging, and living players cannot see ghosts.
- Ghosts chat only with other ghosts.
- A Guardian Angel role can protect the living, and the Phantom was added in June 2024 ([Wikipedia](https://en.wikipedia.org/wiki/Among_Us)).
- A wiki guide says ghost tasks still fill the crew's task bar and visual tasks still show cues, so a living impostor can fake-clear next to a ghost [snippet](https://among-us.fandom.com/wiki/Guide:Ghost).

**Developer view.** Designer Marcus Bromander said "If you get killed first that sucks. Your game is boring," and "We do want to make being ghosts more fun." The article reports that most players quit a match once eliminated. Programmer Forest Willard said Guardian-Angel-style ghosts are "a difficult thing to pull off" ([Inverse](https://www.inverse.com/gaming/among-us-ghost-update)).

**Why it works and where it fails.** Ghost work is aligned with the team goal, so death does not erase contribution. But the ghost has no effect on the social game, so people leave.

**Our mapping.** In our design a completed task advances the aliens' goal whoever does it, which is the same "the work still counts" logic. Respawn replaces the ghost phase, so the lesson is to keep any wait short and give it a function.

### 1.2 Goose Goose Duck (low confidence)
- Community guides say a dead duck can keep triggering sabotages. They disagree on whether ghost goose tasks fill the win bar.
- One guide says the developers decided living and dead should not communicate at all [snippet](https://steamcommunity.com/sharedfiles/filedetails/?id=2575859307). Steam rate-limited my fetches, so I could not confirm this.

### 1.3 Blood on the Clocktower
**Verified.**
- Dead players "may only vote once more during the game". Voting removes the token, and only living players nominate ([glossary](https://wiki.bloodontheclocktower.com/Glossary)).
- Dead players stay in discussion ([Wikipedia](https://en.wikipedia.org/wiki/Blood_on_the_Clocktower)).

**Why it works.** Death removes capability (ability, nomination, all but one vote), not presence.

### 1.4 Project Winter (proximity chat, traitors)
**Ghosts.**
- Ghosts fly around and buff living allies' health, hunger or warmth. Dead traitors debuff instead ([NME](https://www.nme.com/gaming-features/bored-of-among-us-play-project-winter-2846682)).
- A later "Wild Spirit" form costs 75 Ghost Power, and ghost powers share a global cooldown [snippet](https://steamdb.info/patchnotes/3809024).

**Revival.**
- The Medic's revive pulse costs each revived player a permanent max-health penalty. A Scientist can revive only if someone holds the dead player's heart, uses a cloning machine in a lab, and is capped at one per game [snippet](https://steamdb.info/patchnotes/4669963).
- A Necromancer traitor revives the dead into traitor ranks, and traitors can "Bleed" a downed player, which speeds the death timer 4x while held ([patch notes](https://nintendoeverything.com/project-winter-power-balance-vol-2-update-out-now-patch-notes/)).

**Player opinion.** One Steam poster said removing Medic and Scientist in a major update drained the fun. That is a single opinion ([thread](https://steamcommunity.com/app/774861/discussions/0/3828663748259905445)).

**Mapping.** Each revive carries an explicit permanent cost, the "vat" needs a recoverable prerequisite, and a hostile role has a finishing action against the downed. All three are directly relevant to an outed human.

### 1.5 Co-op games where the dead have a job
- **Phasmophobia.**
  - Dead players could grab and throw non-equipment objects from an update dated 2020-11-11 ([TheGamer](https://www.thegamer.com/phasmophobia-update-lets-dead-players-do-more/)).
  - Dead players lose the gear they brought. Insurance pays 50%, 25% or 0% by difficulty.
  - A High Priestess card revives a random dead player. A Monkey Paw revive has a 50% chance to kill the wisher. A revived player cannot die twice in one hunt [snippet](https://attackofthefanboy.com/guides/phasmophobia-what-happens-when-you-die-what-to-do-when-youre-dead/).
- **R.E.P.O.**
  - The corpse becomes a head. Carry it to extraction and fill the quota counter, and the player returns with 1 HP (25 after reaching the ship).
  - Without that, they revive at 25 HP after the round but sit out the rest of it. A healthier player can donate 10 HP ([guide](https://itemlevel.net/how-to-revive-your-friends-in-repo/)).
  - v0.30 (Oct 31 2025) added Death Head Possession. A battery recharges while you are dead and is spent to control your head and interact with the living, and an upgrade extends it ([Insider Gaming](https://insider-gaming.com/repo-monster-update-patch-notes-october-2025/), [Destructoid](https://www.destructoid.com/r-e-p-o-v0-3-0-monster-update-full-patch-notes-listed/)).
  - The patch itself implies the dead previously had little to do.
- **PEAK.**
  - An unconscious Scout has a death timer. Carrying them does not reset it, and it speeds up in fog or when they give up.
  - A ghost can spectate and use voice chat with the living but cannot interact with the world.
  - An Ancient Statue revives once, with Hunger 30 and +5 Curse. A Scout Effigy is a portable revive. An active Checkpoint Flag respawns you at the flag instead of dying ([wiki](https://peak.wiki.gg/wiki/Death)).
- **MIMESIS.** A June 16 2026 update reportedly lets eliminated players take over the monster while still chatting with teammates [snippet](https://gamegeeker.com/pt/news/mimesis-major-update-ai-npc-gameplay-overhaul?country=US).
- **Content Warning.** The Defibrillator costs $300 and must be bought before descending. Sources disagree on one versus three charges ([Dexerto](https://www.dexerto.com/gaming/content-warning-how-to-revive-other-players-2629008/), [wiki](https://contentwarning.wiki.gg/wiki/Defibrillator)).
- **Lethal Company.**
  - Vanilla: when the crew dies, the ship leaves and scrap aboard is lost. The developer said otherwise "it would be way too easy to meet the quota" ([thread](https://steamcommunity.com/app/1966720/discussions/0/4032472470670005882)).
  - A popular revive mod defaults to 2 minutes to revive, 5 revives per level, 25 health, and less health on each repeat revive ([changelog](https://thunderstore.io/c/lethal-company/p/Erk/ReviveCompany_Patched/changelog)).

## 2. Respawn systems

### 2.1 Helldivers 2: shared pool plus delivery
**Verified.**
- Each player brings 5 reinforcement tickets, so a squad of four has 20 (a booster adds 1 per player).
- At zero tickets, one regenerates every 2 minutes.
- If the whole squad dies with tickets left, everyone reinforces together. With none and the objective incomplete, the mission fails.
- The pod is steerable and crushes allies as well as enemies. Stratagem jammers and Ion Storms disable it ([wiki](https://helldivers.wiki.gg/wiki/Reinforce)).

**Design intent.** Johan Pilestedt says reinforcement placement is one of the "watering holes" that pull players together ([PlayStation Blog](https://blog.playstation.com/2024/03/12/helldivers-2-how-arrowhead-turned-the-twin-stick-shooter-original-into-a-bombastic-ps5-sequel/)).

**Reported problems [snippet].** Steam threads from 2024 describe being dropped into a horde and fights over where to reinforce (e.g. [this thread](https://steamcommunity.com/app/553850/discussions/0/4302697419070354167)).

**Why it works.** Death becomes a team resource decision with a visible, funny arrival.

### 2.2 The Finals: coins plus wave timer
- Eliminated players leave a statue that a teammate revives with a 5-second hold. A defibrillator revive returns 50% health.
- Self-respawn costs a coin (start with 2, +1 per round in tournament modes). A team wipe respawns everyone together without coins. A ranked wipe costs 15% of team cash ([Wikipedia](https://en.wikipedia.org/wiki/The_Finals)).
- Qualification timers are 30 s (15 s if your team owns a Cashout) and 27 s for a wipe ([wiki](https://thefinals.wiki/wiki/Cashout)).
- In Quick Cash the timer starts at the first death, later deaths join it, and a death in the last 7 s resets it [snippet](https://thefinals.wiki/wiki/Cashout).

**Why it works.** Players choose when to spend scarce coins. The tension is that players who run out depend on teammates.

### 2.3 Overwatch 2: waves and spawn protection
- Season 12 replaced group respawn with wave respawn. The default rose from 10 s to 12 s. The first death starts a wave, deaths within 6 s join it, and a solo death respawns in 10 s. Waves are disabled in overtime and near the payload's end ([Gfinity](https://www.gfinityesports.com/article/overwatch-2-season-12-patch-notes)).
- Earlier, Blizzard said it would "drastically reduce spawn timers" and Strafe flagged stalled matches as a risk ([Strafe](https://www.strafe.com/news/read/overwatch-2-to-see-drastically-reduced-spawn-timers-in-season-8/)).
- Season 4 "Stranded Spawns" keep the old spawn room locked to the enemy for 7 s after a capture [snippet](https://ggrecon.com/guides/overwatch-2-stranded-spawns).

### 2.4 Apex Legends
- **Banner and beacon.**
  - A beacon channel is 5 s, and each teammate can be respawned once per team per game. The arrival ship is visible and audible.
  - The respawned player gets a fixed kit and cooldown resets ([wiki](https://apexlegends.wiki.gg/wiki/Respawn_Beacon)).
  - A 90-second banner window appears in a search summary only [snippet](https://apexlegends.wiki.gg/wiki/Banner_Card).
- **Season 29 death-box respawn.** Respawn in place takes 7 s at about 20 HP, with a lockout timer that resets after a few minutes alive ([wiki](https://apexlegends.wiki.gg/wiki/Death_Box)).
- **Trios Revival (Aug 6–20 2024).**
  - Beacons and banners were removed. A dead teammate auto-respawns above a living teammate and skydives.
  - Respawn time grows with each round and each death of that teammate, and shrinks when living teammates damage, knock, kill or finish enemies. Respawns end at round 5 ([wiki](https://apexlegends.wiki.gg/wiki/Trios_Revival)).
- **Problems.** Players hid under beacons to ambush revivers ([GGRecon](https://ggrecon.com/articles/ratting-apex-legends-players-are-hiding-inside-respawn-beacons/)). Dexerto (opinion) argues there is little incentive to respawn teammates [snippet](https://www.dexerto.com/apex-legends/apex-legends-camping-meta-831174/).

### 2.5 Valorant
- **Knockout (launched 2026-03-18).** Each kill revives a fallen teammate, and first to 4 rounds wins ([The Spike](https://www.thespike.gg/valorant/news/valorant-knockout-everything-you-need-to-know-about-the-new-game-mode/7763)). One survivor can swing a round [snippet](https://www.thespike.gg/valorant/news/valorant-new-game-mode-knockout-details/7763). I could not confirm whether it is still in rotation.
- **Team Deathmatch.** Respawn takes 1.5 s, with 15 s of damage immunity. After that, lingering in the spawn room hurts you ([Riot](https://playvalorant.com/en-us/news/game-updates/valorant-team-deathmatch-101/)).

### 2.6 Supervive, Left 4 Dead, Space Engineers
- **Supervive.**
  - Stepping on a beacon with a downed or dead ally plays a loud noise to every player and marks the map.
  - Two teams standing on one pause the revive. Everbeacons ignore that pause.
  - A destroyed beacon costs 5,000 gold to repair on one wiki page and 500 on another ([wiki](https://supervive.wiki.gg/wiki/Respawn_Beacons)).
- **Left 4 Dead.**
  - In Campaign, a killed survivor respawns in a closet and another survivor must free them. In Versus, the dead do not respawn.
  - A survivor incapacitated twice without healing dies on the third ([Wikipedia](https://en.wikipedia.org/wiki/Left_4_Dead)).
- **Space Engineers.** You respawn at a survival kit or medical room your faction may use. Destroyed, off, hacked or unpowered ones are unavailable. With none left you land in a starter drop pod at a random location. Death drops your backpack and positive buffs ([wiki](https://spaceengineers.wiki.gg/wiki/Death)).

### 2.7 Borderlands (older clone precedent)
In Borderlands 3, failing "Fight For Your Life" costs 7% of carried cash, you return at the nearest New-U station, and surviving bosses regain full health ([GameWith](https://gamewith.net/borderlands-3/article/show/11152)). I could not verify Borderlands 4's rules.

## 3. What a death costs: summary by cost type

| Cost type | Examples (verified unless marked) |
|---|---|
| Time out | Overwatch 10–12 s waves; Finals 15–30 s; Valorant TDM 1.5 s |
| Shared pool | Helldivers 5 tickets per player, +1 per 2 min at zero; Finals 2 coins +1 per round; Apex beacon once per teammate |
| Lost items or points | Phasmophobia gear (insurance 50/25/0%); Space Engineers backpack; Borderlands 7% cash; Finals wipe 15% cash (ranked) |
| Escalating per death | Apex bleed-out 90/60/30/15 s per knockdown ([wiki](https://apexlegends.wiki.gg/wiki/Health)); Trios Revival timer; Peak +5 Curse; Project Winter permanent max-health loss |
| Map trip | R.E.P.O. head to extraction; Peak statue at campfire; L4D closet; Apex beacon |
| Lost memory | No example found; see §9 |

The extraction-shooter side loses the whole loadout on death. Marathon is moving some inventory to survive death because of "death spirals" ([GameRiv](https://gameriv.com/bungie-addresses-marathon-spawn-rushing-and-death-spirals-plans-quieter-exfils/)). ARC Raiders has a Safe Pocket and no insurance [snippet](https://www.gfinityesports.com/article/arc-raiders-guide-5-essential-tips-every-beginner-needs-to-know).

## 4. Knockdown and revive before death

- **Apex.** A knocked legend crawls with a shield. Bleed-out is 90, 60, 30, then 15 s on each later knockdown. A revive takes 5 s and returns 20 HP. A revive that began after the timer expired completes unless interrupted ([wiki](https://apexlegends.wiki.gg/wiki/Health)).
- **Deep Rock Galactic.**
  - A revive is a 6 s hold. Health returned falls from 60% to 10% across Hazard 1–5. There is no cap on revives, and stacked rescuers combine progress.
  - A total wipe fails the mission, and a perk grants a 10 s grace period ([wiki](https://deeprockgalactic.wiki.gg/wiki/Health)).
- **Marathon [snippet].** A downed state of roughly 30 s, then a locked-out phase of about 20 s where the body cannot be revived but is lootable. After a revive you may return without items ([Mobalytics](https://mobalytics.gg/marathon/guides/how-revival-works)).
- **Brink.** The downed player chooses between a syringe revive and the respawn countdown, which avoids arguments over whether a revive was wanted ([Destructoid](https://www.destructoid.com/splash-damage-addressing-common-shooter-issues-with-brink/)).
- **Finishing the downed.** Project Winter's Bleed (4x timer) and L4D's third incapacitation show a downed state can be sped toward death by an enemy. A knockdown is only a cheap, reversible stage if the finish is slow or contestable.

## 5. Spawn camping and how games prevent it
- **Physical separation.** Overwatch's spawn barrier keeps enemies out, though projectiles can pass [snippet](https://www.pcgamesn.com/overwatch-2/bug-enemy-spawn). Stranded Spawns extends it for 7 s after a capture (§2.3).
- **Short immunity then eviction.** Valorant TDM gives 15 s of immunity, then damages you in spawn (§2.5). Forum players disagree on whether 10, 20 or 30 s changes outcomes [snippet](https://forum.warthunder.com/t/a-simple-solution-to-spawn-camping/78685?page=2); that is opinion.
- **Respawn location choice and cooldown.** Rust bags give a 5-minute cooldown, beds 2 minutes. The cooldown is shared across bags within 50 m, a player may hold 15, and with no bag you land at a random beach point ([guide](https://www.corrosionhour.com/how-do-sleeping-bags-work-in-rust/), [Facepunch](https://wiki.facepunch.com/rust/item/sleepingbag)).
- **Fixed, known spawn points get camped.** DayZ forum players complain that coastal spawns concentrate players, and fully random spawns invite suicide-rerolling for good locations [snippet](https://reddit.fabiomanganiello.com/r/dayz/comments/1vzqbj/lets_discuss_spawning_where_should_new_spawns).
- **Making the revive itself noisy or contestable.** Apex ships are audible and Supervive beacons announce globally (§2.4, §2.6). This deters unwanted approach but also invites third-party ambush.
- **Spawn-rush pressure.** Bungie lists spawn rushing and lobby clearing as problems it is addressing in Marathon (GameRiv, §3).

## 6. What the dead know and may share
- Among Us and (reportedly) GGD wall ghosts off from the living; Phasmophobia silences the dead.
- BotC, PEAK, MIMESIS and R.E.P.O. possession let the dead talk or influence the living.
- Game code cannot stop out-of-band leaks such as Discord. Players raise this repeatedly in forums, and the practical fixes are channel limits and social norms [snippet](https://steamcommunity.com/app/739630/discussions/0/604141771964845204).
- TTT variants differ on whether the dead can talk to the living [snippet](https://www.troubleinterroristtown.com/help/gameplay/).
- **Analysis.** Your pillars (deduction not central, open knowledge) make the dead's knowledge a weak leak. What matters more is proximity voice. A dead or respawning player's voice routing is a `core/` rule, so decide it explicitly rather than by accident.

## 7. Cross-game patterns
1. **Time penalties are short and clustered.** Waves, joined timers and team-wipe respawns (Overwatch, Finals) cut dead time without removing the cost.
2. **Death cost scales with repeat deaths.** Apex bleed-out, Trios timer, Peak curse, Winter max-health and the revive mod all penalise the second death more than the first.
3. **Teammates can pay the cost down.** Trios timers shrink with living teammates' kills. Knockout revives per kill. Finals statues, Peak statues and R.E.P.O. heads are shared work.
4. **A shared pool turns death into a team decision.** Helldivers and Finals coins make "when to die" a macro choice. Death-spiral risk is the known failure.
5. **The respawn point is a map object, and it is the most contested place.** It gets hidden under (Apex), announced (Supervive), made contestable (Supervive pause), hackable (Space Engineers) or jammed (Helldivers).
6. **Protection is short and then expires.** Valorant's 15 s, Overwatch's 7 s lock and Rust's cooldowns all end on a timer.
7. **Dead players retain agency over something small.** BotC's vote, Among Us ghost tasks, R.E.P.O. possession and Project Winter buffs are all ways the dead stay useful.
8. **A second-chance protection exists after revival.** Phasmophobia's revived player cannot die twice in one hunt, and Helldivers and DRG give a few seconds of grace (DRG's wiki notes grab immunity after revival).

## 8. Risks for our design
1. **Known fixed capsules plus open knowledge is a spawn-camping recipe.** It is worse for hidden-role play, where "who killed whom" is not a clean team question.
2. **Farming an outed human.** Roles are identical, so aliens can kill an outed human as readily as he can kill them, and kills as a score-less action still deny his tasks. Nothing in the answers rewards kills, so a farm can still arise through denial: killing him repeatedly stops him doing tasks and sabotage.
3. **Death spiral in the shared pool.** If the pool is what aliens fear to drain, the humans' best strategy may be to drain it, and a draining pool can leave real players with no respawn.
4. **A sabotageable capsule can soft-lock.** Space Engineers solves it with a fallback pod. Apex shows people exploit anything near a beacon.
5. **Respawn drama versus dead time.** Overwatch's own experiments with 75% timers show tempo and kill meaning pull against each other. The wait must be short, or it must be playable (§1.5).
6. **Aliens will stop fearing death if the cost is only a few seconds.** Pure timers fail the "aliens must still fear dying" test, which pushes cost into position, carried items, points or capsule trips.
7. **The humans' ghost or hidden-role tells.** A respawn that reveals a disguise or DNA event changes the secrecy economy, which is a lore and rules question.

## 9. Options for the engineer to decide (all values are placeholders)

**Option A: short timer, escalating per death, decays with time alive.** The first death in a window costs a small wait, and each further death in that window adds to it, resetting after a period alive. This is the Apex bleed-out and Trios shape.
- Pro: it directly answers "outed human must not be trivially farmed" and costs nothing in map design.
- Con: it also punishes the victim, who is whoever is hunted, which can feel unfair.
- Mitigation: count deaths per victim and add short post-respawn immunity (§5).

**Option B: a respawn trip.** The body appears at a capsule that is not where you died, so death costs a walk back. Distance is a design lever through capsule placement.
- Pro: map-level macro decisions, no extra UI, and aliens fear being sent far from their task.
- Con: it risks dead time for slow-walking players (R.E.P.O.'s head-carry is the precedent for turning that trip into a job).

**Option C: shared respawn charge (pool) or per-player coins.**
- Helldivers-style: a House-wide pool, regenerating slowly.
- Finals-style: per-player coins.
- Pro: it makes dying a team decision.
- Con: death-spiral risk, plus the question of whether humans can also draw on the pool. Roles are identical, so an outed human would share it. If aliens' pool is the target, per-player coins avoid that.
- Do not let the pool hit zero as a loss: use a slow regeneration floor, as Helldivers does.

**Option D: carried-item or unbanked-point cost.**
- A death drops what you carry, or a fraction of unbanked points (Phasmophobia, Space Engineers, Borderlands 7%).
- Pro: fear of dying scales with how much you hold, so aliens carrying task parts fear death and outed humans carrying sabotage tools do too.
- Con: it must not touch locked, completed tasks, or the "completed task is locked" answer breaks.
- Anti-farm hook: an item dropped at the death site can be reclaimed, so the killer cannot simply loot it for points.

**Option E: sabotageable capsules with a guaranteed fallback.**
- A capsule can be taken offline by a sabotage task (one point per task, once). While offline, respawns go to the next capsule or a slow fallback.
- Add contested-use rules like Supervive's pause and a loud, visible arrival (§2.4, §2.6).
- Pro: it gives an outed human a real lever, since attacking respawns is a plan.
- Con: it needs a fallback or it soft-locks (Space Engineers' random starter pod).
- It interacts with the open question of per-task versus global sabotage.

**Option F: a short, useful ghost phase.** The waiting second or two lets the dead spectate or ping, or gives a small possession-style action with a recharging budget (R.E.P.O.).
- Pro: it removes dead time without changing the cost.
- Con: it adds a system. It must obey voice routing (§6).

**Recommendation (for you to accept or reject).** A as the backbone, since it is the only option here that targets the outed-human problem directly. Add E, because it makes the capsules a place where the two win conditions collide, plus a small amount of D tied to carried items, not banked points. Hold B and C back unless playtests show deaths feel free. Keep F optional and tiny.

## 10. Open questions for the engineer
1. Does a kill earn nothing? Confirm that no points exist for kills, to keep the farming incentive purely denial-based.
2. Are the capsules per-player (assigned) or shared and nearest-available? This changes camping and sabotage greatly.
3. Is the escalation per victim, per killer, or per match phase?
4. May an outed human use the same capsules, or does being outed change that? The answers say roles are identical, so the default is yes.
5. Does respawn reveal anything about the disguise (face, DNA)? Does a fresh body keep the sculpted face?
6. Does a dead or respawning player lose anything beyond carried items (memory of tasks, unbanked points, mutations)? I found no verified precedent for information loss.
7. May a dead player speak to the living, and if so within what radius? This is a `core/` voice rule.
8. Is a knockdown finishable by an enemy, and how long does it take? Project Winter and L4D show it can speed death.
9. What is the target total dead time per player per match? Without it the timer numbers have no anchor.
10. Is "sabotage a capsule" a per-task sabotage or a global one? It decides whether Option E lives in the task chain or as a separate system.

## Sources
Primary pages are linked inline above. Search-summary-only claims are marked **[snippet]**. Fetch failures (HTTP 402/403/429) are noted in §0.