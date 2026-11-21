#!/usr/bin/env bash
# Build the official OpenCode process daemon (opencode-pty) for Android/Bionic.
# The daemon source and its Cargo.lock come from the exact OpenCode commit
# already checked out by build-opencode-bundle.sh.
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: opencode-pty build failed at line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 OPENCODE_SOURCE_ROOT OUTPUT_BINARY" >&2
  exit 64
fi
SRC_ROOT="$(realpath "$1")"
OUT="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
ANDROID_API="${ANDROID_API:-28}"
NDK="${NDK:-}"
HOST_TAG="${ANDROID_NDK_HOST_TAG:-linux-x86_64}"

[[ -d "$SRC_ROOT/.git" ]] || { echo "opencode-pty: source must be the pinned OpenCode git checkout" >&2; exit 1; }
[[ -f "$SRC_ROOT/packages/process-daemon/Cargo.toml" ]] || { echo "opencode-pty: official process-daemon source is missing" >&2; exit 1; }
[[ -f "$SRC_ROOT/packages/process-daemon/Cargo.lock" ]] || { echo "opencode-pty: official Cargo.lock is missing" >&2; exit 1; }
[[ -n "$NDK" && -d "$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin" ]] || { echo "opencode-pty: Android NDK is required" >&2; exit 1; }
[[ "$ANDROID_API" =~ ^[0-9]+$ ]] || { echo "opencode-pty: ANDROID_API must be numeric" >&2; exit 1; }

case "$TARGET_ARCH" in
  aarch64)
    target="aarch64-linux-android"
    cargo_env="AARCH64_LINUX_ANDROID"
    linker_prefix="aarch64-linux-android"
    expected_machine="AArch64"
    expected_interpreter="/system/bin/linker64"
    ;;
  x86_64)
    target="x86_64-linux-android"
    cargo_env="X86_64_LINUX_ANDROID"
    linker_prefix="x86_64-linux-android"
    expected_machine="Advanced Micro Devices X86-64"
    expected_interpreter="/system/bin/linker64"
    ;;
  *)
    echo "opencode-pty: unsupported architecture '$TARGET_ARCH'" >&2
    exit 2
    ;;
esac

for tool in cargo rustup readelf python3 realpath stat curl sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || { echo "opencode-pty: missing build tool $tool" >&2; exit 1; }
done

# Ghostty has its own Zig requirement, independent of OpenTUI's Zig version.
# Install the exact hash-locked compiler in an isolated directory and use it
# only while Cargo runs the process-daemon build script.
mapfile -t zig_pin < <(python3 - "$REPO_ROOT/tools/supply-chain-lock.json" <<'PY'
import json, sys
pin = json.load(open(sys.argv[1], encoding="utf-8"))["process_daemon"]
print(pin["zig_version"])
print(pin["zig_x86_64_linux_sha256"])
PY
)
test "${#zig_pin[@]}" -eq 2
ZIG_VERSION="${zig_pin[0]}"
ZIG_SHA256="${zig_pin[1]}"
ZIG_ROOT="$REPO_ROOT/work/zig-process-daemon-$ZIG_VERSION"
if [[ ! -x "$ZIG_ROOT/zig" ]]; then
  mkdir -p "$REPO_ROOT/work"
  archive="$REPO_ROOT/work/zig-process-daemon-$ZIG_VERSION.tar.xz"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" -o "$archive"
  echo "$ZIG_SHA256  $archive" | sha256sum -c -
  temp="$REPO_ROOT/work/zig-process-daemon-extract"
  rm -rf "$temp"
  mkdir -p "$temp"
  tar -xJf "$archive" -C "$temp"
  mv "$temp/zig-x86_64-linux-$ZIG_VERSION" "$ZIG_ROOT"
  rmdir "$temp"
fi
export PATH="$ZIG_ROOT:$PATH"
test "$(zig version)" = "$ZIG_VERSION"

# Upstream build.rs supports Linux GNU/musl and Apple/Windows targets, but
# omits Android triples. Extend only its target translation; the Ghostty
# revision, FFI bindings, Rust implementation and Cargo.lock remain upstream.
python3 - "$SRC_ROOT/packages/process-daemon/build.rs" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
anchor = '            "aarch64-unknown-linux-musl" => "aarch64-linux-musl",\n'
addition = (
    anchor
    + '            "aarch64-linux-android" => "aarch64-linux-android",\n'
    + '            "x86_64-linux-android" => "x86_64-linux-android",\n'
)
if text.count(anchor) == 1:
    path.write_text(text.replace(anchor, addition, 1), encoding="utf-8")
elif text.count('"aarch64-linux-android"') == 1 and text.count('"x86_64-linux-android"') == 1:
    pass
else:
    raise SystemExit("opencode-pty: upstream build.rs target map changed; refusing an unreviewed patch")
PY

