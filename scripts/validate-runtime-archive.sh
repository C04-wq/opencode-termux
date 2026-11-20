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
[[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]] || {
  echo "Error: extraction destination already exists." >&2
  exit 1
}

# Inspect member types and names before extraction. The release format is
# intentionally flat: five regular files plus one exact, relative symlink.
# Reject directories, hardlinks, devices, FIFOs, extra paths and duplicates.
VERBOSE_LISTING="$(tar -tvzf "$ARCHIVE")" || {
  echo "Error: runtime archive is corrupt or unreadable." >&2
  exit 1
}
printf '%s\n' "$VERBOSE_LISTING" | awk '
  BEGIN {
    expected["opencode"] = "file"
    expected["ld-musl-aarch64.so.1"] = "file"
    expected["libc.musl-aarch64.so.1"] = "file"
    expected["libgcc_s.so.1"] = "file"
    expected["libstdc++.so.6"] = "link"
    expected["libstdc++.so.6.runtime"] = "file"
  }
  {
    type = substr($1, 1, 1)
    name = $6
    if (!(name in expected)) {
      printf "Error: unexpected runtime archive entry: %s\n", name > "/dev/stderr"
      exit 1
    }
    if (++seen[name] != 1) {
      printf "Error: duplicate runtime archive entry: %s\n", name > "/dev/stderr"
      exit 1
    }
    if (expected[name] == "file" && type != "-") {
      printf "Error: runtime entry must be a regular file: %s\n", name > "/dev/stderr"
      exit 1
    }
    if (expected[name] == "link" &&
        (type != "l" || $7 != "->" || $8 != "libstdc++.so.6.runtime" || NF != 8)) {
      printf "Error: libstdc++.so.6 must be the exact relative symlink to libstdc++.so.6.runtime\n" > "/dev/stderr"
      exit 1
    }
  }
  END {
    if (NR != 6) {
      print "Error: runtime archive must contain exactly six entries." > "/dev/stderr"
      exit 1
    }
    for (name in expected) {
      if (seen[name] != 1) {
        printf "Error: runtime archive is missing required entry: %s\n", name > "/dev/stderr"
        exit 1
      }
    }
  }
' || exit 1

mkdir -p "$DESTINATION"
if ! tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE" -C "$DESTINATION"; then
  rm -rf "$DESTINATION"
  echo "Error: runtime archive extraction failed." >&2
  exit 1
fi

# Termux rejects ET_EXEC before the bundled musl interpreter can run.
ELF_TYPE="$(od -An -tu2 -j16 -N2 "$DESTINATION/opencode" | tr -d '[:space:]')"
if [[ "$ELF_TYPE" != "3" ]]; then
  rm -rf "$DESTINATION"
  echo "Error: OpenCode must be position-independent (ET_DYN=3); found ${ELF_TYPE:-unknown}." >&2
  echo "This package cannot run natively in Termux; refusing to activate it." >&2
  exit 1
fi

for file in "${EXPECTED_FILES[@]}"; do
  if [[ "$file" == "libstdc++.so.6" ]]; then
    if [[ ! -L "$DESTINATION/$file" || "$(readlink "$DESTINATION/$file")" != "libstdc++.so.6.runtime" ]]; then
      rm -rf "$DESTINATION"
      echo "Error: libstdc++.so.6 must link only to libstdc++.so.6.runtime." >&2
      exit 1
    fi
  elif [[ ! -f "$DESTINATION/$file" || -L "$DESTINATION/$file" || ! -s "$DESTINATION/$file" ]]; then
    rm -rf "$DESTINATION"
    echo "Error: runtime archive entry is not a non-empty regular file: $file" >&2
    exit 1
  fi
done
