#!/usr/bin/env bash
# Exercise the real installer against an isolated Termux-like prefix and a
# checksum-verified candidate archive. No Android device or package downloads
# are required; only the OS/package/network boundaries are stubbed.
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: installer integration test failed at line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 ARCHIVE RELEASE_METADATA aarch64|x86_64" >&2
  exit 64
fi
ARCHIVE="$(realpath "$1")"
METADATA="$(realpath "$2")"
TARGET_ARCH="$3"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

case "$TARGET_ARCH" in
  aarch64) HASH_FIELD=archiveSha256; ARCHIVE_ARCH=aarch64 ;;
  x86_64) HASH_FIELD=archiveSha256X86_64; ARCHIVE_ARCH=x86_64 ;;
  *) echo "Unsupported architecture: $TARGET_ARCH" >&2; exit 64 ;;
esac
for cmd in bash git python3 sha256sum tar realpath; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing test dependency: $cmd" >&2; exit 1; }
done

mapfile -t metadata < <(python3 - "$METADATA" "$HASH_FIELD" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
version = data.get("version", "")
digest = data.get(sys.argv[2], "")
bun = data.get("bunVersion", "")
release = data.get("releaseTag", "")
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("invalid runtime version in candidate metadata")
if not re.fullmatch(r"[a-f0-9]{64}", digest):
    raise SystemExit("missing or invalid architecture-specific archive checksum")
if not re.fullmatch(r"\d+\.\d+\.\d+", bun):
    raise SystemExit("invalid Bun version in candidate metadata")
if not re.fullmatch(r"v" + re.escape(version) + r"(?:-[1-9]\d*)?", release):
    raise SystemExit("invalid release tag in candidate metadata")
if data.get("sourceRepo") != "C04-wq/opencode-termux" or data.get("sourceTag") != "v" + version:
    raise SystemExit("candidate metadata does not identify this project's matching source")
if data.get("runtimeId") != "android-bionic-bun-v1":
    raise SystemExit("candidate metadata has an unsupported runtime id")
print(version)
print(digest)
print(bun)
print(release)
PY
)
[[ "${#metadata[@]}" -eq 4 ]] || { echo "Incomplete release metadata" >&2; exit 1; }
VERSION="${metadata[0]}"
EXPECTED_SHA256="${metadata[1]}"
BUN_VERSION="${metadata[2]}"
RELEASE_TAG="${metadata[3]}"
ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || {
  echo "Candidate archive checksum does not match release metadata." >&2
  exit 1
}
[[ "$(basename "$ARCHIVE")" == "opencode-$VERSION-android-$ARCHIVE_ARCH-bundle.tar.gz" ]] || {
  echo "Candidate archive filename does not match version/architecture metadata." >&2
  exit 1
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
TEST_REPO="$WORK/repo"
PREFIX="$WORK/prefix"
STUBS="$WORK/stubs"
mkdir -p "$PREFIX/etc/tls" "$PREFIX/etc" "$STUBS"
git clone --local --quiet "$ROOT" "$TEST_REPO"
git -C "$TEST_REPO" remote set-url origin https://github.com/C04-wq/opencode-termux.git
cp "$METADATA" "$TEST_REPO/release-checksums.json"
printf 'test CA bundle\n' > "$PREFIX/etc/tls/cert.pem"
printf 'nameserver 1.1.1.1\n' > "$PREFIX/etc/resolv.conf"

cat > "$STUBS/uname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$OPENCODE_TEST_ARCH"
STUB
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
set -e
while (($#)); do
  if [[ "$1" == "-o" ]]; then
    cp "$OPENCODE_TEST_ARCHIVE" "$2"
    exit 0
  fi
  shift
done
echo "Unexpected curl invocation in installer integration test." >&2
exit 1
STUB
cat > "$STUBS/pkg" <<'STUB'
#!/usr/bin/env bash
set -e
mkdir -p "$PREFIX/bin" "$PREFIX/lib"
cat > "$PREFIX/bin/bun" <<'BUN'
#!/usr/bin/env bash
if [[ "$#" -eq 1 && "$1" == "--version" ]]; then
  printf '%s\n' "$OPENCODE_TEST_BUN_VERSION"
elif [[ "${*: -1}" == "--version" ]]; then
  printf 'opencode v%s\n' "$OPENCODE_TEST_VERSION"
fi
BUN
cat > "$PREFIX/bin/rg" <<'RG'
#!/usr/bin/env bash
exit 0
RG
printf 'libc++ test stub\n' > "$PREFIX/lib/libc++_shared.so"
chmod 0755 "$PREFIX/bin/bun" "$PREFIX/bin/rg"
STUB
chmod 0755 "$STUBS/"*

export PREFIX
export OPENCODE_TEST_ARCH="$TARGET_ARCH"
export OPENCODE_TEST_ARCHIVE="$ARCHIVE"
export OPENCODE_TEST_VERSION="$VERSION"
export OPENCODE_TEST_BUN_VERSION="$BUN_VERSION"
export PATH="$STUBS:$PREFIX/bin:$PATH"

bash "$TEST_REPO/install.sh"
test -x "$PREFIX/bin/opencode"
test -s "$PREFIX/lib/opencode-termux/lib/opencode/index.js"
test -x "$PREFIX/lib/opencode-termux/lib/opencode/opencode-pty"
test -s "$PREFIX/lib/opencode-termux/lib/opencode/opencode-pty.required"
test -s "$PREFIX/lib/opencode-termux/lib/opencode/$([[ "$TARGET_ARCH" == aarch64 ]] && echo librust_pty_arm64.so || echo librust_pty_x86_64.so)"
test "$(cat "$PREFIX/lib/opencode-termux/.opencode-termux-version")" = "$VERSION"
test "$(cat "$PREFIX/lib/opencode-termux/.opencode-termux-release-tag")" = "$RELEASE_TAG"
test "$(cat "$PREFIX/lib/opencode-termux/.opencode-termux-runtime-id")" = "android-bionic-bun-v1"
test "$(cat "$PREFIX/lib/opencode-termux/.opencode-termux-archive-sha256")" = "$EXPECTED_SHA256"
bash "$PREFIX/bin/opencode" --version | grep -Fxq "opencode v$VERSION"
test ! -e "$PREFIX/bin/opencode-termux"
test ! -e "$PREFIX/bin/opencode-termux-update"
echo "PASS: $TARGET_ARCH installer activated and executed OpenCode $VERSION from a verified candidate archive."
