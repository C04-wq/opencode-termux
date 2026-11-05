#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
REPO_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
PREFIX="/data/data/com.termux/files/usr"
META="$REPO_DIR/release-checksums.json"
RUNTIME="$PREFIX/lib/opencode-termux"
CERT="$PREFIX/etc/tls/cert.pem"
RESOLVER="$PREFIX/etc/resolv.conf"
[[ "$(uname -m)" == aarch64 ]] || { echo "Error: ARM64/aarch64 only." >&2; exit 1; }
[[ -f "$META" ]] || { echo "Error: release-checksums.json missing." >&2; exit 1; }
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
HASH="$(sed -n 's/.*"archiveSha256"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/p' "$META" | head -n1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || { echo "Error: invalid version." >&2; exit 1; }
[[ "$HASH" =~ ^[a-f0-9]{64}$ ]] || { echo "Error: invalid checksum." >&2; exit 1; }
for cmd in git curl tar sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in sha256sum) package="coreutils" ;; *) package="$cmd" ;; esac
    pkg install -y "$package"
  fi
done
[[ -f "$CERT" ]] || pkg install -y ca-certificates
[[ -f "$RESOLVER" ]] || pkg install -y resolv-conf
for cmd in git curl tar sha256sum; do command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }; done
[[ -f "$CERT" && -f "$RESOLVER" ]] || { echo "Termux TLS/resolver files are missing." >&2; exit 1; }

STAGE="$(mktemp -d)"
BACKUP=""
ACTIVATED=0
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf "$STAGE"
  if (( status != 0 )); then
    if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
      rm -rf "$RUNTIME"
      if ! mv "$BACKUP" "$RUNTIME"; then
        echo "Error: failed to restore the previous runtime from $BACKUP." >&2
      fi
    elif [[ "$ACTIVATED" == 1 ]]; then
      rm -rf "$RUNTIME"
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
URL="https://github.com/C04-wq/opencode-termux/releases/download/v$VERSION/opencode-termux-aarch64.tar.gz"
echo "◇ Downloading OpenCode $VERSION…"
curl --fail --location --silent --show-error --retry 3 --retry-all-errors --proto '=https' --proto-redir '=https' "$URL" -o "$STAGE/runtime.tar.gz"
ACTUAL="$(sha256sum "$STAGE/runtime.tar.gz" | awk '{print $1}')"
[[ "$ACTUAL" == "$HASH" ]] || { echo "Error: SHA-256 mismatch; refusing to install." >&2; exit 1; }
echo "✓ SHA-256 verified"
mkdir "$STAGE/files"
tar -xzf "$STAGE/runtime.tar.gz" -C "$STAGE/files"
FILES="opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.runtime"
for file in $FILES; do [[ -s "$STAGE/files/$file" ]] || { echo "Error: archive missing $file" >&2; exit 1; }; done
chmod u+x "$STAGE/files/opencode" "$STAGE/files/ld-musl-aarch64.so.1"
echo "◇ Testing runtime…"
( unset LD_PRELOAD; export LD_LIBRARY_PATH="$STAGE/files"; "$STAGE/files/ld-musl-aarch64.so.1" --library-path "$STAGE/files" "$STAGE/files/opencode" --version ) || { echo "Error: runtime test failed." >&2; exit 1; }

mkdir -p "$PREFIX/lib" "$PREFIX/bin"
NEW="$PREFIX/lib/.opencode-termux-new-$$"
rm -rf "$NEW"; mkdir "$NEW"
for file in $FILES; do cp -a "$STAGE/files/$file" "$NEW/$file"; done
printf '%s\n' "$VERSION" > "$NEW/.opencode-termux-version"
chmod 600 "$NEW/.opencode-termux-version"
printf '%s\n' "$REPO_DIR" > "$NEW/.opencode-termux-repo-dir"
chmod 600 "$NEW/.opencode-termux-repo-dir"
if [[ -e "$RUNTIME" ]]; then BACKUP="$PREFIX/lib/.opencode-termux-backup-$$"; mv "$RUNTIME" "$BACKUP"; fi
if ! mv "$NEW" "$RUNTIME"; then
  [[ -n "$BACKUP" && -d "$BACKUP" ]] && mv "$BACKUP" "$RUNTIME"
  echo "Error: could not activate runtime." >&2; exit 1
fi
ACTIVATED=1

