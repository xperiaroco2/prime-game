#!/usr/bin/env bash
# Installs the verify toolchain in a Linux cloud container the way CI does (.github/actions/setup-toolchain):
# the pinned Godot Linux build in ~/godot/godot (SHA-512 checked on every run, linked as `godot` on PATH when
# /usr/local/bin is writable) and the pinned gdtoolkit. Idempotent: a downloaded zip with the right checksum is
# reused. Usage: tools/cloud/setup.sh (from any folder).
# Also raises the default UDP receive buffer when it is below RMEM_DEFAULT_FIX (tools/runner/doctor.py): some
# container kernels charge about 830 bytes per small datagram, so the 208 KB default held 256 of the 320 datagrams
# verify's stall step queues (#159).
# In a cloud session only (CLAUDE_CODE_REMOTE=true), it leaves the Windows-only TwoVoIP extension out of this clone,
# as CI does (#345): see the last step.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
run="$repo/tools/run.sh"
python="${PYTHON_BIN:-python3}"

# Plain assignments: under `set -e` a failing `pins --get` stops the script.
zip=$("$run" pins --get godot_linux_zip)
url=$("$run" pins --get godot_linux_url)
sha512=$("$run" pins --get godot_linux_sha512)
gdtoolkit=$("$run" pins --get gdtoolkit)

download="$HOME/godot-download"
mkdir -p "$download"
if ! (cd "$download" && echo "$sha512  $zip" | sha512sum -c --status - 2>/dev/null); then
  echo "Downloading $url"
  curl -fsSL --retry 3 -o "$download/$zip.part" "$url"
  mv "$download/$zip.part" "$download/$zip"
fi
(cd "$download" && echo "$sha512  $zip" | sha512sum -c -)

mkdir -p "$HOME/godot"
rm -f "$HOME/godot/${zip%.zip}"
unzip -q -o "$download/$zip" -d "$HOME/godot"
mv -f "$HOME/godot/${zip%.zip}" "$HOME/godot/godot"
chmod +x "$HOME/godot/godot"
"$HOME/godot/godot" --headless --version
if [ -w /usr/local/bin ]; then
  ln -sf "$HOME/godot/godot" /usr/local/bin/godot
  echo "godot on PATH: /usr/local/bin/godot -> $HOME/godot/godot"
fi

# The container is disposable: a system Python marked externally managed (PEP 668) takes the package anyway.
PIP_BREAK_SYSTEM_PACKAGES=1 "$python" -m pip install --disable-pip-version-check -q "gdtoolkit==$gdtoolkit"
"$python" -m pip show gdtoolkit | grep '^Version:'

rmem_min=425984 # RMEM_DEFAULT_FIX in tools/runner/doctor.py
rmem=/proc/sys/net/core/rmem_default
if [ ! -r "$rmem" ]; then
  echo "note: $rmem is not readable; doctor probes the UDP buffer itself"
elif [ "$(cat "$rmem")" -lt "$rmem_min" ]; then
  if (echo "$rmem_min" > "$rmem") 2>/dev/null; then
    echo "net.core.rmem_default raised to $rmem_min"
  else
    echo "warning: cannot raise net.core.rmem_default to $rmem_min; verify's stall step may fail (see doctor)" >&2
  fi
fi

# The TwoVoIP addon ships Windows libraries only (the M5 voice ADR §2, E35 (a)): on Linux Godot prints an `ERROR:`
# line for its .gdextension, which fails verify's Godot steps. CI deletes the .gdextension and its .uid; a session
# that deleted them could commit the deletion. A sparse checkout leaves the two files out of the working tree while
# the index keeps them, so `git status` stays clean and `git add -A` stages nothing. Plain `git update-index
# --skip-worktree` does the same until a switch to a commit that changes either file, a `reset --hard` or a new
# worktree brings it back; the sparse patterns hold through all three (tried in #345). Undo: git sparse-checkout
# disable. tools/runner/doctor.py fails in a cloud session while the .gdextension is in the working tree.
# --no-cone: cone mode takes folders only, and these are two files. Everything else stays in ('/*').
sparse=('/*' '!/addons/twovoip/twovoip.gdextension' '!/addons/twovoip/twovoip.gdextension.uid')
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "note: not a cloud session (CLAUDE_CODE_REMOTE is not true): the TwoVoIP extension stays in the working tree"
elif [ "$(git -C "$repo" config --bool core.sparseCheckout || true)" = "true" ] &&
  [ "$(git -C "$repo" sparse-checkout list)" != "$(printf '%s\n' "${sparse[@]}")" ]; then
  echo "warning: this clone already has other sparse-checkout patterns; the TwoVoIP extension is left as it is" >&2
else
  git -C "$repo" sparse-checkout set --no-cone "${sparse[@]}"
  echo "TwoVoIP extension left out of the working tree (sparse checkout); git status stays clean"
fi

echo
echo "Toolchain ready. The runner finds Godot on PATH; if /usr/local/bin was not writable, first:"
echo "export GODOT_BIN=\$HOME/godot/godot"
