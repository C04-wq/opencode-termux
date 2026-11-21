#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
RUNTIME="$PREFIX/lib/opencode-termux"
LAUNCHER="$PREFIX/bin/opencode"

# Require the runtime marker and recognizable project launchers before
# removing anything. This prevents uninstall from deleting another tool's
# command if the files were replaced after this package was installed.
if [[ ! -f "$RUNTIME/.opencode-termux-version" ]]; then
  echo "Error: this OpenCode Termux runtime is not installed (marker missing)." >&2
  echo "Nothing was removed." >&2
  exit 1
fi
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
  if [[ ! -f "$LAUNCHER" ]] ||
        ! grep -Fq '/lib/opencode-termux' "$LAUNCHER"; then
    echo "Error: $LAUNCHER is not a recognized OpenCode Termux launcher." >&2
    echo "Nothing was removed; inspect the file before retrying." >&2
    exit 1
  fi
fi

echo "This removes only the OpenCode Termux runtime and launcher."
echo "Settings, sessions, and provider credentials will be preserved."
read -r -p "Continue? [y/N] " answer
[[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { echo "Cancelled."; exit 0; }
rm -rf "$RUNTIME"
rm -f "$LAUNCHER"
LEGACY_LAUNCHER2="$PREFIX/bin/opencode2"
if [[ -f "$LEGACY_LAUNCHER2" ]] && grep -Fq '/lib/opencode-termux' "$LEGACY_LAUNCHER2"; then
  rm -f "$LEGACY_LAUNCHER2"
elif [[ -L "$LEGACY_LAUNCHER2" ]]; then
  LEGACY_TARGET="$(readlink -f "$LEGACY_LAUNCHER2" 2>/dev/null || true)"
  case "$LEGACY_TARGET" in "$RUNTIME"/*) rm -f "$LEGACY_LAUNCHER2" ;; esac
fi
echo "Runtime and launchers removed. User data was left untouched."
