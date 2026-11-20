#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VALIDATOR="$ROOT/scripts/validate-runtime-archive.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
make_fixture() {
  local dir="$1" arch="${2:-aarch64}" pty
  case "$arch" in
    aarch64) pty=librust_pty_arm64.so ;;
    x86_64) pty=librust_pty_x86_64.so ;;
    *) echo "invalid fixture architecture: $arch" >&2; exit 1 ;;
  esac
  mkdir -p "$dir/bin" "$dir/lib/opencode"
  printf '#!/bin/sh\nexec bun "$@"\n' > "$dir/bin/opencode"
  printf 'console.log("fixture")\n' > "$dir/lib/opencode/index.js"
  : > "$dir/lib/opencode/bunfig.toml"
  printf 'native\n' > "$dir/lib/opencode/libopentui.so"
  printf 'native\n' > "$dir/lib/opencode/$pty"
  printf 'native\n' > "$dir/lib/opencode/watcher.node"
}
expect_rejected() {
  local archive="$1" name="$2" target_arch="${3:-aarch64}" dest="$TMP/out-$2"
  if TARGET_ARCH="$target_arch" bash "$VALIDATOR" "$archive" "$dest" >/dev/null 2>&1; then
    echo "FAIL: $name archive was accepted" >&2; exit 1
  fi
  [[ ! -e "$dest" && ! -L "$dest" ]] || { echo "FAIL: $name left extraction behind" >&2; exit 1; }
  echo "PASS: rejected $name archive"
}
make_fixture "$TMP/good"
tar -czf "$TMP/good.tar.gz" -C "$TMP/good" bin lib
bash "$VALIDATOR" "$TMP/good.tar.gz" "$TMP/extracted"
[[ -s "$TMP/extracted/bin/opencode" && -s "$TMP/extracted/lib/opencode/index.js" && -f "$TMP/extracted/lib/opencode/bunfig.toml" ]]
echo "PASS: accepted valid native bundle"
make_fixture "$TMP/good-x86_64" x86_64
tar -czf "$TMP/good-x86_64.tar.gz" -C "$TMP/good-x86_64" bin lib
TARGET_ARCH=x86_64 bash "$VALIDATOR" "$TMP/good-x86_64.tar.gz" "$TMP/extracted-x86_64"
[[ -s "$TMP/extracted-x86_64/lib/opencode/librust_pty_x86_64.so" ]]
[[ ! -e "$TMP/extracted-x86_64/lib/opencode/librust_pty_arm64.so" ]]
echo "PASS: accepted valid x86_64 native bundle"
mkdir -p "$TMP/mixed"; cp -a "$TMP/good-x86_64/." "$TMP/mixed/"
printf 'wrong arch\n' > "$TMP/mixed/lib/opencode/librust_pty_arm64.so"
tar -czf "$TMP/mixed.tar.gz" -C "$TMP/mixed" bin lib
expect_rejected "$TMP/mixed.tar.gz" mixed-architecture x86_64
mkdir -p "$TMP/extra"; cp -a "$TMP/good/." "$TMP/extra/"; printf bad > "$TMP/extra/outside"
tar -czf "$TMP/extra.tar.gz" -C "$TMP/extra" bin lib outside
expect_rejected "$TMP/extra.tar.gz" extra
tar --transform='s|bin/opencode|../escape|' -czf "$TMP/traversal.tar.gz" -C "$TMP/good" bin lib
expect_rejected "$TMP/traversal.tar.gz" traversal
mkdir -p "$TMP/link"; cp -a "$TMP/good/." "$TMP/link/"; rm "$TMP/link/bin/opencode"; ln -s /etc/passwd "$TMP/link/bin/opencode"
tar -czf "$TMP/link.tar.gz" -C "$TMP/link" bin lib
expect_rejected "$TMP/link.tar.gz" symlink
mkdir -p "$TMP/missing"; cp -a "$TMP/good/." "$TMP/missing/"; rm "$TMP/missing/lib/opencode/watcher.node"
tar -czf "$TMP/missing.tar.gz" -C "$TMP/missing" bin lib
expect_rejected "$TMP/missing.tar.gz" missing-file
