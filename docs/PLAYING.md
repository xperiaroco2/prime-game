# Playing with friends

How to get PrimeGame, host a game and get your friends into it. This page is for players. Words in quotes are
exactly what the game shows.

**Early releases.** The first zips are release candidates (`v0.6.0-rc...`). The code service that "Join with a
code" and Host use is up, but no full match over the internet has been played on it yet: if a code does not work
for you, play with **Direct (LAN or VPN)** (below). Take the newest release (marked **Latest**).

## 1. Get the game (Windows)

1. Open the project's [Releases page](https://github.com/xperiaroco2/prime-game/releases) and download the zip
   for Windows (named like `PrimeGame-v0.6.0-windows-x86_64.zip`).
2. Unzip it anywhere, for example to your Desktop.
3. Run `PrimeGame.exe` inside the unzipped `PrimeGame` folder.
4. The first time, Windows SmartScreen warns that the app is unrecognised (the game is not signed). Click
   **More info**, then **Run anyway**. It asks only once.

Everyone in a game must use the **same release**. When a new one comes out, all of you download it again.

## 2. Host a game with a code

1. In the main menu, click **Host**.
2. You are now in the lobby. The code shows in the top-right corner, next to "Code" (your own 6 characters; "…" while
   the code service makes your room).
3. To copy it: press **Esc**, open the **Lobby** tab and click **Copy**.
4. Paste the code to your friends in any chat app.

Only people who have the code can join. Keep the game running: when you leave, the game ends for everyone.

## 3. Join with a code

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
1. Under "Direct (LAN or VPN)", replace the `127.0.0.1` in **Address** with the host's address. You can add the
   port to it, like `192.168.1.20:24600`; otherwise the **Port** box is used.
2. Click the **Join** next to **Host Direct** (not the one next to the code).

## 5. When it does not connect

When a join or a host fails, you are back in the main menu, and the line at the bottom starts with "The last session
ended:" followed by the reason. Find the reason here (match the whole quote: two rows start alike):

| The reason starts with | What to do |
|---|---|
| "no game has that code" | Check the code with the host, letter by letter. The host may also have left: ask for the new code. |
| "the code service could not be reached (or this build has none)" | The code service is down, or your network blocks it. Use Direct (LAN or VPN), or the fallback in section 6. |
| "the code service refused the join" | Your game may be older than the code service. Download the newest release (the host too). |
| "the host's lobby is full, or this machine could not reach the host directly" | If the lobby has room, your networks do not let you connect directly. Use the fallback in section 6. |
| "the host's lobby is full" (nothing after it) | Wait for a free place, or ask someone to leave. |
| "no answer from the host" | Direct join: check the host's game is running and in the lobby, the address, and the port; the host's firewall must let UDP in on that port. Code join: the host may have left; ask them to host again. |
| "the host's match is under way" | Wait until the host is back in the lobby, then join again. |
| "the host runs another protocol version", "the host runs another build" or "the host asked for a map this game does not have" | You and the host have different releases. Both download the newest release. |
| "the host closed, or the connection was lost" | The host left or the network dropped. Ask the host to host again, then rejoin. |
| "the map took too long to load here" | The match went on without you. Join again when the host is back in the lobby. |
| "the map did not load on this machine" | Download and unzip the release again, then retry. |
| "the session could not start (see the log): no code service is set" | The game was started with an empty `--signal=` (a test setting). Start it without that, or use **Host Direct**. |
| "the session could not start (see the log)" followed by something else | After **Host Direct**: the port may be in use. Close any other copy of the game, or pick another **Port** (your friends then use it too). |

When you click Join, the line may instead name a problem with what you typed (without "The last session ended:"):

| The message | What to do |
|---|---|
| "type the code the host gave you" | The Code box is empty. |
| "a code is 6 characters of letters and digits, without 0, O, 1, I or L" | The code is mistyped. Copy it again from the host. |
| "type the host's address" | The Address box is empty. |
| "... is neither an address nor a host name" | The address is mistyped. Ask the host for it again. |
| "the port is a number from 1 to 65535, not ..." | Fix the part after the `:` in **Address**, or leave it out and use the **Port** box. |

## 6. The fallback when nothing connects

Some home networks block direct connections between players. Then one of these gets you playing over **Direct
(LAN or VPN)**:

- **playit.gg** (the plan; not tested with the game yet). Only the host installs it. The host creates a free UDP
  tunnel to port 24600, clicks **Host Direct**, and shares the address playit.gg gives them. Friends type that
  address, with its port, into **Address** and click **Join**.
- **Tailscale** (if playit.gg does not work out). Everyone installs Tailscale and joins the host's network (see
  Tailscale's site for its free plan). The host clicks **Host Direct** and shares their Tailscale address.
  Friends join it under Direct.
