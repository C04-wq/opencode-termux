#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="/data/data/com.termux/files/usr"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd -P)"
else
  SCRIPT_DIR=""
fi
REPO_DIR="$SCRIPT_DIR"

# Keep successful setup commands quiet while preserving their full error output.
run_quiet() {
  local log status
  log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    rm -f "$log"
  else
    status=$?
    cat "$log" >&2
    rm -f "$log"
    return "$status"
  fi
}

# Support a normal checkout and: curl -fsSL .../install.sh | bash
# A piped script has no source directory. Adopt an existing clean clone when
# possible, moving it to the managed location so users do not keep two clones.
is_project_checkout() {
  local dir="$1" remote
  [[ -f "$dir/release-checksums.json" && -f "$dir/install.sh" ]] || return 1
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    https://github.com/C04-wq/opencode-termux.git|https://github.com/C04-wq/opencode-termux|git@github.com:C04-wq/opencode-termux.git|ssh://git@github.com/C04-wq/opencode-termux.git) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_project_checkout "$REPO_DIR"; then
  echo "Preparing OpenCode for Termux..."
  if ! command -v git >/dev/null 2>&1; then
    run_quiet pkg install -y git
  fi
  command -v git >/dev/null 2>&1 || { echo "Error: Git could not be installed." >&2; exit 1; }

  SOURCE_REPO="$PREFIX/opt/opencode-termux"
  mkdir -p "$PREFIX/opt"
  if [[ -e "$SOURCE_REPO" && ! -d "$SOURCE_REPO/.git" ]]; then
    echo "Error: $SOURCE_REPO exists but is not a Git checkout. Move it and retry." >&2
    exit 1
  fi

  if [[ -d "$SOURCE_REPO/.git" ]]; then
    is_project_checkout "$SOURCE_REPO" || {
      echo "Error: $SOURCE_REPO is not a clone of C04-wq/opencode-termux." >&2
      exit 1
    }
    REPO_DIR="$SOURCE_REPO"
  else
    REPO_DIR=""
    # Search common Termux home locations for an existing clone. Only a
    # matching origin is considered; unrelated Git repositories are ignored.
    while IFS= read -r git_dir; do
      candidate="${git_dir%/.git}"
      if is_project_checkout "$candidate"; then
        REPO_DIR="$candidate"
        break
      fi
    done < <(find "$HOME" -maxdepth 5 -type d -name .git -prune -print 2>/dev/null | sort)
  fi

  if [[ -n "$REPO_DIR" ]]; then
    if [[ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" ]]; then
      echo "Error: an existing OpenCode Termux clone has local changes:" >&2
      echo "  $REPO_DIR" >&2
      echo "Commit or stash those changes, then run the curl installer again." >&2
      echo "The clone and its files have been left untouched." >&2
      exit 1
    fi
    echo "Found existing clone: $REPO_DIR"
    run_quiet git -C "$REPO_DIR" pull --ff-only
    if [[ "$REPO_DIR" != "$SOURCE_REPO" ]]; then
      if mv "$REPO_DIR" "$SOURCE_REPO"; then
        echo "Migrated existing clone to $SOURCE_REPO"
        REPO_DIR="$SOURCE_REPO"
      else
        echo "Could not move the clone; continuing from its original location." >&2
      fi
    fi
  else
    REPO_DIR="$SOURCE_REPO"
    run_quiet git clone -- https://github.com/C04-wq/opencode-termux.git "$REPO_DIR"
  fi
  is_project_checkout "$REPO_DIR" || { echo "Error: repository checkout is incomplete." >&2; exit 1; }
  exec bash "$REPO_DIR/install.sh" "$@"
fi

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
    run_quiet pkg install -y "$package"
  fi
done
[[ -f "$CERT" ]] || run_quiet pkg install -y ca-certificates
[[ -f "$RESOLVER" ]] || run_quiet pkg install -y resolv-conf
for cmd in git curl tar sha256sum; do command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }; done
[[ -f "$CERT" && -f "$RESOLVER" ]] || { echo "Termux TLS/resolver files are missing." >&2; exit 1; }

STAGE="$(mktemp -d)"
BACKUP=""
NEW=""
ACTIVATED=0
LAUNCHER="$PREFIX/bin/opencode"
UPDATER="$PREFIX/bin/opencode-termux-update"
LAUNCHER_BACKUP="$PREFIX/bin/.opencode-backup-$BASHPID"
UPDATER_BACKUP="$PREFIX/bin/.opencode-updater-backup-$BASHPID"
LAUNCHER_WAS_PRESENT=0
UPDATER_WAS_PRESENT=0
LAUNCHERS_TOUCHED=0
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf "$STAGE"
  if [[ -n "$NEW" ]]; then rm -rf "$NEW"; fi
  if (( status != 0 )); then
    if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
      rm -rf "$RUNTIME"
      if ! mv "$BACKUP" "$RUNTIME"; then
        echo "Error: failed to restore the previous runtime from $BACKUP." >&2
      fi
    elif [[ "$ACTIVATED" == 1 ]]; then
      rm -rf "$RUNTIME"
    fi
    if [[ "$LAUNCHERS_TOUCHED" == 1 ]]; then
      if [[ -e "$LAUNCHER_BACKUP" || -L "$LAUNCHER_BACKUP" ]]; then
        rm -f "$LAUNCHER"
        if ! mv "$LAUNCHER_BACKUP" "$LAUNCHER"; then
          echo "Error: failed to restore the previous launcher from $LAUNCHER_BACKUP." >&2
        fi
      elif [[ "$LAUNCHER_WAS_PRESENT" == 0 ]]; then
        rm -f "$LAUNCHER"
      fi
      if [[ -e "$UPDATER_BACKUP" || -L "$UPDATER_BACKUP" ]]; then
        rm -f "$UPDATER"
        if ! mv "$UPDATER_BACKUP" "$UPDATER"; then
          echo "Error: failed to restore the previous updater from $UPDATER_BACKUP." >&2
        fi
      elif [[ "$UPDATER_WAS_PRESENT" == 0 ]]; then
        rm -f "$UPDATER"
      fi
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
URL="https://github.com/C04-wq/opencode-termux/releases/download/v$VERSION/opencode-termux-aarch64.tar.gz"
echo "Downloading OpenCode $VERSION..."
curl --fail --location --silent --show-error --retry 3 --retry-all-errors --proto '=https' --proto-redir '=https' "$URL" -o "$STAGE/runtime.tar.gz"
ACTUAL="$(sha256sum "$STAGE/runtime.tar.gz" | awk '{print $1}')"
[[ "$ACTUAL" == "$HASH" ]] || { echo "Error: SHA-256 mismatch; refusing to install." >&2; exit 1; }
echo "Verifying package integrity... OK"
mkdir "$STAGE/files"
tar -xzf "$STAGE/runtime.tar.gz" -C "$STAGE/files"
FILES="opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.runtime"
for file in $FILES; do [[ -s "$STAGE/files/$file" ]] || { echo "Error: archive missing $file" >&2; exit 1; }; done
chmod u+x "$STAGE/files/opencode" "$STAGE/files/ld-musl-aarch64.so.1"
echo "Checking runtime..."
VERSION_OUTPUT="$( unset LD_PRELOAD; export LD_LIBRARY_PATH="$STAGE/files"; "$STAGE/files/ld-musl-aarch64.so.1" --library-path "$STAGE/files" "$STAGE/files/opencode" --version )" || { echo "Error: runtime test failed." >&2; exit 1; }
[[ "$VERSION_OUTPUT" == "opencode v$VERSION" ]] || { echo "Error: unexpected runtime version: $VERSION_OUTPUT" >&2; exit 1; }

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

cat > "$STAGE/opencode-launcher" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -e
unset LD_PRELOAD
export OPENCODE_DISABLE_AUTOUPDATE=1
export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
PREFIX="/data/data/com.termux/files/usr"
RUNTIME="$PREFIX/lib/opencode-termux"
export LD_LIBRARY_PATH="$RUNTIME${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
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
      CURSOR_HIDDEN=0
      restore_cursor() {
        if [[ "$CURSOR_HIDDEN" == 1 ]]; then
          printf '\033[?25h'
          CURSOR_HIDDEN=0
        fi
      }
      trap 'restore_cursor' EXIT
      trap 'restore_cursor; exit 130' INT
      trap 'restore_cursor; exit 143' TERM
      trap 'restore_cursor; exit 129' HUP
      printf '\033[?25l'
      CURSOR_HIDDEN=1
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
        if [[ "$KEY" == $'\x04' ]]; then
          SELECTED=2
          break
        elif [[ "$KEY" == $'\x1b' ]]; then
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
      restore_cursor
      trap - EXIT INT TERM HUP
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

exec "$RUNTIME/opencode" "$@"
LAUNCHER
chmod 755 "$STAGE/opencode-launcher"

cat > "$STAGE/opencode-termux-update" <<UPDATER
#!/data/data/com.termux/files/usr/bin/bash
set -e
REPO_DIR="$REPO_DIR"
LOG="\$(mktemp)"
if git -C "\$REPO_DIR" pull --ff-only >"\$LOG" 2>&1; then
  rm -f "\$LOG"
else
  STATUS=\$?
  cat "\$LOG" >&2
  rm -f "\$LOG"
  exit "\$STATUS"
fi
exec bash "\$REPO_DIR/install.sh"
UPDATER
chmod 755 "$STAGE/opencode-termux-update"

# Activate launchers transactionally: keep the previous files until the
# installed runtime passes its final test.
LAUNCHERS_TOUCHED=1
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
  LAUNCHER_WAS_PRESENT=1
  mv "$LAUNCHER" "$LAUNCHER_BACKUP"
fi
if [[ -e "$UPDATER" || -L "$UPDATER" ]]; then
  UPDATER_WAS_PRESENT=1
  mv "$UPDATER" "$UPDATER_BACKUP"
fi
mv "$STAGE/opencode-launcher" "$LAUNCHER"
mv "$STAGE/opencode-termux-update" "$UPDATER"

FINAL_VERSION="$( unset LD_PRELOAD; export LD_LIBRARY_PATH="$RUNTIME"; export SSL_CERT_FILE="$CERT"; "$RUNTIME/opencode" --version )" || { echo "Error: installed runtime failed final test." >&2; exit 1; }
[[ "$FINAL_VERSION" == "opencode v$VERSION" ]] || { echo "Error: installed runtime returned an unexpected version: $FINAL_VERSION" >&2; exit 1; }
if [[ -n "$BACKUP" ]]; then rm -rf "$BACKUP"; BACKUP=""; fi
rm -f "$LAUNCHER_BACKUP" "$UPDATER_BACKUP"
echo "OpenCode $VERSION installed successfully."
echo "Start: opencode"
echo "Update: opencode-termux-update"
echo "Uninstall: bash \"$REPO_DIR/uninstall.sh\""
