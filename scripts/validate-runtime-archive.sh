#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ARCHIVE="${1:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"
DESTINATION="${2:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"

EXPECTED_FILES=(
  opencode
  ld-musl-aarch64.so.1
  libc.musl-aarch64.so.1
  libgcc_s.so.1
  libstdc++.so.6
  libstdc++.so.6.runtime
)

[[ -f "$ARCHIVE" ]] || { echo "Error: runtime archive not found." >&2; exit 1; }
[[ ! -e "$DESTINATION" ]] || { echo "Error: extraction destination already exists." >&2; exit 1; }

LISTING="$(tar -tzf "$ARCHIVE")" || {
  echo "Error: runtime archive is corrupt or unreadable." >&2
  exit 1
}
mapfile -t ARCHIVE_FILES <<< "$LISTING"
if [[ "${#ARCHIVE_FILES[@]}" -ne "${#EXPECTED_FILES[@]}" ]]; then
  echo "Error: runtime archive contains an unexpected number of entries." >&2
  exit 1
fi

for file in "${ARCHIVE_FILES[@]}"; do
  case "$file" in
    opencode|ld-musl-aarch64.so.1|libc.musl-aarch64.so.1|libgcc_s.so.1|libstdc++.so.6|libstdc++.so.6.runtime) ;;
    *)
      echo "Error: unexpected runtime archive entry: $file" >&2
      exit 1
      ;;
  esac
done

for expected in "${EXPECTED_FILES[@]}"; do
  count=0
  for actual in "${ARCHIVE_FILES[@]}"; do
    [[ "$actual" == "$expected" ]] && ((count += 1))
  done
  [[ "$count" -eq 1 ]] || {
    echo "Error: runtime archive must contain exactly one $expected entry." >&2
    exit 1
  }
done

mkdir -p "$DESTINATION"
tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE" -C "$DESTINATION"

for file in "${EXPECTED_FILES[@]}"; do
  if [[ "$file" == "libstdc++.so.6" ]]; then
    if [[ ! -L "$DESTINATION/$file" || "$(readlink "$DESTINATION/$file")" != "libstdc++.so.6.runtime" ]]; then
      echo "Error: libstdc++.so.6 must link only to libstdc++.so.6.runtime." >&2
      exit 1
    fi
  elif [[ ! -f "$DESTINATION/$file" || -L "$DESTINATION/$file" || ! -s "$DESTINATION/$file" ]]; then
    echo "Error: runtime archive entry is not a non-empty regular file: $file" >&2
    exit 1
  fi
done
