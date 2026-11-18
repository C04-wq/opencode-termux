#!/usr/bin/env bash
# Validate and execute a packaged ARM64 Termux runtime under QEMU.
set -Eeuo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <runtime-archive.tar.gz> <expected-version> <work-directory>" >&2
  exit 64
fi

ARCHIVE="$1"
VERSION="$2"
WORKDIR="$3"
TERMUX_RUNTIME_PATH="/data/data/com.termux/files/usr/lib/opencode-termux"
TERMUX_INTERPRETER="$TERMUX_RUNTIME_PATH/ld-musl-aarch64.so.1"

[[ -f "$ARCHIVE" ]] || { echo "Runtime archive not found: $ARCHIVE" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || {
  echo "Invalid expected OpenCode version: $VERSION" >&2
  exit 64
}
for command in bash readelf qemu-aarch64 timeout sha256sum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

mkdir -p "$WORKDIR"
RUNTIME="$WORKDIR/runtime"
SYSROOT="$WORKDIR/termux-sysroot"
SERVE_LOG="$WORKDIR/opencode-serve.log"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

bash "$(dirname "$0")/validate-runtime-archive.sh" "$ARCHIVE" "$RUNTIME"

readelf -h "$RUNTIME/opencode" | grep -Eq 'Machine:.*AArch64'
readelf -l "$RUNTIME/opencode" | grep -Fq "$TERMUX_INTERPRETER" || {
  echo "OpenCode ELF is not patched to use the Termux musl interpreter." >&2
  exit 1
}

# QEMU resolves the ELF's absolute PT_INTERP under this synthetic Termux root.
mkdir -p "$SYSROOT$TERMUX_RUNTIME_PATH"
cp "$RUNTIME/ld-musl-aarch64.so.1" "$SYSROOT$TERMUX_RUNTIME_PATH/"

VERSION_OUTPUT="$(timeout 60s env -u LD_PRELOAD qemu-aarch64 -L "$SYSROOT" \
  -E LD_LIBRARY_PATH="$RUNTIME" "$RUNTIME/opencode" --version)"
[[ "$VERSION_OUTPUT" == "opencode v$VERSION" ]] || {
  echo "Unexpected emulated runtime version: $VERSION_OUTPUT" >&2
  exit 1
}
echo "$VERSION_OUTPUT"

# A live serve process exercises the ELF interpreter and libraries beyond --version.
set +e
timeout 12s env -u LD_PRELOAD qemu-aarch64 -L "$SYSROOT" \
  -E LD_LIBRARY_PATH="$RUNTIME" "$RUNTIME/opencode" serve \
  --hostname 127.0.0.1 --port 4099 >"$SERVE_LOG" 2>&1
SERVE_STATUS=$?
set -e
if [[ "$SERVE_STATUS" -ne 124 ]]; then
  echo "OpenCode serve exited before the smoke-test timeout (status $SERVE_STATUS)." >&2
  cat "$SERVE_LOG" >&2
  exit 1
fi

echo "OpenCode serve remained running under ARM64 emulation."
sha256sum "$ARCHIVE"
echo "ARM64 archive structure, PT_INTERP, direct execution, version, and serve startup verified."
