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
BASE="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors "$BASE/" -o "$TMP/index.html"

ARCHIVE="$(grep -oE 'alpine-minirootfs-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.tar\.gz' "$TMP/index.html" | sort -Vu | tail -n 1)"
if [ -z "$ARCHIVE" ]; then
  echo "Error: no stable Alpine minirootfs found for branch v${BRANCH}." >&2
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
# The host rootfs is x86_64, while the package index being verified is aarch64.
# Fetch the official branch's ARM64 signing keys so apk can verify that index.
KEYS_BASE="https://gitlab.alpinelinux.org/alpine/aports/-/raw/${BRANCH}-stable/main/alpine-keys/aarch64"
sudo mkdir -p "$ROOT/usr/share/apk/keys/aarch64" "$ROOT/etc/apk/keys"
for key in \
  alpine-devel@lists.alpinelinux.org-58199dcc.rsa.pub \
  alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub; do
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors \
    "$KEYS_BASE/$key" -o "$TMP/$key"
  sudo install -m 0644 "$TMP/$key" "$ROOT/usr/share/apk/keys/aarch64/$key"
  sudo install -m 0644 "$TMP/$key" "$ROOT/etc/apk/keys/$key"
done
sudo chroot "$ROOT" /sbin/apk --version
echo "Prepared Alpine v${BRANCH} chroot at $ROOT"
