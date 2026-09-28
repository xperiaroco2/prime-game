#!/usr/bin/env bash
# Test 4: union with entries whose LAST line is unique (end sentinel). Do all lines of both entries survive?
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)/run4"
rm -rf "$ROOT"; mkdir -p "$ROOT"; cd "$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
g() { git -c init.defaultBranch=main -c core.autocrlf=false "$@"; }
entry() { printf '\n## %s\n- Who intervened: %s\n- Rule file: CLAUDE.md\n- Status: rule added\n<!-- end %s -->\n' "$1" "$2" "$1"; }
g init -q r; cd r
printf 'INTERVENTIONS.md merge=union\n' > .gitattributes
printf '# Interventions\n' > INTERVENTIONS.md
g add .; g commit -qm base
g switch -qc eng; entry 2026-09-28-eng-a engineer >> INTERVENTIONS.md; g commit -qam eng
g switch -q main; g switch -qc des; entry 2026-09-28-des-b designer >> INTERVENTIONS.md; g commit -qam des
g switch -q main; g merge -q --no-ff eng -m "PR eng"
g switch -q des
if g rebase main >/dev/null 2>&1; then echo "rebase: OK"; else echo "rebase: CONFLICT"; fi
cat INTERVENTIONS.md
echo "--- line counts: expected 2x each field ---"
for p in 'Rule file' 'Status: rule added' '<!-- end'; do printf '%s: ' "$p"; grep -c -- "$p" INTERVENTIONS.md; done
