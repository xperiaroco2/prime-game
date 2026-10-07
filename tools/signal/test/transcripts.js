// The shared signalling transcripts (tests/fixtures/signal/, docs/ARCHITECTURE.md §4.8), read the
// way tests/unit/net/signal/signal_transcripts.gd reads them for SignalRouter and LanSignalling.

import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const FOLDER = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "tests", "fixtures", "signal");

// Every transcript, so a deleted one fails the suites (signal_transcripts.gd's NAMES).
export const NAMES = [
  "caps_candidates.json",
  "caps_forwarded_too_large.json",
  "caps_full.json",
  "caps_too_large.json",
  "flow_closed.json",
  "flow_host_left.json",
  "flow_join.json",
  "flow_no_room.json",
  "flow_wrong_version.json",
  "forged_candidate_to.json",
  "forged_close.json",
  "forged_from.json",
  "forged_offer.json",
  "forged_reopen.json",
  "forged_roles.json",
  "turn_per_joiner.json",
];

// Every transcript by file name, sorted.
export function all() {
  const found = new Map();
  for (const name of readdirSync(FOLDER).filter((each) => each.endsWith(".json")).sort()) {
    found.set(name, JSON.parse(readFileSync(join(FOLDER, name), "utf8")));
  }
  return found;
}

// Whether only the Worker can replay the transcript: it needs TURN credentials minted, from the
// fake API answers in its config.turn.minted, in order ("turn_only" says why).
export function turnOnly(transcript) {
  return transcript.turn_only !== undefined;
}

// The steps with "repeat" unrolled, each one's text ready to send as "raw".
export function stepsOf(transcript) {
  const steps = [];
  for (const rawStep of transcript.steps) {
    const step = structuredClone(rawStep);
    if (step.send !== undefined) {
      step.raw = JSON.stringify(step.send);
    }
    if (step.pad_to !== undefined) {
      step.raw = step.raw + " ".repeat(step.pad_to - step.raw.length);
    }
    for (let i = 0; i < (step.repeat ?? 1); i++) {
      steps.push(step);
    }
  }
  return steps;
}

// The codes the transcript's service hands out, in order, as the router's code source.
export function codeSource(transcript) {
  const codes = [...transcript.config.codes];
  return () => (codes.length === 0 ? "" : String(codes.shift()));
}

// A message as canonical text (sorted keys at every level), so messages compare as JSON values.
export function canonical(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonical).join(",")}]`;
  }
  if (typeof value === "object" && value !== null) {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

// One delivery as a line: "<socket> <message>[ close]".
export function line(socket, message, close) {
  return `${socket} ${canonical(message)}${close ? " close" : ""}`;
}

export function expectedLines(step) {
  return (step.expect ?? []).map((each) => line(each.to, each.msg, each.close ?? false));
}
