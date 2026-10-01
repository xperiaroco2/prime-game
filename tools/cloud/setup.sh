#!/usr/bin/env bash
# Installs the verify toolchain in a Linux cloud container the way .github/workflows/ci.yml does:
# the pinned Godot Linux build in ~/godot/godot (SHA-512 checked on every run, linked as `godot` on PATH when
# /usr/local/bin is writable) and the pinned gdtoolkit. Idempotent: a downloaded zip with the right checksum is
# reused. Usage: tools/cloud/setup.sh (from any folder).
# Also raises the default UDP receive buffer when it is below RMEM_DEFAULT_FIX (tools/runner/doctor.py): some
# container kernels charge about 830 bytes per small datagram, so the 208 KB default held 256 of the 320 datagrams
# verify's stall step queues (#159).
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

echo
echo "Toolchain ready. The runner finds Godot on PATH; if /usr/local/bin was not writable, first:"
echo "export GODOT_BIN=\$HOME/godot/godot"
