#!/usr/bin/env bash
# PROPOSAL prototype: PostToolUse hook for .gd files. Exit 2 + stderr => shown to Claude.
set -u
payload="$(cat)"
file="$(printf '%s' "$payload" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write((j.tool_input&&j.tool_input.file_path)||"")})')"
case "$file" in *.gd) ;; *) exit 0 ;; esac
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="$(realpath --relative-to="$root" "$file" 2>/dev/null || echo "$file")"
case "$rel" in addons/*|.godot/*) exit 0 ;; esac   # gdtoolkit ignores excluded_directories for explicit paths (#395)
gt="${GDTOOLKIT_DIR:+$GDTOOLKIT_DIR/}"
out=""; rc=0
"${gt}gdformat" "$file" >/dev/null 2>&1 || { out+=$'gdformat failed (syntax gdtoolkit cannot parse?)\n'; rc=2; }
lint="$("${gt}gdlint" "$file" 2>&1)" || { out+="$lint"$'\n'; rc=2; }
chk="$(cd "$root" && timeout 60 "${GODOT_BIN:-godot}" --headless --no-header --path . --check-only -s "res://${rel}" 2>&1)" || { out+="$(printf '%s\n' "$chk" | grep -E 'SCRIPT ERROR|Parse Error|at: GDScript' )"$'\n'; rc=2; }
[ $rc -ne 0 ] && printf '%s' "$out" >&2
exit $rc
