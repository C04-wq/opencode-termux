#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PREFIX="$TMP/prefix"
mkdir -p "$PREFIX/etc/apt/sources.list.d" "$TMP/bin"

cat > "$TMP/bin/pkg" <<'PKG'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "update" && "$2" == "-y" ]]
echo "mock package index refresh"
PKG
chmod +x "$TMP/bin/pkg"
export PATH="$TMP/bin:$PATH"

cat > "$PREFIX/etc/apt/sources.list" <<'LIST'
# legacy Main repository comment must remain untouched
deb https://termux.net stable main
LIST

cat > "$PREFIX/etc/apt/sources.list.d/main.sources" <<'SOURCES'
Types: deb
URIs: https://termux.net/apt/termux-main
Suites: stable
Components: main
SOURCES

MIGRATION_FUNCTION="$(sed -n '/^migrate_legacy_termux_repository() {$/,/^}$/p' "$ROOT/install.sh")"
[[ -n "$MIGRATION_FUNCTION" ]]
eval "$MIGRATION_FUNCTION"
migrate_legacy_termux_repository

grep -Fq 'deb https://packages.termux.dev/apt/termux-main stable main' "$PREFIX/etc/apt/sources.list"
grep -Fq 'URIs: https://packages.termux.dev/apt/termux-main' "$PREFIX/etc/apt/sources.list.d/main.sources"
grep -Fq '# legacy Main repository comment must remain untouched' "$PREFIX/etc/apt/sources.list"
[[ -f "$PREFIX/etc/apt/sources.list.opencode-termux.bak" ]]
[[ -f "$PREFIX/etc/apt/sources.list.d/main.sources.opencode-termux.bak" ]]
! grep -Eiq '^[[:space:]]*(deb([[:space:]]|$)|URIs:[[:space:]]*)[^#]*https?://termux\\.net([/:[:space:]]|$)' "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.d/main.sources"

echo "PASS: legacy sources.list and modern deb822 main.sources are migrated and backed up."
