#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat > "$TMP/bin/dpkg-query" <<'STUB'
#!/usr/bin/env bash
case "${DPKG_QUERY_MODE:-missing}" in
  missing) exit 1 ;;
  found) printf '%s: %s\n' "${DPKG_QUERY_PACKAGE:-opencode1}" "$2"; exit 0 ;;
  *) exit 2 ;;
esac
STUB
chmod 755 "$TMP/bin/dpkg-query"
export PATH="$TMP/bin:$PATH"
source "$ROOT/scripts/package-owner.sh"

export DPKG_QUERY_MODE=missing
[[ -z "$(get_dpkg_package_owner /some/path)" ]]
echo "PASS: missing dpkg owner is a normal empty result"

export DPKG_QUERY_MODE=found
export DPKG_QUERY_PACKAGE=opencode1
[[ "$(get_dpkg_package_owner /some/path)" == "opencode1" ]]
echo "PASS: known dpkg owner is parsed"
