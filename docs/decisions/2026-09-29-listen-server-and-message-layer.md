# Listen server and the message layer

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** the engineer (approved in chat with the M2 manager session on 2026-09-29); recorded from #31

## Context
The [MVP rules](2026-09-29-mvp-rules.md) need a hosting model before M2 designs intents, events and entitlement (#32).
The [stack ADR](2026-09-29-technical-stack-from-the-brief.md) chose Godot's multiplayer over ENet behind a transport
abstraction; the M1 spike found where Godot's high-level helpers work against invariant 2 (`docs/ARCHITECTURE.md` §4,
#13):
- `SceneMultiplayer` parses incoming RPC, spawn and sync commands even when the game sends none, so any `@rpc` method
  under its root becomes callable by clients.
- `SceneMultiplayer.server_relay` defaults to `true` in 4.7: clients can send messages to each other through the host.
- A `MultiplayerSynchronizer` sends to every peer until someone adds a visibility filter.

## Decision
- **Listen server.** One player creates the lobby and hosts: the host is peer 1 and plays. No dedicated server.
- **Loopback.** The host's own client talks to the host through an in-process loopback transport, through the same
  codec and the same per-peer filter as every other client (invariant 2).
- **Own messages over `MultiplayerPeer`** (ENet first), not RPCs, `MultiplayerSpawner` or `MultiplayerSynchronizer`.
  Every outgoing message is built per recipient in one place, which the information-leak test checks.
- **The host leaving or crashing ends the match.** Clients see the connection to the host close and return to the
  main menu with a message. No host migration: the successor would have to hold all hidden state in advance. No
  reconnection in the MVP.
- **A client leaving mid-match** counts as dead for the win conditions; its held item drops where it stood.
- **Nobody joins during a match** (`refuse_new_connections`).
- **Loading:** the game scene loads with threaded loading and a longer ENet timeout; the round starts when every peer
  confirmed it loaded. In #13 a main-thread freeze of 2–4 s dropped the peer.
- **Reach:** the MVP is played over a LAN or a VPN (Radmin VPN, ZeroTier, Tailscale), plus a UPnP attempt (the `UPNP`
  class exists in 4.7.2). Internet play without a VPN stays the M6 ADR (Steam vs WebRTC).

The wire format (schemas, encoding, versioning, reliability per message type) stays M3 (`docs/ARCHITECTURE.md` §4).

## Alternatives
- **Godot's RPCs, `MultiplayerSpawner` and `MultiplayerSynchronizer`:** rejected for the three reasons in Context.
  Each would need its own guard to keep hidden information and client-to-client messages out, instead of one place
  that builds every message.
- **Host migration:** rejected; the successor would have to hold all hidden state in advance.

## Consequences
- `net/` provides the ENet transport and an in-process loopback behind one abstraction; `server/` builds every
  message per recipient.
- Checked against the API dump for 4.7.2: `server_disconnected` is a signal of `MultiplayerAPI`, which this layer does
  not use; on the raw `MultiplayerPeer` the host's loss shows as the connection status or `peer_disconnected` for
  peer 1. #32 and M3 pick which.
- **Risks carried:**
  - #21: test between two machines before M3 depends on ENet.
  - The host's upload for voice: 3.3 to 4.9 Mbit/s with 10 players all talking, and the unexplained per-send ENet cost
    ([voice ADR](2026-09-29-voice-approach.md)).
