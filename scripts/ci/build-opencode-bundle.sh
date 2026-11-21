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
#   lib/opencode/librust_pty_<architecture>.so       bionic bun-pty (cargo)
#   lib/opencode/libfff_c-*.so               Bionic FFF C ABI (cargo, both arches)
#   lib/opencode/opencode-pty                official OpenCode PTY daemon (cargo + Ghostty)
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

TARGET_ARCH="${TARGET_ARCH:-aarch64}"
case "$TARGET_ARCH" in
  aarch64)
    OPENCODE_ARCH="arm64"
    PTY_LIB_NAME="librust_pty_arm64.so"
    EXPECTED_TUI_MACHINE="ARM aarch64"
    TUI_ARTIFACT="$ROOT/artifacts/transplant/opentui-bionic/libopentui.so"
    TUI_SLOT="core-linux-arm64-musl"
    ;;
  x86_64)
    OPENCODE_ARCH="x64"
    PTY_LIB_NAME="librust_pty_x86_64.so"
    EXPECTED_TUI_MACHINE="x86-64"
    TUI_ARTIFACT="$ROOT/artifacts/transplant/opentui-bionic-x86_64/libopentui.so"
    TUI_SLOT="core-linux-x64-musl"
    ;;
  *)
    echo "unsupported TARGET_ARCH '$TARGET_ARCH' (supported: aarch64, x86_64)" >&2
    exit 2
    ;;
esac

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

if [ "$TARGET_ARCH" = aarch64 ]; then
  work="$ROOT/work/bundle/$OPENCODE_VERSION"
  out="$ROOT/artifacts/bundle/$OPENCODE_VERSION"
else
  work="$ROOT/work/bundle/$OPENCODE_VERSION-$TARGET_ARCH"
  out="$ROOT/artifacts/bundle/$OPENCODE_VERSION-$TARGET_ARCH"
fi
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

# Bun lifecycle scripts invoke `bun` from PATH even when the initial install
# was started via an absolute executable path. Expose the hash-verified host
# binary to every subprocess in this build step.
export PATH="$work/host/bun-linux-x64:$PATH"

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
  "$(python3 tools/ocver.py bunpty ref)" "$(python3 -c 'import json; print(json.load(open("tools/supply-chain-lock.json"))["fff"]["version"])')" <<'PY'
import json
import re
import sys
from pathlib import Path

root, opentui, bunpty, fff = Path(sys.argv[1]), sys.argv[2], sys.argv[3].lstrip("v"), sys.argv[4]


def pin(path: Path, name: str) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.search(r'"' + re.escape(name) + r'":\s*"([^"]+)"', text)
    if match is None:
        raise SystemExit(f"{path.name}: no pin for {name}")
    return match.group(1)


sys.path.insert(0, str(Path.cwd() / "tools"))
from bun_lock import load_bun_lock

bun_lock = load_bun_lock(root / "bun.lock")
found = {
    "opentui": pin(root / "package.json", "@opentui/core"),
    "bun-pty": pin(root / "packages/core/package.json", "bun-pty"),
    "fff": bun_lock["workspaces"]["packages/core"]["dependencies"]["@ff-labs/fff-bun"],
}
expected = {"opentui": opentui, "bun-pty": bunpty, "fff": fff}
drift = {name: (found[name], expected[name]) for name in found if found[name] != expected[name]}
if drift:
    raise SystemExit(
        "upstream pins moved; update tools/supply-chain-lock.json and the natives: "
        + ", ".join(f"{k} {a} != {b}" for k, (a, b) in drift.items())
    )
print(f"pins: opentui {opentui}, bun-pty {bunpty}")
PY
OPENCODE_BUN_VERSION="$BUN_VERSION" python3 tools/patch-opencode-source.py "$src"
python3 tools/patch-opencode-bundle.py --target-arch "$TARGET_ARCH" "$src"

cd "$src"
"$host_bun" install \
  --ignore-scripts \
  --filter 'opencode' --filter '@opencode/cli' --filter '@opencode/app' \
  --os='*' --cpu='*' --libc='*'

