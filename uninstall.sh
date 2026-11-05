#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
PREFIX="/data/data/com.termux/files/usr"
echo "This removes only the opencode-termux runtime and launchers."
echo "Settings, sessions, and provider credentials will be preserved."
read -r -p "Continue? [y/N] " answer
[[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { echo "Cancelled."; exit 0; }
rm -rf "$PREFIX/lib/opencode-termux"
rm -f "$PREFIX/bin/opencode" "$PREFIX/bin/opencode-termux-update"
echo "Runtime and launchers removed. User data was left untouched."
