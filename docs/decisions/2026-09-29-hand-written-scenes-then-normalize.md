# Agents hand-write `.tscn`/`.tres`, then `normalize`; `check` lints UIDs

- **Status:** Accepted
- **Date:** 2026-09-29 (decided 2026-09-28, Phase A tier 3 item T2; built in M0 stages 1 and 6)
- **Deciders:** the agent (a Phase A tier 3 choice open to the engineer's veto; no veto recorded)

## Context
Humans write no code, so agents write scenes and resources as text. Godot fails silently in three ways (tested
locally on 4.7.2): a uid that belongs to another existing file is followed, and the next editor save makes it
canonical (a copied template uid or `.uid` sidecar); duplicate uids only warn; a missing script `.uid` on a fresh clone
gets a new uid. It also drops, without an error, a property it does not know, one at its default value, and every line
after a parse error.

## Decision
- The agent writes readable text and never invents or copies a uid or a `.uid` sidecar.
- `tools\run.cmd normalize <files>` re-saves the files in headless editor context (`--headless -e -s`), which adds
  the header uid and node `unique_id`s exactly as the designer's editor would. A second run is byte-identical. It
  compares property keys before and after, and on a loss restores the file and fails.
- `check` fails on UID warnings from the import, on files the import creates or changes, and on an `ext_resource` uid
  that resolves to a different file than its `path=`.

## Alternatives
- Let the editor fix files on the next open: the silent uid adoption above.
- Generate uids in the agent: they can collide with, or copy, existing ones.

## Consequences
The headless editor re-save is undocumented: `normalize`'s selftest runs it against the real Godot, and it is re-checked
on every Godot upgrade. Research: `docs/history/2026-09-28-phase-a/AGENT_WORKFLOW-proposal.md` §12.4 and
`local-tests/uidlab/`.
