# Interventions log

Human interventions and the rule each one produced ([KICKOFF §5.2](history/KICKOFF.md)) are kept as **one file per entry** in
[`docs/interventions/`](interventions/), named `YYYY-MM-DD-<who>-<slug>.md`, so two branches never conflict
([ADR](decisions/2026-09-28-one-file-per-entry-logs.md)).

Do not append entries to this file. Use `/log-intervention` (from M0), or add a new file in `docs/interventions/`.