python3 - "$REPO_ROOT/tools/supply-chain-lock.json" "$SRC_ROOT/packages/process-daemon/Cargo.toml" "$SRC_ROOT/packages/process-daemon/ghostty-revision" "$target" "$(zig version)" <<'PY'
import json, re, sys
lock_path, manifest_path, ghostty_path, target, zig_version = sys.argv[1:]
lock = json.load(open(lock_path, encoding="utf-8"))
pin = lock.get("process_daemon")
if not isinstance(pin, dict):
    raise SystemExit("opencode-pty: process_daemon is missing from supply-chain-lock.json")
manifest = open(manifest_path, encoding="utf-8").read()
name = re.search(r'^name\s*=\s*"([^"]+)"', manifest, re.M)
version = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.M)
if not name or name.group(1) != pin.get("package"):
    raise SystemExit("opencode-pty: official Cargo package name differs from the supply-chain lock")
if not version or version.group(1) != pin.get("version"):
    raise SystemExit("opencode-pty: official daemon version differs from the supply-chain lock")
ghostty = open(ghostty_path, encoding="utf-8").read().strip()
if ghostty != pin.get("ghostty_commit"):
    raise SystemExit(f"opencode-pty: Ghostty revision {ghostty} differs from locked {pin.get('ghostty_commit')}")
if target not in pin.get("android_targets", []):
    raise SystemExit(f"opencode-pty: Android target {target} is not allowlisted in the supply-chain lock")
if zig_version != pin.get("zig_version"):
    raise SystemExit(f"opencode-pty: Zig {zig_version} differs from locked {pin.get('zig_version')}")
PY

toolchain="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
linker="$toolchain/${linker_prefix}${ANDROID_API}-clang"
[[ -x "$linker" ]] || { echo "opencode-pty: missing NDK linker $linker" >&2; exit 1; }
# Install the target under the upstream process-daemon toolchain override.
# Its rust-toolchain.toml may differ from the repository builder toolchain.

printf -v linker_var 'CARGO_TARGET_%s_LINKER' "$cargo_env"
printf -v rustflags_var 'CARGO_TARGET_%s_RUSTFLAGS' "$cargo_env"
export "$rustflags_var=-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"
export "$linker_var=$linker"
export CC="$linker"
export CXX="$toolchain/${linker_prefix}${ANDROID_API}-clang++"
export AR="$toolchain/llvm-ar"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"

manifest="$SRC_ROOT/packages/process-daemon/Cargo.toml"
(
  cd "$SRC_ROOT/packages/process-daemon"
  rustup target list --installed | grep -qx "$target" || rustup target add "$target"
  # Run the upstream daemon's complete native test suite once on the Linux CI
  # host (the x86_64 build job); both Android targets still compile test harnesses.
  if [[ "${RUN_UPSTREAM_NATIVE_TESTS:-1}" == "1" ]]; then
    env -u CC -u CXX -u AR -u CARGO_BUILD_TARGET -u CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER -u CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER -u CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS -u CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS cargo test --locked --manifest-path "$manifest"
  fi
  cargo build --locked --release --target "$target" --manifest-path "$manifest"
  cargo test --locked --no-run --target "$target" --manifest-path "$manifest"
)

built="$SRC_ROOT/packages/process-daemon/target/$target/release/opencode-pty"
[[ -s "$built" ]] || { echo "opencode-pty: Cargo did not produce $built" >&2; exit 1; }
header="$(readelf -h "$built")"
grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" || { echo "opencode-pty: daemon is not a 64-bit ELF" >&2; exit 1; }
grep -q "Type:.*DYN" <<<"$header" || { echo "opencode-pty: daemon is not a position-independent executable" >&2; exit 1; }
grep -Fq "$expected_machine" <<<"$header" || { echo "opencode-pty: wrong ELF architecture for $TARGET_ARCH" >&2; exit 1; }
alignments="$(readelf -lW "$built" | awk '$1 == "LOAD" { print $NF }')"
[[ -n "$alignments" ]] || { echo "opencode-pty: no PT_LOAD segments found" >&2; exit 1; }
while IFS= read -r alignment; do
  alignment="${alignment#0x}"
  if (( 16#$alignment < 16384 )); then
    echo "opencode-pty: Android 16 KB page alignment missing (PT_LOAD alignment 0x$alignment)" >&2
    exit 1
  fi
done <<<"$alignments"
interpreter="$(readelf -l "$built" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
[[ "$interpreter" == "$expected_interpreter" ]] || {
  echo "opencode-pty: expected Android interpreter $expected_interpreter, got ${interpreter:-none}" >&2
  exit 1
}
needed="$(readelf -d "$built" | awk '/NEEDED/{print $NF}')"
if grep -Eq 'libc\.so\.6|ld-linux|libgcc_s\.so' <<<"$needed"; then
  echo "opencode-pty: non-Android runtime dependency detected: $needed" >&2
  exit 1
fi

install -D -m 0755 "$built" "$OUT"
test -x "$OUT"
echo "opencode-pty: built official daemon for $target"
echo "opencode-pty: $OUT ($(stat -c%s "$OUT") bytes)"
echo "opencode-pty: interpreter $interpreter"
echo "opencode-pty: NEEDED ${needed:-none}"
