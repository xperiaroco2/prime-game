// TURN credentials per joiner (M6-10, D17 (b), E55): Cloudflare Realtime TURN mints a username and
// credential for each host offer to a joiner, so the relay goes only to a joiner a host is
// connecting, never with "found" (a code pasted in a public chat hands out no relay). On only when
// both secrets are set; with neither, the service is exactly what it was without TURN.
//
// The API (developers.cloudflare.com/realtime/turn/generate-credentials/, read 2026-10-04):
// POST https://rtc.live.cloudflare.com/v1/turn/keys/<key id>/credentials/generate-ice-servers with
// "Authorization: Bearer <API token>" and {"ttl": seconds} answers 201 with {"iceServers": [...]},
// a STUN entry and a TURN entry of six URLs, one username and one credential.

import * as codec from "./codec.js";

// The secrets' names, as Cloudflare's page calls the key's id and its API token.
export const KEY_ID = "TURN_KEY_ID";
export const API_TOKEN = "TURN_KEY_API_TOKEN";
// How long a credential lasts, in seconds: D17's 10 minutes, a placeholder, "not a decision".
// `TURN_TTL_SECONDS` in wrangler.toml's [vars] replaces it. Cloudflare's FAQ: when a credential
// expires while its allocation is in use, "after a short delay, the connection will be
// disconnected"; a credential lasts at most 48 hours.
export const TTL_SECONDS = 600;
export const TTL_VAR = "TURN_TTL_SECONDS";
export const MAX_TTL_SECONDS = 48 * 3600;
// How long the service waits for the API before the offer goes without TURN.
export const TIMEOUT_MS = 5000;
export const API = "https://rtc.live.cloudflare.com/v1/turn/keys";

// The TURN key from the Worker's secrets, or null when none is configured. One secret without the
// other is no TURN, logged: each `wrangler secret put` goes live at once, so the service runs between
// the engineer's two commands.
export function turnFrom(env, log = (text) => console.log(text)) {
  const keyId = env[KEY_ID] ?? "";
  const token = env[API_TOKEN] ?? "";
  if (keyId === "" && token === "") {
    return null;
  }
  if (keyId === "" || token === "") {
    log(`signal: no TURN until both ${KEY_ID} and ${API_TOKEN} are set`);
    return null;
  }
  const ttl = Number(env[TTL_VAR] ?? TTL_SECONDS);
  if (!Number.isInteger(ttl) || ttl < 1 || ttl > MAX_TTL_SECONDS) {
    throw new Error(`signal: ${TTL_VAR} is not a whole number of seconds from 1 to ${MAX_TTL_SECONDS}`);
  }
  return { keyId, token, ttl };
}

// The TURN entries of one fresh credential, by the clients' rules for "ice_servers": only "turn:"
// and "turns:" URLs (the configuration already names the STUN server), none on port 53 (the page:
// "known to be blocked by web browsers"), each entry split into entries of at most
// codec.MAX_ICE_URLS URLs with the same username and credential, so no protocol change is needed.
// Throws when the API fails or answers what the clients would drop.
export async function mint(turn, fetchFn, timeoutMs = TIMEOUT_MS) {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), timeoutMs);
  let body;
  try {
    const response = await fetchFn(`${API}/${encodeURIComponent(turn.keyId)}/credentials/generate-ice-servers`, {
      method: "POST",
      headers: { Authorization: `Bearer ${turn.token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ttl: turn.ttl }),
      signal: abort.signal,
    });
    if (response.status !== 201) {
      throw new Error(`signal: the TURN API answered ${response.status}`);
    }
    body = await response.json();
  } finally {
    clearTimeout(timer);
  }
  if (typeof body !== "object" || body === null || !Array.isArray(body.iceServers)) {
    throw new Error("signal: the TURN API answered no iceServers");
  }
  const servers = [];
  for (const entry of body.iceServers) {
    if (typeof entry !== "object" || entry === null || !Array.isArray(entry.urls)) {
      throw new Error("signal: the TURN API answered an entry without urls");
    }
    const urls = entry.urls.filter((url) => typeof url === "string" && relayed(url) && !port53(url));
    if (urls.length > 0 && (typeof entry.username !== "string" || typeof entry.credential !== "string")) {
      throw new Error("signal: the TURN API answered a TURN entry without its username and credential");
    }
    for (let at = 0; at < urls.length; at += codec.MAX_ICE_URLS) {
      servers.push({
        urls: urls.slice(at, at + codec.MAX_ICE_URLS),
        username: entry.username,
        credential: entry.credential,
      });
    }
  }
  if (servers.length === 0) {
    throw new Error("signal: the TURN API answered no TURN URL");
  }
  return servers;
}

// `base` (the configuration's servers) and then `turn`'s entries, as many as the list holds,
// checked by the clients' rules; throws when no TURN entry fits or the clients would drop the list.
export function withTurn(base, turn) {
  if (base.length >= codec.MAX_ICE_SERVERS) {
    throw new Error(`ICE_SERVERS leaves no room for TURN (${codec.MAX_ICE_SERVERS} entries at most)`);
  }
  const servers = [...structuredClone(base), ...turn].slice(0, codec.MAX_ICE_SERVERS);
  const offer = { t: "offer", v: codec.VERSION, id: 1, sdp: "v=0", ice_servers: servers };
  const decoded = codec.decode(new TextEncoder().encode(JSON.stringify(offer)), codec.Side.TO_JOINER);
  if (decoded.why !== undefined) {
    throw new Error(`signal: the TURN API answered servers the clients drop (${decoded.why})`);
  }
  return decoded.fields.ice_servers;
}

function relayed(url) {
  return url.startsWith("turn:") || url.startsWith("turns:");
}

// Whether the URL names port 53: "turn:host:53" or "turn:host:53?transport=udp".
function port53(url) {
  return /:53(\?|$)/.test(url);
}
