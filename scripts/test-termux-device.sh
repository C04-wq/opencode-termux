#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
ARCHIVE="${1:-}"
CHECKSUM_FILE="${2:-}"

if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Usage: bash scripts/test-termux-device.sh /path/to/opencode-VERSION-android-ARCH-bundle.tar.gz [/path/to/SHA256SUMS]" >&2
  exit 2
fi
DEVICE_ARCH="$(uname -m)"
case "$DEVICE_ARCH" in
  aarch64)
    TARGET_ARCH="aarch64"
    ARCHIVE_ARCH="aarch64"
    PTY_LIBRARY="librust_pty_arm64.so"
    EXPECTED_ELF_MACHINE="AArch64"
    ;;
  x86_64)
    TARGET_ARCH="x86_64"
    ARCHIVE_ARCH="x86_64"
    PTY_LIBRARY="librust_pty_x86_64.so"
    EXPECTED_ELF_MACHINE="Advanced Micro Devices X86-64"
    ;;
  *)
    echo "Error: unsupported device architecture '$DEVICE_ARCH'; supported: aarch64, x86_64." >&2
    exit 1
    ;;
esac
for cmd in bun rg tar sha256sum timeout; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd. Install it with: pkg install bun ripgrep libc++" >&2
    exit 1
  }
done

# Verify the exact candidate archive before extracting or executing it.
if [[ -z "$CHECKSUM_FILE" ]]; then
  if [[ -f "$ARCHIVE.sha256" ]]; then
    CHECKSUM_FILE="$ARCHIVE.sha256"
  elif [[ -f "$(dirname "$ARCHIVE")/SHA256SUMS" ]]; then
    CHECKSUM_FILE="$(dirname "$ARCHIVE")/SHA256SUMS"
  fi
fi
[[ -n "$CHECKSUM_FILE" && -f "$CHECKSUM_FILE" ]] || {
  echo "Error: checksum file not found. Pass SHA256SUMS or place it beside the archive." >&2
  exit 1
}
ARCHIVE_DIR="$(cd -- "$(dirname -- "$ARCHIVE")" && pwd -P)"
ARCHIVE="$ARCHIVE_DIR/$(basename -- "$ARCHIVE")"
CHECKSUM_DIR="$(cd -- "$(dirname -- "$CHECKSUM_FILE")" && pwd -P)"
CHECKSUM_FILE="$CHECKSUM_DIR/$(basename -- "$CHECKSUM_FILE")"
EXPECTED_SHA256="$(awk -v archive="$(basename -- "$ARCHIVE")" '$2 == archive || $2 == "*" archive { print $1; exit }' "$CHECKSUM_FILE")"
[[ "$EXPECTED_SHA256" =~ ^[a-f0-9]{64}$ ]] || {
  echo "Error: checksum file does not contain a valid SHA-256 entry for $(basename -- "$ARCHIVE")." >&2
  exit 1
}
ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || {
  echo "Error: candidate archive SHA-256 mismatch; refusing to execute it." >&2
  exit 1
}
echo "Candidate SHA-256 verified."

[[ -s "$PREFIX/lib/libc++_shared.so" ]] || {
  echo "Termux libc++ is missing. Install it with: pkg install libc++" >&2
  exit 1
}
[[ -s "$PREFIX/etc/tls/cert.pem" ]] || {
  echo "Termux TLS certificates are missing. Install ca-certificates." >&2
  exit 1
}

VERSION="$(basename "$ARCHIVE" | sed -n "s/^opencode-\\([0-9][0-9.]*\\)-android-$ARCHIVE_ARCH-bundle\\.tar\\.gz$/\\1/p")"
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
mkdir -p "$PREFIX/opt"
cleanup_failed_candidate() {
  local status=$?
  if (( status != 0 )); then
    rm -rf "$CANDIDATE"
  fi
}
trap cleanup_failed_candidate EXIT

TARGET_ARCH="$TARGET_ARCH" bash "$(dirname "$0")/validate-runtime-archive.sh" "$ARCHIVE" "$CANDIDATE"
for required in \
  bin/opencode \
  lib/opencode/index.js \
  lib/opencode/bunfig.toml \
  lib/opencode/$PTY_LIBRARY \
  lib/opencode/watcher.node \
  lib/opencode/opencode-pty \
  lib/opencode/opencode-pty.required; do
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
    grep -Fq "$EXPECTED_ELF_MACHINE" <<<"$header" || {
      echo "Error: native module does not match $TARGET_ARCH: $native_file" >&2
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
  echo "Verified $native_count Android $TARGET_ARCH native modules."
else
  echo "Note: readelf is not installed; device-side ELF inspection was skipped."
fi

"$CANDIDATE/lib/opencode/opencode-pty" --version

# Exercise the actual daemon protocol and create a real Android PTY. The
# playground starts the daemon, creates a shell, sends a command, reads a
# terminal snapshot, then releases the service on quit.
PTY_SMOKE_ROOT="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/opencode-pty-smoke.XXXXXX")"
PTY_SMOKE_LOG="$PTY_SMOKE_ROOT/play.log"
if ! printf 'new\nrun echo OPENCODE_PTY_ANDROID_SMOKE_OK\nwait 500\nquit\n' |
  timeout 30 "$CANDIDATE/lib/opencode/opencode-pty" play --name termux-smoke --runtime-dir "$PTY_SMOKE_ROOT" > "$PTY_SMOKE_LOG" 2>&1; then
  cat "$PTY_SMOKE_LOG" >&2
  rm -rf "$PTY_SMOKE_ROOT"
  echo "Error: official PTY daemon failed its Android IPC/terminal smoke test." >&2
  exit 1
fi
if ! grep -Fq 'OPENCODE_PTY_ANDROID_SMOKE_OK' "$PTY_SMOKE_LOG"; then
  cat "$PTY_SMOKE_LOG" >&2
  rm -rf "$PTY_SMOKE_ROOT"
  echo "Error: daemon started but did not return the PTY command output." >&2
  exit 1
fi
rm -rf "$PTY_SMOKE_ROOT"
echo "Official opencode-pty daemon and real terminal IPC passed."

echo "Testing OpenCode $VERSION ($TARGET_ARCH) with the real Termux Bun runtime..."
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
