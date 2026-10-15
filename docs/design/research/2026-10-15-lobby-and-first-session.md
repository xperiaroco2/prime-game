# The lobby as a play space and the first session: research report (round 3)

**Scope.** This round covers the lobby as a place to play (our lobby is the aliens' spaceship), the trip from lobby to match, the return after a match, onboarding in party and hidden-role games, role reveal screens, in-world hints, and hosting UX. I read these first and did not repeat them: `docs/design/research/README.md`; `docs/GDD.md` §1 (pillars) and §3 (the base loop at lines 76-92: Lobby, a 5 s Countdown, Loading, a 3 s Pregame with a dark screen showing your own role, Round, and a black, frozen, silent End); `docs/design/tutorial.md` §1 to §2 (the offline solo tutorial: nine lessons, two stand-ins, the first-launch invite); the round 1 meta report (B1 to B5 cover the friendslop wave, numbers included, and its risks section covers face sculpting); and the round 2 win report (the Werwölfe-style "balance hint"). `docs/design/m8-match.md` is not on `main`. I read it from commit `7b58a2b3a` (#1090). It leaves open how the trip maps onto Lobby, Countdown, Loading and Pregame.

**Tags.** [V] means I verified it on the cited page. [V-s] means it comes only from a search-result summary because the page refused the fetch (403, 402 or 404). [P] is a player's or critic's opinion. [A] is my analysis. **The shared web-search budget ran out after about 45 searches and 25 fetches.** Some planned checks were never run: the Fall Guys round-intro screen, the Among Us role-intro screen, and the Lethal Company end-of-day screen in detail. Those items are marked "not verified" below.

---

## Part A. Lobbies that are fun on their own

### A1. Among Us: the waiting room is a small map with one terminal
- **Mechanism** [V-s]: players spawn in a room styled like a map's dropship. One laptop serves two jobs: anyone can change their own look there, and only the host can change the match options there. Cosmetics can only be changed in a lobby ([wiki via search](https://among-us.fandom.com/wiki/Practice), [PC Gamer](https://pcgamer.com/how-to-customize-your-character-in-among-us)).
- **Practice mode** (formerly Freeplay) [V-s]: solo and offline, with still "dummy" crewmates. A laptop lets you add or complete tasks and switch your role to the traitor. The dummies reset when enough of them die or when you finish your tasks ([wiki](https://among-us.fandom.com/wiki/Practice)).
- **Update 16.0.0 (25 Mar 2025)** [V]: a lobby browser with filters for map, roles, player speed and other settings, plus **skill tags (Beginner, Intermediate, Expert)** that a host picks when creating a game. The settings "can still be edited once you're in the Dropship". The reason given was the player survey ([Innersloth](https://www.innersloth.com/a-match-made-in-update-16-0-0-emergency-meeting-40)).
- **Why it works** [A]: the lobby is part of the game world, so you move with the match's controls from second one, and the one terminal is the obvious thing to walk to.
- **What goes wrong** [A]: there is nothing to *do* except walk and dress up. The fun depends on the people in the room.
- **Our map** [A]: our lobby already lets players walk, crouch, sneak and use proximity voice (GDD §3, line 78; crouch and sneak everywhere since #989). The ship needs at least one obvious terminal (settings for the host, the look for everyone), and the Beginner tag idea matters for public play later.

### A2. Splatoon: the wait is practice time, plus a warning
- **Splatoon 3** [V]: the lobby has a test range with fixed targets, targets that shoot back, a wall for practising specials, and a button that cleans up the ink. Friends appear as "ghosts" ([Shacknews](https://www.shacknews.com/article/132026/splatoon-3-multiplayer-test-range-lobby)). Developer Sato: "we put in quite a lot of effort so that players can have fun even while waiting for the match to start", and players should "feel the presence of others right then and there, even before the battle starts" ([Nintendo, Ask the Developer](https://www.nintendo.com/en-za/News/2022/September/Ask-the-Developer-Vol-7-Splatoon-3-Chapter-3-2263040.html)).
- **Splatoon 1** [V-s]: a jumping minigame on the GamePad during matchmaking. One source says you can get so absorbed that you "end up missing the start of your online match". Splatoon 2 dropped it ([Splatoon wiki via search](https://splatoonwiki.org/wiki/Arcade)).
- **Loading minigames used to be patented** [V-s]: Namco's US 5718632 covered "auxiliary game program code" played while the main game loads, and it expired on 27 Nov 2015 ([TechRaptor](https://techraptor.net/gaming/news/patent-loading-screen-minigames-finally-expires), [Techdirt](https://archive.techdirt.com/articles/20151127/06515332914/patent-mini-games-within-loading-screens-expires-explosion-better-game-loading-screens-forecasted.shtml)). Not legal advice. Today this only matters as history.
- **Our map** [A]: the best lobby toy is the match's own verbs (throwing, knocking down, raising, sneaking, the muffled-voice wall). That teaches and entertains at once. A toy that is a separate game pulls attention away from the Ready step.

### A3. Deep Rock Galactic's Space Rig: a hub full of physical jokes
[V] from the [Space Rig wiki](https://deeprockgalactic.wiki.gg/wiki/Space_Rig):
- **Toys:** 25 kickable barrels, one of them green; some barrel actions trigger a Mission Control line. A barrel hoop that slides sideways, with a counter. Jumping through the hoop "harms you and sends you to the Medbay". A button that gives everyone slow-motion low gravity. A small football game with goals you place yourself. An arcade cabinet whose high-score table sometimes shows fake scores from in-world characters (2% chance each for some names).
- **The bar:** drinks get you drunk, and passing out sends you to the Medbay. **Wall monitors in the Medbay count each player's downs and how many times they passed out from drinking.**
- **Starting a mission:** only the host can use the mission terminal. Choosing a mission powers up the drop pod and opens it. "The host standing inside the pod for 15 seconds forces the mission to start. If the whole team is inside, this drops to 5 seconds."
- **Seasonal dressing:** the bar changes for events, e.g. Rocktoberfest 2025 ([wiki via search](https://deeprockgalactic.wiki.gg/wiki/Space_Rig)) [V-s].
- **Why it works** [A]: every toy is physical and visible to everyone, so watching someone fail is shared entertainment. The low-stakes "death" (the Medbay) is a joke, not a punishment. The launch rule makes Ready a *place* to stand, with a fallback for when someone dawdles.
- **What goes wrong** [A]: a hub this rich costs a lot of content. Several barrel tasks take hours, which suits a game played for hundreds of hours, not a 10-minute party.
- **Our map** [A]: three ideas fit us closely. (1) Ready as standing in a launch zone, with a host fallback timer. (2) A harmless "faint" in the lobby that only moves you (it matches our respawn pillar). (3) A wall that counts silly lobby stats.

### A4. PEAK's airport: a lobby added to after launch
[V] from the [PEAK Airport wiki](https://peak.wiki.gg/wiki/Airport):
- You spawn in elevators "whose doors open after a few seconds", which is a small entrance.
- **A mirror** shows your character and emotes. **A passport** customizes your look. A climbing wall tests movement. Two conveyor belts run in opposite directions and carry players standing or ragdolling on them.
- **Chess pieces and basketballs** were added in 1.30.a (23 Sep 2025, three months after the 1.0 launch on 16 Jun 2025). A patch two days later made the hoop count any thrown object, and it fires confetti.
- **A photobooth:** a 3 s countdown, four photos, and an automatic screenshot when the photos are shown.
- **The gate kiosk** starts an expedition and shows a boarding pass. **The invite kiosk** invites Steam friends.
- Seasonal reskins came and went (Halloween 1.35.a, holidays 1.50.a, reverted 1.52.a).
- The run starts when the plane crashes onto the shore ([Wikipedia](https://en.wikipedia.org/wiki/Peak_(video_game))) [V-s]. I did not verify the crash cutscene itself.
- **Why it works** [A]: every toy reuses a core system (climbing, throwing, ragdolls), and the photobooth makes a souvenir that gets shared, which is free advertising.
- **What goes wrong** [A]: the passport is lost after takeoff ([Thunderstore mod note](https://thunderstore.io/c/peak/p/tony4twenty/Plane_Crash_Passports)) [V-s], so the look is fixed once you leave.
- **Our map** [A]: a ship photobooth that frames the whole crew fits our photo task (GDD, Photography). The camera code already exists.

### A5. Sea of Thieves taverns: synchronised joining
- [V-s]: when two players play instruments, the first leads the shanty and anyone who joins plays backing in sync. Drunk players play out of tune. There are commendations for drinking or doing a "Make Friends" emote *at the same time* as another crew ([wiki via search](https://seaofthieves.wiki.gg/wiki/Instruments)). The onboarding is a 15-minute tutorial island, replayable from the main menu ([Shacknews via search](https://shacknews.com/article/115766/maiden-voyage-campaign-guide-sea-of-thieves)) [V-s].
- **Why it works** [A]: joining in costs one button and always sounds good, so strangers make something together in seconds.
- **Our map** [A]: a group dance or music toy where each extra player adds a layer fits "aliens throw the best party". The party music can then be the same in-world object that annoys the neighbours in the match.

### A6. Content Warning's house: a tiny face editor and the screening
- **The face** [V-s]: a screen in the house lets you type **up to three characters** as your face, then rotate, scale and recolour them ([Dexerto](https://www.dexerto.com/gaming/content-warning-how-to-change-faces-2624084/), [GGRecon](https://www.ggrecon.com/guides/content-warning-how-to-change-faces/)).
- **The return** [V]: a TV in the house, "in front of a sofa and two wooden chairs", plays the footage you extracted. Views tick up "in real time", and commenters react to the items and monsters on screen. Afterwards you can save the film as a .WebM, rewatch it, or close it; once closed it cannot be reopened ([Content Warning wiki](https://contentwarning.wiki.gg/wiki/TV)).
- **Why it works** [A]: the score comes with the replay of your own failures, watched together on a couch with voice on. That is the laugh.
- **Our map** [A]: our End is a black, frozen, silent screen (GDD §3, lines 91-92). Content Warning puts the debrief *in the hub, with voice*. That is the strongest single lesson for "the return".

### A7. Lethal Company's ship and R.E.P.O.'s truck
- **Lethal Company** [V-s]: furniture is bought at the terminal and can be moved, rotated and stored. The stock changes per quota ([Prima](https://primagames.com/tips/how-to-move-furniture-in-lethal-company)). A player pulls the lever to land once a moon is chosen ([Prima](https://primagames.com/tips/tips-and-tricks-for-new-players-in-lethal-company)). Guides say "in-game tutorials are scarce" and that new players learn from the terminal's `help` ([Steam thread](https://steamcommunity.com/app/1966720/discussions/0/3944651039520816478)) [P].
- **End-of-day notes** [V-s]: "Most Profitable" goes to whoever brought in the most scrap value, "Laziest Employee" to whoever took the fewest steps, and "Most Paranoid" to whoever turned the camera most ([SuperCheats via search](https://www.supercheats.com/lethal-company/employee-notes-in-lethal-company-explained); I could not fetch the page or verify a fourth note).
- **R.E.P.O.** [V]: between levels you shop at a "Service Station". Update 0.4.0 (7 May 2026) added cosmetics, a redesigned shop and a racing mode ([Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.)), with over 500 cosmetic items ([search summary of Destructoid](https://destructoid.com/r-e-p-o-cosmetics-update-patch-notes)) [V-s]. A mod's description says it lets "your head open much wider when you speak" (default 45). That implies the base game opens the avatar's head with your voice ([Thunderstore](https://thunderstore.io/c/repo/p/DuckyVR/CrazyHeadRotations/)) [V-s, inferred].
- **Our map** [A]: stats that are silly but true ("fewest steps") make laughs out of real data. A body that reacts to the voice shows who is talking without any HUD, which suits a proximity-voice game and plasticine faces.

### A8. Two 2026 entries and a genre request
- **Yapyap (2026)** [V-s]: a hub you return to after each run. A grimoire upstairs reveals a wand's spoken incantations if you hold the wand and read it. You start a run by walking to an orb and activating it ([Into Indie Games](https://intoindiegames.com/walkthroughs/tips-tricks/ultimate-guide-to-yapyap/)). The rules are learned from an object in the hub, not a menu.
- **Meccha Chameleon (Jun 2026)** [V-s]: hiders get a preparation phase to paint and pose while hunters are locked out, so practice happens inside the match ([player.one](https://www.player.one/meccha-chameleon-controls-guide-default-pc-keybinds-paint-mode-beginner-tips-163583)).
- **Lockdown Protocol players asked for this** [V]: a 13 Oct 2024 thread asks for a "firing range, tasks, minigame exclusive to lobby", and for hosts to control weapon spawns and ammo ([Steam](https://steamcommunity.com/app/2780980/discussions/0/4692279523714716353)). The store lists Early Access on 22 Jul 2024 and release on 18 Nov 2025 ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)) [V], and mentions no host settings. A forum reply attributed to the developers says more weapons "just becomes a murder fest" ([Steam](https://steamcommunity.com/app/2780980/discussions/0/4754200750486400770)) [P, unconfirmed]. **I could not verify the "none / normal / lots" weapon setting in M8 §7 as Lockdown Protocol's.** Treat the reference as the engineer's memory.

---

## Part B. From lobby to match: launch as theatre

- **DRG**: the pod as the Ready button (A3) [V]. A match starts with players "inside the descending Drop Pod just before it lands". The pod is a Safe zone for about 27 s after landing (1% damage, enemies cannot climb in). A player who keeps stepping in and out makes the beep drop in pitch, and then the pod "closes and the mission starts suddenly" ([Drop Pod wiki](https://deeprockgalactic.wiki.gg/wiki/Drop_Pod)) [V]. That is a joke built into the rules.
- **PEAK**: the boarding pass at the gate, then a crash that puts everyone on the shore (A4).
- **Fortnite**: a pre-game island where nobody takes damage, then a 10 s timer, then the bus ([Fortnite wiki via search](https://fortnite.fandom.com/wiki/File:Spawn_Island_(C2S5_-_Hangar_1)_-_Location_-_Fortnite.png)) [V-s]. Epic sped the bus up after players complained it took too long ([mein-mmo](https://mein-mmo.de/en/the-battle-bus-in-fortnite-now-flies-faster-at-fan-request,280743)) [V-s]. Transition theatre has a speed limit.
- **Among Us role intro**: not verified live (search budget). From memory: a short screen naming your side, and teammates for the traitors. Do not rely on this.
- **Why launches work** [A]: (1) the trip *explains the fiction*: we fly down, we land, we party. (2) It hides loading behind something to watch. (3) It is a shared beat ("here we go") that sets the energy before the first second of play.
- **What goes wrong** [A]: anything longer than the loading itself is boring the 20th time, so a skip or a short version for veterans matters (Fortnite's bus). A role screen whose timing or shape differs by role can leak the role.
- **Our map** [A]: our Countdown (5 s) and Loading are already separate phases (GDD §3, lines 80-83), and Pregame is 3 s of a dark screen during which nobody hears anybody. The descent can *be* the Countdown plus Loading, and Pregame stays the private beat. Keeping Pregame silent is a feature: nobody can react to their role out loud.

---

## Part C. The return: results, replays, laughter

- **Content Warning**: the replay *is* the result, on a couch, with voice (A6) [V].
- **Lethal Company**: true but silly superlatives (A7) [V-s].
- **Mario Party bonus stars** [V-s]: from Mario Party 7 on, three of six bonus categories are drawn at random at the end. Players find this both "fair" (you can't rig it) and "deflating" when a player with no stars wins ([MarioWiki](https://www.mariowiki.com/Bonus_Star), [Zatu review](https://zatu.com/en-us/blogs/reviews/super-mario-party-review)) [P]. **Superlatives must never change who won.**
- **Overwatch Play of the Game** [V-s]: an algorithm picks a highlight. Kaplan said some plays "aren't showing great" (a turret's kills after its owner died, a long-range shot) and planned a more cinematic camera ([TweakTown via search](https://www.tweaktown.com/news/52434/overwatch-play-game-feature-cinematic/index.html)). An automatic highlight needs a camera that reads well.
- **DRG Medbay monitors** count downs and pass-outs (A3) [V]. That is a persistent tally of embarrassments, in the hub.
- **Our map** [A]: our End names only the winning side. The roles are dealt privately but are not protected (GDD §1). After the match there is nothing left to hide, so the return can reveal everything: who was human, what each side did, who triggered the cops. That is the "laughter" beat our design now skips. One project fact limits the replay route: the host's command logs are kept only in debug builds (10 newest, `ReplayFiles.KEEP`, `docs/design/tutorial.md` §2.1). A replay that players see would be new work, not a reuse.

---

## Part D. Onboarding without long tutorials

### D1. Principles with sources
- **One decision at a time** [V]: Jackbox's games "never ask for several choices at once". Creative director Allard Laban judges every interface by whether "my aunt's going to find it very difficult", and private instructions go to each player's own phone ([Built In](https://builtin.com/media-gaming/jackbox-games-design-party-pack)). This goes back to Harry Gottlieb's "Jack Principles" (GDC 1997): keep the pace, and make sure people know what to do next ([Karl Kapp](https://karlkapp.com/in-games-and-learning-interfaces-strive-for-an-interactive-conversation-interface/)) [V-s].
- **Veterans may skip** [V]: in Job Job "first player in (VIP) can still skip the intro/tutorials in the moment" ([Jackbox PP8](https://jackboxgames.com/streaming-moderation-accessibility-features-jackbox-party-pack-eight)). The tutorial is part of the match, and one person decides whether the group needs it.
- **Rules arrive when needed** [V]: "Clocktower is designed to explain the rules to players piecemeal". Voting rules come "just before their first vote". The order is theme, then goal, then rules, and the rules sheet "takes no more than five minutes to read". A practice round: "I've never found this is needed". Opening remarks exist "to put the players at ease, to remove any anxiety" ([BotC](https://bloodontheclocktower.com/blogs/news/explaining-the-rules-to-new-players)).
- **A newcomer among veterans** [V]: "Many enthusiastic veteran players tend to overload new players with information". "They need to know that it is okay if they die". Give a newcomer a role that lets them "enjoy their first game without fear of death" ([BotC Storyteller Advice](https://wiki.bloodontheclocktower.com/Storyteller_Advice)).
- **Train with the world** [V]: "Portal is effectively an extended player training exercise" (Robin Walker). "We start players in a visually unique room with memorable objects" (Kim Swift). Playtesters "would charge down the stairs without noticing what was creating the portals" (Jason Brashill) ([Portal commentary](https://theportalwiki.com/wiki/Portal_developer_commentary)).
- **Attention is scarce** [V-s]: Celia Hodent's deck says players "can hardly read tutorial text while busy fighting enemies" and to "reduce memory load" ([IxDA PDF via search](https://interaction19.ixda.org/download/talk-the-ux-of-fortnite-celia-hodent.pdf)).
- **Explain in a sentence** [V-s]: Fall Guys' Joe Walsh wants to explain a level "within a sentence" and to let players have a good time "without tutorials on every single level" ([PCGamesInsider via search](https://www.pcgamesinsider.biz/feature/69833/how-mediatonic-made-the-takeshis-castle-of-video-games-in-fall-guys/)).

### D2. What goes wrong in the genre
- **Dread Hunger**: a 25-minute tutorial that never lets you play the traitor ([GamingTrend via search](https://gamingtrend.com/reviews/dread-hunger-review-the-waters-not-as-deep-as-it-seems/)) [V-s, P]. New players meet the hidden role cold.
- **Project Winter**: a player wrote that after "30 min collecting wood, losing" a newcomer will "UNINSTALL" ([Steam](https://steamcommunity.com/app/774861/discussions/0/2268068817148846439)) [P]. The studio later added a faster mode, "Cabin Fever", that is easier for new players ([search summary](https://www.pcgamer.com/uk/project-winter-a-survival-game-all-about-lies-and-betrayal-leaves-early-access-soon)) [V-s].
- **Rainbow Six Siege**: a newcomer playlist with three maps and a level cap of 50, then an onboarding redesign in Siege X (10 Jun 2025) ([devtrackers](https://devtrackers.gg/r6-siege/p/e49946ff-dev-blog-playlist-improvements), [BusinessWire](https://secure.businesswire.com/news/home/20250313917397/en/Rappel-Into-a-New-Era-With-Tom-Clancys-Rainbow-Six-Siege-X-Available-on-June-10)) [V-s].
- **Voice games**: Lethal Company threads report mics that silently don't work and tinny voice ([Steam](https://steamcommunity.com/app/1966720/discussions/0/3944650879128886928)) [P]. Another game's new player could not tell which key tested the mic ([Steam](https://steamcommunity.com/app/2960770/discussions/0/595135824845137670)) [P].

### D3. Our map
[A] Our tutorial is solo and offline, with nine lessons on controls and systems (`tutorial.md` §1), and since #825 it has no tasks. It cannot teach the things that make *our* match: the two win conditions, points, the neighbours' anger, and "being outed is not a loss". The BotC and Jackbox pattern fills that gap: the first match teaches itself just in time, a veteran or the host can skip it, and the lobby shows the systems live. The voice lesson (lesson 8) checks the mic against a stand-in. The ship should repeat that check socially ("can you hear me?" is the first sentence of every party).

---

## Part E. Hosting UX: presets and a balance hint

- **Among Us (Oct 2018)** [V]: "Reset To Defaults" became a "Recommended Settings" checkbox that "will automatically adjust the number of impostors and kill cooldown settings as players join" ([Innersloth devlog](https://innersloth.itch.io/among-us/devlog/53996/balance-tweaks-in-among-us-20181029)).
- **Phasmophobia** [V]: custom difficulty with up to 3 saved presets. "Each option is tied to a reward multiplier" ([Kinetic](https://kineticgames.co.uk/news/phasmophobia-apocalypse)). The multiplier works as a running "how hard is this" readout.
- **Jackbox** [V-s]: a family-friendly filter that does *not* filter player content, plus a separate moderation tool. Official advice for public play: turn both on ([search summary of Jackbox blogs](https://www.jackboxgames.com/blog/safety-and-moderation-streaming-jackbox-games)).
- **The balance hint**: round 2 proposed a Werwölfe-style score sum in the lobby (`2026-10-15-win-and-pacing.md`, lines 184 and 260). This round adds two delivery forms: an auto-adjusting default and a single readout.
- **Our map** [A]: the host will have at least the number of humans (M8 §2), the anger threshold (M8 §5) and weapons none/normal/lots (M8 §7), plus per-task subtask counts (#256). That is too many knobs for a party host. Presets with one "who is favoured" readout, plus an auto default that follows the player count, are the proven shapes.

---

## Part F. Cosmetics and the face in the lobby

- **Identity before beauty** [V-s]: in Among Us, colour is the main way to tell players apart. Each new colour must "stand apart enough from the other colors to avoid being a source of confusion", and Innersloth said it wanted to "slowly move away" from colour as identification ([Sportskeeda](https://sportskeeda.com/esports/news-among-us-developer-updates-12-15-player-games)).
- **Tight limits** [V-s]: Content Warning's face is three characters (A6).
- **Free-form creation gets abused** [V-s]: within weeks of the Spore Creature Creator's June 2008 release, YouTube filled with genital creatures ("sporn"). Producer Lucy Bradshaw: "whether it's modelling clay, dolls or crayons, a small number of people can be counted on to use it for something vulgar". EA warned, then suspended, then removed accounts. Will Wright: "We just have to make sure those people aren't messing up the experience for others" ([bit-tech](https://bit-tech.net/news/gaming/ea-clamps-down-on-sporn/1), [GameSpot](https://www.gamespot.com/articles/wright-appraises-sporn/1100-6234442/)). Gamesradar noted many survived the censors ([Gamesradar](https://gamesradar.com/spores-rudest-creatures)) [P]. **This is the missing source on sculpt moderation from round 1, and it names modelling clay.**
- **Local host tools** [V-s]: Jackbox's VIP can hide or skip another player's drawing on screen ([search summary](https://www.jackboxgames.com/blog/safety-and-moderation-streaming-jackbox-games)).
- **Show it off where people are** [V]: PEAK's mirror, DRG's wardrobe in the hub (A3, A4).
- **Our map** [A]: plasticine faces made in the lobby are the most on-brand part of the first second. The tone pillar allows cringe but not every shape, and round 1 already flagged that a face must never leak a role.

---

## Mapping to our game, in short
[A]
- **The ship already exists as a level** (`levels/lobby/lobby.tscn`) with movement and voice. What it lacks: things to do, the fiction (a ship that flies down), a social return, and a lesson in our *match* rules.
- **Our "first second" has three parts**: the first launch (the tutorial invite, `tutorial.md` §1), the first lobby, and the first match. The tutorial covers controls. Nothing yet covers sides, points, anger or the cops.
- **Hidden-role limits on lobby toys**: in the lobby nobody has a role yet, so anything there is safe. Pregame and End are where leaks or reveals happen.

## 1. Cross-game patterns
1. **The lobby teaches with the core verbs**: Splatoon's range, PEAK's climbing wall and hoop, DRG's physics barrels, Among Us's practice laptop. Separate minigames distract (Splatoon 1's "missing the start").
2. **Ready is a place or an action, with a fallback**: DRG's pod (15 s for the host alone, 5 s for the whole team), PEAK's gate, Yapyap's orb.
3. **One terminal, two audiences**: everyone's look plus the host's rules (the Among Us laptop).
4. **Small toys added after launch carry long-tail updates**: PEAK 1.30.a three months after launch; seasonal reskins at DRG and PEAK.
5. **The debrief happens in the hub, with voice, and is funny because the data is true**: Content Warning's TV, Lethal Company's notes, DRG's monitors.
6. **Rules come just in time, and veterans may skip them**: BotC, Jackbox's VIP skip, Splatoon's warm-up.
7. **Hosts get a default that adjusts to player count, plus presets with a readout**: Among Us, Phasmophobia.
8. **Free-form creation needs a limit or a local "hide"**: Spore, Content Warning, Jackbox.

## 2. Risks for our design
- **The lobby is more fun than the match**: players linger and the Ready step stalls (Splatoon 1). Mitigation: a launch rule with a host fallback.
- **The launch drags on the tenth run**: theatre has to fit inside the real loading time, with a short version (Fortnite's bus).
- **The role screen leaks**: different length, sound or animation per role can be read off a stream or a face cam. The text must differ, nothing else.
- **The first match is unreadable**: two win conditions, points, anger and the cops all at once. Veterans "overload" the newcomer (BotC).
- **A silent, frozen End wastes the laugh**: the reveal is where comedy pays off.
- **Face abuse**: the Spore history says it happens within weeks. Party hosts play with friends, but streamers do too.
- **Role leak through looks**: round 1's risk stands.
- **Content cost**: one engineer with agents. Each lobby toy is ongoing upkeep (a bot scenario, the leak test if it touches roles, docs).
- **Mic failures in a voice game**: a newcomer whose mic doesn't work has no fun at all.

## 3. Options for the engineer (not decisions; every value is a placeholder)

**Option 1: the ship as a sandbox of the match's verbs.** The ship holds one live sample of each match system, with no stakes. Throwable party junk. A "practice guest" stand-in to knock down and raise (the tutorial's stand-in code, `tutorial.md` §2.2). A soundproof door showing how walls muffle voice. A small toy anger gauge next to a speaker, which fills when players bang things and triggers a harmless ship-side joke (lights flash, a recorded voice complains) instead of cops.
- Pro: teaches the open-knowledge rules (anger, muffling, raising) in the first minute, with no text. It reuses existing parts and is cheap per item.
- Con: every toy is upkeep. The toy gauge must read as clearly *not* the match's rule (different numbers).
- **Recommended first.**

**Option 2: the descent as Countdown and Loading, and Ready as a place.** Players get ready by standing on a launch pad in the ship's drop bay (placeholder rule: everyone on the pad starts the 5 s Countdown; the host alone for 15 s forces it; anyone stepping off cancels, as today). The countdown and loading show the ship diving to the House, ending with the doors opening. Pregame keeps its 3 s and its silence.
- Pro: gives the fiction ("each match they fly down") a body, hides loading, and turns Ready into play.
- Con: needs a ship model and animation, plus a short version. A pad rule changes the `SetReady` intent's UX (the state machine itself is unchanged).
- Recommended second, after Option 1.

**Option 3: a role card that reads the same and says one sentence.** Same layout, length and sound for both sides; only the words differ. Line 1: your side ("You are an alien" / "You are a human in disguise", placeholders). Line 2: one sentence on your goal. Line 3: one first thing to do. On a player's first match (a `user://` flag, like the tutorial invite), the card stays up for a placeholder 8 s instead of 3 s, but only on that player's own screen. The host's clock is unaffected, because everyone else is still in the dark screen too.
- Pro: BotC's "theme, goal, rules" in three lines, and no role leak by timing.
- Con: the 8 s happens before the round clock starts. Making the Pregame length per peer needs a check against the phase machine. It may be easier to keep 3 s everywhere and let Option 4 carry the rest.
- Recommended as the minimum (same layout and length); the longer first-time card is optional.

**Option 4: a first-party guide, just in time and skippable.** For a player's first few matches (placeholder: 2), short HUD hints appear on first contact: the first time the anger meter moves, the first death, the first time points can be spent, the first time the cops are called. Each hint is one line, shown once. The host can turn the guide off for the whole room (Jackbox's VIP skip), and each player can turn it off in settings. Optionally, a "first party" badge on the nameplate that the host can disable.
- Pro: covers what the solo tutorial cannot, follows Hodent and BotC, and costs nothing for veterans.
- Con: hints must come from the player's own filtered events only (invariant 2), never from the host's state. The badge can attract either help or bullying.
- **Recommended.**

**Option 5: the after-party on the ship.** Keep End short (placeholder 3 s, black, the winning side). Then everyone is back on the ship with voice on, and a big screen plays the reveal: who was human, then 3 or 4 superlatives drawn from a pool of true stats (placeholder examples: most mischief, most points spent on stalling the cops, most raises, fewest steps), then a "how the cops were called" timeline. Superlatives never change the result. Later: a short replay clip of one moment.
- Pro: puts the laugh beat where Content Warning puts it. All the data is post-match, so there is no leak.
- Con: needs a host-to-all results event after End, which is new wire work, and a screen in the ship. A visible replay is a larger feature (logs are debug-only today).
- **Recommended** once the M8 match is playable.

**Option 6: host presets plus one balance readout.** A few named presets (placeholders: "Chill", "Standard", "Mayhem"), each bundling the number of humans, the anger threshold and the weapons level. An "auto" default for the human count follows the player count as people join (the round 2 table is a placeholder). One readout shows which side the current settings favour, computed from the balance model (#1089). Editing any knob switches the preset to "Custom" and keeps the readout live.
- Pro: one decision for a casual host, full control for a tinkerer (Jackbox, Among Us, Phasmophobia).
- Con: the readout is only as honest as the model. It must be labelled an estimate.
- Recommended when the settings land.

**Option 7: a sculpting booth with limits and a local hide.** Faces are shaped in a ship booth facing a mirror, visible to others (the PEAK and DRG pattern). The tool is constrained: a fixed base head, a small set of push, pull and pinch tools, symmetry on by default, volume and protrusion caps (placeholders), no free-text decals. Any player can hide another player's face on their own screen only, replacing it with a stock face (Jackbox's VIP pattern, made local). Faces are role-neutral by construction: everyone is an alien in the fiction.
- Pro: the most on-brand fun-in-the-first-second feature, and it uses the Spore lesson before the problem arrives.
- Con: caps reduce comedy; the cap level is a matter of taste for the engineer. Sync cost: a face has to travel as compact parameters, not a mesh.
- Recommended for M8.3, as planned.

**Option 8: a ship that remembers.** The ship carries the host's history as decoration: a tally wall (cops called, fires started, parties won per side) and a souvenir shelf of photos from the photo task or a ship photobooth.
- Pro: DRG's monitors and PEAK's photobooth both make laughs and screenshots, and this is a hook for meta-progression without power.
- Con: persistence per host; faces and photos need the same moderation thought as Option 7.
- Optional, later.

**Recommendation in short** [A]: build Option 1 and Option 3's same-layout rule first (cheap, and they protect the pillars). Then Option 4 and Option 2. Option 5 once the match is playable, Option 6 with the settings, and Option 7 in M8.3.

## 4. Open questions for the engineer
1. Should Ready be a place (a pad in the drop bay) or stay a button? If a place, should the host have a forcing timer?
2. Should the role card stay 3 s for everyone, or may a first-timer's card last longer on his own screen?
3. Should a newcomer be visible as one (a badge), or should the first-party guide be private only?
4. What should the after-party reveal: the roles, superlatives, the cops' timeline, a replay? And how long may it run before Ready opens again?
5. Should the ship have a toy anger gauge, or does that confuse the real rule?
6. Which presets, and does the host want a balance readout at all?
7. Face sculpting: how tight are the caps, is there a local hide, and should a sculpt be saveable and shareable?
8. Is a lobby with strangers (public play) in scope? Skill tags, kicks and moderation follow from that answer.
9. Should the ship visibly fly (the descent as theatre), and does the House's garage tech (M8 §1, open) become a ship part?

## Could not verify
The Among Us role-intro screen; the Fall Guys round-intro screen; the Lethal Company performance-report grade and its fourth note; the PEAK crash cutscene; Lockdown Protocol's "none / normal / lots" weapon setting; and whether Lethal Company has a first-day orientation. The shared web-search budget ran out before these could be checked.