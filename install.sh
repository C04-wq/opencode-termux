#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Report the exact failing activation step before the EXIT trap rolls back.
trap 'status=$?; printf "\\nError: installer failed at line %s (exit %s): %s\\n" "$LINENO" "$status" "$BASH_COMMAND" >&2' ERR

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

# Compact terminal UI: show the project mark before the real download meter.
# When stdout is not a terminal, keep output suitable for scripts and CI.
UI_ENABLED=0
UI_STARTED="${OPENCODE_TERMUX_UI_STARTED:-0}"
if [[ -t 1 ]]; then UI_ENABLED=1; fi
UI_ANIMATION_PID=""
ui_draw_logo() {
  local shade="$1" row col padding=0 columns="${COLUMNS:-0}"
  if [[ "$columns" =~ ^[0-9]+$ ]] && (( columns > 32 )); then
    padding=$(( (columns - 32) / 2 ))
  fi
  for (( row=0; row<20; row++ )); do
    printf '%*s' "$padding" ''
    for (( col=0; col<16; col++ )); do
      if (( row >= 8 && row < 16 && col >= 4 && col < 12 )); then
        printf '\033[48;2;75;70;70m  '
      else
        printf '\033[48;2;%s;%s;%sm  ' "$shade" "$((shade - 5))" "$((shade - 5))"
      fi
    done
    printf '\033[0m\n'
  done
}
UI_CURSOR_HIDDEN=0
ui_hide_cursor() {
  (( UI_ENABLED == 1 )) || return 0
  [[ "$UI_CURSOR_HIDDEN" == 1 ]] && return 0
  printf '\033[?25l' >/dev/tty 2>/dev/null || return 0
  UI_CURSOR_HIDDEN=1
}
ui_restore_cursor() {
  [[ "$UI_CURSOR_HIDDEN" == 1 ]] || return 0
  printf '\033[?25h' >/dev/tty 2>/dev/null || true
  UI_CURSOR_HIDDEN=0
}
ui_handle_signal() {
  local status="$1"
  ui_animation_stop
  ui_restore_cursor
  exit "$status"
}
trap 'ui_restore_cursor' EXIT
trap 'ui_handle_signal 130' INT
trap 'ui_handle_signal 143' TERM
trap 'ui_handle_signal 129' HUP
ui_start() {
  (( UI_ENABLED == 1 )) || return 0
  ui_hide_cursor
  [[ "$UI_STARTED" == 1 ]] && return 0
  printf '\n'
  ui_draw_logo 241
  printf '\n'
  UI_STARTED=1
  export OPENCODE_TERMUX_UI_STARTED=1
}
ui_animation_start() {
  (( UI_ENABLED == 1 )) || return 0
  [[ -n "$UI_ANIMATION_PID" ]] && return 0
  (
    local shade=241
    while :; do
      printf '\033[s\033[21A'
      ui_draw_logo "$shade"
      printf '\033[u'
      if [[ "$shade" == 241 ]]; then shade=255; else shade=241; fi
      sleep 0.7
    done
  ) >/dev/tty 2>/dev/null &
  UI_ANIMATION_PID=$!
}
ui_animation_stop() {
  [[ -n "$UI_ANIMATION_PID" ]] || return 0
  kill "$UI_ANIMATION_PID" 2>/dev/null || true
  wait "$UI_ANIMATION_PID" 2>/dev/null || true
  UI_ANIMATION_PID=""
  if (( UI_ENABLED == 1 )); then
    printf '\033[s\033[21A'
    ui_draw_logo 241
    printf '\033[u'
  fi
}
ui_finish() {
  (( UI_ENABLED == 1 )) || return 0
  ui_animation_stop
  printf '\n\n'
  if [[ "$INSTALL_ACTION" == "updated" ]]; then
    printf '\033[32mOpenCode updated successfully. The update process completed successfully.\033[0m\n'
  else
    printf '\033[32mOpenCode installed successfully.\033[0m\n'
  fi
  printf '  Version: %s\n' "$VERSION"
  printf '  Run: opencode\n\n'
}
ui_start

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
    # Termux may expose executable-bit drift from previous installs as Git
    # modifications. Ignore mode-only differences before checking for a dirty
    # checkout, but only after the repository origin has been verified above.
    run_quiet git -C "$REPO_DIR" config core.filemode false
    if [[ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" ]]; then
      echo "Error: an existing OpenCode Termux clone has local changes:" >&2
      echo "  $REPO_DIR" >&2
      echo "Commit or stash those changes, then run the curl installer again." >&2
      echo "The clone and its files have been left untouched." >&2
      exit 1
    fi

    run_quiet git -C "$REPO_DIR" pull --ff-only
    if [[ "$REPO_DIR" != "$SOURCE_REPO" ]]; then
      if mv "$REPO_DIR" "$SOURCE_REPO"; then

        REPO_DIR="$SOURCE_REPO"
      else
        printf 'Warning: could not move the clone; continuing from its original location.\n' >&2
      fi
    fi
  else
    REPO_DIR="$SOURCE_REPO"

    run_quiet git clone -- https://github.com/C04-wq/opencode-termux.git "$REPO_DIR"
  fi
  is_project_checkout "$REPO_DIR" || { echo "Error: repository checkout is incomplete." >&2; exit 1; }

  exec bash "$REPO_DIR/install.sh" "$@"
fi

# Keep executable entry points runnable in the managed checkout. Termux may
# report chmod-only changes as Git modifications, so disable filemode tracking
# before changing permissions; content changes remain detectable.
run_quiet git -C "$REPO_DIR" config core.filemode false
chmod 755 "$REPO_DIR/opencode-termux" "$REPO_DIR/manager.sh"

META="$REPO_DIR/release-checksums.json"
RUNTIME="$PREFIX/lib/opencode-termux"
INSTALL_ACTION="installed"
if [[ -s "$RUNTIME/.opencode-termux-version" ]]; then
  INSTALL_ACTION="updated"
fi
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
MANAGER="$PREFIX/bin/opencode-termux"
LAUNCHER_BACKUP="$PREFIX/bin/.opencode-backup-$BASHPID"
UPDATER_BACKUP="$PREFIX/bin/.opencode-updater-backup-$BASHPID"
MANAGER_BACKUP="$PREFIX/bin/.opencode-manager-backup-$BASHPID"
LAUNCHER_WAS_PRESENT=0
UPDATER_WAS_PRESENT=0
MANAGER_WAS_PRESENT=0
LAUNCHERS_TOUCHED=0
cleanup() {
  local status=$?
  trap - EXIT
  ui_animation_stop
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
      if [[ -e "$MANAGER_BACKUP" || -L "$MANAGER_BACKUP" ]]; then
        rm -f "$MANAGER"
        if ! mv "$MANAGER_BACKUP" "$MANAGER"; then
          echo "Error: failed to restore the previous manager from $MANAGER_BACKUP." >&2
        fi
      elif [[ "$MANAGER_WAS_PRESENT" == 0 ]]; then
        rm -f "$MANAGER"
      fi
    fi
  fi
  ui_restore_cursor
  exit "$status"
}
trap cleanup EXIT
URL="https://github.com/C04-wq/opencode-termux/releases/download/v$VERSION/opencode-termux-aarch64.tar.gz"

if (( UI_ENABLED == 1 )); then
  # Pulse the logo while curl renders its real byte-based transfer progress.
  ui_animation_start
  curl --fail --location --progress-bar --show-error --retry 3 --retry-all-errors --proto '=https' --proto-redir '=https' "$URL" -o "$STAGE/runtime.tar.gz"
else
  curl --fail --location --silent --show-error --retry 3 --retry-all-errors --proto '=https' --proto-redir '=https' "$URL" -o "$STAGE/runtime.tar.gz"
fi
ACTUAL="$(sha256sum "$STAGE/runtime.tar.gz" | awk '{print $1}')"
[[ "$ACTUAL" == "$HASH" ]] || { echo "Error: SHA-256 mismatch; refusing to install." >&2; exit 1; }

bash "$REPO_DIR/scripts/validate-runtime-archive.sh" "$STAGE/runtime.tar.gz" "$STAGE/files"

FILES="opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.runtime"
chmod u+x "$STAGE/files/opencode" "$STAGE/files/ld-musl-aarch64.so.1"
# The packaged ELF has an absolute PT_INTERP pointing at the final runtime
# directory. It cannot be executed from STAGE before activation. The
# transactional final smoke test below runs it from RUNTIME and restores the
# previous runtime automatically if that test fails.

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

ui_draw_logo() {
  local shade="$1" row col padding=0 columns="${COLUMNS:-0}"
  if [[ "$columns" =~ ^[0-9]+$ ]] && (( columns > 32 )); then
    padding=$(( (columns - 32) / 2 ))
  fi
  for (( row=0; row<20; row++ )); do
    printf '%*s' "$padding" ''
    for (( col=0; col<16; col++ )); do
      if (( row >= 8 && row < 16 && col >= 4 && col < 12 )); then
        printf '\033[48;2;75;70;70m  '
      else
        printf '\033[48;2;%s;%s;%sm  ' "$shade" "$((shade - 5))" "$((shade - 5))"
      fi
    done
    printf '\033[0m\n'
  done
}
ui_animation_start() {
  (
    local shade=241
    while :; do
      printf '\033[s\033[28A'
      ui_draw_logo "$shade"
      printf '\033[u'
      if [[ "$shade" == 241 ]]; then shade=255; else shade=241; fi
      sleep 0.7
    done
  ) >/dev/tty 2>/dev/null &
  UI_ANIMATION_PID=$!
}
ui_animation_stop() {
  [[ -n "${UI_ANIMATION_PID:-}" ]] || return 0
  kill "$UI_ANIMATION_PID" 2>/dev/null || true
  wait "$UI_ANIMATION_PID" 2>/dev/null || true
  UI_ANIMATION_PID=""
  printf '\033[s\033[28A'
  ui_draw_logo 241
  printf '\033[u'
}

# Check GitHub quietly. A network/API failure must never prevent OpenCode from starting.
if [[ -n "$REPO_DIR" && -t 0 && -t 1 ]] && command -v curl >/dev/null 2>&1 && command -v sort >/dev/null 2>&1; then
  INSTALLED_VERSION="$(cat "$RUNTIME/.opencode-termux-version" 2>/dev/null || true)"
  REMOTE_METADATA="$(curl --fail --location --silent --show-error --connect-timeout 3 --max-time 6 --header 'Cache-Control: no-cache' "$UPDATE_URL" 2>/dev/null || true)"
  LATEST_VERSION="$(printf '%s\n' "$REMOTE_METADATA" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ "$INSTALLED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ && "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
    NEWEST="$(printf '%s\n%s\n' "$INSTALLED_VERSION" "$LATEST_VERSION" | sort -V | tail -n1)"
    if [[ "$LATEST_VERSION" != "$INSTALLED_VERSION" && "$NEWEST" == "$LATEST_VERSION" ]]; then
      printf '\n'
      ui_draw_logo 241
      printf '\n'
      UI_ANIMATION_PID=""
      printf 'A new OpenCode version is available: %s (installed: %s).\n\n' "$LATEST_VERSION" "$INSTALLED_VERSION"
      CURSOR_HIDDEN=0
      restore_cursor() {
        ui_animation_stop
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
      print_gradient_text() {
        local label="$1" index length progress red green blue char
        length="${#label}"
        printf ' '
        for (( index=0; index<length; index++ )); do
          progress=$(( index * 100 / (length > 1 ? length - 1 : 1) ))
          red=$(( 62 + progress * 150 / 100 ))
          green=$(( 62 + progress * 150 / 100 ))
          blue=$(( 62 + progress * 150 / 100 ))
          char="${label:index:1}"
          printf '\033[48;2;%d;%d;%dm\033[1;30m%s' "$red" "$green" "$blue" "$char"
        done
        printf '\033[0m '
      }
      draw_update_menu() {
        printf '\033[3A'
        if [[ "$SELECTED" == 1 ]]; then
          printf '\033[2K\033[32m●\033[0m'
          print_gradient_text 'Install update now'
          printf '\n'
          printf '\033[2K\n'
          printf '\033[2K○ Wait for the next version\n'
        else
          printf '\033[2K○ Install update now\n'
          printf '\033[2K\n'
          printf '\033[2K\033[32m●\033[0m'
          print_gradient_text 'Wait for the next version'
          printf '\n'
        fi
      }
      printf '○ Install update now\n'
      printf '\n'
      printf '○ Wait for the next version\n'
      draw_update_menu
      ui_animation_start
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
      ui_animation_stop
      if [[ "$SELECTED" == 1 ]]; then
        # Keep the cursor hidden through the updater and installer hand-off.
        # Remove the decision menu and leave the cursor directly below the logo.
        printf '\033[8A\033[J'
        if OPENCODE_TERMUX_UI_STARTED=1 "$PREFIX/bin/opencode-termux-update"; then
          restore_cursor
          trap - EXIT INT TERM HUP
          exec "$0" "$@"
        else
          restore_cursor
          trap - EXIT INT TERM HUP
          printf 'Update failed. Starting the currently installed version.\n' >&2
        fi
      else
        restore_cursor
        trap - EXIT INT TERM HUP
      fi
    fi
  fi
fi

exec "$RUNTIME/opencode" "$@"
LAUNCHER
chmod 755 "$STAGE/opencode-launcher"

# Keep one canonical manager implementation; this is also the file installed by users from the checkout.
cp "$REPO_DIR/manager.sh" "$STAGE/opencode-termux-manager"
chmod 755 "$STAGE/opencode-termux-manager"

cat > "$STAGE/opencode-termux-update" <<'UPDATER'
#!/data/data/com.termux/files/usr/bin/bash
set -e
# OPENCODE_TERMUX_UPDATER=1
PREFIX="/data/data/com.termux/files/usr"
RUNTIME="$PREFIX/lib/opencode-termux"
REPO_DIR="$(cat "$RUNTIME/.opencode-termux-repo-dir" 2>/dev/null || true)"
if [[ -z "$REPO_DIR" || ! -f "$REPO_DIR/install.sh" ]]; then
  echo "Error: managed repository checkout was not found." >&2
  exit 1
fi
# Termux filesystems may report chmod-only changes even when tracked content
# is untouched. Ignore permission-bit drift, while Git still detects content edits.
git -C "$REPO_DIR" config core.filemode false
LOG="$(mktemp)"
if git -C "$REPO_DIR" pull --ff-only >"$LOG" 2>&1; then
  rm -f "$LOG"
else
  STATUS=$?
  cat "$LOG" >&2
  rm -f "$LOG"
  exit "$STATUS"
fi
exec bash "$REPO_DIR/install.sh"
UPDATER
chmod 755 "$STAGE/opencode-termux-update"

# Protect the updater path too: never back up or replace an unrelated file.
if [[ -e "$UPDATER" || -L "$UPDATER" ]]; then
  if [[ ! -f "$UPDATER" ]] ||
    ! grep -Fq 'OPENCODE_TERMUX_UPDATER=1' "$UPDATER" ||
    ! grep -Fq 'install.sh' "$UPDATER"; then
    echo "Error: an unrecognized command already exists at $UPDATER." >&2
    echo "It has been left untouched. Identify its source, then rerun this installer." >&2
    exit 1
  fi
fi

# Protect the manager path too: never replace an unrelated command.
if [[ -e "$MANAGER" || -L "$MANAGER" ]]; then
  if [[ ! -f "$MANAGER" ]] || ! grep -Fq 'OPENCODE_TERMUX_MANAGER=1' "$MANAGER"; then
    echo "Error: an unrecognized command already exists at $MANAGER." >&2
    echo "It has been left untouched. Identify its source, then rerun this installer." >&2
    exit 1
  fi
fi

# Migrate only installations whose ownership can be established. Never
# overwrite an unknown command in PREFIX/bin: it may belong to another tool.
NPM_GLOBAL_ROOT=""
NPM_OPENCODE_PACKAGE=""
if command -v npm >/dev/null 2>&1; then
  NPM_GLOBAL_ROOT="$(npm root -g 2>/dev/null || true)"
  NPM_OPENCODE_PACKAGE="$NPM_GLOBAL_ROOT/opencode-termux"
fi

LEGACY_NPM_OWNS_COMMAND=0
if [[ -n "$NPM_GLOBAL_ROOT" && -f "$NPM_OPENCODE_PACKAGE/package.json" ]] &&
  node -e 'const p=require(process.argv[1]); process.exit(p.name === "opencode-termux" && (typeof p.bin === "string" || (p.bin && Object.prototype.hasOwnProperty.call(p.bin, "opencode"))) ? 0 : 1)' "$NPM_OPENCODE_PACKAGE/package.json"; then
  if [[ -L "$LAUNCHER" ]]; then
    LAUNCHER_TARGET="$(readlink -f "$LAUNCHER" 2>/dev/null || true)"
    case "$LAUNCHER_TARGET" in
      "$NPM_OPENCODE_PACKAGE"/*) LEGACY_NPM_OWNS_COMMAND=1 ;;
    esac
  fi
fi

if [[ "$LEGACY_NPM_OWNS_COMMAND" == 1 ]]; then

  run_quiet npm uninstall -g --ignore-scripts opencode-termux
fi

# Termux packages are identified through dpkg ownership, not by filename.
# Remove only known OpenCode package names; leave unknown package owners alone.
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]] && command -v dpkg-query >/dev/null 2>&1; then
  source "$REPO_DIR/scripts/package-owner.sh"
  PACKAGE_OWNER="$(get_dpkg_package_owner "$LAUNCHER")"
  case "$PACKAGE_OWNER" in
    opencode|opencode1|opencode-termux|opencode-wrapper|opencode1-wrapper)

      run_quiet pkg uninstall -y "$PACKAGE_OWNER"
      ;;
  esac
fi

# An existing launcher is replaceable only when it is a previous launcher
# from this project. A runtime marker or the distinctive managed launcher
# configuration establishes ownership. Unknown/manual launchers are preserved.
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
  MANAGED_LAUNCHER=0
  if [[ -f "$LAUNCHER" ]] &&
    grep -Fq 'OPENCODE_DISABLE_AUTOUPDATE=1' "$LAUNCHER" &&
    grep -Fq '/lib/opencode-termux' "$LAUNCHER"; then
    MANAGED_LAUNCHER=1
  fi
  if [[ "$MANAGED_LAUNCHER" != 1 ]]; then
    echo "Error: an unrecognized OpenCode command already exists at $LAUNCHER." >&2
    echo "It has been left untouched. Identify/uninstall its source, then rerun this installer." >&2
    exit 1
  fi
fi

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
if [[ -e "$MANAGER" || -L "$MANAGER" ]]; then
  MANAGER_WAS_PRESENT=1
  mv "$MANAGER" "$MANAGER_BACKUP"
fi
mv "$STAGE/opencode-launcher" "$LAUNCHER"
mv "$STAGE/opencode-termux-update" "$UPDATER"
mv "$STAGE/opencode-termux-manager" "$MANAGER"

# Enforce executable permissions at the final destination as well as in staging.
# This repairs restrictive umasks or stale non-executable manager files on upgrades.
chmod 755 "$LAUNCHER" "$UPDATER" "$MANAGER"
for executable in "$LAUNCHER" "$UPDATER" "$MANAGER"; do
  [[ -x "$executable" ]] || {
    echo "Error: installed command is not executable: $executable" >&2
    exit 1
  }
done

FINAL_VERSION="$( unset LD_PRELOAD; export LD_LIBRARY_PATH="$RUNTIME"; export SSL_CERT_FILE="$CERT"; "$RUNTIME/opencode" --version )" || { echo "Error: installed runtime failed final test." >&2; exit 1; }
[[ "$FINAL_VERSION" == "opencode v$VERSION" ]] || { echo "Error: installed runtime returned an unexpected version: $FINAL_VERSION" >&2; exit 1; }
if [[ -n "$BACKUP" ]]; then rm -rf "$BACKUP"; BACKUP=""; fi
rm -f "$LAUNCHER_BACKUP" "$UPDATER_BACKUP" "$MANAGER_BACKUP"
ui_finish
if (( UI_ENABLED == 0 )); then
  if [[ "$INSTALL_ACTION" == "updated" ]]; then
    printf 'OpenCode updated successfully. The update process completed successfully.\n'
  else
    printf 'OpenCode installed successfully.\n'
  fi
  printf 'Version: %s | Start: opencode | Manage: opencode-termux --help\n' "$VERSION"
fi
