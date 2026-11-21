#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ARCHIVE="${1:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"
DESTINATION="${2:?Usage: validate-runtime-archive.sh ARCHIVE DESTINATION}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"

case "$TARGET_ARCH" in
  aarch64)
    PTY_LIBRARY="librust_pty_arm64.so"
    OTHER_PTY_LIBRARY="librust_pty_x86_64.so"
    ;;
  x86_64)
    PTY_LIBRARY="librust_pty_x86_64.so"
    OTHER_PTY_LIBRARY="librust_pty_arm64.so"
    ;;
  *)
    echo "Error: unsupported TARGET_ARCH '$TARGET_ARCH' (supported: aarch64, x86_64)." >&2
    exit 2
    ;;
esac

[[ -f "$ARCHIVE" ]] || { echo "Error: native runtime archive not found." >&2; exit 1; }
[[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]] || {
  echo "Error: extraction destination already exists." >&2
  exit 1
}

# Validate every member before extraction to reject traversal and special files.
LISTING="$(tar -tzf "$ARCHIVE")" || {
  echo "Error: native runtime archive is corrupt." >&2
  exit 1
}
printf '%s\n' "$LISTING" | awk '
  BEGIN { ok=1 }
  {
    name=$0
    sub(/\/$/, "", name)
    if (name == "" || name ~ /^\// || name ~ /(^|\/)\.\.(\/|$)/ ||
        name ~ /(^|\/)\.($|\/)/ ||
        !(name == "bin" || name == "bin/opencode" ||
          name == "lib" || name == "lib/opencode" || name ~ /^lib\/opencode\//)) {
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

VERBOSE="$(tar -tvzf "$ARCHIVE")" || {
  echo "Error: cannot inspect archive member types." >&2
  exit 1
}
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

for required in bin/opencode lib/opencode/index.js lib/opencode/bunfig.toml "lib/opencode/$PTY_LIBRARY" lib/opencode/watcher.node; do
  printf '%s\n' "$LISTING" | grep -Fxq "$required" || {
    echo "Error: required runtime entry is missing: $required" >&2
    exit 1
  }
done

if printf '%s\n' "$LISTING" | grep -Fxq "lib/opencode/$OTHER_PTY_LIBRARY"; then
  echo "Error: archive contains a PTY library for the other architecture: $OTHER_PTY_LIBRARY" >&2
  exit 1
fi

printf '%s\n' "$LISTING" | grep -Eq '^lib/opencode/[^/]+\.so$' || {
  echo "Error: native Android shared libraries are missing." >&2
  exit 1
}

mkdir -p "$DESTINATION"
if ! tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE" -C "$DESTINATION"; then
  rm -rf "$DESTINATION"
  echo "Error: native runtime extraction failed." >&2
  exit 1
fi

for path in bin/opencode lib/opencode/index.js "lib/opencode/$PTY_LIBRARY" lib/opencode/watcher.node; do
  if [[ ! -f "$DESTINATION/$path" || -L "$DESTINATION/$path" || ! -s "$DESTINATION/$path" ]]; then
    rm -rf "$DESTINATION"
    echo "Error: required runtime file is missing or invalid: $path" >&2
    exit 1
  fi
done
if [[ ! -f "$DESTINATION/lib/opencode/bunfig.toml" || -L "$DESTINATION/lib/opencode/bunfig.toml" ]]; then
  rm -rf "$DESTINATION"
  echo "Error: Bun configuration is missing or invalid." >&2
  exit 1
fi
if [[ ! -x "$DESTINATION/bin/opencode" ]]; then
  rm -rf "$DESTINATION"
  echo "Error: runtime launcher is not executable." >&2
  exit 1
fi

daemon="$DESTINATION/lib/opencode/opencode-pty"
daemon_marker="$DESTINATION/lib/opencode/opencode-pty.required"
if [[ -e "$daemon" || -e "$daemon_marker" ]]; then
  if [[ ! -f "$daemon" || -L "$daemon" || ! -x "$daemon" || ! -f "$daemon_marker" || -L "$daemon_marker" || ! -s "$daemon_marker" ]]; then
    rm -rf "$DESTINATION"
    echo "Error: official opencode-pty daemon and requirement marker must be packaged together and executable." >&2
    exit 1
  fi
fi

echo "Native Android $TARGET_ARCH bundle structure verified."
