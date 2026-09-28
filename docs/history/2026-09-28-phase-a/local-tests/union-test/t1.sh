#!/usr/bin/env bash
# Test 1: two branches append a multi-line entry at EOF of a merge=union file.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)/run1"
rm -rf "$ROOT"; mkdir -p "$ROOT"; cd "$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
g() { git -c init.defaultBranch=main -c core.autocrlf=false "$@"; }

setup() { # $1 = dir, $2 = with-attr (1/0)
  g init -q "$1"; cd "$1"
  mkdir -p docs
  if [ "$2" = 1 ]; then printf 'docs/INTERVENTIONS.md merge=union\nCREDITS.md merge=union\n' > .gitattributes; g add .gitattributes; fi
  printf '# Interventions\n\nAppend-only log.\n\n## 2026-09-01 seed\n- Trigger: seed\n- Rule: seed rule\n' > docs/INTERVENTIONS.md
  g add docs; g commit -qm base
  g switch -qc eng
  printf '\n## 2026-09-28 eng-lesson\n- Trigger: agent pushed without tests\n- Rule: CLAUDE.md rule 12\n' >> docs/INTERVENTIONS.md
  g commit -qam "eng entry"
  g switch -q main; g switch -qc des
  printf '\n## 2026-09-28 des-lesson\n- Trigger: agent edited core/\n- Rule: CLAUDE.md rule 13\n' >> docs/INTERVENTIONS.md
  g commit -qam "des entry"
  g switch -q main
  g merge -q --no-ff eng -m "merge PR eng"   # first PR lands
}

echo "=== A) WITH merge=union: rebase des onto main ==="
( setup withattr 1
  g switch -q des
  if g rebase main >/dev/null 2>&1; then echo "rebase: OK (no conflict)"; else echo "rebase: CONFLICT"; g rebase --abort; fi
  echo "--- resulting file ---"; cat docs/INTERVENTIONS.md
  echo "--- conflict markers? ---"; grep -c '^<<<<<<<\|^>>>>>>>' docs/INTERVENTIONS.md || true
)
echo
echo "=== B) WITH merge=union: merge main into des (GitHub 'Update branch' equivalent, done locally) ==="
( cd withattr; g switch -q des; g reset -q --hard ORIG_HEAD 2>/dev/null; g log --oneline -1
  if g merge -q --no-edit main >/dev/null 2>&1; then echo "merge: OK (no conflict)"; else echo "merge: CONFLICT"; g merge --abort; fi
  cat docs/INTERVENTIONS.md
)
echo
echo "=== C) CONTROL without attribute: rebase des onto main ==="
( setup noattr 0
  g switch -q des
  if g rebase main >/dev/null 2>&1; then echo "rebase: OK"; else echo "rebase: CONFLICT"; g diff --name-only --diff-filter=U; g rebase --abort; fi
)
echo
echo "=== D) server-side simulation: bare clone + git merge-tree --write-tree (no worktree) ==="
( g clone -q --bare withattr bare.git; cd bare.git
  echo "-- default (bare repo, no attr source) --"
  g merge-tree --write-tree --name-only main des; echo "exit=$?"
  echo "-- with -c attr.tree=main --"
  g -c attr.tree=main merge-tree --write-tree --name-only main des; echo "exit=$?"
  echo "-- with --attr-source=main --"
  g --attr-source=main merge-tree --write-tree --name-only main des; echo "exit=$?"
)
