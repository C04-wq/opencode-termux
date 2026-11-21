#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Report the exact failing activation step before the EXIT trap rolls back.
trap 'status=$?; printf "Error: installer failed at line %s (exit %s): %s\\n" "$LINENO" "$status" "$BASH_COMMAND" >&2' ERR

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd -P)"
else
  SCRIPT_DIR=""
fi
REPO_DIR="$SCRIPT_DIR"

# Reject unsupported devices before invoking pkg, which may trigger mirror setup.
DEVICE_ARCH="$(uname -m)"
case "$DEVICE_ARCH" in
  aarch64) TARGET_ARCH="aarch64"; HASH_FIELD="archiveSha256" ;;
  x86_64) TARGET_ARCH="x86_64"; HASH_FIELD="archiveSha256X86_64" ;;
  *)
    echo "Error: unsupported architecture '$DEVICE_ARCH'. Supported architectures: aarch64 (ARM64) and x86_64." >&2
    exit 1
    ;;
esac

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

# Migrate the obsolete termux.net Main repository before attempting package
# installation. That endpoint can return a successful but incomplete index, so
# pkg update alone does not make current packages such as bun discoverable.
migrate_legacy_termux_repository() {
  local sources_dir file backup suffix update_log status changed=0
  sources_dir="$PREFIX/etc/apt/sources.list.d"

  # Current Termux uses deb822 files (main.sources); older installs may use
  # sources.list or *.list. Inspect all three formats.
  for file in "$PREFIX/etc/apt/sources.list" "$sources_dir"/*.list "$sources_dir"/*.sources; do
    [[ -f "$file" ]] || continue

    # Only active Main repository declarations are rewritten. Preserve comments
    # and unrelated repositories, including root and X11.
    if grep -Eiq '^[[:space:]]*(deb([[:space:]]|$)|URIs:[[:space:]]*)[^#]*https?://termux\.net([/:[:space:]]|$)' "$file"; then
      backup="${file}.opencode-termux.bak"
      suffix=0
      while [[ -e "$backup" ]]; do
        suffix=$((suffix + 1))
        backup="${file}.opencode-termux.bak.${suffix}"
      done
      cp -p "$file" "$backup"

      if ! sed -i -E \
        -e '/^[[:space:]]*deb([[:space:]]|$)/ s#https?://termux\.net(/apt/termux-main)?#https://packages.termux.dev/apt/termux-main#g' \
        -e '/^[[:space:]]*URIs:[[:space:]]*/ s#https?://termux\.net(/apt/termux-main)?#https://packages.termux.dev/apt/termux-main#g' \
        "$file"; then
        cp -p "$backup" "$file"
        echo "Error: could not migrate the obsolete Termux repository in $file." >&2
        return 1
      fi

      if grep -Eiq '^[[:space:]]*(deb([[:space:]]|$)|URIs:[[:space:]]*)[^#]*https?://termux\.net([/:[:space:]]|$)' "$file"; then
        cp -p "$backup" "$file"
        echo "Error: legacy termux.net source remains in $file; refusing to continue." >&2
        return 1
      fi

      changed=1
      echo "Updated obsolete Termux Main repository in $file"
      echo "Backup: $backup"
    fi
  done

  if [[ "$changed" == 1 ]]; then
    echo "Refreshing the official Termux Main repository (packages.termux.dev)..."
    update_log="$(mktemp)"
    if pkg update -y >"$update_log" 2>&1; then
      cat "$update_log"
      rm -f "$update_log"
    else
      status=$?
      cat "$update_log" >&2
      rm -f "$update_log"
      echo "Error: the official Termux Main repository could not be refreshed." >&2
      echo "Check connectivity, then run: pkg update" >&2
      return "$status"
    fi
  fi
}

