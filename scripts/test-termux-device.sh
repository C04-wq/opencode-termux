#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
ARCHIVE="${1:-}"

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Usage: bash scripts/test-termux-device.sh /path/to/opencode-VERSION-android-aarch64-bundle.tar.gz" >&2
  exit 2
fi
[[ "$(uname -m)" == "aarch64" ]] || {
  echo "Error: this test requires a physical ARM64 Termux device." >&2
  exit 1
}
for cmd in bun rg tar; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd. Install it with: pkg install bun ripgrep libc++" >&2
    exit 1
  }
done
[[ -s "$PREFIX/lib/libc++_shared.so" ]] || {
  echo "Termux libc++ is missing. Install it with: pkg install libc++" >&2
  exit 1
}
[[ -s "$PREFIX/etc/tls/cert.pem" ]] || {
  echo "Termux TLS certificates are missing. Install ca-certificates." >&2
  exit 1
}

VERSION="$(basename "$ARCHIVE" | sed -n 's/^opencode-\([0-9][0-9.]*\)-android-aarch64-bundle\.tar\.gz$/\1/p')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Error: archive filename does not contain a valid OpenCode version." >&2
  exit 1
}

CANDIDATE="$PREFIX/opt/opencode-termux-candidate-$VERSION"
[[ ! -e "$CANDIDATE" ]] || {
  echo "Error: candidate directory already exists: $CANDIDATE" >&2
  echo "Remove it first if you want to repeat this test." >&2
  exit 1
}
mkdir -p "$PREFIX/opt" "$CANDIDATE"
cleanup_failed_candidate() {
  local status=$?
  if (( status != 0 )); then
    rm -rf "$CANDIDATE"
  fi
}
trap cleanup_failed_candidate EXIT

tar -xzf "$ARCHIVE" -C "$CANDIDATE"
for required in \
  bin/opencode \
  lib/opencode/index.js \
  lib/opencode/bunfig.toml \
  lib/opencode/librust_pty_arm64.so \
  lib/opencode/watcher.node; do
  [[ -f "$CANDIDATE/$required" ]] || {
    echo "Error: candidate archive is missing $required" >&2
    exit 1
  }
done
[[ -x "$CANDIDATE/bin/opencode" ]] || {
  echo "Error: candidate launcher is not executable." >&2
  exit 1
}

if command -v readelf >/dev/null 2>&1; then
  native_count=0
  while IFS= read -r -d '' native_file; do
    header="$(readelf -h "$native_file")"
    grep -q "AArch64" <<<"$header" || {
      echo "Error: native module is not AArch64: $native_file" >&2
      exit 1
    }
    grep -q "DYN" <<<"$header" || {
      echo "Error: native module is not PIE/ET_DYN: $native_file" >&2
      exit 1
    }
    native_count=$((native_count + 1))
  done < <(find "$CANDIDATE/lib/opencode" -type f \( -name '*.so' -o -name '*.node' \) -print0)
  (( native_count > 0 )) || {
    echo "Error: no native ELF modules were found." >&2
    exit 1
  }
  echo "Verified $native_count Android ARM64 native modules."
else
  echo "Note: readelf is not installed; device-side ELF inspection was skipped."
fi

export OPENCODE_LAUNCHER="$CANDIDATE/bin/opencode"
echo "Testing OpenCode $VERSION with the real Termux Bun runtime..."
VERSION_OUTPUT="$("$CANDIDATE/bin/opencode" --version 2>&1)"
printf '%s\n' "$VERSION_OUTPUT"
grep -Fq "$VERSION" <<<"$VERSION_OUTPUT" || {
  echo "Error: candidate reported an unexpected OpenCode version." >&2
  exit 1
}
"$CANDIDATE/bin/opencode" --help >/dev/null
"$CANDIDATE/bin/opencode" serve --help >/dev/null

trap - EXIT
echo
echo "Non-interactive device checks passed."
echo "Candidate runtime: $CANDIDATE"
echo "Next, launch the interactive TUI to validate terminal input, PTY and file watching:"
echo "  $CANDIDATE/bin/opencode"
echo "The existing OpenCode installation was not modified."
echo "Remove the candidate when finished:"
echo "  rm -rf \"$CANDIDATE\""
