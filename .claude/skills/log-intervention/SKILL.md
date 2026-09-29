---
name: log-intervention
description: Record a human's correction of the agent as a docs/interventions entry and promote its rule into the right instruction file in the same PR. Use when a human corrects the agent's way of working, or says "запам'ятай" or "remember" and chooses the project over personal memory.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(git log *)
  - PowerShell(git log *)
---

# Log an intervention (docs/AGENT_WORKFLOW.md §3 and §10)

1. **Project or personal?** After "запам'ятай" or "remember", ask exactly one question in the human's language:
   "для проєкту (PR) чи тільки для вас?" (for the project, as a PR, or only for you?).
   - Personal: propose the exact line for `~/.claude/CLAUDE.md`, write it only after the human approves, and stop.
     Never put shared rules or task state in auto memory.
   - Project: continue. If the human wants to discuss the rule before it is written down, open an issue from
     `.github/ISSUE_TEMPLATE/intervention.md` instead and stop.
2. **Where it lands.** On a task branch `<area>/<n>-<slug>`: in this branch, so it ships in the task's PR. Otherwise
   open an issue (feature template, label `area:tooling`, goal "log intervention: <rule>") and use `start-task`.
3. **The entry:** `docs/interventions/YYYY-MM-DD-<who>-<slug>.md`, where `<who>` is `engineer` or `designer` (the
   human who intervened) and the date is today's (`Get-Date -Format yyyy-MM-dd`, or `date +%F`). Read the newest
   existing entry and follow its format:
   - `# YYYY-MM-DD: <the rule in a few words>`;
   - **Who intervened**, and **Session** (whose session, surface, model, and the task or stage);
   - **What happened**: facts, including what the human said, paraphrased;
   - **Why it happened**: the agent's actual reasoning error, not a generic cause;
   - **Rule adopted**: numbered, each an instruction an agent can follow;
   - **Where the rule lives now**: this entry, plus each file it was promoted into.
4. **Promote the rule** to the narrowest place that is loaded when it matters:
   - root `CLAUDE.md` only for rules that apply to every task (it is always loaded; 150-line budget);
   - an area `CLAUDE.md` (`core/`, `content/`, …) for one area;
   - `.claude/rules/<topic>.md` with `paths:` for a kind of file;
   - a skill step for a procedure; a hook or permission rule when it must be enforced (engineer-owned, ask first).
   Write it as an instruction and put `<!-- see docs/interventions/<file> -->` on the next line. Only edit files your
   human owns or that are shared (root `CLAUDE.md` ownership map). The designer's agent does not edit engine-owned
   files: it writes the entry and asks the engineer in the PR to promote the rule, naming the file.
5. **Check budgets:** `tools\run.cmd lint`. Over budget: scope a rule to `paths:`, move it into a skill, or retire an
   old rule, and say in the entry which you did.
6. **Commit:** `docs: log intervention <slug>` with the entry and the promoted rule together. The PR goes out with
   `finish-task`.
