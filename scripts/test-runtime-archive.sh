#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VALIDATOR="$ROOT/scripts/validate-runtime-archive.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES=(opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.runtime)
mkdir "$TMP/good"
for file in "${FILES[@]}"; do printf 'fixture:%s\n' "$file" > "$TMP/good/$file"; done
tar -czf "$TMP/good.tar.gz" -C "$TMP/good" "${FILES[@]}"
bash "$VALIDATOR" "$TMP/good.tar.gz" "$TMP/extracted"
for file in "${FILES[@]}"; do
  [[ -s "$TMP/extracted/$file" && ! -L "$TMP/extracted/$file" ]]
done
echo "PASS: valid runtime archive"

mkdir "$TMP/extra"
cp "$TMP/good/"* "$TMP/extra/"
printf 'unexpected\n' > "$TMP/extra/extra.txt"
tar -czf "$TMP/extra.tar.gz" -C "$TMP/extra" .
if bash "$VALIDATOR" "$TMP/extra.tar.gz" "$TMP/extra-out" >/dev/null 2>&1; then
  echo "FAIL: archive with extra paths was accepted" >&2
  exit 1
fi
echo "PASS: unexpected paths rejected"

mkdir "$TMP/traversal"
cp "$TMP/good/"* "$TMP/traversal/"
printf 'escape\n' > "$TMP/traversal/../outside"
tar -czf "$TMP/traversal.tar.gz" -C "$TMP/traversal" .
if bash "$VALIDATOR" "$TMP/traversal.tar.gz" "$TMP/traversal-out" >/dev/null 2>&1; then
  echo "FAIL: archive with traversal entry was accepted" >&2
  exit 1
fi
echo "PASS: traversal entries rejected"

mkdir "$TMP/symlink"
for file in "${FILES[@]}"; do
  if [[ "$file" == opencode ]]; then ln -s /etc/passwd "$TMP/symlink/$file"
  else printf 'fixture:%s\n' "$file" > "$TMP/symlink/$file"
  fi
done
tar -czf "$TMP/symlink.tar.gz" -C "$TMP/symlink" "${FILES[@]}"
if bash "$VALIDATOR" "$TMP/symlink.tar.gz" "$TMP/symlink-out" >/dev/null 2>&1; then
  echo "FAIL: archive containing a symlink was accepted" >&2
  exit 1
fi
echo "PASS: symbolic links rejected"