# Install Termux dependencies. If a package is missing from stale local
# indexes, refresh the repository metadata once and retry before failing.
APT_INDEX_REFRESHED=0
install_termux_packages() {
  local log status update_log
  migrate_legacy_termux_repository
  log="$(mktemp)"
  if pkg install -y "$@" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  else
    status=$?
  fi

  if [[ "$APT_INDEX_REFRESHED" == 0 ]] &&
     grep -Eiq 'Unable to locate package|has no installation candidate|Package .* is not available' "$log"; then
    rm -f "$log"
    APT_INDEX_REFRESHED=1
    echo "A required Termux package was not found in the local package index; refreshing repositories..."
    update_log="$(mktemp)"
    if pkg update -y >"$update_log" 2>&1; then
      cat "$update_log"
      rm -f "$update_log"
    else
      status=$?
      cat "$update_log" >&2
      rm -f "$update_log"
      echo "Error: could not refresh Termux package indexes." >&2
      echo "Check your connection and repository selection with: termux-change-repo" >&2
      return "$status"
    fi

    log="$(mktemp)"
    if pkg install -y "$@" >"$log" 2>&1; then
      rm -f "$log"
      return 0
    else
      status=$?
    fi
  fi

  cat "$log" >&2
  if grep -Eiq '404 Not Found|binary-(aarch64|x86_64)/Packages' "$log"; then
    echo "The selected Termux mirror does not provide the $DEVICE_ARCH package index." >&2
    echo "Run: termux-change-repo" >&2
    echo "Select Main repository and choose the official packages.termux.dev mirror (or packages-cf.termux.dev)." >&2
    echo "Then run: pkg update" >&2
  elif grep -Eiq 'Unable to locate package|has no installation candidate|Package .* is not available' "$log"; then
    echo "Error: required Termux package(s) are still unavailable after refreshing package indexes: $*" >&2
    echo "Use the official Main repository and update Termux with: pkg upgrade" >&2
  fi
  rm -f "$log"
  return "$status"
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
    install_termux_packages git
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
[[ -f "$META" ]] || { echo "Error: release-checksums.json missing." >&2; exit 1; }
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
if [[ -n "${OPENCODE_TERMUX_EXPECTED_VERSION:-}" && "$VERSION" != "$OPENCODE_TERMUX_EXPECTED_VERSION" ]]; then
  echo "Error: requested Termux runtime $OPENCODE_TERMUX_EXPECTED_VERSION, but repository metadata currently selects $VERSION. Refusing to install a different release." >&2
  exit 1
fi
HASH="$(sed -n "s/.*\"$HASH_FIELD\"[[:space:]]*:[[:space:]]*\"\\([a-f0-9]*\\)\".*/\\1/p" "$META" | head -n1)"
SOURCE_REPO_PIN="$(sed -n 's/.*"sourceRepo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
SOURCE_TAG="$(sed -n 's/.*"sourceTag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
RELEASE_TAG="$(sed -n 's/.*"releaseTag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
RUNTIME_ID="$(sed -n 's/.*"runtimeId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$META" | head -n1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Error: invalid version." >&2; exit 1; }
if [[ ! "$HASH" =~ ^[a-f0-9]{64}$ ]]; then
  if [[ "$TARGET_ARCH" == "x86_64" ]]; then
    echo "Error: no verified x86_64 runtime is published for OpenCode $VERSION yet. Automated x86_64 build and release validation must complete before installation." >&2
  else
    echo "Error: invalid or missing ARM64 archive checksum in release metadata." >&2
  fi
  exit 1
fi
[[ "$SOURCE_TAG" == "v$VERSION" ]] || {
  echo "Error: native runtime source tag does not match the pinned version." >&2
  exit 1
}
if [[ "$RELEASE_TAG" != "v$VERSION" ]]; then
  RELEASE_REVISION="${RELEASE_TAG#v$VERSION-}"
  [[ "$RELEASE_TAG" == "v$VERSION-"* && "$RELEASE_REVISION" =~ ^[1-9][0-9]*$ ]] || {
    echo "Error: package release tag does not match the pinned version." >&2
    exit 1
  }
fi
[[ "$SOURCE_REPO_PIN" == "C04-wq/opencode-termux" && "$RUNTIME_ID" == "android-bionic-bun-v1" ]] || {
  echo "Error: native runtime source is not an approved release." >&2
  exit 1
}
for cmd in git curl tar sha256sum sed find grep awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in sha256sum) package="coreutils" ;; *) package="$cmd" ;; esac
    install_termux_packages "$package"
  fi
done
# The native bundle runs on Termux Bun and loads Bionic modules at runtime.
if ! command -v bun >/dev/null 2>&1 || ! command -v rg >/dev/null 2>&1 || [[ ! -s "$PREFIX/lib/libc++_shared.so" ]]; then
  echo "Preparing native runtime dependencies..."
  install_termux_packages bun ripgrep libc++
fi
for cmd in git curl tar sha256sum sed find grep awk bun rg; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done
[[ -s "$PREFIX/lib/libc++_shared.so" ]] || { echo "Termux libc++ shared library is missing." >&2; exit 1; }
[[ -f "$CERT" ]] || install_termux_packages ca-certificates
[[ -f "$RESOLVER" ]] || install_termux_packages resolv-conf
[[ -f "$CERT" && -f "$RESOLVER" ]] || { echo "Termux TLS/resolver files are missing." >&2; exit 1; }

STAGE="$(mktemp -d)"
BACKUP=""
NEW=""
ACTIVATED=0
LAUNCHER="$PREFIX/bin/opencode"
LAUNCHER_BACKUP="$PREFIX/bin/.opencode-backup-$BASHPID"
LAUNCHER_WAS_PRESENT=0
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
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
ARCHIVE="opencode-$VERSION-android-$TARGET_ARCH-bundle.tar.gz"
URL="https://github.com/$SOURCE_REPO_PIN/releases/download/$RELEASE_TAG/$ARCHIVE"
echo "Downloading OpenCode $VERSION..."
curl --fail --location --silent --show-error --retry 3 --retry-all-errors --proto '=https' --proto-redir '=https' "$URL" -o "$STAGE/runtime.tar.gz"
ACTUAL="$(sha256sum "$STAGE/runtime.tar.gz" | awk '{print $1}')"
[[ "$ACTUAL" == "$HASH" ]] || { echo "Error: SHA-256 mismatch; refusing to install." >&2; exit 1; }
echo "Verifying package integrity... OK"
TARGET_ARCH="$TARGET_ARCH" bash "$REPO_DIR/scripts/validate-runtime-archive.sh" "$STAGE/runtime.tar.gz" "$STAGE/files"
# Release assets are built with a prefix placeholder so the same pinned bundle
# works in every Termux installation path.
find "$STAGE/files/lib/opencode" -type f -name '*.js' -exec \
  sed -i "s|@TERMUX_PREFIX@/lib/opencode|$RUNTIME/lib/opencode|g" {} +
