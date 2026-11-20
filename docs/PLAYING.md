# Playing with friends

How to get PrimeGame, host a game and get your friends into it. This page is for players. Words in quotes are
exactly what the game shows (small headings, such as "Code", show in capitals).

**Early releases.** The code service that hosting and "Join" with a code use is up, but few matches over the internet
have been played on it yet: if a code does not work for you, join by address (section 4). Take the newest release
(marked **Latest**).

## 1. Get the game (Windows)

1. Open the project's [Releases page](https://github.com/xperiaroco2/prime-game/releases) and download the zip
   for Windows (named like `PrimeGame-v0.8.0-windows-x86_64.zip`).
2. Unzip it anywhere, for example to your Desktop.
3. Run `PrimeGame.exe` inside the unzipped `PrimeGame` folder.
4. The first time, Windows SmartScreen warns that the app is unrecognised (the game is not signed). Click
   **More info**, then **Run anyway**. It asks only once.

Everyone in a game must use the **same release**. When a new one comes out, all of you download it again.

The very first time, the game opens in the tutorial's room and asks "First time here?": **Start the tutorial** (about
three minutes) or **Skip**. After that (and after Skip) it starts in your own ship, where you can walk around alone.
Everything else starts from the menu: press **Esc** (the hint at the bottom left says so) to open it.

## 2. Host a game with a code

1. Press **Esc** and click **Host a game**.
2. You are now in your lobby. Press **Esc** again: the code is at the top of the menu, under "Code" (your own 6
   characters; "…" while the code service makes your room). The match console in the ship shows it too.
3. Click **Copy** next to it and paste the code to your friends in any chat app.

If no code shows, the code service is not answering (the match console says "The code service isn't answering. To
let more players in, host directly."): leave (**Esc**, **Leave the session**) and host by address (section 4).

Only people who have the code can join. Keep the game running: when you leave, the game ends for everyone.

## 3. Join with a code

1. Press **Esc** and open **Find a lobby**.
2. Type the code into **Code**, or paste it exactly as the host's **Copy** gave it (6 characters, nothing between
   them). Upper or lower case does not matter; **Join** turns on once all 6 characters are there.
3. Click **Join** (or press Enter).
4. The connecting screen shows the step: "Finding the game", then "Connecting to the host", then "Entering the
   lobby". **Cancel** (or Esc) takes you back to your ship.

**On the same home network** you may not need the code at all: **Find a lobby** lists the games running nearby
under "Lobbies nearby" ("No lobbies nearby" when there are none). Pick one and click the **Join** under the list
(or double-click it).

## 4. Join by address (LAN or VPN)

Use this when you are all on the same home network, on a shared VPN, or with the fallback in section 6.

**The host:**
1. Press **Esc**, open **Find a lobby** and click **Join by address**.
2. Click **Host a game** there, beside **Join** (not the menu's own **Host a game**, which hosts with a code). The
   game hosts on the port named under the address box ("Port 24600"). To use another port, type it as `:24601` in
   **Host address** first (your friends then add it to your address too).
3. Tell your friends your address: your computer's local address (like `192.168.1.20`) on a home network, or your
   VPN address on a VPN.
4. If Windows asks whether to let PrimeGame use the network, allow it. The game uses UDP on that port.

**Everyone else:**
1. Press **Esc**, open **Find a lobby** and click **Join by address**.
2. Type the host's address into **Host address**. You can add the port to it, like `192.168.1.20:24600`; otherwise
   the port under the box is used.
3. Click **Join**. **Back** returns to the code box.

## 5. When it does not connect

When a join or a host fails, a screen says what happened. Its first button, when there is one, is the quickest way
on; **Back** (or Esc) returns to your ship, with what you typed still there.

| The screen says | What to do |
|---|---|
| "Couldn't connect" and "No game has this code. Check it with the host." | Check the code with the host, letter by letter. The host may also have left: ask for the new code. |
| "Couldn't connect" and "The code service isn't answering. Join directly with the host's address." | The code service is down, or your network blocks it. Click **Join directly** and join by address (section 4), or use the fallback in section 6. |
| "Couldn't connect" and "No link to the host. If the lobby has room, ask the host for an address and join directly." | Your networks do not let you connect to each other. Click **Join directly** and use the fallback in section 6. |
| "Couldn't connect" and "The lobby is full." | Wait for a free place, or ask someone to leave; then **Try again**. |
| "Couldn't connect" and "The host isn't answering. Check the address and the network." | Check that the host's game is running and in the lobby, the address and the port; the host's firewall must let UDP in on that port. With a code: the host may have left; ask them to host again. Then **Try again**. |
| "Couldn't connect" and "The round has already started. Join when everyone is back in the lobby." | Wait until the host is back in the lobby, then **Try again**. |
| "Couldn't connect" and "The host has another version of the game. You need the same one." (sometimes with "Host:" and "You:" versions) | You and the host have different releases. Both download the newest release. |
| "Connection lost" | The host left or the network dropped. Ask the host to host again, then join again. |
| "The map didn't load" and "The round goes on without you." | The match went on without you. Join again when the host is back in the lobby; if it keeps happening, download and unzip the release again. |
| "Couldn't start the game" | Hosting failed, often because the port is in use. Close any other copy of the game and **Try again**, or host on another port (section 4; your friends then use it too). |
| "The session stopped" and "The game ran into an error. The details are in the log." | Something went wrong in the game. Tell the person who shared the game with you what you were doing. |

## 6. The fallback when nothing connects

Some home networks block direct connections between players. Then one of these gets you playing with **Join by
address** (section 4):

- **playit.gg** (the plan; not tested with the game yet). Only the host installs it. The host creates a free UDP
  tunnel to port 24600, clicks **Host a game** under **Join by address**, and shares the address playit.gg gives them.
  Friends type that address, with its port, into **Host address** and click **Join**.
- **Tailscale** (if playit.gg does not work out). Everyone installs Tailscale and joins the host's network (see
  Tailscale's site for its free plan). The host clicks **Host a game** under **Join by address** and shares their Tailscale
  address. Friends join it by address.
