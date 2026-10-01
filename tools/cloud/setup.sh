#!/usr/bin/env bash
# Installs the verify toolchain in a Linux cloud container the way .github/workflows/ci.yml does:
# the pinned Godot Linux build in ~/godot/godot (SHA-512 checked on every run) and the pinned gdtoolkit.
# Idempotent: a downloaded zip with the right checksum is reused. Usage: tools/cloud/setup.sh
# Also raises the default UDP receive buffer when it is below 416 KB: some container kernels charge about 830 bytes per
# small datagram, so the 208 KB default held 256 of the 320 datagrams verify's stall step queues (#159).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
run="$repo/tools/run.sh"

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

python3 -m pip install --disable-pip-version-check -q "gdtoolkit==$gdtoolkit"
python3 -m pip show gdtoolkit | grep '^Version:'

# The stall backlog (tools/runner/doctor.py, STALL_BACKLOG_DATAGRAMS) needs room; `doctor` warns if it still lacks it.
rmem_min=425984
rmem=/proc/sys/net/core/rmem_default
if [ -r "$rmem" ] && [ "$(cat "$rmem")" -lt "$rmem_min" ]; then
  if [ -w "$rmem" ]; then
    echo "$rmem_min" > "$rmem"
    echo "net.core.rmem_default raised to $rmem_min"
  else
    echo "warning: cannot raise net.core.rmem_default to $rmem_min; verify's stall step may fail (see doctor)" >&2
  fi
fi

echo
echo "Toolchain ready. Before running the runner:"
echo "export GODOT_BIN=\$HOME/godot/godot"
