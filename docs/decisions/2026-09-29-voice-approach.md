# Voice approach after the M1 spike

- **Status:** Proposed (the go/no-go is the humans' call)
- **Date:** 2026-09-29
- **Deciders:** the engineer (go/no-go); proposed by the agent from the M1 spike (#12 to #16)

## Context
The founding stack ([ADR](2026-09-29-technical-stack-from-the-brief.md)) picked Opus through the `two-voip-godot-4`
GDExtension (TwoVoIP), with a known Windows risk, and left the go/no-go to an M1 spike. The spike ran on throwaway
branches that are never merged; the numbers and steps are in the handoff comments of #12 (codec on Windows), #13
(ENet), #14 (movement), #15 (proximity voice) and #16 (measurements). Open spike issues: #21 (ENet), #22 (Godot 4.8).

| Spike | Branch (on `origin`, not merged) | Head |
|---|---|---|
| #12 codec loopback | `voice/12-m1-spike-confirm-the-opus-voice-addon` | `df3aa33` |
| #13 ENet host and clients | `net/13-m1-spike-host-and-two-clients-over-enet` | `2bfb110` |
| #14 first-person walk | `client/14-m1-spike-first-person-capsules-walking` | `f992a05` |
| #15 proximity voice | `voice/15-m1-spike-proximity-voice-with-3d-falloff` | `0d578ba` |
| #16 measurements | `voice/16-m1-spike-measure-voice-latency-cpu-cost` | `2b209ac` |

Machines: a PC (Windows 11 Pro, Ryzen 7 3700X, USB microphone, sound through the monitor's HDMI/DP speakers) and a
laptop (Windows, Ryzen AI 7 350, built-in speakers). Godot 4.7.2, WASAPI, 48 kHz.

## What the spike found

### Codec and platforms
- **TwoVoIP v6.5** works on Windows x86_64 with Godot 4.7.2 from its release binary (SHA-256
  `811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7`); no build from source.
- **v6.6 crashes** the editor and `check` on import (integer divide by zero in the DLL). Upstream
  goatchurchprime/two-voip-godot-4#107 is still open (checked 2026-09-29).
- The fallbacks (`one-voip-godot-4`, Steam voice, PCM) were not tried: the first option worked.
- Linux and macOS: the v6.5 archive ships binaries for both; not tested.
- **Godot 4.7.2 cannot read microphones with more than two channels** (most laptop microphone arrays): the game
  freezes. Fixed upstream for 4.8 (godotengine/godot#101673); tracked in #22. 4.8 is not released yet.

### Relay or direct: relay through the host
- Clients can only reach the host, so direct voice needs peer-to-peer connections and NAT traversal.
- With relay, a client never receives voice it is not entitled to (invariant 2). Direct sending would trust the
  speaker's client to obey the host's routing.
- The host routes each frame by the rule in `core/` and never decodes Opus.
- Voice rides its own ENet channel, **unreliable unordered**: with ordered delivery ENet dropped reordered frames
  before the jitter buffer could use them (915/995 frames against 959–973/995 under the same simulated loss).

### Latency, mouth to ear
Measured acoustically. A click from one client's loudspeaker reaches the other client's microphone twice: first through
the air, then again after the whole voice path. The gap between the two is mouth to ear, device buffers included, and
needs no shared clock.

| Setup | Median |
|---|---|
| One machine, RNNoise on | 365–375 ms (3 runs) |
| One machine, RNNoise off | 343 ms |
| One machine, Discord running | 689 ms |
| Two machines on Wi-Fi, Discord running on the PC | 532 ms, then 550 ms |

Where the clean one-machine case goes:

| Part | ms | Who controls it |
|---|---|---|
| Audio devices and Windows: output device, air, input device | 258–271 (about 70 %) | the player's hardware and Windows |
| Frame age at encoding (20 ms frame + microphone backlog) | 30 | the game |
| Network legs on one machine | 10–13 | the game (and the network) |
| Jitter buffer and playback queue | 29–39 | the game |
| Godot's reported output latency | 10 | Godot |
| RNNoise noise suppression | ~23 | the game (optional) |

- **In plain words:** the game's own path is about 85 ms, or 108 ms with noise suppression. The rest is sound
  waiting in Windows' audio mixer and in the devices' buffers. Godot cannot see that time: it reports 10 ms of output
  latency throughout. Any voice program on the same PC with the same devices pays it too.
- **Discord** running on the PC made that device part about 310 ms slower (581 ms instead of ~265). Windows restarted
  its audio engine (`audiodg`) when Discord started, and the delay went away as soon as Discord quit. The game's own
  path did not change. Players will usually have Discord open.
- **Over Wi-Fi** the playback queue grew from ~35 ms to 75 ms (p90 93). The per-leg timestamps work on one machine
  only, so the game's own path between two machines is an estimate: about 155 ms.
- **Not measured:** two machines without Discord; how the ~265 ms splits between output (the monitor's speakers)
  and input (the USB microphone); a headset.

### CPU (20 ms frames; one core = 20 000 µs per frame)
| Per stream | PC | Laptop |
|---|---|---|
| Encode with RNNoise (the microphone path) | 671 µs (3.4 %) | 669 µs |
| Encode without RNNoise | 145 µs (0.7 %) | 145 µs |
| Decode and mix | 54 µs (0.27 %); 69–84 µs in game | 165 µs in game |
| Host routing of one frame, GDScript only, 9 listeners | 24 µs | |

- **Ten players all talking** (the worst case, no voice activity detection): one encode and nine decodes per client
  every 20 ms, 5.8–8.2 % of one core on the PC and 10.7 % on the laptop.
- **Microphones at 44.1 kHz** add ~400 µs of resampling per encode.
- **Open:** in game, relaying one frame to one listener with the ENet send cost 111–167 µs against 10 µs without it.
  If that is real, a host relaying 81 streams would spend ~40 % of one core on its main thread. Not explained or
  measured.

### Bandwidth
- **Opus** at 24 kbit/s, complexity 5, VBR: 40–50 B per 20 ms frame of speech, 25 B of silence.
- **One speaker** uploads ~43 kbit/s at the ENet level, ~54 kbit/s on the wire. About half of each message is
  `var_to_bytes` framing.
- **Host upload for 10 players**, everyone talking to everyone (90 streams): ~4.9 Mbit/s with the spike's format,
  ~3.3 with a compact binary header. With voice activity detection and at most two speakers at a time: ~0.65 Mbit/s.
  Host download stays under 0.5 Mbit/s.
- **Silence is not free:** without voice activity detection or Opus DTX, a silent player still sends 50 messages a
  second (~26 kbit/s). Once snapshots are filtered, that steady stream would also show roughly where the player is.

### Jitter buffer
- A reorder wait of 2 frames and a 60 ms prebuffer before playback starts; it resets after a 500 ms gap.
- It waited 0 ms for reordering on loopback and on the LAN.
- The playback queue is 36–52 % of the game's own path, ~10 % of mouth to ear.

## Decision
*Pending the humans' go/no-go.* The agent proposes **go** with the thresholds below. The alternatives are listed in
Alternatives.

**Go thresholds (proposed).** They judge only what the game controls. The devices and Windows cost the same for any
voice program on that PC, and the next codec would not change them.

| Measure | Threshold | Measured |
|---|---|---|
| The game's own path, mouth to ear minus the devices | ≤ 200 ms on one machine and over a LAN | ~108 ms on one machine, ~155 ms estimated over Wi-Fi |
| CPU for 10 players all talking, the weaker machine | ≤ 15 % of one core | 10.7 % (laptop) |
| Host upload for 10 players, everyone hears everyone | ≤ 5 Mbit/s | ~4.9 (spike format), ~3.3 (compact header) |
| The humans' listening test on two machines | "sounds right" | passed in #15 |

The 200 ms is half of the 400 ms that the telephone planning guideline ITU-T G.114 treats as the limit for
conversation. The other half is left for the devices.

**If go:**
- The codec is TwoVoIP **v6.5**, behind the `voice/` codec interface. v6.6 or later only after goatchurchprime/two-voip-godot-4#107
  is fixed and `check` passes with it.
- Adding the addon to `main` (`addons/`, binaries through Git LFS) is its own stop-and-ask when M5 starts.
- Voice is relayed through the host on its own unreliable unordered channel. The host routes by the `core/` rule and
  never decodes.
- Windows first. Linux and macOS binaries exist but are untested.

## Alternatives
- **Threshold on the whole mouth-to-ear path**: ≤ 400 ms (G.114) on the reference PC without Discord. It passes, with
  a 25–35 ms margin. But it judges our monitor's speakers and USB microphone, not the game, and it fails the moment
  Discord runs (689 ms), which the game cannot fix.
- **The ear only**: go on the humans' listening test, with the numbers above kept as a baseline and no hard
  threshold. The cheapest option, but a later regression has no number to be checked against.
- **No-go**: try the next codec option (Steam voice through GodotSteam, then PCM). It would not change the ~70 %
  spent in devices and Windows, and it adds the Steam dependency before the M6 decision on NAT traversal.

## Consequences
**Lowering the device part** (not the game's code; to try in M5, or give as advice to players):
- A wired headset instead of monitor speakers: sound over HDMI/DP can add a lot of buffering. The spike also
  had no echo cancellation: the latency test had to mute the listener between clicks to stop howling. Players will
  need headphones anyway, or the game needs echo cancellation.
- Compare with and without Discord on two machines, and look for the Discord or Windows setting that causes it
  (communications ducking, audio enhancements, exclusive mode).
- Windows audio enhancements off; the microphone at 48 kHz (44.1 kHz also costs ~400 µs of CPU per frame).
- Check whether Godot 4.7 or 4.8 can open WASAPI with a smaller buffer, and what `audio/driver/output_latency`
  changes.

**In the game's path** (M5): an adaptive prebuffer instead of a fixed 60 ms; RNNoise as a setting (−23 ms, and
encoding about 4.6× cheaper); voice activity detection or Opus DTX; possibly 10 ms frames.

**Risks carried forward:**
- #22: Godot 4.8 for multi-channel microphones, before any playtest with laptop players.
- #21: a killed windowed client can make the ENet host drop the other one; investigate before M3 depends on ENet.
- The host's per-send ENet cost with many listeners: measure in M3 or M5.
- godotengine/godot#123963: `create_server` passes `max_channels` as the incoming bandwidth. Keep `max_channels` 0
  on the server, or unreliable packets are throttled to 1/32.

The spike's lessons for the real code are in `docs/ARCHITECTURE.md` §4 (protocol), §6 (voice) and §7 (movement).
