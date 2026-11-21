#!/usr/bin/env bash
# Build bun-pty's rust-pty shared library for Android/Bionic.
#
# TARGET_ARCH selects a Termux architecture. Supported cross targets here:
#   aarch64 -> aarch64-linux-android
#   x86_64  -> x86_64-linux-android
#
# This helper's x86_64 support is only one native dependency milestone; it
# does not make the complete OpenCode bundle or installer x86_64-compatible.
#
# Usage: TARGET_ARCH=aarch64|x86_64 build-rust-pty-android.sh OUTPUT_SO [SOURCE_DIR]
#
# Env:
#   TARGET_ARCH   Android CPU architecture (default: aarch64)
#   BUN_PTY_REF   git ref to build (default from tools/ocver.py)
#   BUN_PTY_SRC   checkout directory (default work/bun-pty)
#   ANDROID_API   API level for the cross linker (default 28)
#   NDK           Android NDK root; required for cross builds
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT="${1:?usage: build-rust-pty-android.sh OUTPUT_SO [SOURCE_DIR]}"
SRC="${2:-${BUN_PTY_SRC:-work/bun-pty}}"
REF="${BUN_PTY_REF:-$(python3 tools/ocver.py bunpty ref)}"
ANDROID_API="${ANDROID_API:-28}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"

case "$TARGET_ARCH" in
  aarch64)
    target="aarch64-linux-android"
    linker_prefix="aarch64-linux-android"
    rust_env="AARCH64_LINUX_ANDROID"
    cc_env="aarch64_linux_android"
    expected_elf='AArch64'
    ;;
  x86_64)
    target="x86_64-linux-android"
    linker_prefix="x86_64-linux-android"
    rust_env="X86_64_LINUX_ANDROID"
    cc_env="x86_64_linux_android"
    expected_elf='Advanced Micro Devices X86-64'
    ;;
  *)
    echo "bun-pty: unsupported TARGET_ARCH '$TARGET_ARCH' (supported by this helper: aarch64, x86_64)" >&2
    exit 2
    ;;
esac

for tool in cargo git readelf file python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing command: $tool" >&2; exit 1; }
done

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q .
  git -C "$SRC" remote add origin https://github.com/sursatech/bun-pty.git
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
# Android os module, so the build dies on cfg(target_os = "android").
manifest="$SRC/rust-pty/Cargo.toml"
portable_pty_version="$(python3 tools/ocver.py bunpty portable_pty)"
[ "$portable_pty_version" = "0.9.0" ] || {
  echo "bun-pty: unsupported locked portable-pty version '$portable_pty_version'" >&2
  exit 1
}
if grep -q 'portable-pty = { version = "0.8.1"' "$manifest"; then
  sed -i 's/portable-pty = { version = "0.8.1"/portable-pty = { version = "=0.9.0"/' "$manifest"
fi
grep -q 'portable-pty = { version = "=0.9.0"' "$manifest" || {
  echo "bun-pty: portable-pty pin changed upstream; update this script" >&2
  exit 1
}

# portable-pty 0.9 replaces serial/termios with serial2, which supports
# Android. Update only this dependency to the exact lockfile version, then
# require Cargo.lock to remain fixed for the actual build. Do this for native
# Termux builds as well as NDK cross-builds.
cargo update --manifest-path "$SRC/rust-pty/Cargo.toml" -p portable-pty --precise "$portable_pty_version"

if [ -n "${NDK:-}" ]; then
  command -v rustup >/dev/null 2>&1 || { echo "missing command: rustup (required for Android cross-compilation)" >&2; exit 1; }
  [[ "$ANDROID_API" =~ ^[0-9]+$ ]] || { echo "bun-pty: ANDROID_API must be a numeric API level" >&2; exit 1; }
  host_tag="${ANDROID_NDK_HOST_TAG:-linux-x86_64}"
  toolchain="$NDK/toolchains/llvm/prebuilt/$host_tag/bin"
  linker="$toolchain/${linker_prefix}${ANDROID_API}-clang"
  test -x "$linker" || { echo "bun-pty: missing NDK linker $linker" >&2; exit 1; }
  rustup target list --installed | grep -qx "$target" || rustup target add "$target"
  printf -v cargo_linker_var 'CARGO_TARGET_%s_LINKER' "$rust_env"
  printf -v cargo_rustflags_var 'CARGO_TARGET_%s_RUSTFLAGS' "$rust_env"
  export "$cargo_rustflags_var=-C link-arg=-Wl,-z,max-page-size=16384"
  printf -v cc_var 'CC_%s' "$cc_env"
  printf -v ar_var 'AR_%s' "$cc_env"
  export "$cargo_linker_var=$linker"
  export "$cc_var=$linker"
  test -x "$toolchain/llvm-ar" || { echo "bun-pty: missing NDK archiver $toolchain/llvm-ar" >&2; exit 1; }
  export "$ar_var=$toolchain/llvm-ar"
  echo "bun-pty: cross building for $target with $linker"
elif [ "$TARGET_ARCH" = aarch64 ] && [ "$(uname -m)" = aarch64 ]; then
  echo "bun-pty: native bionic build (no NDK)"
  target=""
else
  echo "bun-pty: NDK is required to build $TARGET_ARCH outside its native Termux environment" >&2
  exit 1
fi

build_args=(build --locked --release --manifest-path "$SRC/rust-pty/Cargo.toml")
[ -n "$target" ] && build_args+=(--target "$target")
cargo "${build_args[@]}"

if [ -n "$target" ]; then
  built="$SRC/rust-pty/target/$target/release/librust_pty.so"
else
  built="$SRC/rust-pty/target/release/librust_pty.so"
fi
test -f "$built" || { echo "bun-pty: build produced no $built" >&2; exit 1; }

machine="$(readelf -h "$built" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')"
[ "$machine" = "$expected_elf" ] || {
  echo "bun-pty: expected ELF machine '$expected_elf' for $TARGET_ARCH, got '${machine:-unknown}'" >&2
  exit 1
}
alignments="$(readelf -lW "$built" | awk '$1 == "LOAD" { print $NF }')"
[[ -n "$alignments" ]] || { echo "bun-pty: no PT_LOAD segments found" >&2; exit 1; }
while IFS= read -r alignment; do
  alignment="${alignment#0x}"
  if (( 16#$alignment < 16384 )); then
    echo "bun-pty: Android 16 KB page alignment missing (PT_LOAD alignment 0x$alignment)" >&2
    exit 1
  fi
done <<<"$alignments"
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