if grep -rlq '@TERMUX_PREFIX@' "$STAGE/files/lib/opencode"; then
  echo "Error: native bundle contains an unresolved install path." >&2
  exit 1
fi
chmod 755 "$STAGE/files/bin/opencode"
echo "Native runtime package prepared; executable test will run after activation."

mkdir -p "$PREFIX/lib" "$PREFIX/bin"
NEW="$PREFIX/lib/.opencode-termux-new-$$"
rm -rf "$NEW"; mkdir -p "$NEW"
cp -a "$STAGE/files/bin" "$NEW/bin"
mkdir -p "$NEW/lib"
cp -a "$STAGE/files/lib/opencode" "$NEW/lib/opencode"
printf '%s\n' "$VERSION" > "$NEW/.opencode-termux-version"
chmod 600 "$NEW/.opencode-termux-version"
printf '%s\n' "$REPO_DIR" > "$NEW/.opencode-termux-repo-dir"
chmod 600 "$NEW/.opencode-termux-repo-dir"
printf '%s\n' "$RUNTIME_ID" > "$NEW/.opencode-termux-runtime-id"
chmod 600 "$NEW/.opencode-termux-runtime-id"
printf '%s\n' "$HASH" > "$NEW/.opencode-termux-archive-sha256"
chmod 600 "$NEW/.opencode-termux-archive-sha256"
cp "$REPO_DIR/THIRD_PARTY_NOTICES.md" "$NEW/THIRD_PARTY_NOTICES.md"
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
export SSL_CERT_FILE="/data/data/com.termux/files/usr/etc/tls/cert.pem"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export OPENCODE_LAUNCHER="$PREFIX/bin/opencode"
RUNTIME="$PREFIX/lib/opencode-termux"

exec "$RUNTIME/bin/opencode" "$@"
LAUNCHER
chmod 755 "$STAGE/opencode-launcher"

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
  echo "Found legacy npm installation (opencode-termux); replacing it..."
  run_quiet npm uninstall -g --ignore-scripts opencode-termux
fi

# Termux packages are identified through dpkg ownership, not by filename.
# Remove only known OpenCode package names; leave unknown package owners alone.
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]] && command -v dpkg-query >/dev/null 2>&1; then
  source "$REPO_DIR/scripts/package-owner.sh"
  PACKAGE_OWNER="$(get_dpkg_package_owner "$LAUNCHER")"
  case "$PACKAGE_OWNER" in
    opencode|opencode1|opencode-termux|opencode-wrapper|opencode1-wrapper)
      echo "Found Termux package installation ($PACKAGE_OWNER); replacing it..."
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
mv "$STAGE/opencode-launcher" "$LAUNCHER"

# Enforce executable permissions at the final destination as well as in staging.
# This repairs restrictive umasks or stale non-executable launcher files on upgrades.
chmod 755 "$LAUNCHER"
[[ -x "$LAUNCHER" ]] || {
  echo "Error: installed command is not executable: $LAUNCHER" >&2
  exit 1
}

echo "Checking installed runtime..."
FINAL_VERSION="$( unset LD_PRELOAD; export SSL_CERT_FILE="$CERT"; "$RUNTIME/bin/opencode" --version )" || { echo "Error: installed runtime failed final test." >&2; exit 1; }
[[ "$FINAL_VERSION" == "opencode v$VERSION" ]] || { echo "Error: installed runtime returned an unexpected version: $FINAL_VERSION" >&2; exit 1; }
# Remove only recognizable legacy project commands. Never delete unrelated files.
if [[ -f "$PREFIX/bin/opencode-termux-update" ]] &&
   grep -Fq 'git -C' "$PREFIX/bin/opencode-termux-update" &&
   grep -Fq 'install.sh' "$PREFIX/bin/opencode-termux-update"; then
  rm -f "$PREFIX/bin/opencode-termux-update"
fi
if [[ -f "$PREFIX/bin/opencode-termux" ]] &&
   grep -Fq 'OPENCODE_TERMUX_MANAGER=1' "$PREFIX/bin/opencode-termux"; then
  rm -f "$PREFIX/bin/opencode-termux"
fi
if [[ -n "$BACKUP" ]]; then rm -rf "$BACKUP"; BACKUP=""; fi
rm -f "$LAUNCHER_BACKUP"
echo "OpenCode $VERSION installed successfully."
echo "Start: opencode"
echo "Update: opencode update"
