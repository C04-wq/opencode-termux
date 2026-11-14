#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
PREFIX="/data/data/com.termux/files/usr"
RUNTIME="$PREFIX/lib/opencode-termux"
LAUNCHER="$PREFIX/bin/opencode"
UPDATER="$PREFIX/bin/opencode-termux-update"

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
    ! grep -Fq 'OPENCODE_DISABLE_AUTOUPDATE=1' "$LAUNCHER" ||
    ! grep -Fq '/lib/opencode-termux' "$LAUNCHER"; then
    echo "Error: $LAUNCHER is not a recognized OpenCode Termux launcher." >&2
    echo "Nothing was removed; inspect the file before retrying." >&2
    exit 1
  fi
fi
if [[ -e "$UPDATER" || -L "$UPDATER" ]]; then
  if [[ ! -f "$UPDATER" ]] ||
    ! grep -Fq 'git -C' "$UPDATER" ||
    ! grep -Fq 'install.sh' "$UPDATER"; then
    echo "Error: $UPDATER is not a recognized OpenCode Termux updater." >&2
    echo "Nothing was removed; inspect the file before retrying." >&2
    exit 1
  fi
fi

echo "This removes only the opencode-termux runtime and launchers."
echo "Settings, sessions, and provider credentials will be preserved."
read -r -p "Continue? [y/N] " answer
[[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { echo "Cancelled."; exit 0; }
rm -rf "$RUNTIME"
rm -f "$LAUNCHER" "$UPDATER"
echo "Runtime and launchers removed. User data was left untouched."
