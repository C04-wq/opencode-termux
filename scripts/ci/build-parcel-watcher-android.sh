#!/usr/bin/env bash
# Cross-compile @parcel/watcher's N-API module for Android/Bionic.
# This build-only helper produces the Bionic N-API module for both supported Android targets.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SRC_ROOT="${1:?usage: build-parcel-watcher-android.sh OPENCODE_SOURCE_ROOT OUTPUT_NODE}"
OUT="${2:?usage: build-parcel-watcher-android.sh OPENCODE_SOURCE_ROOT OUTPUT_NODE}"
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
ANDROID_API="${ANDROID_API:-28}"
NDK="${NDK:-}"

[[ -d "$SRC_ROOT/node_modules/.bun" ]] || {
  echo "watcher: OpenCode Bun dependencies not found under $SRC_ROOT/node_modules/.bun" >&2
  exit 1
}
[[ -n "$NDK" && -d "$NDK/toolchains/llvm/prebuilt" ]] || {
  echo "watcher: NDK is required for Android cross-compilation" >&2
  exit 1
}
[[ "$ANDROID_API" =~ ^[0-9]+$ ]] || {
  echo "watcher: ANDROID_API must be numeric" >&2
  exit 1
}

case "$TARGET_ARCH" in
  x86_64)
    triple="x86_64-linux-android"
    expected_machine="Advanced Micro Devices X86-64"
    ;;
  aarch64)
    triple="aarch64-linux-android"
    expected_machine="AArch64"
    ;;
  *)
    echo "watcher: unsupported TARGET_ARCH '$TARGET_ARCH' (supported: aarch64, x86_64)" >&2
    exit 2
    ;;
esac

host_tag="${ANDROID_NDK_HOST_TAG:-linux-x86_64}"
toolchain="$NDK/toolchains/llvm/prebuilt/$host_tag/bin"
sysroot="$NDK/toolchains/llvm/prebuilt/$host_tag/sysroot"
cxx="$toolchain/${triple}${ANDROID_API}-clang++"
[[ -x "$cxx" ]] || { echo "watcher: missing NDK C++ compiler $cxx" >&2; exit 1; }

for cmd in find readelf install realpath; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "watcher: missing command $cmd" >&2; exit 1; }
done

mapfile -t watcher_manifests < <(find "$SRC_ROOT/node_modules/.bun" -path '*/@parcel/watcher/package.json' -type f -print)
[[ "${#watcher_manifests[@]}" -eq 1 ]] || {
  echo "watcher: expected exactly one @parcel/watcher source package, found ${#watcher_manifests[@]}" >&2
  printf '%s\n' "${watcher_manifests[@]}" >&2
  exit 1
}
watcher_dir="$(dirname "${watcher_manifests[0]}")"
addon_dir="$watcher_dir/node_modules/node-addon-api"
if [[ ! -f "$addon_dir/napi.h" ]]; then
  addon_header="$(find -L "$SRC_ROOT/node_modules/.bun" -type f -path '*/node-addon-api/napi.h' -print -quit)"
  [[ -n "$addon_header" ]] || {
    echo "watcher: node-addon-api headers were not found in the installed Bun dependency tree" >&2
    exit 1
  }
  addon_dir="$(dirname "$addon_header")"
fi

node_include="${NODE_INCLUDE_DIR:-/usr/include/node}"
[[ -f "$node_include/node_api.h" ]] || {
  echo "watcher: Node-API headers missing at $node_include (install libnode-dev or set NODE_INCLUDE_DIR)" >&2
  exit 1
}

sources=(
  src/binding.cc
  src/Watcher.cc
  src/Backend.cc
  src/DirTree.cc
  src/Glob.cc
  src/Debounce.cc
  src/watchman/BSER.cc
  src/watchman/WatchmanBackend.cc
  src/shared/BruteForceBackend.cc
  src/linux/InotifyBackend.cc
  src/unix/legacy.cc
)
for source in "${sources[@]}"; do
  [[ -f "$watcher_dir/$source" ]] || {
    echo "watcher: required upstream source missing: $source" >&2
    exit 1
  }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
objects=()
for source in "${sources[@]}"; do
  object="$tmp/${source//\//_}.o"
  "$cxx" --sysroot="$sysroot" -std=c++17 -O2 -fPIC \
    -DNAPI_VERSION=4 -DNAPI_DISABLE_CPP_EXCEPTIONS \
    -DNODE_GYP_MODULE_NAME=watcher -fvisibility=default \
    -DWATCHMAN -DINOTIFY -DBRUTE_FORCE \
    -I"$node_include" -I"$addon_dir" -I"$watcher_dir/src" \
    -c "$watcher_dir/$source" -o "$object"
  objects+=("$object")
done

mkdir -p "$(dirname "$OUT")"
# node-gyp builds this addon with default symbol visibility. Make that
# explicit for the standalone NDK build so NODE_API_MODULE's registration
# entry point is exported from the shared object.
"$cxx" --sysroot="$sysroot" -shared -pthread -Wl,--export-dynamic "${objects[@]}" \
  -Wl,-soname,watcher.node -Wl,-z,relro -Wl,-z,now -Wl,-z,max-page-size=16384 -o "$tmp/watcher.node"

machine="$(readelf -h "$tmp/watcher.node" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')"
[[ "$machine" == "$expected_machine" ]] || {
  echo "watcher: expected ELF machine '$expected_machine', got '${machine:-unknown}'" >&2
  exit 1
}
alignments="$(readelf -lW "$tmp/watcher.node" | awk '$1 == "LOAD" { print $NF }')"
[[ -n "$alignments" ]] || { echo "watcher: no PT_LOAD segments found" >&2; exit 1; }
while IFS= read -r alignment; do
  alignment="${alignment#0x}"
  if (( 16#$alignment < 16384 )); then
    echo "watcher: Android 16 KB page alignment missing (PT_LOAD alignment 0x$alignment)" >&2
    exit 1
  fi
done <<<"$alignments"
needed="$(readelf -d "$tmp/watcher.node" | awk '/NEEDED/{print $NF}')"
if printf '%s\n' "$needed" | grep -Eq 'lib(c|m|dl|pthread|rt)\.so\.[0-9]'; then
  echo "watcher: glibc-linked dependency found: $needed" >&2
  exit 1
fi
dyn_symbols="$(readelf --dyn-syms --wide "$tmp/watcher.node")"
if ! grep -F 'napi_register_module_v1' <<<"$dyn_symbols" >/dev/null; then
  echo "watcher: N-API registration export is missing" >&2
  printf '%s\n' "$dyn_symbols" | grep -E 'napi_register|node_api_module' >&2 || true
  exit 1
fi

install -m 0644 "$tmp/watcher.node" "$OUT"
echo "watcher: built $TARGET_ARCH Android/Bionic N-API module -> $OUT ($(stat -c%s "$OUT") bytes)"
echo "watcher: ELF $machine; NEEDED $(printf '%s ' $needed)"
