#!/usr/bin/env bash
# Test 2: union with templated multi-line entries that share identical lines; plus CLAUDE.md numbered rules and CREDITS rows.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)/run2"
rm -rf "$ROOT"; mkdir -p "$ROOT"; cd "$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
g() { git -c init.defaultBranch=main -c core.autocrlf=false "$@"; }

g init -q r; cd r
printf '* merge=union\n' > .gitattributes
printf '# Interventions\n' > INTERVENTIONS.md
printf '# Rules\n1. Rule one.\n2. Rule two.\n\n## Other section\ntext\n' > CLAUDE.md
printf '| Asset | Author | License |\n|---|---|---|\n| a.ogg | X | CC0 |\n' > CREDITS.md
g add .; g commit -qm base
g switch -qc eng
cat >> INTERVENTIONS.md <<'EOF'

## 2026-09-28 eng-push-without-tests
- Who intervened: engineer
- What went wrong: agent pushed without running GdUnit4
- Rule file: CLAUDE.md
- Rule text: Run tests before every push.
- Status: rule added
---
EOF
printf '# Rules\n1. Rule one.\n2. Rule two.\n3. Run tests before every push.\n\n## Other section\ntext\n' > CLAUDE.md
printf '| b.png | Kenney | CC0 |\n' >> CREDITS.md
g commit -qam eng
g switch -q main; g switch -qc des
cat >> INTERVENTIONS.md <<'EOF'

## 2026-09-28 des-edited-core
- Who intervened: designer
- What went wrong: designer agent edited core/
- Rule file: CLAUDE.md
- Rule text: Designer agent never edits core/.
- Status: rule added
---
EOF
printf '# Rules\n1. Rule one.\n2. Rule two.\n3. Designer agent never edits core/.\n\n## Other section\ntext\n' > CLAUDE.md
printf '| c.wav | Sonniss | CC-BY 4.0 |\n' >> CREDITS.md
g commit -qam des
g switch -q main; g merge -q --no-ff eng -m "PR eng"
g switch -q des
if g rebase main >/dev/null 2>&1; then echo "rebase: OK (no conflict reported)"; else echo "rebase: CONFLICT"; fi
for f in INTERVENTIONS.md CLAUDE.md CREDITS.md; do echo "----- $f -----"; cat -A "$f" | sed 's/\$$//'; done
