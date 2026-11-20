#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ARCHIVE="${1:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"
DESTINATION="${2:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"
[[ -f "$ARCHIVE" ]] || { echo "Error: native runtime archive not found." >&2; exit 1; }
[[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]] || { echo "Error: extraction destination already exists." >&2; exit 1; }

# Upstream tar layout: bin/opencode and a flat lib/ module directory.
# Validate all names and member types before extracting any content.
LISTING="$(tar -tzf "$ARCHIVE")" || { echo "Error: native runtime archive is corrupt." >&2; exit 1; }
printf '%s\n' "$LISTING" | awk '
  BEGIN { ok=1 }
  {
    name=$0
    sub(/\/$/, "", name)
    if (name == "" || name ~ /^\// || name ~ /(^|\/)\.\.(\/|$)/ ||
        name ~ /(^|\/)\.($|\/)/ ||
        !(name == "bin" || name == "bin/opencode" || name == "lib" || name ~ /^lib\//)) {
      printf "Error: unsafe or unexpected archive path: %s\n", $0 > "/dev/stderr"
      ok=0
    }
    if (++seen[$0] != 1) {
      printf "Error: duplicate archive path: %s\n", $0 > "/dev/stderr"
      ok=0
    }
  }
  END { if (NR < 5 || !ok) exit 1 }
' || exit 1

VERBOSE="$(tar -tvzf "$ARCHIVE")" || { echo "Error: cannot inspect archive member types." >&2; exit 1; }
printf '%s\n' "$VERBOSE" | awk '
  {
    type=substr($1,1,1)
    name=$6
    if (type != "-" && type != "d") {
      printf "Error: links and special files are not allowed: %s\n", name > "/dev/stderr"
      exit 1
    }
  }
' || exit 1

for required in bin/opencode lib/index.js lib/bunfig.toml lib/librust_pty_arm64.so lib/watcher.node; do
  printf '%s\n' "$LISTING" | grep -Fxq "$required" || {
    echo "Error: required runtime entry is missing: $required" >&2
    exit 1
  }
done
printf '%s\n' "$LISTING" | grep -Eq '^lib/[^/]+\.so$' || {
  echo "Error: native Android shared libraries are missing." >&2
  exit 1
}

mkdir -p "$DESTINATION"
if ! tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE" -C "$DESTINATION"; then
  rm -rf "$DESTINATION"
  echo "Error: native runtime extraction failed." >&2
  exit 1
fi
for path in bin/opencode lib/index.js lib/bunfig.toml lib/librust_pty_arm64.so lib/watcher.node; do
  if [[ ! -f "$DESTINATION/$path" || -L "$DESTINATION/$path" || ! -s "$DESTINATION/$path" ]]; then
    rm -rf "$DESTINATION"
    echo "Error: required runtime file is missing or invalid: $path" >&2
    exit 1
  fi
done
echo "Native Android bundle structure verified."
