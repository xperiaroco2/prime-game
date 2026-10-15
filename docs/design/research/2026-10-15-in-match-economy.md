# In-match economies and upgrades: research report

## 0. Scope and verification notes

Most pages were checked live on 2026-10-15. Several wikis (Liquipedia, Fandom, deadlock.wiki) returned 403 or 402 to my fetch tool. Where a claim comes only from a search-engine summary of such a page, I mark it "(search summary)".

Two figures I could not confirm:
- **Valorant's 9,000 credit cap.** One guide states it ([tapin](https://spacex.tapin.gg/blogs/valorant-economy-guide-2026)); the ONE Esports and Gfinity guides don't mention a cap. Treat it as unverified.
- **CS2 teammate money visibility.** I found no source for whether teammates' money is shown.

Also unverified:
- Current live Dota 2 gold values. I only have the 7.31 notes.
- Whether Goose Goose Duck has any in-match economy. I found only cosmetic currencies.
- Detailed Dread Hunger and Project Winter traitor economy numbers. Only patch-note fragments exist.

Labels used below: **[F]** verified fact, **[O]** player or critic opinion, **[A]** my analysis.

---

## 1. Round-based shooter economies

### Counter-Strike 2

**How it works.**
- Win pays $3,250. The loss bonus runs $1,400, $1,900, $2,400, $2,900, then $3,400 from the fifth consecutive loss, and a win resets it. [F]
- Cap is $16,000 per player; money above it is lost. [F]
- Kill rewards are weapon-dependent: $300 for a rifle, $900 for a shotgun, $1,500 for a knife, $100 for an AWP. [F]
- Planting the bomb gives $300 per attacker even on a lost round. [F]
- Source: the community wiki [guildorder](https://guildorder.com/games/csgo/wiki/economy-basics), which itself warns that figures change across versions.

**Why it works.**
- The escalating consolation lets a losing team afford a full buy within a few rounds. A German-language article ([hotspawn, search summary](https://www.hotspawn.com/?p=159222)) says it exists so a team can still fight back.
- The cap forces spending ("don't over-save"), and the guide recommends spending surplus on teammates. [F]
- Weapon-dependent kill pay discourages hoarding the strongest tool. [A]

**What goes wrong.**
- The economy rewards deliberately skipping a round ("eco") to save money. [A]
- Enemy economy is inferred rather than seen, and third-party overlays estimate it from loss streaks ([Overwolf tool, search summary](https://economytool.overwolf.com/)).

### Valorant

**How it works.**
- Win pays 3,000. Loss pays 1,900, then 2,400, then 2,900 from the third consecutive loss.
- A kill pays 200. A plant pays 300 per attacker. A defuse pays nothing extra.
- Pistol rounds start at 800. Credits don't carry across the half switch.
- Source: [ONE Esports](https://www.oneesports.gg/valorant/valorant-economy-guide-how-to-earn-credits-and-what-to-buy-with-them/). [F]
- Gfinity states the loss bonus cannot exceed 2,900 ([Gfinity](https://www.gfinityesports.com/article/valorant-economy-guide-money-explained-resource-weapons-equipment-abilities-pc)). [F]
- A bad-enough streak still funds a rifle (2,900 for a Vandal). [A]

**Takeaway.**
- Both games pair a capped, linear consolation with a hard reset at set points. [A]
- Neither pays much for the deciding action: Valorant's defuse pays nothing, and CS2's defuse pays only the defuser $300 with no team reward. [F]

---

## 2. Bounties and comeback mechanics in MOBAs

### League of Legends (Patch 14.21, October 2024)

**How it works.**
- Bounty is based purely on gold. A player accrues 1 bounty per 4 gold from kills and assists, and 1 per 20 gold from minions and monsters while positive. [F]
- Gold given away on death reduces the bounty by 1 per 4 gold.
- The first 100 bounty is not applied, so 400g of kills yields +100.
- A Shut Down clears the bounty. A bounty above 700 carries its remainder into the next life.
- A negative bounty lowers the base kill gold the victim's team gives up.
- Source: [official 14.21 notes](https://www.leagueoflegends.com/en-us/news/game-updates/patch-14-21-notes/).

**Why.** Riot's stated rationale:
- Bounties should be more intuitive; the streak-based calculation did not match player expectations.
- They are tuned to "generally reduce total gold given and to favor the losing team".
- Losing teams give up less gold in fights, so "games should snowball more slowly". [F]

**2025-2026 follow-ups.**
- A mini-rework in 2025 made bounties not fully reset on death and made objectives weigh more ([esports.gg, search summary](https://esports.gg/news/league-of-legends/next-lol-bounty-changes-should-mean-less-snowballing-devs-hope/)).
- A page I believe covers Wild Rift (the site name is "riftpatchnotes"; not verified) says Patch 7.2b tuned the bounty system because one-sided stomps fell sharply while comebacks rose only slightly. It aimed to stop leading teams feeling "overly punished for playing well" ([riftpatchnotes](https://www.riftpatchnotes.com/system/gold-xp)).
- [A] The lesson: a visible lead tax can overshoot, and the leader's reward for playing well needs protecting.

### Dota 2

**Streak and kill gold (7.31 notes, [Liquipedia](https://liquipedia.net/dota2/Version_7.31)).**
- Base hero kill bounty went from 120 + 8×level to 125 + 8×level.
- Streak gold changed from 100/135/170/205/240/275/310/345 to 60/100/150/210/280/360/450/550.
- The page's own formula (5x²+5x) does not reproduce its listed values, so I trust the listed values.
- Per a search summary of Liquipedia, streaks start at 3 kills and cap at 10, and ending a streak pays Shutdown Gold. I could not fetch that page.

**Reliable and unreliable gold.**
- Death penalties take only from the unreliable pool, and buyback spends reliable gold first ([ONE Esports, search summary](https://www.oneesports.gg/dota2/dota-2-7-26b-patch-breakdown-towers-buffed-hero-talents-and-denies-nerfed)).
- Buyback cost became 100 + Networth/13 in 7.11 ([GosuGamers, search summary](https://www.gosugamers.net/dota2/news/46622-understanding-patch-7-11-welcome-changes-in-disguise)).

**Opinion.** A 2023 Steam thread argued comeback mechanisms became over-rewarding. [O] I did not verify current live values.

### Deadlock (2026 patches)

This is the most recent fully checked comeback economy.

**Souls and bounties (6.30 patch, [Tracklock](https://tracklock.gg/articles/deadlock-update-06-30-26-patch-notes)). [F]**
- The minimum unsecured souls that drop on death went from 150 to 50 + 5 per minute.
- Base kill bounty went 250 to 200, with a max still 2,200 at 40 minutes.
- Trooper bounty went 116 + 1.16/min to 100 + 2/min.
- The deniable orb ratio went 40% to 50%.
- The Unstable Rift comeback bonus scales linearly from none at 0% net worth behind to full at 15% behind.
- The urn is now a standalone objective. The runner is not revealed, but the urn is louder.
- The urn bounty decays starting 45 seconds after pickup and drains over the next 45 seconds.

**Urn changes (6.04 patch, [Tracklock](https://tracklock.gg/articles/deadlock-update-06-04-26-patch-notes)). [F]**
- The overall urn bounty is reduced by 20%, except for the trailing team.
- The runner gets a 35% bonus on deposit.
- The trailing team's sprint bonus went from +4m to +5m, with +35% debuff resistance.
- The comeback aura shrank from 60m to 20m.
- Delivery became a capture point with 6s/12s/18s progress depending on whether you are favored, neutral or unfavored.

**Other details.**
- Per a search summary of the community wiki, orbs can be denied by shooting them. If an ally secures one, it is shared with the courier; the souls otherwise go to the courier.
- The same summary says a May 2026 change was reverted after a tournament team used a purchased item to manipulate the urn state ([deadlock.wiki, search summary](https://deadlock.wiki/Souls/Update_history)).
- [A] Valve moved from a flat leader tax toward scaled, linear-ramped comeback rewards that are only worth anything if you are behind. Souls at risk on death give a "bank or spend" rhythm without eliminating anyone.

---

## 3. Hidden-role and traitor economies

### Trouble in Terrorist Town (original gamemode)

I read the gamemode source.

**Starting credits.** Traitors start with 2 credits, plus 1 if alone. Detectives start with 1 ([init.lua](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/terrortown/gamemode/init.lua), [player_ext/equip logic](https://github.com/Facepunch/garrysmod/tree/master/garrysmod/gamemodes/terrortown/gamemode)). [F]

**Team-wide traitor award ([player.lua](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/terrortown/gamemode/player.lua), `CheckCreditAward`). [F]**
- When the dead innocents reach 35% (`ttt_credits_award_pct` = 0.35) of the innocent total, every living traitor gets 1 credit.
- It repeats each time another 35% have died since the last award.
- Killing a Detective gives the killer 1 credit.
- A traitor death gives all active Detectives 1 credit.
- Detectives get nothing for killing traitors (`ttt_det_credits_traitorkill` = 0).

**Spending and visibility.**
- Equipment costs one credit ([help page](https://www.troubleinterroristtown.com/help/gameplay/)). [F]
- The server sends your bought-items list only to you (`SendBought`). [F]
- Using a role-unique item can reveal your role ([wiki](https://troubleinterroristtown.wiki.gg/wiki/Roles)). Collecting credits from a body without being a Detective also reveals a traitor. [F]

**Why it works [A].** Credits come from the team's progress (kills crossing a share threshold), so no single player can farm them. Purchases are private while use leaks information, which makes buying and using separate tension points.

### Project Winter

- The Vol 2 rework gives traitors stat buffs for trapping and sabotaging objectives, and warmth and hunger gains for every 10 social credits ([Nintendo Everything](https://nintendoeverything.com/project-winter-power-balance-vol-2-update-out-now-patch-notes/)). [F]
- Staying near survivors fills an information wheel that reveals health, then role (same source). [F]
- Traitor crates give "traitor points" for special actions; remote sabotage costs 16 credits (search summary of patch notes). I did not verify beyond that.
- One reviewer called traitors the easier role ([search summary](https://store.epicgames.com/achievements/project-winter-3b9e84?lang=pl)). [O]
- [A] This is the closest traitor-economy analogue. Sabotage itself pays out as power, which is the design pattern our "one point per task sabotage" follows.

### Dread Hunger

- Thralls get spells from a bone charm. Per a [GamesFuze guide](https://gamesfuze.com/guides/dread-hunger-how-to-use-bone-charm/), those include a cannibal summon, a blinding storm, and a spirit walk lasting 15-25 seconds.
- Totems (3 wood + 1 bone) speed up spell recovery; the effect is maxed at 8 totems and does not reduce individual cooldowns ([wiki, search summary](https://dread-hunger.fandom.com/wiki/Totem)).
- [A] Power is gated by a craft step that costs visible time and resources, plus a cap. I could not verify anything about the resource economy beyond this.

### Other hidden-role references

- **The Traitors (TV show).** Missions add money to a shared pot. If any Traitor survives, they take the whole pot ([Wikipedia](https://en.wikipedia.org/wiki/The_Traitors_(American_TV_series))). [A] The point: the group's cooperative output is what the traitors win, which is the same dilemma as helping charge a generator.
- **Lockdown Protocol.** The Steam page lists no currency or upgrades, only cosmetic "Points Shop" items; it has 82% positive of 9,504 reviews ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)). [F] The one balance thread I found says small lobbies and task distribution make dissidents swingy ([Steam discussion](https://steamcommunity.com/app/2780980/discussions/0/6546631477890117789)). [O]
- **Among Us and Goose Goose Duck.** Both use cosmetic and meta currencies only ([PC Gamer](https://www.pcgamer.com/uk/big-among-us-update-adds-four-new-roles-an-xp-system-and-multiple-currencies), [GamerJournalist](https://gamerjournalist.com/how-to-get-gold-coins-in-goose-goose-duck/)). [F] I found no in-match economy for either.

---

## 4. Cash-out, extraction and quota economies

### The Finals

**Rules ([wiki](https://thefinals.wiki/wiki/Cashout)). [F]**
- Opening a vault starts a 20-second timer.
- A deposited box pays 20% immediately and 80% to whoever owns the station at timer end; the page also says the owner gets the full value, so it contradicts itself.
- Steals take 6-7 seconds and everyone is alerted when a Cashout goes active.
- Elimination pays $500 and a vault open $1,000. Depositing pays $2,000-$4,000.
- Respawn takes 30 seconds, or 15 if the team owned a Cashout.
- Finals are first to $50,000.

**Double Jeopardy.** If a second box is inserted into an active station and that team fails to hold it, it loses 50% of its total cash. This is meant to discourage griefing, and it is publicly announced.

[A] Value is earned in public and defended in public. The risk is an explicit, visible trade.

### R.E.P.O.

- Players deliver valuables to extraction and spend SURPLUS on permanent upgrades at a Service Station ([Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.)). [F]
- It peaked around 230,000 concurrent players and was the second-highest-grossing paid Steam game for the week of 11-18 March 2025 (same page, noted unsourced). [F]
- Upgrades cost roughly $2K (stamina) to $12K and rise as you progress ([Destructoid](https://www.destructoid.com/r-e-p-o-strength-chart-how-many-strength-upgrades-do-you-need-to-grab-everything/), [ProGameGuides](https://progameguides.com/r-e-p-o/all-items-and-upgrades-in-r-e-p-o/)).
- I could not confirm whether upgrades are shared or personal.

### Lethal Company

- Quota starts at 130. The quota increase formula is `100 × (1 + timesFulfilled²/16) × random(0.5-1.5)`, with no cap ([wiki, search summary](https://lethal-company.fandom.com/wiki/Profit_Quota)). The wiki and a mod doc agree on the base; it is reverse-engineered.
- Failing a quota loses everything.
- Forum users dispute the "early haul locks you into a high quota" claim ([Steam thread](https://steamcommunity.com/app/1966720/discussions/0/4038103682228231024)). [O]
- Unwinnable argues rising quotas are intentional: each success promises harder work ([Unwinnable](https://unwinnable.com/2024/02/16/lethal-company-and-the-ethos-of-the-bad-job/)). [O]

### Content Warning

- Views become money, and three days require 3k views at the start. Shop items run from $20 (flashlight) to $600 ([GGRecon](https://ggrecon.com/guides/content-warning-all-items)). Details are thin.

### Bounty carriers in battle royale and extraction

- **Warzone.** Taking the Most Wanted contract publicly marks you with a red crowned icon for all players, with a survival timer. Team kills cut 25s and cache opens cut 10s off the timer. Surviving pays cash and a squad revive ([Activision](https://blog.activision.com/call-of-duty/2020-04/Call-of-Duty-Warzone-Contracts-Most-Wanted)). [F] The 2025 Season 5 Reloaded notes say contracts return to Battle Royale Solos, award a UAV, and drop an airdrop near the survivor ([Sportskeeda](https://www.sportskeeda.com/call-of-duty-game/warzone-season-5-reloaded-patch-notes-2025)).
- **Hunt: Showdown.** Carrying a bounty reveals your approximate location to all hunters, shown as lightning bolts on the map ([Wikipedia](https://en.wikipedia.org/wiki/Hunt:_Showdown)). The 2025 event added a currency (Pledge Marks) that can be stolen from slain hunters; holders carry at most 6 ([Crytek](https://press.crytek.com/hunt-showdown-1896-confirms-date-for-desalle-return-and-brand-new-in-game-event-judgement-of-the-fool)).
- [A] The pattern: the more valuable your cargo, the more visible you are, and it is capped.

---

## 5. Roguelite run and meta progression

### Risk of Rain 2 (run scaling)

- The difficulty coefficient is `coeff = (1 + 0.3×(players−1) + minutes × 0.0506 × difficulty × players^0.2) × 1.15^stages`.
- Chest cost is `baseCost × coeff^1.25`, so prices climb faster than difficulty. [F] ([wiki](https://riskofrain2.wiki.gg/wiki/Difficulty)).
- [A] A convex price curve ties spending power to elapsed time, so early purchases are cheap and a late buyer pays a premium.

### Hades (meta progression)

- Chthonic Vitality has 3 ranks costing 10, 20 and 40 Darkness for +1 HP per room each, 70 total, and a full Mirror costs 35,365 Darkness for the red and green talents. A reset costs one Chthonic Key and refunds the Darkness ([Prima Games](https://primagames.com/gaming/hades-guide-mirror-of-night-upgrades-fated-list-of-prophecies), search summary).
- Commentators note an investment delay: upgrades take a while to pay off ([Mechanics of Magic](https://mechanicsofmagic.com/2025/11/04/loops-and-arcs-in-hades/)). [O]
- [A] Small, refundable, slow meta-steps keep early matches playable for newcomers.

### Battle-royale loot curves

- Apex loot rides on zone tiers. Helmets rise from 0.52% in Basic to 3% in High-tier zones. A random Hot Zone each match raises weapon share to 28% from about 21%, and up to one fully kitted weapon spawns there (data from Season 15, last edited October 2023) ([Apex wiki](https://apexlegends.wiki.gg/wiki/Loot)). [F]
- A search summary says Season 30 (August 2026) trimmed loot-gathering time by removing some supply bins and wildlife loot ([DotEsports](https://dotesports.com/apex-legends/news/apex-legends-season-30-looting-change-overhaul-corrupted-attachments)). I could not fetch the page to confirm.
- I found no designer source tying ring timing to loot quality, so I draw no conclusion there.

---

## 6. Party games with point stores and catch-up

- **Mario Party Jamboree.** Stars cost 20 coins. A shop item makes stars cost 40 coins for a chosen opponent ([MarioWiki](https://www.mariowiki.com/Star_(Mario_Party_series)), [AOL review](https://www.aol.com/super-mario-party-jamboree-learns-130000561.html)). Reviewers note bonus stars and luck cause swingy finishes. [O]
- **Mario Kart 8.** The item table is chosen by race rank at the moment the box is opened, so trailing players draw stronger items ([MarioWiki](https://www.mariowiki.com/Mario_Kart_8_item_probability_distributions)). [F] A critic calls the blue shell's targeting of the leader the most unfair design ([Cubed3](https://www.cubed3.com/features/opinion/8-examples-of-mario-kart-8s-broken-item-balancing)). [O]
- [A] Catch-up that targets the visible leader is a joke about the leader as much as a handicap. That fits a comedic tone, but players resent it when it feels arbitrary.

---

## 7. Information powers ("wallhacks") and how games keep them fair

| Game | Power | Duration, cooldown | Tell or counter |
|---|---|---|---|
| Valorant Sova | Recon bolt reveals enemies | 3.2-3.5s reveal; cooldown 35 raised to 40s in 4.08 ([The Spike](https://thespike.gg/valorant/agents/sova), [ONE Esports](https://www.oneesports.gg/valorant/sova-nerf-patch-4-08-shock-dart-drone)) | Destroyable; the shot reveals the shooter's position; patch 6.07 made the dart larger ([win.gg](https://win.gg/valorant-patch-6-07-makes-it-easy-to-destroy-sovas-recon/)) |
| Valorant Fade | Haunt reveals enemies in its sightline | 40s cooldown, shorter range, 12s black trails ([ONE Esports](https://www.oneesports.gg/valorant/tenz-fade-replace-sova/)) | Destroyable; designed as "recon at a personal level, more potent in a localized area" ([Engadget](https://www.engadget.com/valorant-fade-agent-announced-221805702.html)) |
| Apex Bloodhound | Cone scan | 25s cooldown, ~1.8s activation, 3s tracking, 75m max, 125° cone | Targets see an alert on screen ("SONAR DETECTED") per the wiki; the effect is visible to everyone (search summary of [Apex wiki](https://apexlegends.fandom.com/wiki/Bloodhound_(Mobile)) and [GameSpot](https://www.gamespot.com/articles/apex-legends-season-6-patch-notes-reveal-new-recon/1100-6481052/)) |
| Dead by Daylight, Nowhere to Hide | Reveals survivors near a generator | 3/4/5s by tier, range 24m, triggered by damaging a generator ([wiki](https://deadbydaylight.wiki.gg/wiki/Nowhere_to_Hide)) | Range tuning: 18m was tried in a test build, then reverted to 24m with the origin moved to the generator |
| Dead by Daylight, Object of Obsession | Counter | Reveals the reader's aura for as long as they read yours ([wiki, search summary](https://deadbydaylight.wiki.gg/wiki/Object_of_Obsession)) | The reader becomes visible while reading |
| Among Us cameras | Live feed | Always available | A red light shows others someone is watching; guides call it a tell ([allthings.how, search summary](https://allthings.how/every-among-us-map-explained-vents-cameras-and-kill-zones/)). The Admin map shows approximate room-level positions only (same source) |

**Fairness levers across these [A].**
1. Short duration, in single-digit seconds.
2. A cooldown or charge limit.
3. A narrow shape: a cone or range, not global.
4. A visible tell to the target or to everyone.
5. A cost, either a purchase or a trade-off.
6. A counter-action, such as shooting the dart, standing still, or a reciprocal perk.

Information is partial: Admin shows rooms, Seer's sensor gives direction without distance, and Fade adds trails. I found no source arguing whether the cost should be high or the cooldown long. Both approaches appear in the table.

---

## 8. Cross-game patterns

1. **Income is public and capped, or tied to team progress.** CS and Valorant cap the consolation. TTT awards by team threshold. The Finals pays on defended deposits.
2. **Consolation is capped and linear.** CS2 caps at the fifth loss and Valorant at the third. Deadlock ramps linearly with the gap and caps at 15% behind. Nobody gives unlimited catch-up.
3. **Leader taxes are dampened or have thresholds.** League's first 100 bounty is ignored and Wild Rift tuned the system back after overshooting. Deadlock cut the leader's urn bounty by 20% only for the leading team.
4. **Death costs the carried amount, not the whole.** Deadlock unsecured souls and Dota unreliable gold drop on death, while banked or reliable gold is safe.
5. **High-value cargo is visible.** Warzone, Hunt and The Finals reveal carriers or active cash-outs. A published risk sits next to the reward.
6. **Prices are convex over time or purchases.** Risk of Rain 2 uses coeff^1.25. Hades costs double per rank (10, 20, 40). R.E.P.O. prices climb with progress. Mario Party shows the opposite for stars: a fixed price with a sabotage item.
7. **Purchases are private, use is public.** TTT sends the bought list only to the buyer, but using an item can out the role.
8. **Information powers have six levers (section 7).** Games that skip the tell or counter get patched (Sova's dart enlarged, Nowhere to Hide range changed).
9. **Meta-progression stays cosmetic or small.** Among Us, Goose Goose Duck and Lockdown Protocol meta currencies are cosmetic. Hades is small steps with refunds.

---

## 9. Risks for our design

1. **Speed and stamina mutations feed back into point earning [A].** If a mutation raises task completion rate, it is a growth loop. The point pool is bounded, so the real contest is who captures tasks first, not total supply.
2. **Hiding the pool's size creates hoarding.** If players can't see how many points remain, they either rush or sit on points. CS2's cap is the counter: unspent money is wasted.
3. **Sabotage-then-complete is available to everyone [A].** Roles are mechanically identical. If sabotage pays a point regardless of who does it, aliens can sabotage-and-complete too for two points, and the human's unique lever disappears. The sabotage rule must say who benefits (see open question 1).
4. **Sabotage points reward self-harm for the aliens.** A task delay costs aliens time; whether it pays depends on pacing. This could make deliberate stalling a dominant strategy for everyone.
5. **The human budget is bounded by the aliens' goal [A].** Suppose the aliens need K completed tasks of T. Humans can complete at most K−1 without losing, so the points a human can earn from completions are capped by the win condition itself. That is the trade-off you want, but the values must make it real.
6. **Being outed starves the human of points, so they stop being a threat.** You said outed should be a disadvantage, not a loss. Without a consolation stream the human can fall behind on mutations and become irrelevant.
7. **See-through-walls dominates hide-and-seek play [A].** An outed human with no cover is easy to track. Without tells, a first-bought scan becomes the default.
8. **Dying costs nothing, so death can't tax points.** Respawn capsules make death a minor event. A death tax needs to be light, or it recreates elimination by another route.
9. **Meta-progression can break fairness across matches.** If the apparatus remembers power, veterans start ahead. Hades is the cautionary design: its steps are small and refundable.
10. **Public points leak roles.** A scoreboard split into task points and sabotage points would reveal humans. You want deduction to be non-central, but not trivial.

---

## 10. Options for the engineer

All values are placeholders.

### Option A: Convex pricing with a purchase cap
Each mutation bought raises the next price (for example 1, 2, 4 placeholder points). There is a total cap on mutations per player, and unspent points keep full value.

- **For:** Simple, matches Risk of Rain 2 and Hades. Slows the first-mover loop.
- **Against:** No help for a trailing player. The cap wastes points once reached.
- **Recommendation:** Adopt the convex curve and a cap on strong mutations; skip a global cap on points.

### Option B: A capped, linear consolation for outed humans
Points per sabotage rise from a base value to a cap as more aliens treat that human as outed. The trigger could be a public "outed" state.

- **For:** Matches "being outed is a disadvantage, not a loss". CS2 and Valorant cap the stream (sources above). Deadlock ramps it linearly with the gap.
- **Against:** Needs a clear, public definition of "outed". Players could feign being outed to trigger it.
- **Recommendation:** Apply it to the discount at the apparatus instead of extra points. That keeps the "one point per task, once" rule intact and is harder to farm.

### Option C: Carried and banked points
Fresh points are "carried" and drop partly on death; visiting the apparatus banks them. A death drops a fraction (placeholder) and nothing else.

- **For:** Gives a reason to visit the apparatus. Deadlock and Dota both use this shape.
- **Against:** Kills become profitable for the killer, which cuts against "killing is not a win".
- **Recommendation:** Only if the drop goes to a neutral pickup, not to the killer. Otherwise skip it.

### Option D: Scouting power with six levers
Make see-through-walls the top-price mutation. Give it a short pulse, a cooldown, a cone or radius, a visible tell on the user (eye glow, sound), and a counter (standing still, cover materials, or a rival mutation). Prices and effects are public.

- **For:** Every lever has precedent in section 7. Open knowledge fits: counters are known to all.
- **Against:** Hard to tune. Proximity voice may interact with the tell (a sound that is audible in the voice mix).
- **Recommendation:** Adopt it, and decide the tell first. A power with no tell was patched in multiple games.

### Option E: Accounting rules for task and sabotage points
Pin down exactly who earns what:
- One completion point for the doer.
- One sabotage point per task, once, to the first sabotager.
- No point for undoing your own sabotage.
- Locked tasks pay nothing more.

- **For:** Closes the farming loop and the "everyone sabotage-and-fixes" loophole at the cost of one extra rule.
- **Against:** Hard for players to track. A first-sabotager rule rewards speed.
- **Recommendation:** Adopt it, and decide whether sabotage counts toward the humans' win progress regardless of who does it.

### Option F: Visibility and reset rules
- Points total is private; mutations show on the body (a comic morph on a plasticine character).
- Points reset each match.
- Cross-match meta-progression is cosmetic or a side-grade, not raw power.
- A stealable, capped meta currency is not recommended.

- **For:** Mutations on the body double as the visible tell, and a buy station is a clue only through behavior.
- **Against:** A visible mutation list leaks who has been earning. Cosmetic-only meta may limit replay motivation.
- **Recommendation:** Adopt the body morph and per-match reset. Pick meta-progression separately, starting with cosmetics and unlocks of variety.

---

## 11. Open questions for the engineer

1. **Who earns a sabotage point?** Only the human side, or anyone who sabotages? If anyone, how do you prevent sabotage-then-complete becoming a universal 2-point play?
2. **Does the human win condition count sabotage by anyone, or only by humans?**
3. **How many tasks and how many points per match?** Is the pool (T tasks × 2 points) visible to players?
4. **Are points personal, team, or both?** Can a human's points be pooled or given away?
5. **What does "outed" mean mechanically?** A public vote, a flag, or a behavior trigger? Can it be cleared?
6. **Is the strongest mutation (see-through-walls) once per match, per round, or on a cooldown?** Does the user get a visible tell?
7. **Is the apparatus a single fixed place, and is using it visible to others?**
8. **Death tax: any, and where do dropped points go?**
9. **Reset: per match only, or do some mutations persist? What does meta-progression unlock?**
10. **Are point totals visible to others, partly or fully?** Fully visible totals leak roles; fully hidden totals remove the "who is farming" clue.
11. **Can an alien "help" a human complete a task to pass points?** Is that allowed or blocked?