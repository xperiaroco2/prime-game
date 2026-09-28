#!/usr/bin/env bash
set -u
file="$(node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input.file_path||"")}catch(e){}})')"
case "$file" in *.gd) ;; *) exit 0 ;; esac
root="${CLAUDE_PROJECT_DIR:-$PWD}"
rel="$(realpath --relative-to="$root" "$file")"
case "$rel" in addons/*|.godot/*|tools/out/*) exit 0 ;; esac
gt="${GDTOOLKIT_DIR:+$GDTOOLKIT_DIR/}"
rc=0; msg=""
if "${gt}gdformat" "$file" >/dev/null 2>&1; then sed -i 's/\r$//' "$file"; else msg+="gdformat could not parse $rel"$'\n'; rc=2; fi
if ! out="$("${gt}gdlint" "$file" 2>&1)"; then msg+="$out"$'\n'; rc=2; fi
check() { (cd "$root" && timeout 60 "${GODOT_BIN:-godot}" --headless --no-header --path . --check-only -s "res://$rel" 2>&1); }
if ! out="$(check)"; then
  if printf '%s' "$out" | grep -qE 'not declared in the current scope|Could not find type'; then
    (cd "$root" && timeout 300 "${GODOT_BIN:-godot}" --headless --no-header --path . --import >/dev/null 2>&1)
    out="$(check)" && out=""
  fi
  [ -n "$out" ] && { msg+="$(printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|at: GDScript')"$'\n'; rc=2; }
fi
[ "$rc" -ne 0 ] && printf '%s' "$msg" >&2
exit "$rc"
