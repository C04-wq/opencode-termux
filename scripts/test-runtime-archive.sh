#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VALIDATOR="$ROOT/scripts/validate-runtime-archive.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES=(opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.runtime)
make_fixture() {
  local dir="$1" link_target="${2:-libstdc++.so.6.runtime}"
  mkdir -p "$dir"
  for file in "${FILES[@]}"; do
    if [[ "$file" == "libstdc++.so.6" ]]; then
      ln -s "$link_target" "$dir/$file"
    elif [[ "$file" == "opencode" ]]; then
      # Minimal little-endian ELF64 header with e_type=ET_DYN (3).
      # The archive validator checks the ELF type before activation.
      printf '\\177ELF\\002\\001\\001\\000\\000\\000\\000\\000\\000\\000\\000\\000\\003\\000' > "$dir/$file"
    else
      printf 'fixture:%s\n' "$file" > "$dir/$file"
    fi
  done
}
expect_rejected() {
  local archive="$1" name="$2"
  local destination="$TMP/out-$name"
  if bash "$VALIDATOR" "$archive" "$destination" >/dev/null 2>&1; then
    echo "FAIL: $name archive was accepted" >&2
    exit 1
  fi
  [[ ! -e "$destination" && ! -L "$destination" ]] || {
    echo "FAIL: $name archive left an extraction destination behind" >&2
    exit 1
  }
  echo "PASS: $name archive rejected before extraction"
}

make_fixture "$TMP/good"
tar -czf "$TMP/good.tar.gz" -C "$TMP/good" "${FILES[@]}"
bash "$VALIDATOR" "$TMP/good.tar.gz" "$TMP/extracted"
for file in "${FILES[@]}"; do
  if [[ "$file" == "libstdc++.so.6" ]]; then
    [[ -L "$TMP/extracted/$file" && "$(readlink "$TMP/extracted/$file")" == "libstdc++.so.6.runtime" ]]
  else
    [[ -s "$TMP/extracted/$file" && ! -L "$TMP/extracted/$file" ]]
  fi
done
echo "PASS: valid runtime archive"

# Extra path, traversal, unexpected symlink, hardlink, and wrong allowed-link target.
mkdir "$TMP/extra"
cp -a "$TMP/good/." "$TMP/extra/"
printf 'extra\n' > "$TMP/extra/extra"
tar -czf "$TMP/extra.tar.gz" -C "$TMP/extra" "${FILES[@]}" extra
expect_rejected "$TMP/extra.tar.gz" extra

mkdir "$TMP/traversal"
cp -a "$TMP/good/." "$TMP/traversal/"
tar --transform='s|^opencode$|../outside|' -czf "$TMP/traversal.tar.gz" -C "$TMP/traversal" "${FILES[@]}"
expect_rejected "$TMP/traversal.tar.gz" traversal
[[ ! -e "$TMP/outside" ]]

mkdir "$TMP/badlink"
make_fixture "$TMP/badlink"
rm "$TMP/badlink/opencode"
ln -s /etc/passwd "$TMP/badlink/opencode"
tar -czf "$TMP/badlink.tar.gz" -C "$TMP/badlink" "${FILES[@]}"
expect_rejected "$TMP/badlink.tar.gz" badlink

mkdir "$TMP/wrongtarget"
make_fixture "$TMP/wrongtarget" /etc/passwd
tar -czf "$TMP/wrongtarget.tar.gz" -C "$TMP/wrongtarget" "${FILES[@]}"
expect_rejected "$TMP/wrongtarget.tar.gz" wrongtarget

mkdir "$TMP/hardlink"
make_fixture "$TMP/hardlink"
rm "$TMP/hardlink/opencode"
ln "$TMP/hardlink/libgcc_s.so.1" "$TMP/hardlink/opencode"
tar -czf "$TMP/hardlink.tar.gz" -C "$TMP/hardlink" "${FILES[@]}"
expect_rejected "$TMP/hardlink.tar.gz" hardlink
