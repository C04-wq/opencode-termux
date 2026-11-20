#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILDER="$ROOT/scripts/ci/build-rust-pty-android.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for arch in arm i686 armv7l i386; do
  log="$TMP/$arch.log"
  status=0
  TARGET_ARCH="$arch" bash "$BUILDER" "$TMP/$arch.so" >"$log" 2>&1 || status=$?
  if [[ "$status" -ne 2 ]]; then
    echo "FAIL: unsupported architecture '$arch' returned $status (expected 2)" >&2
    cat "$log" >&2
    exit 1
  fi
  grep -Fq "unsupported TARGET_ARCH '$arch'" "$log" || {
    echo "FAIL: unsupported architecture '$arch' did not produce a clear diagnostic" >&2
    cat "$log" >&2
    exit 1
  }
  [[ ! -e "$TMP/$arch.so" ]] || {
    echo "FAIL: unsupported architecture '$arch' unexpectedly produced an output" >&2
    exit 1
  }
  echo "PASS: rejected unsupported PTY target $arch"
done
