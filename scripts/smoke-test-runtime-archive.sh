#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: smoke test failed at line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR
if [[ $# -ne 3 ]]; then echo "Usage: $0 <native-bundle.tar.gz> <version> <new-workdir>" >&2; exit 64; fi
ARCHIVE=$1 VERSION=$2 WORKDIR=$3
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
case "$TARGET_ARCH" in
  aarch64)
    EXPECTED_ELF_MACHINE="AArch64"
    PTY_LIBRARY="librust_pty_arm64.so"
    ;;
  x86_64)
    EXPECTED_ELF_MACHINE="Advanced Micro Devices X86-64"
    PTY_LIBRARY="librust_pty_x86_64.so"
    ;;
  *)
    echo "Unsupported TARGET_ARCH '$TARGET_ARCH' (supported: aarch64, x86_64)" >&2
    exit 64
    ;;
esac
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
for native in "$ROOT"/lib/opencode/*.so "$ROOT"/lib/opencode/*.node; do
  [[ -f "$native" ]] || continue
  header="$(readelf -h "$native")"
  grep -q 'Class:.*ELF64' <<<"$header"
  grep -q 'Type:.*DYN' <<<"$header"
  grep -Eq "Machine:.*$EXPECTED_ELF_MACHINE" <<<"$header"
  if readelf -d "$native" 2>/dev/null | grep -Eq 'NEEDED.*libc\.so\.6'; then
    echo "glibc dependency found in Android module: $native" >&2; exit 1
  fi
done
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
export PREFIX="$WORKDIR/prefix" BUN_TEST_LOG="$WORKDIR/bun-test" BUN_TEST_VERSION="$VERSION"
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
