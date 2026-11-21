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

for tool in cargo rustup zig readelf python3 realpath stat; do
  command -v "$tool" >/dev/null 2>&1 || { echo "opencode-pty: missing build tool $tool" >&2; exit 1; }
done

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

toolchain="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
linker="$toolchain/${linker_prefix}${ANDROID_API}-clang"
[[ -x "$linker" ]] || { echo "opencode-pty: missing NDK linker $linker" >&2; exit 1; }
rustup target list --installed | grep -qx "$target" || rustup target add "$target"

printf -v linker_var 'CARGO_TARGET_%s_LINKER' "$cargo_env"
export "$linker_var=$linker"
export CC="$linker"
export CXX="$toolchain/${linker_prefix}${ANDROID_API}-clang++"
export AR="$toolchain/llvm-ar"
export CARGO_BUILD_TARGET="$target"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"

manifest="$SRC_ROOT/packages/process-daemon/Cargo.toml"
(
  cd "$SRC_ROOT/packages/process-daemon"
  # Run the upstream daemon's complete native test suite on the Linux CI host
  # before cross-compiling. Then compile the Android-target test harnesses too.
  cargo test --locked --manifest-path "$manifest"
  cargo build --locked --release --target "$target" --manifest-path "$manifest"
  cargo test --locked --no-run --target "$target" --manifest-path "$manifest"
)

built="$SRC_ROOT/packages/process-daemon/target/$target/release/opencode-pty"
[[ -s "$built" ]] || { echo "opencode-pty: Cargo did not produce $built" >&2; exit 1; }
header="$(readelf -h "$built")"
grep -Fq "$expected_machine" <<<"$header" || { echo "opencode-pty: wrong ELF architecture for $TARGET_ARCH" >&2; exit 1; }
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
