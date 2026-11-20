#!/usr/bin/env bash
# Build the Android runtime bundle (2.2.7+).
#
# 2.2.6 and earlier compiled one ELF per release: Bun, the module graph and
# every native asset in a single file (~86 MB deb, ~244 MiB installed). The
# bundle keeps the same module graph as JavaScript and runs it on the `bun`
# package Termux already ships, so the package only carries what is actually
# Android-specific:
#
#   lib/opencode/index.js + hashed assets   module graph (this build)
#   lib/opencode/libopentui-*.so            bionic OpenTUI (zig + NDK)
#   lib/opencode/librust_pty_arm64.so       bionic bun-pty (cargo)
#   lib/opencode/watcher.node               bionic @parcel/watcher
#   bin/opencode                            shell wrapper, execs bun
#
# Everything is lock-driven: the OpenCode commit, Bun version, OpenTUI pin and
# bun-pty ref all come from tools/supply-chain-lock.json.
#
# Asset paths are baked at build time, so the bundle is built against the
# placeholder `@TERMUX_PREFIX@` and rewritten when it is packaged or installed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${OPENCODE_VERSION:=$(python3 tools/ocver.py current)}"
BUN_VERSION="$(python3 tools/ocver.py field bun_version "$OPENCODE_VERSION")"
PREFIX_PLACEHOLDER="${PREFIX_PLACEHOLDER:-@TERMUX_PREFIX@}"
install_dir="$PREFIX_PLACEHOLDER/lib/opencode"
api="${ANDROID_API:-28}"

readarray -t locked < <(python3 - "$OPENCODE_VERSION" "$BUN_VERSION" <<'PY'
import json
import sys

version, bun_version = sys.argv[1], sys.argv[2]
lock = json.load(open("tools/supply-chain-lock.json", encoding="utf-8"))
opencode = lock["opencode"][version]
host = lock["source_build_bun_" + bun_version.replace(".", "_")]
print(opencode["commit"])
print(host["linux_x64_archive_sha256"])
PY
)
test "${#locked[@]}" -eq 2
commit="${locked[0]}"

work="$ROOT/work/bundle/$OPENCODE_VERSION"
mkdir -p "$work"

# ---- host Bun: the builder, never shipped -----------------------------------
host_zip="$work/bun-linux-x64.zip"
if [ ! -x "$work/host/bun-linux-x64/bun" ]; then
  curl -fsSLo "$host_zip" "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-linux-x64.zip"
  echo "${locked[1]}  $host_zip" | sha256sum -c -
  unzip -oq "$host_zip" -d "$work/host"
fi
host_bun="$work/host/bun-linux-x64/bun"
test "$("$host_bun" --version)" = "$BUN_VERSION" || {
  echo "host bun is not $BUN_VERSION" >&2
  exit 1
}

# ---- pinned source ---------------------------------------------------------
src="$work/opencode"
if [ ! -d "$src/.git" ]; then
  mkdir -p "$src"
  git -C "$src" init -q .
  git -C "$src" remote add origin https://github.com/anomalyco/opencode.git
fi
git -C "$src" fetch -q --depth=1 origin "$commit"
git -C "$src" checkout -q --detach FETCH_HEAD
test "$(git -C "$src" rev-parse HEAD)" = "$commit"
# The lock mirrors pins upstream owns; stop before shipping mismatched natives.
python3 - "$src" "$(python3 tools/ocver.py field opentui_version "$OPENCODE_VERSION")" \
  "$(python3 tools/ocver.py bunpty ref)" <<'PY'
import json
import re
import sys
from pathlib import Path

root, opentui, bunpty = Path(sys.argv[1]), sys.argv[2], sys.argv[3].lstrip("v")


def pin(path: Path, name: str) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r'"' + re.escape(name) + r'":\s*"([^"]+)"', text)
    if match is None:
        raise SystemExit(f"{path.name}: no pin for {name}")
    return match.group(1)


found = {
    "opentui": pin(root / "package.json", "@opentui/core"),
    "bun-pty": pin(root / "packages/core/package.json", "bun-pty"),
}
expected = {"opentui": opentui, "bun-pty": bunpty}
drift = {name: (found[name], expected[name]) for name in found if found[name] != expected[name]}
if drift:
    raise SystemExit(
        "upstream pins moved; update tools/supply-chain-lock.json and the natives: "
        + ", ".join(f"{k} {a} != {b}" for k, (a, b) in drift.items())
    )
