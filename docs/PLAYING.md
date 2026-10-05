# Playing with friends

How to get PrimeGame, host a game and get your friends into it. This page is for players. Words in quotes are
exactly what the game shows.

**Not live yet.** Two parts are still coming:
- **The first release.** Until it is published, there is no zip to download.
- **The code service.** The game's "Join with a code" and Host need it, and this build has none yet. Until it is
  live, play with **Direct (LAN or VPN)** (below).

## 1. Get the game (Windows)

1. Open the project's [Releases page](https://github.com/xperiaroco2/prime-game/releases) and download the zip
   for Windows (named like `PrimeGame-v0.6.0-windows-x86_64.zip`).
2. Unzip it anywhere, for example to your Desktop.
3. Run `PrimeGame.exe` inside the unzipped `PrimeGame` folder.
4. The first time, Windows SmartScreen warns that the app is unrecognised (the game is not signed). Click
   **More info**, then **Run anyway**. It asks only once.

Everyone in a game must use the **same release**. When a new one comes out, all of you download it again.

## 2. Host a game with a code

Coming: needs the code service.

1. In the main menu, click **Host**.
2. You are now in the lobby. The code shows in the top-left corner as "Code: ABCDEF" (your own 6 characters).
3. To copy it: press **Esc**, open the **Lobby** tab and click **Copy**.
4. Paste the code to your friends in any chat app.

Only people who have the code can join. Keep the game running: when you leave, the game ends for everyone.

## 3. Join with a code

Coming: needs the code service.

1. In the main menu, under "Join with a code", type or paste the code into **Code**. Spaces, dashes and
   upper or lower case do not matter.
2. Click **Join** (or press Enter).
3. The connecting screen shows "Joining the game with code ABCDEF" and the step: "Finding the game", then
   "Connecting", then "Joined: waiting for the host". **Cancel** takes you back to the menu.

## 4. Direct (LAN or VPN)

Use this when you are all on the same home network, on a shared VPN, or with the fallback in section 6. It works
today.

**The host:**
1. Leave **Port** at 24600 unless you have a reason to change it.
2. Click **Host Direct**.
3. Tell your friends your address: your computer's local address (like `192.168.1.20`) on a home network, or your
   VPN address on a VPN.
4. If Windows asks whether to let PrimeGame use the network, allow it. The game uses UDP on the port above.

**Everyone else:**
1. Under "Direct (LAN or VPN)", type the host's address into **Address**. You can add the port to it, like
   `192.168.1.20:24600`; otherwise the **Port** box is used.
2. Click the **Join** next to **Host Direct** (not the one next to the code).

## 5. When it does not connect

When a join fails, you are back in the main menu, and the line at the bottom starts with "The last session ended:"
followed by the reason. Find the reason here:

| The reason starts with | What to do |
|---|---|
| "no game has that code" | Check the code with the host, letter by letter. The host may also have left: ask for the new code. |
| "the code service could not be reached (or this build has none)" | The code service is down, or not live yet. Use Direct (LAN or VPN), or the fallback in section 6. |
| "the code service refused the join" | You and the host have different releases. Both download the newest release. |
| "the host's lobby is full, or this machine could not reach the host directly" | If the lobby has room, your networks do not let you connect directly. Use the fallback in section 6. |
| "no answer from the host" | Direct join: check the host's game is running and in the lobby, the address, and the port. The host's firewall must let UDP in on that port. |
| "the host's lobby is full" | Wait for a free place, or ask someone to leave. |
| "the host's match is under way" | Wait until the host is back in the lobby, then join again. |
| "the host runs another protocol version" or "the host runs another build" | You and the host have different releases. Both download the newest release. |
| "the host closed, or the connection was lost" | The host left or the network dropped. Ask the host to host again, then rejoin. |
| "the map took too long to load here" | The match went on without you. Join again when the host is back in the lobby. |
| "the map did not load on this machine" | Download and unzip the release again, then retry. |
| "the session could not start (see the log): this build has no code service yet" | Host clicked while the code service is not live. Use **Host Direct** instead. |

Before you click Join, the menu may also complain about what you typed:

| The message | What to do |
|---|---|
| "type the code the host gave you" | The Code box is empty. |
| "a code is 6 characters of letters and digits, without 0, O, 1, I or L" | The code is mistyped. Copy it again from the host. |

## 6. The fallback when nothing connects

Some home networks block direct connections between players. Then one of these gets you playing over **Direct
(LAN or VPN)**:

- **playit.gg** (the plan; not tested with the game yet). Only the host installs it. The host creates a free UDP
  tunnel to port 24600, clicks **Host Direct**, and shares the address playit.gg gives them. Friends type that
  address, with its port, into **Address** and click **Join**.
- **Tailscale** (if playit.gg does not work out). Everyone installs Tailscale and joins the host's network (free
  for up to 6 users). The host clicks **Host Direct** and shares their Tailscale address. Friends join it under
  Direct.