cat > "$PREFIX/bin/opencode" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -e
unset LD_PRELOAD
export OPENCODE_DISABLE_AUTOUPDATE=1
export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
PREFIX="/data/data/com.termux/files/usr"
RUNTIME="$PREFIX/lib/opencode-termux"
REPO_DIR="$(cat "$RUNTIME/.opencode-termux-repo-dir" 2>/dev/null || true)"
UPDATE_URL="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/release-checksums.json"

# Check GitHub quietly. A network/API failure must never prevent OpenCode from starting.
if [[ -n "$REPO_DIR" && -t 0 && -t 1 ]] && command -v curl >/dev/null 2>&1 && command -v sort >/dev/null 2>&1; then
  INSTALLED_VERSION="$(cat "$RUNTIME/.opencode-termux-version" 2>/dev/null || true)"
  REMOTE_METADATA="$(curl --fail --location --silent --show-error --connect-timeout 3 --max-time 6 --header 'Cache-Control: no-cache' "$UPDATE_URL" 2>/dev/null || true)"
  LATEST_VERSION="$(printf '%s\n' "$REMOTE_METADATA" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ "$INSTALLED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ && "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
    NEWEST="$(printf '%s\n%s\n' "$INSTALLED_VERSION" "$LATEST_VERSION" | sort -V | tail -n1)"
    if [[ "$LATEST_VERSION" != "$INSTALLED_VERSION" && "$NEWEST" == "$LATEST_VERSION" ]]; then
      printf '\nA new OpenCode version is available: %s (installed: %s).\n\n' "$LATEST_VERSION" "$INSTALLED_VERSION"
      SELECTED=1
      printf 'Use ↑/↓ to choose and Enter to confirm.\n'
      printf '\n'
      draw_update_menu() {
        printf '\033[2A'
        if [[ "$SELECTED" == 1 ]]; then
          printf '\033[2K\033[32m●\033[0m Install update now\n'
          printf '\033[2K  Wait for the next version\n'
        else
          printf '\033[2K  Install update now\n'
          printf '\033[2K\033[32m●\033[0m Wait for the next version\n'
        fi
      }
      printf '  Install update now\n'
      printf '  Wait for the next version\n'
      draw_update_menu
      while true; do
        KEY=""
        if ! read -rsn1 KEY </dev/tty; then
          SELECTED=2
          break
        fi
        if [[ "$KEY" == $'\\x04' ]]; then
          SELECTED=2
          break
        elif [[ "$KEY" == $'\\x1b' ]]; then
          SEQUENCE=""
          read -rsn2 -t 0.1 SEQUENCE </dev/tty || true
          case "$SEQUENCE" in
            '[A') SELECTED=1 ;;
            '[B') SELECTED=2 ;;
          esac
          draw_update_menu
        elif [[ -z "$KEY" ]]; then
          break
        fi
      done
      printf '\n'
      if [[ "$SELECTED" == 1 ]]; then
        if "$PREFIX/bin/opencode-termux-update"; then
          exec "$0" "$@"
        else
          printf 'Update failed. Starting the currently installed version.\n' >&2
        fi
      fi
    fi
  fi
fi

exec "$RUNTIME/ld-musl-aarch64.so.1" --library-path "$RUNTIME" "$RUNTIME/opencode" "$@"
LAUNCHER
chmod 755 "$PREFIX/bin/opencode"

cat > "$PREFIX/bin/opencode-termux-update" <<UPDATER
#!/data/data/com.termux/files/usr/bin/bash
set -e
REPO_DIR="$REPO_DIR"
git -C "\$REPO_DIR" pull --ff-only
exec bash "\$REPO_DIR/install.sh"
UPDATER
chmod 755 "$PREFIX/bin/opencode-termux-update"

( unset LD_PRELOAD; export LD_LIBRARY_PATH="$RUNTIME"; export SSL_CERT_FILE="$CERT"; "$RUNTIME/ld-musl-aarch64.so.1" --library-path "$RUNTIME" "$RUNTIME/opencode" --version ) || { echo "Error: installed runtime failed final test." >&2; exit 1; }
if [[ -n "$BACKUP" ]]; then rm -rf "$BACKUP"; BACKUP=""; fi
echo "✓ OpenCode $VERSION installed"
echo "Run: opencode"
echo "Update: opencode-termux-update"
echo "Uninstall: bash \"$REPO_DIR/uninstall.sh\""