print(f"pins: opentui {opentui}, bun-pty {bunpty}")
PY
OPENCODE_BUN_VERSION="$BUN_VERSION" python3 tools/patch-opencode-source.py "$src"
python3 tools/patch-opencode-bundle.py "$src"

cd "$src"
"$host_bun" install \
  --ignore-scripts \
  --filter '@opencode/cli' --filter '@opencode/app' \
  --os='*' --cpu='*' --libc='*'

# The TUI shim must hand Bionic's tagged pointers to the FFI unchanged, and
# OpenTUI's asset loader must accept process.platform "android". Both patch the
# installed @opentui/core chunks, so they run before Bun bundles them.
python3 "$ROOT/tools/patch-opentui-ffi.py" "$src"
python3 "$ROOT/tools/patch-opentui-loader.py" "$src"
python3 "$ROOT/tools/patch-fff-android.py" "$src"

# ---- natives ---------------------------------------------------------------
tui="$ROOT/artifacts/transplant/opentui-bionic/libopentui.so"
test -f "$tui" || {
  echo "missing bionic OpenTUI: $tui (run the libopentui build first)" >&2
  exit 1
}
# The verified copy keeps its debug info for the guard scan; ship a stripped one.
strip_bin="${LLVM_STRIP:-llvm-strip}"
command -v "$strip_bin" >/dev/null 2>&1 || {
  echo "missing $strip_bin (set LLVM_STRIP)" >&2
  exit 1
}
tui_ship="$work/libopentui.so"
cp -f "$tui" "$tui_ship"
"$strip_bin" --strip-unneeded "$tui_ship"
test "$(stat -c %s "$tui_ship")" -lt "$(stat -c %s "$tui")" || {
  echo "stripping libopentui did not shrink it" >&2
  exit 1
}
file "$tui_ship" | grep -q 'ARM aarch64' || {
  echo "stripped libopentui is not aarch64" >&2
  exit 1
}
# Bun bundles a native slot for every platform; identical bytes collapse into
# one hashed asset, and only the android slot is ever dlopened.
mapfile -t tui_slots < <(find node_modules/.bun -path '*/@opentui/core-*/*' \
  \( -name libopentui.so -o -name libopentui.dylib -o -name opentui.dll \) | sort)
test "${#tui_slots[@]}" -ge 2 || {
  echo "expected several @opentui/core-* slots, got: ${tui_slots[*]:-none}" >&2
  exit 1
}
printf '%s\n' "${tui_slots[@]}" | grep -q 'core-linux-arm64-musl' || {
  echo "the bionic slot (@opentui/core-linux-arm64-musl) is missing from: ${tui_slots[*]}" >&2
  exit 1
}
for slot in "${tui_slots[@]}"; do
  case $slot in
    # Bun keys the emitted asset on content *and* extension, so the darwin and
    # win32 slots only dedupe against each other if they are empty.
    */core-linux-*) cp -f "$tui_ship" "$slot" ;;
    *) : > "$slot" ;;
  esac
done
echo "opentui: installed the stripped bionic build in ${#tui_slots[@]} slots"

# fff's bionic build is a plain aarch64 shared object; Bun copies it into the
# bundle as an asset, so it only has to exist at build time.
fff_lib="$(find "$src/node_modules" -path '*@ff-labs/fff-bin-android-arm64/libfff_c.so')"
test "$(printf '%s\n' "$fff_lib" | wc -l)" -eq 1 && [ -f "$fff_lib" ] || {
  echo "expected one fff android arm64 build, got: ${fff_lib:-none}" >&2
  exit 1
}
file "$fff_lib" | grep -q 'ARM aarch64' || {
  echo "fff android build is not aarch64: $fff_lib" >&2
  exit 1
}
echo "fff: $(basename "$fff_lib")"

pty="$work/librust_pty_arm64.so"
NDK="${NDK:-}" ANDROID_API="$api" bash "$ROOT/scripts/ci/build-rust-pty-android.sh" "$pty"

watcher="$(find "$src/node_modules/.bun" -path '*@parcel+watcher-android-arm64@*/node_modules/@parcel/watcher-android-arm64/watcher.node')"
test "$(printf '%s\n' "$watcher" | wc -l)" -eq 1 && [ -f "$watcher" ] || {
  echo "expected one @parcel/watcher-android-arm64, got: $watcher" >&2
  exit 1
}