# The TUI shim must hand Bionic's tagged pointers to the FFI unchanged, and
# OpenTUI's asset loader must accept process.platform "android". Both patch the
# installed @opentui/core chunks, so they run before Bun bundles them.
python3 "$ROOT/tools/patch-opentui-ffi.py" "$src"
python3 "$ROOT/tools/patch-opentui-loader.py" "$src"
# Build FFF's official C ABI from its pinned Rust source for this exact
# Android target. Replace the npm binary package's native file with our build;
# x86_64 gets a local platform package using the same official source version.
fff_lib="$work/libfff_c.so"
TARGET_ARCH="$TARGET_ARCH" NDK="${NDK:-}" ANDROID_API="$api" \
  bash "$ROOT/scripts/ci/build-fff-android.sh" "$fff_lib"
FFF_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["fff"]["version"])' "$ROOT/tools/supply-chain-lock.json")"
fff_package="$src/node_modules/@ff-labs/fff-bin-android-$OPENCODE_ARCH"
mkdir -p "$fff_package"
printf '{"name":"@ff-labs/fff-bin-android-%s","version":"%s","license":"MIT","os":["android"],"cpu":["%s"],"files":["libfff_c.so"]}\n' \
  "$OPENCODE_ARCH" "$FFF_VERSION" "$OPENCODE_ARCH" > "$fff_package/package.json"
install -m 0644 "$fff_lib" "$fff_package/libfff_c.so"
file "$fff_package/libfff_c.so" | grep -q "$EXPECTED_TUI_MACHINE" || {
  echo "FFF C ABI has the wrong architecture for $TARGET_ARCH" >&2
  exit 1
}
python3 "$ROOT/tools/patch-fff-android.py" --target-arch "$TARGET_ARCH" "$src"

# Typecheck the patched CLI so updater/launcher integration errors fail CI
# before the JavaScript bundle is emitted.
"$host_bun" run --filter '@opencode/cli' typecheck

# ---- natives ---------------------------------------------------------------
tui="$TUI_ARTIFACT"
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
file "$tui_ship" | grep -q "$EXPECTED_TUI_MACHINE" || {
  echo "stripped libopentui has the wrong architecture for $TARGET_ARCH" >&2
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
printf '%s\n' "${tui_slots[@]}" | grep -q "$TUI_SLOT" || {
  echo "the bionic slot (@opentui/$TUI_SLOT) is missing from: ${tui_slots[*]}" >&2
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

echo "fff: source-built Android C ABI installed for $TARGET_ARCH"

pty="$work/librust_pty_$TARGET_ARCH.so"
TARGET_ARCH="$TARGET_ARCH" NDK="${NDK:-}" ANDROID_API="$api" \
  bash "$ROOT/scripts/ci/build-rust-pty-android.sh" "$pty"

# Build the official OpenCode persistent PTY daemon (not bun-pty's shared
# library). It is packaged beside the bundle and selected through the upstream
# OPENCODE_PTY_BIN override supported by core's persistent-pty runtime.
pty_daemon="$work/opencode-pty"
TARGET_ARCH="$TARGET_ARCH" NDK="${NDK:-}" ANDROID_API="$api" \
  bash "$ROOT/scripts/ci/build-opencode-pty-android.sh" "$src" "$pty_daemon"

watcher="$work/watcher.node"
TARGET_ARCH="$TARGET_ARCH" NDK="${NDK:-}" ANDROID_API="$api" \
  bash "$ROOT/scripts/ci/build-parcel-watcher-android.sh" "$src" "$watcher"

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
OPENCODE_TARGET=linux-$OPENCODE_ARCH-android \
OPENCODE_INSTALL_DIR="$install_dir" \
  "$host_bun" run script/build.ts --skip-install
cd "$ROOT"

lib="$src/packages/cli/dist/cli-linux-$OPENCODE_ARCH-android/lib"
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

rm -rf "$out"
mkdir -p "$out/lib"
cp -a "$lib/." "$out/lib/"
install -m 0755 "$pty" "$out/lib/$PTY_LIB_NAME"
install -m 0755 "$pty_daemon" "$out/lib/opencode-pty"
printf '%s\n' "$commit" > "$out/lib/opencode-pty.required"
install -m 0644 "$watcher" "$out/lib/watcher.node"
# Empty bunfig: the wrapper points bun at it so a project's bunfig.toml or
# .env in the user's cwd never changes how the CLI starts.
: > "$out/lib/bunfig.toml"
find "$out/lib" -type f -exec chmod 0644 {} +
chmod 0755 "$out/lib/$PTY_LIB_NAME" "$out/lib/opencode-pty"

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
