#!/usr/bin/env bash
# Build bun-pty's rust-pty shared library for Android/Bionic.
#
# opencode's `#pty` backend imports bun-pty, which dlopens
# `librust_pty_arm64.so` at module load. The npm tarball only ships glibc and
# musl builds, so a Termux bundle needs its own bionic copy.
#
# Two build modes:
#   * NDK cross build (CI):        set NDK, builds aarch64-linux-android
#   * native Termux build:         run on aarch64 without NDK, builds for the
#                                 host (bionic) target
#
# Usage: build-rust-pty-android.sh OUTPUT_SO [SOURCE_DIR]
#
# Env:
#   BUN_PTY_REF   git ref to build (default from tools/ocver.py, lock key
#                 bun_pty.ref) -- a tag or commit
#   BUN_PTY_SRC   checkout directory (default work/bun-pty)
#   ANDROID_API   API level for the cross linker (default 28)
#   NDK           Android NDK root; required off-device
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${1:?usage: build-rust-pty-android.sh OUTPUT_SO [SOURCE_DIR]}"
SRC="${2:-${BUN_PTY_SRC:-work/bun-pty}}"
REF="${BUN_PTY_REF:-$(python3 tools/ocver.py bunpty ref)}"
ANDROID_API="${ANDROID_API:-28}"

for tool in cargo git readelf; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing command: $tool" >&2; exit 1; }
done

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q .
  git -C "$SRC" remote add origin https://github.com/sursaone/bun-pty.git
fi
git -C "$SRC" fetch -q --depth=1 origin "$REF"
git -C "$SRC" checkout -q --detach FETCH_HEAD
ACTUAL_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
EXPECTED_COMMIT="$(python3 tools/ocver.py bunpty commit)"
[ "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT" ] || {
  echo "bun-pty: fetched commit $ACTUAL_COMMIT does not match locked commit $EXPECTED_COMMIT" >&2
  exit 1
}
echo "bun-pty: $ACTUAL_COMMIT ($REF; lock verified)"

# portable-pty 0.8.1 -> serial -> termios 0.2.2, whose crates.io release has no
# Android os module, so the build dies on `cfg(target_os = "android")`.
# portable-pty 0.9 carries the Android support upstream.
manifest="$SRC/rust-pty/Cargo.toml"
if grep -q 'portable-pty = { version = "0.8.1"' "$manifest"; then
  sed -i 's/portable-pty = { version = "0.8.1"/portable-pty = { version = "0.9"/' "$manifest"
fi
grep -q 'portable-pty = { version = "0.9"' "$manifest" || {
  echo "bun-pty: portable-pty pin changed upstream; update this script" >&2
  exit 1
}

target=""
if [ -n "${NDK:-}" ]; then
  host_tag="linux-x86_64"
  toolchain="$NDK/toolchains/llvm/prebuilt/$host_tag/bin"
  linker="$toolchain/aarch64-linux-android$ANDROID_API-clang"
  test -x "$linker" || { echo "bun-pty: missing NDK linker $linker" >&2; exit 1; }
  target="aarch64-linux-android"
  rustup target list --installed | grep -qx "$target" || rustup target add "$target"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker"
  export CC_aarch64_linux_android="$linker"
  export AR_aarch64_linux_android="$toolchain/llvm-ar"
  echo "bun-pty: cross building for $target with $linker"
elif [ "$(uname -m)" = "aarch64" ]; then
  echo "bun-pty: native bionic build (no NDK)"
else
  echo "bun-pty: NDK is required when not building on an aarch64 host" >&2
  exit 1
fi

build_args=(build --release --manifest-path "$SRC/rust-pty/Cargo.toml")
[ -n "$target" ] && build_args+=(--target "$target")
cargo "${build_args[@]}"

if [ -n "$target" ]; then
  built="$SRC/rust-pty/target/$target/release/librust_pty.so"
else
  built="$SRC/rust-pty/target/release/librust_pty.so"
fi
test -f "$built" || { echo "bun-pty: build produced no $built" >&2; exit 1; }

# Gates: bionic only. A glibc soname means the wrong libc was linked and the
# library will fail to dlopen on device; zero bun_pty_* exports means the FFI
# surface the JS expects is gone.
file "$built" | grep -q 'ARM aarch64' || { echo "bun-pty: not an aarch64 object: $(file -b "$built")" >&2; exit 1; }
needed="$(readelf -d "$built" | awk '/NEEDED/{print $NF}')"
if printf '%s\n' "$needed" | grep -Eq 'lib(c|m|dl|pthread|rt)\.so\.[0-9]'; then
  echo "bun-pty: glibc-linked NEEDED found: $needed" >&2
  exit 1
fi
exports="$(readelf --dyn-syms "$built" | grep -c ' bun_pty_' || true)"
[ "$exports" -ge 8 ] || { echo "bun-pty: expected 8 bun_pty_* exports, found $exports" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
install -m 0755 "$built" "$OUT"
echo "bun-pty: $OUT ($(stat -c%s "$OUT") bytes)"
echo "bun-pty: NEEDED $(printf '%s ' $needed)"
