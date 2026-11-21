#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: smoke test failed at line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR
if [[ $# -ne 3 ]]; then echo "Usage: $0 <native-bundle.tar.gz> <version> <new-workdir>" >&2; exit 64; fi
ARCHIVE=$1 VERSION=$2 WORKDIR=$3
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
case "$TARGET_ARCH" in
  aarch64)
    EXPECTED_ELF_MACHINE="AArch64"
    EXPECTED_ANDROID_LINKER="/system/bin/linker64"
    PTY_LIBRARY="librust_pty_arm64.so"
    ;;
  x86_64)
    EXPECTED_ELF_MACHINE="Advanced Micro Devices X86-64"
    EXPECTED_ANDROID_LINKER="/system/bin/linker64"
    PTY_LIBRARY="librust_pty_x86_64.so"
    ;;
  *)
    echo "Unsupported TARGET_ARCH '$TARGET_ARCH' (supported: aarch64, x86_64)" >&2
    exit 64
    ;;
esac
# The validator runs in a child shell; pass through the architecture selection.
export TARGET_ARCH
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 64; }
[[ ! -e "$WORKDIR" && "$WORKDIR" != / ]] || { echo "Work directory must be new" >&2; exit 64; }
for cmd in bash sh readelf sha256sum; do command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }; done
mkdir -p "$(dirname "$WORKDIR")"; mkdir "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT
STAGED="$WORKDIR/staged"
bash "$(dirname "$0")/validate-runtime-archive.sh" "$ARCHIVE" "$STAGED"
ROOT="$WORKDIR/runtime"
export ROOT
mkdir -p "$ROOT/bin" "$ROOT/lib"
mv "$STAGED/bin/opencode" "$ROOT/bin/opencode"
mv "$STAGED/lib/opencode" "$ROOT/lib/opencode"
chmod 755 "$ROOT/bin/opencode"
sh -n "$ROOT/bin/opencode"
for native in "$ROOT"/lib/opencode/*.so "$ROOT"/lib/opencode/*.node "$ROOT"/lib/opencode/opencode-pty; do
  [[ -f "$native" ]] || continue
  header="$(readelf -h "$native")"
  grep -q 'Class:.*ELF64' <<<"$header"
  grep -q 'Type:.*DYN' <<<"$header"
  grep -Eq "Machine:.*$EXPECTED_ELF_MACHINE" <<<"$header"
  alignments="$(readelf -lW "$native" | awk '$1 == "LOAD" { print $NF }')"
  [[ -n "$alignments" ]] || { echo "no PT_LOAD segments found in $native" >&2; exit 1; }
  if [[ "${REQUIRE_16KB_PAGE_ALIGNMENT:-1}" == "1" ]]; then
    while IFS= read -r alignment; do
      alignment="${alignment#0x}"
      if (( 16#$alignment < 16384 )); then
        echo "Android 16 KB page alignment missing in $native (PT_LOAD alignment 0x$alignment)" >&2
        exit 1
      fi
    done <<<"$alignments"
  fi
  if readelf -d "$native" 2>/dev/null | grep -Eq 'NEEDED.*libc\.so\.6'; then
    echo "glibc dependency found in Android module: $native" >&2; exit 1
  fi
done
# Check that the watcher exposes a registration mechanism understood by the
# N-API loader. The ARM64 prebuilt addon uses NODE_API_MODULE's constructor
# registration; the x86_64 source build exports the explicit N-API entry points.
watcher="$ROOT/lib/opencode/watcher.node"
watcher_symbols="$(readelf --dyn-syms --wide "$watcher")"
case "$TARGET_ARCH" in
  aarch64)
    if ! grep -Eq 'UND[[:space:]]+napi_module_register' <<<"$watcher_symbols"; then
      echo "ARM64 watcher is missing the N-API constructor registration import." >&2
      exit 1
    fi
    if ! readelf -SW "$watcher" | grep -Eq '\.init_array[[:space:]]+INIT_ARRAY'; then
      echo "ARM64 watcher is missing its N-API registration constructor table." >&2
      exit 1
    fi
    ;;
  x86_64)
    for symbol in napi_register_module_v1 node_api_module_get_api_version_v1; do
      if ! grep -Eq "GLOBAL[[:space:]]+DEFAULT[[:space:]]+[0-9]+[[:space:]]+$symbol([[:space:]]|$)" <<<"$watcher_symbols"; then
        echo "x86_64 watcher is missing exported N-API entry point: $symbol" >&2
        exit 1
      fi
    done
    ;;
esac

# The official opencode-pty daemon is an executable (not bun-pty's .so).
# New source-built candidates must contain it; published legacy archives can
# be smoke-tested with REQUIRE_OFFICIAL_PTY_DAEMON=0 during migration.
daemon="$ROOT/lib/opencode/opencode-pty"
if [[ -f "$daemon" ]]; then
  [[ -s "$daemon" && -x "$daemon" && -s "$ROOT/lib/opencode/opencode-pty.required" ]] || { echo "official opencode-pty daemon or marker missing" >&2; exit 1; }
  daemon_header="$(readelf -h "$daemon")"
  grep -q "Machine:.*$EXPECTED_ELF_MACHINE" <<<"$daemon_header"
  daemon_interpreter="$(readelf -l "$daemon" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
  [[ "$daemon_interpreter" == "$EXPECTED_ANDROID_LINKER" ]] || { echo "wrong opencode-pty Android interpreter: $daemon_interpreter" >&2; exit 1; }
  daemon_needed="$(readelf -d "$daemon" | awk '/NEEDED/{print $NF}')"
  if grep -Eq 'libc\.so\.6|ld-linux|libgcc_s\.so' <<<"$daemon_needed"; then echo "glibc dependency found in opencode-pty: $daemon_needed" >&2; exit 1; fi
elif [[ "${REQUIRE_OFFICIAL_PTY_DAEMON:-1}" == "1" ]]; then
  echo "official opencode-pty daemon missing from source-built candidate" >&2
  exit 1
else
  echo "WARN: testing a legacy archive predating the official opencode-pty daemon"
fi

# Exercise the shipped shell launcher without loading Android/Bionic modules
# on the Linux CI host. The stub verifies the module path and argument contract.
mkdir -p "$WORKDIR/prefix/bin"
cat > "$WORKDIR/prefix/bin/bun" <<'BUN'
#!/usr/bin/env bash
set -e
printf '%s\n' "$OPENCODE_ROOT" > "$BUN_TEST_LOG.root"
printf '%s\n' "$OPENCODE_LAUNCHER" > "$BUN_TEST_LOG.launcher"
printf '%s\n' "$BUN_PTY_LIB" > "$BUN_TEST_LOG.pty"
printf '%s\n' "$OPENCODE_DISABLE_AUTOUPDATE" > "$BUN_TEST_LOG.autoupdate"
printf '%s\n' "$*" > "$BUN_TEST_LOG.args"
if [[ "${*: -1}" == "--version" ]]; then echo "opencode v$BUN_TEST_VERSION"; fi
BUN
chmod 755 "$WORKDIR/prefix/bin/bun"
mkdir -p "$WORKDIR/stubs"
cat > "$WORKDIR/stubs/uname" <<'UNAME'
#!/usr/bin/env sh
printf '%s\n' "$BUN_TEST_ARCH"
UNAME
chmod 755 "$WORKDIR/stubs/uname"
export PREFIX="$WORKDIR/prefix" BUN_TEST_LOG="$WORKDIR/bun-test" BUN_TEST_VERSION="$VERSION"
export BUN_TEST_ARCH="$TARGET_ARCH"
export PATH="$WORKDIR/stubs:$PATH"
env -u OPENCODE_LAUNCHER bash "$ROOT/bin/opencode" --version > "$WORKDIR/version.txt"
if ! grep -Fxq "opencode v$VERSION" "$WORKDIR/version.txt"; then
  echo "Unexpected launcher version output:" >&2
  cat "$WORKDIR/version.txt" >&2
  echo "Bun stub invocation log:" >&2
  for log in "$BUN_TEST_LOG".*; do [[ -f "$log" ]] && { echo "--- $log" >&2; cat "$log" >&2; }; done
  exit 1
fi
grep -Fxq "$ROOT/lib/opencode" "$BUN_TEST_LOG.root"
grep -Fxq "$ROOT/bin/opencode" "$BUN_TEST_LOG.launcher"
grep -Fxq "$ROOT/lib/opencode/$PTY_LIBRARY" "$BUN_TEST_LOG.pty"
grep -Fxq 1 "$BUN_TEST_LOG.autoupdate"
grep -Fq -- '--smol' "$BUN_TEST_LOG.args"
grep -Fq -- "$ROOT/lib/opencode/index.js --version" "$BUN_TEST_LOG.args"
echo "PASS: Android $TARGET_ARCH ELF modules are Bionic shared libraries without glibc dependencies."
echo "PASS: native launcher resolves the installed bundle, selects Bun and forwards arguments."
cat "$WORKDIR/version.txt"
sha256sum "$ARCHIVE"