# ---- bundle ----------------------------------------------------------------
# The TUI banner is embedded at build time from .release/v<version>-highlights.md.
highlights_file="$ROOT/.release/v$OPENCODE_VERSION-highlights.md"
if [ -f "$highlights_file" ]; then
  grep -qx '### Highlights' "$highlights_file" || {
    echo "$highlights_file needs a '### Highlights' heading for the TUI banner" >&2
    exit 1
  }
  OPENCODE_RELEASE_NOTES="$(cat "$highlights_file")"
  export OPENCODE_RELEASE_NOTES
  echo "highlights: $(grep -c '^- ' "$highlights_file") bullets from $highlights_file"
fi

cd "$src/packages/cli"
OPENCODE_CHANNEL=latest OPENCODE_VERSION="$OPENCODE_VERSION" \
OPENCODE_TARGET=linux-arm64-android \
OPENCODE_INSTALL_DIR="$install_dir" \
  "$host_bun" run script/build.ts --skip-install
cd "$ROOT"

lib="$src/packages/cli/dist/cli-linux-arm64-android/lib"
test -f "$lib/index.js" || {
  echo "bundle not produced: $lib/index.js" >&2
  exit 1
}
# The tagged-pointer passthrough has to survive minification; BigInt.asUintN is
# the marker that only the patched shim emits.
grep -aq 'BigInt.asUintN' "$lib"/*.js || {
  echo "tagged-pointer passthrough missing from the bundle" >&2
  exit 1
}
# Upstream only warns about a malformed section; check the titles landed.
if [ -n "${OPENCODE_RELEASE_NOTES:-}" ]; then
  python3 - "$lib" "$highlights_file" <<'PY'
import re
import sys
from pathlib import Path

lib, notes = Path(sys.argv[1]), Path(sys.argv[2])
titles = re.findall(r"^- \*\*(.+?)\*\*", notes.read_text(encoding="utf-8"), re.M)
if not titles:
    raise SystemExit(f"{notes}: no '- **Title**: ...' bullets to embed")
bundle = "".join(p.read_text(encoding="utf-8", errors="ignore") for p in lib.glob("*.js"))
missing = [title for title in titles if title not in bundle]
if missing:
    raise SystemExit("highlights missing from the bundle: " + ", ".join(missing))
print(f"highlights embedded: {len(titles)}")
PY
fi

out="$ROOT/artifacts/bundle/$OPENCODE_VERSION"
rm -rf "$out"
mkdir -p "$out/lib"
cp -a "$lib/." "$out/lib/"
install -m 0755 "$pty" "$out/lib/librust_pty_arm64.so"
install -m 0644 "$watcher" "$out/lib/watcher.node"
# Empty bunfig: the wrapper points bun at it so a project's bunfig.toml or
# .env in the user's cwd never changes how the CLI starts.
: > "$out/lib/bunfig.toml"
find "$out/lib" -type f -exec chmod 0644 {} +
chmod 0755 "$out/lib/librust_pty_arm64.so"

# Every asset the bundle references by absolute path must exist in the tree;
# a missing one only shows up on device otherwise.
python3 - "$out/lib" "$install_dir" <<'PY'
import re
import sys
from pathlib import Path

lib = Path(sys.argv[1])
install = sys.argv[2].rstrip("/") + "/"
pattern = re.compile(re.escape(install) + r'([A-Za-z0-9._/-]+)')
missing = set()
for js in lib.glob("*.js"):
    for name in pattern.findall(js.read_text(encoding="utf-8", errors="ignore")):
        if not (lib / name).is_file():
            missing.add(name)
if missing:
    raise SystemExit("bundle references missing assets: " + ", ".join(sorted(missing)))
print(f"bundle assets verified ({len(list(lib.glob('*'))) } files)")
PY

python3 - "$OPENCODE_VERSION" "$out" "$work" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

version, out, work = sys.argv[1:4]


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


lib = Path(out) / "lib"
files = sorted(p for p in lib.rglob("*") if p.is_file())
report = {
    "ver": version,
    "pipeline": "runtime-bundle",
    "install_dir": os.environ.get("OPENCODE_INSTALL_DIR"),
    "files": len(files),
    "bytes": sum(p.stat().st_size for p in files),
    "natives": {
        p.name: {"size": p.stat().st_size, "sha256": digest(p)}
        for p in files
        if p.suffix in (".so", ".node")
    },
}
Path(out, "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(f"bundle: {report['files']} files, {report['bytes']} bytes -> {out}")
PY
