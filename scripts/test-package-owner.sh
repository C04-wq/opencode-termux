#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat > "$TMP/bin/dpkg-query" <<'STUB'
#!/data/data/com.termux/files/usr/bin/bash
case "${DPKG_QUERY_MODE:-missing}" in
  missing) exit 1 ;;
  found) printf '%s: /data/data/com.termux/files/usr/bin/opencode\n' "${DPKG_QUERY_PACKAGE:-opencode1}"; exit 0 ;;
esac
STUB
chmod 755 "$TMP/bin/dpkg-query"
PATH="$TMP/bin:$PATH"
source "$ROOT/scripts/package-owner.sh"

DPKG_QUERY_MODE=missing
[[ -z "$(get_dpkg_package_owner /some/path)" ]]
echo "PASS: missing dpkg owner is a normal empty result"

DPKG_QUERY_MODE=found
DPKG_QUERY_PACKAGE=opencode1
[[ "$(get_dpkg_package_owner /some/path)" == "opencode1" ]]
echo "PASS: known dpkg owner is parsed"
