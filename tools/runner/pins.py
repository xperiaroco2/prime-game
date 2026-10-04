"""Pinned tool versions. One place; CI reads them with `run.py pins`.

See docs/decisions/2026-09-28-toolchain-pins.md before changing any of these.
"""

GODOT = "4.7.2"
# Prefix of `godot --version` for the official 4.7.2 stable build.
GODOT_VERSION_PREFIX = "4.7.2.stable.official"
# The Linux build CI downloads from the official release, and its checksum from that release's SHA512-SUMS.txt.
GODOT_LINUX_ZIP = f"Godot_v{GODOT}-stable_linux.x86_64.zip"
GODOT_LINUX_URL = f"https://github.com/godotengine/godot/releases/download/{GODOT}-stable/{GODOT_LINUX_ZIP}"
GODOT_LINUX_SHA512 = (
    "9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b14"
    "67edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
)
# The export templates of the same release (#369): the .tpz and its checksum from that release's SHA512-SUMS.txt. The
# templates folder Godot looks for is named after the build, `4.7.2.stable` (the .tpz's templates/version.txt).
GODOT_TEMPLATES_TPZ = f"Godot_v{GODOT}-stable_export_templates.tpz"
GODOT_TEMPLATES_URL = f"https://github.com/godotengine/godot/releases/download/{GODOT}-stable/{GODOT_TEMPLATES_TPZ}"
GODOT_TEMPLATES_SHA512 = (
    "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5"
    "f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
)
GODOT_TEMPLATES_VERSION = f"{GODOT}.stable"
GDTOOLKIT = "4.5.0"
GDUNIT4 = "6.2.1"
PYTHON_MIN = (3, 11)
GH_MIN = (2, 97, 0)
CLAUDE_CODE_MIN = (2, 1, 281)

ALL = {
    "godot": GODOT,
    "godot_linux_zip": GODOT_LINUX_ZIP,
    "godot_linux_url": GODOT_LINUX_URL,
    "godot_linux_sha512": GODOT_LINUX_SHA512,
    "godot_templates_tpz": GODOT_TEMPLATES_TPZ,
    "godot_templates_url": GODOT_TEMPLATES_URL,
    "godot_templates_sha512": GODOT_TEMPLATES_SHA512,
    "gdtoolkit": GDTOOLKIT,
    "gdunit4": GDUNIT4,
    "python_min": ".".join(map(str, PYTHON_MIN)),
    "gh_min": ".".join(map(str, GH_MIN)),
    "claude_code_min": ".".join(map(str, CLAUDE_CODE_MIN)),
}
