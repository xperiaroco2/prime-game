# Public repository on GitHub Free

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
On GitHub Free, a **private** repo gets no server-side enforcement: no protected branches, rulesets, required checks
or code-owner review (the API returned 403 on this account's private repos). Local guards can be bypassed by an
agent-written script run through the runner. Humans write zero code, so agents write everything, including anything
that could push to `main`.

## Decision
The repo is **public on GitHub Free**. `main` gets a ruleset: block force pushes, restrict deletions, require a PR.
Required status checks are added only after the CI PR has merged. Code-owner review stays off (authors cannot approve
their own PRs, so it would force the engineer to approve every designer PR). No admin bypass.

The Phase A archive is published **as is**. It contains a GitHub handle, an organization name and local paths; the
engineer judged this irrelevant for a hobby project.

## Alternatives
- Private on personal Pro, or on an org Team plan ($4/user/month): the same enforcement, but it costs money.
- Private on Free: $0, but no server-side enforcement.

## Consequences
- Game source and hidden-role logic are public.
- Server rulesets are the real barrier against pushes to `main`; the local layers only catch accidents earlier.
- Evidence: `docs/history/2026-09-28-phase-a/research/gaps.md` (gap1-01 to gap1-16).
