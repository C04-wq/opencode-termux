#!/usr/bin/env bash
# Build FFF's official C ABI from its locked Rust source for Android/Bionic.
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: FFF Android build failed at line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 OUTPUT_LIBFF_C_SO" >&2
  exit 64
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
OUT="$1"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
ANDROID_API="${ANDROID_API:-28}"
NDK="${NDK:-}"
HOST_TAG="${ANDROID_NDK_HOST_TAG:-linux-x86_64}"
WORK="$(dirname "$OUT")"
SRC="$WORK/fff-source"

[[ -n "$NDK" && -f "$NDK/build/cmake/android.toolchain.cmake" ]] || { echo "FFF: Android NDK CMake toolchain is required" >&2; exit 1; }
for tool in cargo rustup git readelf file python3 realpath stat cmake; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FFF: missing build tool $tool" >&2; exit 1; }
done

case "$TARGET_ARCH" in
  aarch64)
    target="aarch64-linux-android"
    cargo_env="AARCH64_LINUX_ANDROID"
    linker_prefix="aarch64-linux-android"
    android_abi="arm64-v8a"
    expected_machine="AArch64"
    ;;
  x86_64)
    target="x86_64-linux-android"
    cargo_env="X86_64_LINUX_ANDROID"
    linker_prefix="x86_64-linux-android"
    android_abi="x86_64"
    expected_machine="Advanced Micro Devices X86-64"
    ;;
  *)
    echo "FFF: unsupported architecture '$TARGET_ARCH'" >&2
    exit 2
    ;;
esac

readarray -t pins < <(python3 - "$REPO_ROOT/tools/supply-chain-lock.json" "$target" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
pin = lock.get("fff")
if not isinstance(pin, dict):
    raise SystemExit("FFF source pin is missing from supply-chain-lock.json")
if sys.argv[2] not in pin.get("android_targets", []):
    raise SystemExit("FFF Android target is not allowlisted by the supply-chain lock")
print(pin["commit"])
print(pin["version"])
print(pin["crate"])
PY
)
[[ "${#pins[@]}" -eq 3 ]] || { echo "FFF: incomplete supply-chain pin" >&2; exit 1; }
FFF_COMMIT="${pins[0]}"
FFF_VERSION="${pins[1]}"
FFF_CRATE="${pins[2]}"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/dmtrKovalenko/fff.git "$SRC"
fi
git -C "$SRC" fetch --depth=1 origin "$FFF_COMMIT"
git -C "$SRC" checkout --detach "$FFF_COMMIT"
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$FFF_COMMIT" ]] || { echo "FFF: source commit does not match lock" >&2; exit 1; }

python3 - "$SRC/Cargo.lock" "$SRC/crates/fff-c/Cargo.toml" "$FFF_VERSION" "$FFF_CRATE" <<'PY'
import re, sys, tomllib
lock_path, crate, version, name = sys.argv[1:]
manifest = open(crate, encoding="utf-8").read()
locked = tomllib.load(open(lock_path, "rb"))
if not re.search(rf'^name\s*=\s*"{re.escape(name)}"', manifest, re.M):
    raise SystemExit("FFF C ABI crate name differs from source lock")
if not re.search(rf'^version\s*=\s*"{re.escape(version)}"', manifest, re.M):
    raise SystemExit("FFF C ABI crate version differs from source lock")
if not re.search(rf'package\s*=\s*"fff-search".*?version\s*=\s*"{re.escape(version)}"', manifest, re.S):
    raise SystemExit("FFF search core version differs from source lock")
core = next((item for item in locked["package"] if item["name"] == "fff-search"), None)
if not core or core["version"] != version:
    raise SystemExit("FFF Cargo.lock core version differs from source lock")
PY
[[ -s "$SRC/Cargo.lock" ]] || { echo "FFF: upstream Cargo.lock is missing" >&2; exit 1; }

manifest="$SRC/Cargo.toml"
(
  cd "$SRC"
  # Exercise the official crate tests natively before setting cross-compiler
  # variables; otherwise CMake/cc would try to use the Android linker on host.
  cargo test --locked -p "$FFF_CRATE" --manifest-path "$manifest"
)

toolchain="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
linker="$toolchain/${linker_prefix}${ANDROID_API}-clang"
cxx="$toolchain/${linker_prefix}${ANDROID_API}-clang++"
[[ -x "$linker" && -x "$cxx" ]] || { echo "FFF: NDK clang toolchain is incomplete" >&2; exit 1; }
rustup target list --installed | grep -qx "$target" || rustup target add "$target"

printf -v linker_var 'CARGO_TARGET_%s_LINKER' "$cargo_env"
printf -v rustflags_var 'CARGO_TARGET_%s_RUSTFLAGS' "$cargo_env"
export "$linker_var=$linker"
export "$rustflags_var=-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"
export CC="$linker"
export CXX="$cxx"
export AR="$toolchain/llvm-ar"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"
export CMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
export CMAKE_ANDROID_NDK="$NDK"
export CMAKE_ANDROID_ARCH_ABI="$android_abi"
export CMAKE_SYSTEM_VERSION="$ANDROID_API"
export ANDROID_ABI="$android_abi"
export ANDROID_PLATFORM="android-$ANDROID_API"
export CMAKE_BUILD_TYPE=Release
export PKG_CONFIG_ALLOW_CROSS=1

(
  cd "$SRC"
  cargo build --locked --release -p "$FFF_CRATE" --target "$target" --manifest-path "$manifest"
  cargo test --locked --no-run -p "$FFF_CRATE" --target "$target" --manifest-path "$SRC/Cargo.toml"
)

built="$SRC/target/$target/release/libfff_c.so"
[[ -s "$built" ]] || { echo "FFF: Cargo did not produce $built" >&2; exit 1; }
header="$(readelf -h "$built")"
grep -Fq "Class: ELF64" <<<"$header" || { echo "FFF: library is not a 64-bit ELF" >&2; exit 1; }
grep -q "Type:.*DYN" <<<"$header" || { echo "FFF: C ABI output is not a shared library" >&2; exit 1; }
grep -Fq "$expected_machine" <<<"$header" || { echo "FFF: wrong ELF architecture for $TARGET_ARCH" >&2; exit 1; }
alignments="$(readelf -lW "$built" | awk '$1 == "LOAD" { print $NF }')"
[[ -n "$alignments" ]] || { echo "FFF: no PT_LOAD segments found" >&2; exit 1; }
while IFS= read -r alignment; do
  alignment="${alignment#0x}"
  if (( 16#$alignment < 16384 )); then
    echo "FFF: Android 16 KB page alignment missing (PT_LOAD alignment 0x$alignment)" >&2
    exit 1
  fi
done <<<"$alignments"
needed="$(readelf -d "$built" | awk '/NEEDED/{print $NF}')"
if grep -Eq 'libc\.so\.6|ld-linux|libgcc_s\.so' <<<"$needed"; then
  echo "FFF: non-Android runtime dependency detected: $needed" >&2
  exit 1
fi

install -D -m 0644 "$built" "$OUT"
echo "FFF: built official C ABI from dmtrKovalenko/fff $FFF_VERSION ($FFF_COMMIT)"
echo "FFF: Android target $target; PT_LOAD alignment verified at 16 KB"
echo "FFF: $OUT ($(stat -c%s "$OUT") bytes)"
