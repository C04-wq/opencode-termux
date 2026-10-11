#!/usr/bin/env bash
# Bootstrap Alpine from its official mirror without Docker or third-party actions.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <alpine-stable-branch> <rootfs-directory>" >&2
  exit 64
fi
BRANCH="$1"
ROOT="$2"
if ! [[ "$BRANCH" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Error: invalid Alpine stable branch: $BRANCH" >&2
  exit 64
fi
BASE="https://dl-cdn.alpinelinux.org/alpine/v\${BRANCH}/releases/x86_64"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors "$BASE/" -o "$TMP/index.html"
BRANCH_RE="$(printf '%s' "$BRANCH" | sed 's/\./\\./g')"
ARCHIVE="$(grep -oE 'alpine-minirootfs-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.tar\.gz' "$TMP/index.html" | grep -E "^alpine-minirootfs-\${BRANCH_RE}\.[0-9]+-x86_64\.tar\.gz$" | sort -Vu | tail -n 1)"
if [ -z "$ARCHIVE" ]; then
  echo "Error: no stable Alpine minirootfs found for branch v\${BRANCH}." >&2
  exit 1
fi
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors "$BASE/$ARCHIVE" -o "$TMP/$ARCHIVE"
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors "$BASE/$ARCHIVE.sha256" -o "$TMP/$ARCHIVE.sha256"
(cd "$TMP" && sha256sum --check "$ARCHIVE.sha256")
sudo rm -rf "$ROOT"
sudo mkdir -p "$ROOT"
sudo tar -xzf "$TMP/$ARCHIVE" -C "$ROOT"
sudo rm -f "$ROOT/etc/resolv.conf"
sudo cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
sudo chroot "$ROOT" /sbin/apk --version
echo "Prepared Alpine v\${BRANCH} chroot at $ROOT"
