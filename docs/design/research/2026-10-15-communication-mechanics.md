# Communication as a mechanic in proximity-voice games, and tools to help or disrupt it

## 0. Method, confidence and what this builds on

**Tags.**
- **[V]**: verified on a page I fetched or in primary source code.
- **[V, snippet]**: comes only from a search-result summary. I did not read the page.
- **[P]**: a player's or writer's opinion.
- **[A]**: my analysis.

**Effort.** About 50 web searches, 22 fetches and 8 reads of primary source code through `gh api` (BetterCrewLink, Garry's Mod TTT). The session's shared search budget ran out near the end, so two questions stayed unchecked: whether R.E.P.O. has public lobbies, and how Among Us 3D handles voice moderation. Many wikis refused the fetch (Fandom 402; Barotrauma, Pocket Tactics, Unreal and GameSpot 403), so some facts are snippet-only.

**What this builds on, and does not repeat.**
- The House report (§6) set out three layers for walls and voice: a cosmetic muffle on the listener, a `core/` rule that walls shrink the radius, or distance only. It also showed that Godot 4.7.2 has `attenuation_filter_*` properties.
- The death report (§6) found that nothing in game code can stop a Discord leak.
- Round 1 (B4) found that voice range makes stories.

**Today's rules, checked in the repo.**
- `core/voice/round_voice.gd:3-7`: the living hear the living within `living_m`. A downed player hears but is heard by nobody. The dead hear nobody.
- GDD §11 (`docs/GDD.md:715-720`): no meetings.
- GDD §6 (`docs/GDD.md:228`) leaves "Which items affect voice (for example radios)?" open.
- `voice/CLAUDE.md`: `voice/` is plumbing. Routing is a `core/` rule, and "the client may narrow what it plays, never widen it".
- The decided M8 design is on branch `content/1090-docs-design-the-m8-match-design-in-one` (commit 7b58a2b3a). It is not on `main` yet.

---

## 1. Range and channels: walkies, radios, intercoms, trumpets

### 1.1 Lethal Company: the walkie-talkie and the ship's text line
- **How it works.**
  - [V, snippet] You buy the walkie from the ship's terminal and must switch it on.
  - [V, snippet] You hold the mouse button to talk and cannot hear others while transmitting.
  - [V, snippet] Range is unlimited. The limit is the battery, which drains faster while you talk. It recharges only at the ship's charger. ([Dot Esports](https://dotesports.com/indies/news/how-to-get-and-use-walkie-talkies-in-lethal-company), [Steam](https://steamcommunity.com/app/1966720/discussions/0/3881598799624094543))
  - [V, snippet] The dead are on a separate channel: only other dead players hear them, and they cannot speak to the living ([Steam](https://steamcommunity.com/app/1966720/discussions/0/4034727918503359594)).
  - [V, snippet] The terminal's signal translator sends a text line to every player's screen. Guides say it is cut at **9 characters** ([Prima](https://primagames.com/tips/how-good-is-signal-translator-in-lethal-company-answered)).
  - [V, snippet] Guides say the Eyeless Dog hears voice and walkie chatter. One Steam player says it does not hear the walkie ([itemlevel](https://itemlevel.net/lethal-company-what-does-the-eyeless-dog-hear-how-to-counter)). Contested.
- **Why it works.** [A] Every channel has a cost: the battery, deafness while you talk, a creature that might hear you, a 9-character cap. The crew on the ship becomes a clumsy mission control, and that clumsiness is the comedy.
- **What goes wrong.** [P] A death cuts you off from the team ([Prima, snippet, cited in round 1](https://primagames.com/?p=210331)).

### 1.2 SCP: Secret Laboratory: tiered radios and a public intercom
- **Radios.** [V] Four ranges, about 108 m, 180 m, 1,080 m and 7,200 m (the page's figures are garbled; this is my reading). There is a 200-unit battery, and talking costs far more than listening:

  | Range | Idle drain | Talking drain | Talk time |
  |---|---|---|---|
  | Short | 0.5/min | 40/min | ~5 min |
  | Ultra | 13.5/min | 240/min | ~50 s |

  Receiving costs nothing. Any player with a radio hears every transmission, whatever their team. When two radios are on different ranges, both talk at the larger one ([SCP:SL wiki](https://en.scpslgame.com/index.php?title=Radio)).
- **Intercom.** [V, snippet] One room broadcasts to the whole facility: by default up to **20 s** of speech, then a **120 s** cooldown, both settable by the server ([biligame wiki](https://wiki.biligame.com/scpsl/Entrance_Zone), [config reference](https://xgamingserver.com/docs/scp-secret-laboratory/gameplay-config-reference)).
- **Why it works.** [A] The global channel is a *place* you must reach and hold, so a broadcast is an event and a target. The radio battery prices range against airtime.
- **What goes wrong.** [P] A 2018 player said range changes by floor confused people ([Steam](https://steamcommunity.com/app/700330/discussions/0/1728701877455754630)).

### 1.3 Phasmophobia: local and global talk, and an enemy that hears both
- **How it works.**
  - [V, snippet] Local push-to-talk reaches about 10 to 20 m (sources differ). Global (walkie) reaches everyone ([Pro Game Guides](https://progameguides.com/phasmophobia/how-to-talk-in-phasmophobia/)).
  - [V, snippet] The ghost hears your microphone whether or not you press a key.
  - [V, snippet] During a hunt the walkie gives only static.
  - [V, snippet] A January 2021 beta made hunting ghosts listen for voices "based on how loud your mic is", so whispering stays safe ([Twinfinite](https://twinfinite.net/news/new-phasmophobia-update-lets-ghosts-listen-out-for-player-voices/)). The community wiki gives 20 m for talking and 10 m for whispering ([Steam](https://steamcommunity.com/app/739630/discussions/0/2956040588014783432)).
- **Why it works.** [A] Talking is a resource with a price, and the price rises exactly when talk matters most (a hunt). Whispering becomes a skill.

### 1.4 Sea of Thieves: one item, two directions
- [V, snippet] The Speaking Trumpet's amplify end makes your voice and text carry farther to *other* crews. Its whisper end shrinks your voice so only players very close hear, your own crew included ([Sea of Thieves wiki](https://seaofthieves.wiki.gg/wiki/Speaking_Trumpet)).
- [A] One prop gives both "be heard far" and "be private", and you can see from across a deck which end someone is holding.

### 1.5 PEAK and R.E.P.O.: long-range sound without voice, and the talking dead
- **PEAK.**
  - [V, snippet] The Bugle can be heard from 150 to 175 m, and you set its pitch by where you look ([PEAK wiki](https://peak.wiki.gg/wiki/Bugle)).
  - [V] Ghosts follow living players and "Living Scouts are able to see and hear all Ghosts". Talking while switching targets makes a "pronounced Doppler effect" ([PEAK wiki](https://peak.wiki.gg/wiki/Death)).
- **R.E.P.O.** [V, snippet] A dead player's head can talk to the living through proximity voice for a limited charge that drains fast and refills slowly ([Destructoid](https://www.destructoid.com/how-does-death-head-battery-work-in-r-e-p-o)).

### 1.6 Barotrauma: radios with channels, and a jammer
- [V, snippet] A headset is needed to use the radio: 350 m, channels 0000 to 10000, with local and radio talk on separate keys ([wiki](https://www.barotraumagame.com/wiki/Headset), fetch refused).
- [V] Treacherous Tides (2023) added the traitor **Radio Jammer**, "a handheld battery-powered device that temporarily disables radio communications (both text and voice chat)" ([devtrackers](https://devtrackers.gg/barotrauma/p/e0eca4e3-out-now-treacherous-tides-update)).

### 1.7 Among Us via BetterCrewLink: a menu of voice rules
The proximity mod's lobby settings, read from source ([`src/common/ISettings.d.ts`, `static/locales/en/translation.json`](https://github.com/OhMyGuus/BetterCrewLink)) [V]:
- "Walls Block Audio" and "Hear People in Vision Only".
- "Comms Sabotage Disables Voice".
- "Hear Through Cameras".
- "Hear Impostors in Vents" and "Private Talk in Vents".
- "Impostor Radio" and "Private Impostor Radio". The private version's description: "Crewmates nearby cannot hear an impostor while they talk on the radio." So by default, a crewmate standing next to an impostor overhears his radio talk.
- "Impostors Hear Dead" (the `haunting` flag).
- "Ghosts can Talk Ingame": ghosts hear each other anywhere; the living still cannot hear them.
- "Grace Period": "Seconds of voice kept alive after a round starts, so nobody is cut off mid-sentence."

[A] This is the most useful single source for this topic. The community turned almost every voice question into a host toggle, and the toggles map one to one onto `VoiceRule` data in our `core/`. The default that a *secret channel leaks locally* is the key idea: a private line exists, but using it near others is a tell.

### 1.8 TTT and Project Winter: team channels
- **TTT.** [V] A traitor who holds Shift talks only to other traitors. Living players' voice is global. Spectators are heard only by spectators ([TTT help](https://www.troubleinterroristtown.com/help/gameplay/)).
- **Project Winter.**
  - [V] Traitors start with a red radio to their partner ([Steam, cited in round 1](https://store.steampowered.com/app/774861/Project_Winter/)).
  - [V, snippet] Survivors can craft radios and hand them out. Accepting one overrides the traitor's starting radio, and refusing one is read as a tell ([GodisaGeek, 2021](https://godisageek.com/2021/02/how-to-win-at-project-winter-the-ultimate-survival-guide/)).
  - [V] A traitor ability item, "Jam Radios", exists (Dec 2022 notes, [Steam](https://store.steampowered.com/news/app/774861/view/5623338145769340429), from round 1).

**What goes wrong across §1.** [A] A cheap, unlimited global channel makes proximity pointless: TTT's living voice is global because its tension comes from guns, not range. Every game that keeps range meaningful prices the long channel by battery, place, cooldown, deafness or a listening enemy.

---

## 2. Voice as input

- **Phasmophobia.**
  - [V] The spirit box, Ouija board and Monkey Paw take spoken phrases. Saying the ghost's name can raise its activity.
  - [V] Console recognition supported English, French, Italian, German, Spanish, Brazilian Portuguese and Japanese at release.
  - [V] If the Xbox microphone disconnects, the game "defaults to the TEXT option" ([Kinetic Games](https://kineticgames.co.uk/news/phasmophobia-voice-recognition-update)).
  - [V, snippet] If recognition fails, the spirit box answers randomly ([Steam](https://steamcommunity.com/app/739630/discussions/0/3816290897715638391)).
- **Mage Arena.**
  - [V] Released in early access on 24 July 2025. Over 16,000 peak players and 2,600 reviews in five days, spread largely by TikTok ([Wikipedia](https://en.wikipedia.org/wiki/Mage_Arena)).
  - [V, snippet] You say "Fireball" or "Freeze". Wormhole is "Worm" at the entrance and "Hole" at the exit, with about a 45 s cooldown ([Destructoid](https://www.destructoid.com/all-spells-list-mage-arena/)).
  - [P, snippet] Misheard incantations make the funny accidents.
- **Yapyap.**
  - [V, snippet] Continuous recognition, no push-to-talk ([WindowsForum](https://windowsforum.com/windows-news.4/yapyap-voice-setup-guide-fix-microphone-access-and-input-for-instant-spells.400218/)).
  - [V] Its developer on the spells: "we kind of design it so that it's funny, and you laugh about it with your friends, but… it's hard to make it deep" ([GameDiscoverCo](https://newsletter.gamediscover.co/p/how-yapyap-jammed-its-way-to-1-million)).
  - Not verified: any no-microphone mode in Yapyap or Mage Arena. I found none.
- **SCP-939 (SCP:SL).** [V] It cannot see beyond about 2 m. It perceives sound as blips, and "players who are speaking into their mic are visible at a distance based on how loud they talk" ([SCP:SL wiki](https://en.scpslgame.com/index.php?title=939)).
- **Accessibility.** [V] Base speech recognition "on individual words from a small vocabulary (eg. 'yes' 'no' 'open') instead of long phrases" ([Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/intermediate/)).

[A] **What it means for us.**
- Recognising words needs a speech model per language, which would be a new dependency. Our players may speak Ukrainian, English or anything else, and Phasmophobia's own list leaves out many languages.
- The cheap, language-free form is **loudness as input**, as Phasmophobia's hunts and SCP-939 use it. Our gate already knows when a frame leaves (`voice/voice_gate.gd`), so "a speaking player is heard or seen" needs no recognition at all.
- Shouting a word as a spell is "funny but shallow" by the developer's own words. It suits a one-off gag item better than a core verb.

---

## 3. Disguise, mimicry and fake sounds

- **SCP-939's Mimicry** [V] ([SCP:SL wiki](https://en.scpslgame.com/index.php?title=939)):
  - It stores the last 4 s of speech from a human it recently killed or marked, up to 8 voices.
  - It plays a clip, or part of one, through a "Mimic Point" on the ground. Only SCP-939 sees the point, and it vanishes beyond 20 m. Cooldown 10 s.
  - Separately it mimics gunshots, footsteps and grenades, with a 3 s cooldown.
  - Players can opt out of being recorded, and recordings are deleted when the player leaves.
- **Skinwalkers (a Lethal Company mod).** [V, snippet]
  - It records chatter and plays it from monsters' bodies as proximity voice. It is client-side, so players hear different things.
  - Since 3.0.0 it writes no files and keeps clips in memory.
  - The experimental build had 110K downloads and is now marked deprecated ([Thunderstore](https://thunderstore.io/c/lethal-company/p/RugbugRedfern/SkinwalkersExperimental/)).
- **MIMESIS.**
  - [V] Early access in October 2025 and over a million copies in 50 days. Its AI monster "mimics players' voices, movements, and behavior in real time" and "learns from player voices and actions during each match" (press release of 16 June 2026, [Game Developer](https://www.gamedeveloper.com/press-release/mimesis-major-update-makes-its-ai-driven-monster-more-unpredictable)). The method (clips or synthesis) is not stated.
  - [P, snippet] Reviews say the mimicry "lacks depth and context", so mimics are easy to spot after a while ([VaporLens](https://vaporlens.app/app/2827200/mimesis.md)).
- **ARC Raiders.**
  - [V] Embark told The Guardian (15 April 2026) that 95% of active players use proximity chat ([FRVR](https://frvr.com/blog/news/arc-raiders-devs-reveal-95-of-all-players-actively-use-prox-chat-with-just-30-focused-on-pvp/)).
  - [V, snippet] It ships "Raider Voice", a built-in voice changer with 10 presets that you can apply to proximity only, party only, or both ([Deltia's Gaming](https://deltiasgaming.com/?p=391402)). Embark's stated aim, "a safe space" for strangers, is snippet-only ([Unreal](https://www.unrealengine.com/developer-interviews/embark-studios-build-the-award-winning-arc-raiders-with-unreal-engine), fetch refused).
- **TTT's traitor Radio** [V], read from source ([`ttt_radio.lua`, `lang/english.lua`](https://github.com/Facepunch/garrysmod)):
  - "Plays sounds to distract or deceive." You place it, then trigger it from a menu.
  - The buttons: Scream, Explosion, several gun bursts, C4 beeping, Burning, Footsteps.
  - A queue of at most 5 sounds, 0.5 s apart.

**Why it works.** [A] A fake sound is misinformation the players did not have to voice. It creates "who said that?" moments without asking anyone to act. Recording a real voice is far stronger, and far creepier: SCP-939 limits it to victims, puts a range leash on it, and lets players opt out.

**What goes wrong.** [A]
- Impersonating a specific friend can feel mean. Recording raises consent questions even in a hobby game, as the opt-out shows.
- A pitch-shift disguise costs latency. Godot's `AudioEffectPitchShift` is a bus effect, and a larger FFT means more latency ([docs 4.2](https://docs.godotengine.org/en/4.2/classes/class_audioeffectpitchshift.html); the class exists in our `tools/out/godot-api/4.7.2/extension_api.json`, grep, but I did not read its 4.7 page).
- Voice is spatialized on the listener here, so a disguise means a separate bus per disguised speaker on every listener.

---

## 4. Silencing and jamming
- [V, snippet] **Goose Goose Duck's Silencer** (evil side) mutes a player during meetings and gives up venting to do it. Only the Silencer sees the icon on the silenced player ([Prima](https://primagames.com/gaming/goose-goose-duck-roles-explained)).
- [V, snippet] **Town of Salem's Blackmailer** silences a target for the whole next day. The victim's workaround is the Last Will ([GamersDecide](https://gamersdecide.com/articles/town-of-salem-guide)).
- [V] Jamming in other games:
  - Barotrauma's battery-powered jammer (§1.6).
  - BetterCrewLink's "Comms Sabotage Disables Voice" (§1.7).
  - [V, snippet] Phasmophobia's walkie static during hunts (§1.3).

[A] Silencing works in meeting-based games because a meeting is short and the silenced player is still *seen*: the silence itself is evidence. A long silence in a 10-minute real-time match is dead time, and our "never boring" pillar rejects that. What survives the move to our game: **jam a channel, never a person**, for a short, visible window. Example: radios and the house's long-range channel go to static for 20 s (placeholder) while face-to-face voice still works.

---

## 5. Misinformation and false callouts
- **Blood on the Clocktower.**
  - [V, snippet] Its designer says that because evil works in the shadows, you can make a good player work against their own interests by making their information false ("drunk or poisoned"), and that new players find it hilarious when they turn out to be the drunk ([Tabletop Gaming, 2021](https://www.pressreader.com/uk/tabletop-gaming/20210625/281556587905841)).
  - [P] A Pandemonium Institute blog post by a friend of the company calls good-side misinformation "an anomaly" in the genre ([BotC](https://bloodontheclocktower.com/news/blood-on-the-clocktower-is-a-strategy-game)).
- **Barotrauma.** [V] Traitors get **code words** to find each other in open talk. The crew votes, and if at least half pick the same person, that player is accused. A right guess fails the traitor's objective; a wrong one costs the crew money (§1.6 source).
- **Hunt: Showdown.** [P, snippet] Enemies hear proximity voice. One player describes another "swearing they wouldn't kill us, only to be waiting outside with his teammate to ambush us" ([Steam](https://steamcommunity.com/app/594650/discussions/8/3338785229808802048)).
- **Dark and Darker.** [P, snippet] Strangers "spam crouch to show friendliness": a wordless signal that can be faked ([Steam](https://steamcommunity.com/app/2016590/discussions/0/3767858814404435567/?ctp=2)).

[A] **What it means for us.** Deduction is not central and being outed is never a loss, so a lie about *who* gains little. The valuable lies are about **where and what**: "the bins are fine, I just checked", "the cake's done", "I'll stall the cops" (already decided). The game should give humans tools that make such lies *plausible*: a fake noise, a fake marker, a voice from the wrong room. The aliens' counter should be to *go and look*, which costs them time. That is our win currency.

---

## 6. Coordinated teams: Discord groups and friends in public lobbies
- **Code cannot stop it.**
  - [V, snippet] Among Us coverage noted that friends in a public lobby share information over Discord, and that the only fix would be to stop people playing with friends, "which is part of the fun" ([PC Gamer](https://pcgamer.com/of-course-there-are-already-among-us-cheaters), body not fetched).
  - [P, snippet] Forum Werewolf hosts call "no external communication" "too hard to enforce" and lock channels instead ([Spring forum](https://springrts.com/phpbb/viewtopic.php?p=340923)).
- **Dead by Daylight closes the gap with in-game information.**
  - [V, snippet] The January 2022 developer update put the escape-rate gap between solo players and groups on voice "up to 15%". It said such information "can already be easily conveyed with a quick callout over voice chat", and that killers tuned for groups were too strong against solo players ([Gfinity](https://www.gfinityesports.com/article/january-2022-developer-update-details-improved-solo-survivor-wiggle-mechanics-further-perk-addon-changes)).
  - [V] The fix, Patch 6.5.0, shows every survivor's current action (repair, heal, unhook, chest and so on) with a progress ring. The killer cannot see it ([DbD wiki](https://deadbydaylight.wiki.gg/wiki/Status_HUD)).
- **Apex Legends designs for players without voice.**
  - [V] Respawn: "We playtested for a month with voice comms off and fake names to simulate playing with random people" (2019, [devtrackers](https://devtrackers.gg/apex-legends/p/85b61669-playapex)).
  - [V, snippet] Pings are context-sensitive voice lines from your character, and the game also has text-to-speech and speech-to-text ([PC Gamer](https://www.pcgamer.com/au/apex-legends-ping-system-is-a-tiny-miracle-for-fps-teamwork-and-communication/)).
- **ARC Raiders.** [V, snippet] It "really tr[ies] to favor matchmaking solos with solos" ([Pocket Tactics](https://www.pockettactics.com/arc-raiders/interview-proximity-chat), fetch refused).

[A] **What it means for us.**
1. **Discord helps the humans more than the aliens.** A Discord call is a free, perfect private radio. Project Winter gives traitors exactly that on purpose (a red radio) and lets survivors override it. Whether our humans know each other is not decided. If they do, two humans on Discord can split mischief and fake alibis perfectly.
2. **The DbD lesson is the strongest pattern found:** put into the game whatever a Discord group would shout. The aliens already get markers for ongoing mischief (M8 design §5). A shared, open task board with progress per chain (open knowledge is a pillar) is the same move.
3. **Apex's lesson:** test the game with voice off. If a match is still playable and fun on pings alone, a Discord group's edge is bounded.
4. **Hobby scope:** the audience is mostly friends (Meccha Chameleon "recommends friends" because public servers are messy, round 1 B3). So "friends who all know each other on Discord" is the *normal* case, not cheating. Design the friend lobby first and treat public lobbies as a setting.

---

## 7. Playing without a microphone
- **Among Us.**
  - [V, snippet] Innersloth's 2021 devlog framed Quick Chat, the age gate and accounts as making play "more safe for children". Guests are locked to Quick Chat ([itch.io devlog](https://itch.io/devlog/235010/info-on-accounts.amp), [eSafety](https://www.esafety.gov.au/key-topics/esafety-guide/among-us)).
  - [P, snippet] Players call Quick Chat too limited for discussion.
- **TTT's radio commands.** [V] B opens a menu of lines: help, yes, no, imwith, see, traitor, suspect, check. "Some commands include the name of the player you're aiming at", and each can be bound to a key ([TTT help](https://www.troubleinterroristtown.com/help/gameplay/)).
- **Xbox Accessibility Guideline 119.** [V, snippet] "Voice chat isn't the same as making text chat accessible" and the reverse; "players should be able to communicate through the method of their choosing". It asks for live speech-to-text for deaf players and text-to-speech "broadcast on the voice channel" for players who do not speak ([Microsoft Learn](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/119)).
- **Game Accessibility Guidelines.** [V] "Provide a visual indication of who is currently speaking"; allow a preference for playing "with players who... are willing to play without voice chat" ([GAG](https://gameaccessibilityguidelines.com/intermediate/)).

[A] **The trap for us.** A global ping or a global text chat is a channel that ignores walls and range. It is the exact leak our per-peer filtering and proximity rules exist to stop. The fix that keeps the rules: a **ping or quick-chat line is a sound made by your avatar**, a voiced line heard under the same `VoiceRule` as speech, plus a marker only for listeners who hear it. Then a player without a microphone is as present as one with a microphone, and no more.

---

## 8. Dead-player voice in a 30 s respawn

| Game | The dead | Source |
|---|---|---|
| Lethal Company | Dead hear the dead only | [V, snippet] above |
| TTT | Spectators talk to spectators only | [V] |
| PEAK | Ghosts heard by the living | [V] |
| R.E.P.O. | The head talks, on a limited charge | [V, snippet] |
| BetterCrewLink | Host toggles, including "Impostors Hear Dead" | [V] |
| LOCKDOWN Protocol | Ghosts spectate; voice rules not found | [V, snippet] ([Steam](https://steamcommunity.com/app/2780980/discussions/0/4635988522932715980)) |
| Ours today | Dead hear nobody; downed are mute | `core/voice/round_voice.gd:3-7` |

[A] With a 30 s respawn and "a killed alien tells everyone who killed him" already decided, what the dead know is worth little. The real question is **what 30 s of waiting feels like**. Today it is silence plus world sounds. A shared waiting channel for the dead (the Lethal Company and TTT model) turns those 30 s into social time at no cost to the information rules.

---

## (1) Cross-game patterns

1. **Every long-range channel has a price** [V/A]: battery (LC, SCP:SL, Barotrauma), a place and cooldown (SCP:SL intercom 20 s / 120 s), deafness while talking (LC), static at the worst moment (Phasmophobia), or an enemy who hears (Phasmophobia, SCP-939, Hunt). Free global channels make proximity pointless.
2. **A private line that leaks locally** [V]: BetterCrewLink's impostor radio is overheard by default unless the host makes it private. Project Winter's radios are a visible exchange you can refuse. Secrecy that has a tell keeps the social game alive.
3. **One device, two directions** [V, snippet]: the Sea of Thieves trumpet is loud or whisper, and you can see which.
4. **Fake sounds beat fake roles** [V]: TTT's radio soundboard and SCP-939's environmental mimicry create doubt about *where* without forcing anyone to lie to a face.
5. **Recorded voices are strong and need limits** [V]: SCP-939 uses victims only, a 20 m leash, an opt-out, and deletes clips on leave. Skinwalkers keeps clips in memory only.
6. **Jam channels, not people, briefly** [V/A]: Barotrauma, Project Winter, comms sabotage. Long personal silences belong to meeting games.
7. **Close the Discord gap with in-game information, not bans** [V]: DbD's status HUD after an escape-rate gap of up to 15%, Apex's month of voice-off testing, ARC Raiders' solo matchmaking.
8. **Voice as input works as comedy, not depth** [V]: Yapyap's developer, Mage Arena's misheard spells. Loudness-as-input needs no language model (Phasmophobia, SCP-939).
9. **Accessibility means choice of method** [V]: XAG 119 and GAG. Context pings are an accessibility feature that also helps everyone (the ESA case study, snippet).

## (2) Risks for our design

1. **"The side that talks wins" gets worse with any global channel** [A]. The aliens are the majority, so a cheap house-wide channel multiplies their coordination. Every channel added must be priced, and humans must be able to contest or poison it.
2. **Discord gives humans a free, perfect private line** [A], if humans know each other. That could flip balance in friend groups, which are the normal audience. Whether humans know each other must be decided before tuning.
3. **Pings, subtitles and text bypassing the rules** [A]. A ping system, a speech-to-text overlay or a text chat that ignores `VoiceRule` would leak hidden information past walls. Our `bots` information-leak test should cover any new channel.
4. **Players without a microphone lose** [A] in a design where talk decides the match. Quick lines that are voiced in-world fix this; a text box alone does not, because it is not spatial.
5. **Recording and impersonation** [A] can feel mean between friends and raise consent issues. SCP-939's opt-out is the minimum.
6. **Cost in the voice plumbing** [A/V]. Pitch shift is a bus effect with FFT latency, and per-speaker buses multiply across 10 players. A core rule for walls needs geometry queries (the House report §6). Both touch architecture boundaries and need the engineer's word.
7. **Dead time from silencing** [A]: a long personal mute breaks "never boring".
8. **Voice recognition** [A] would be a new dependency, with language gaps (Phasmophobia's list), noise and microphone setup pain (Yapyap's troubleshooting guides). It is a stop-and-ask item.
9. **Public lobbies** [P/A] bring strangers' voices to teens. A per-player local mute is required. It is client-side narrowing, which `voice/CLAUDE.md` allows.

## (3) Options for the engineer (all values are placeholders; none decided)

**Option A: hearing levels instead of a yes/no rule.**
- **What.** A `core/` voice rule returns *clear*, *muffled* or *none* per pair: distance plus a count of closed doors and walls between the two (placeholder: open line within 8 m is clear; one wall or a closed door is muffled to 4 m; two is none). The listener applies the muffle with the existing `extra_db` and a low-pass filter.
- **Why.** Doors become a privacy tool. A human closes the pantry door and whispers; an alien who opens it hears clearly. This builds the "walls muffle" decision into play.
- **Trade-offs.** It needs geometry in `core/`, which is an architecture boundary. A muffled-only cosmetic version is cheaper but adds no rules.
- **Recommendation.** First the cosmetic muffle, then the core rule if playtests want doors to matter.

**Option B: the party's PA system as the house's one global channel.**
- **What.** An alien party sound system (a mic stand by the speakers) broadcasts your voice to the whole House and garden for up to 15 s, then cools down for 90 s. **Every use is loud mischief:** it adds a little neighbours' anger.
- **Why.**
  - The aliens get a priced way to coordinate.
  - The humans get a stage for false callouts ("mischief in the garage!") that costs the aliens a trip.
  - Using it ties communication to the decided anger meter.
- **Trade-offs.** It adds a channel that ignores range. Its place, cooldown and anger cost are the limits.
- **Recommendation.** Yes, as the first and only long-range channel.

**Option C: a few handheld party walkies that leak locally.**
- **What.** Two to four walkies on the map, on one shared channel, with a battery that drains mostly while talking. Your words are *also* heard in normal proximity around you, as BetterCrewLink's default does.
- **Why.** Aliens can keep a remote helper. A human can pocket one to cut the link, or keep it to listen. Anyone near a talker can eavesdrop.
- **Trade-offs.** It is a second long-range channel, so it may make B redundant. It also opens "who has the walkie?" item play.
- **Recommendation.** Later, after B is measured. It is an item, so it is open to all roles (identical roles).

**Option D: the human toolbox against talk, three cheap gadgets.**
Open to everyone, but useful mostly to humans.
1. **The party fog machine on the cable box (jam).** A mischief station that puts the PA and walkies to static for 20 s. Face-to-face voice still works.
2. **The party balloon (anonymise).** Inhale and your voice is pitch-shifted for 30 s. If many players do it, nobody's callout is attributable. It is comic and fits the cringe-fun tone.
3. **The fake-noise toy (deceive).** Place it and trigger one of a few party noises (a glass breaking, bins falling, the doorbell) from up to 20 m away, 3 uses.

- **Why.** Each attacks the aliens' talk without silencing a person. The aliens' counter is to go and look, which costs them time.
- **Trade-offs.**
  - The balloon needs a per-speaker effect on every listener.
  - The noise toy must never raise the real meter, or it becomes free anger.
- **Recommendation.** The noise toy first: cheapest, no voice plumbing. Then the jam. The balloon after a CPU check.

**Option E: voiced quick lines and context pings, under the voice rule.**
- **What.** A wheel of 8 lines: "Here!", "Mischief here!", "Help me", "Need this item", "On it", "Follow me", "Watch him" (the aimed player), "Liar!".
  - Each is spoken by your avatar in a comic alien text-to-speech voice and heard only by whoever would hear your voice (Option A levels included).
  - It also shows a marker to those listeners.
  - Subtitles of heard speech are an accessibility setting, again only for voices the listener hears.
- **Why.** Players without a microphone are present. Public lobbies become playable. No channel leaks.
- **Trade-offs.** Text-to-speech may need an engine feature or a recorded line set. Check the 4.7.2 API before choosing.
- **Recommendation.** Yes, before any public-lobby work. Test it the Apex way: a playtest with voice off.

**Option F: shrink what a Discord can add.**
- **What.** Put what a group on a call would shout into an open, in-world task board: chain progress and active mischief, the DbD move. Add a lobby preset, "Friends on a call", that the host sets. It shifts a placeholder balance knob, for example one more human or a shorter cops' minute.
- **Trade-offs.** It needs the balance model (#1089) to say which side Discord helps. A preset is honest, but players can lie about it.
- **Recommendation.** The board yes; the preset only after playtests show a gap.

**Option G: the dead wait together in the ship.**
- **What.** For the 30 s, the dead hear and talk to each other anywhere, never to the living. Framing: they are beamed up to the ship's lounge (the lobby), with its music. The rule is one new `VoiceRule` case.
- **Why.** It turns the 30 s into banter. It leaks almost nothing, given the decided killer reveal.
- **Trade-offs.** It changes today's "the dead hear nobody" (GDD §11), which was a decision.
- **Recommendation.** Yes, if the engineer agrees to reopen that line.

**Overall recommendation.** In order: A (the cosmetic muffle first), E, B, D's noise toy, G; then C and the rest of D after playtests.

## (4) Open questions for the engineer

1. Do the humans know each other? This decides whether Discord, or an in-game private channel for humans, is a balance problem.
2. Is one house-wide channel (B) wanted at all, or should all talk stay strictly local?
3. Should walls be a rule in `core/` (who hears) or only a sound on the listener (how it sounds)? The first is an architecture boundary.
4. May the dead talk to each other during the 30 s (reopens GDD §11)?
5. Is any voice-as-input in scope (loudness only, or words with a recognition dependency)?
6. Is recording or replaying a real player's voice ever acceptable? If so, with an opt-out by default?
7. Public lobbies: a target, or friends-only for now? This decides how urgent E and per-player mute are.
8. For players without a microphone: a comic alien text-to-speech voice, a recorded line set, or markers only?