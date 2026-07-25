#!/usr/bin/env bash
# Creates a Termux-compatible ARM64 package from OpenCode's official musl build.
#
# Android does not expose /etc/resolv.conf.  A stock musl resolver therefore
# falls back to localhost and OpenCode cannot reach model APIs from Termux.  We
# build the small musl runtime used by this package with Termux's resolver path.
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <opencode-version> <output-tarball> [official-archive-sha256]" >&2
  exit 64
fi

VERSION="$1"
OUTPUT="$2"
EXPECTED_UPSTREAM_SHA256="${3:-}"
ALPINE_VERSION="3.21"
ALPINE_REPO="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main/aarch64"
MUSL_VERSION="1.2.5"
MUSL_SHA256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"
TERMUX_RESOLV_CONF="/data/data/com.termux/files/usr/etc/resolv.conf"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/upstream" "$WORKDIR/root" "$WORKDIR/stage"
curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors \
  "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-arm64-musl.tar.gz" \
  -o "$WORKDIR/upstream.tar.gz"
if [ -n "$EXPECTED_UPSTREAM_SHA256" ]; then
  ACTUAL_UPSTREAM_SHA256="$(sha256sum "$WORKDIR/upstream.tar.gz" | awk '{print $1}')"
  if [ "$ACTUAL_UPSTREAM_SHA256" != "$EXPECTED_UPSTREAM_SHA256" ]; then
    echo "Error: official archive checksum does not match GitHub's release metadata." >&2
    exit 1
  fi
fi
tar -xzf "$WORKDIR/upstream.tar.gz" -C "$WORKDIR/upstream"

if [ ! -x "$WORKDIR/upstream/opencode" ]; then
  echo "Error: the official archive does not contain an executable named opencode." >&2
  exit 1
fi

curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors "$ALPINE_REPO/APKINDEX.tar.gz" -o "$WORKDIR/APKINDEX.tar.gz"
tar -xzf "$WORKDIR/APKINDEX.tar.gz" -C "$WORKDIR"

apk_version() {
  awk -v package="$1" '
    $0 == "P:" package { found = 1; next }
    found && /^V:/ { sub(/^V:/, ""); print; exit }
    /^$/ { found = 0 }
  ' "$WORKDIR/APKINDEX"
}

fetch_apk() {
  local package="$1"
  local version
  version="$(apk_version "$package")"
  if [ -z "$version" ]; then
    echo "Error: Alpine package $package was not found." >&2
    exit 1
  fi
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors \
    "$ALPINE_REPO/${package}-${version}.apk" -o "$WORKDIR/${package}.apk"
  tar -xzf "$WORKDIR/${package}.apk" -C "$WORKDIR/root"
}

fetch_apk libgcc
fetch_apk libstdc++

curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --retry-all-errors \
  "https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz" \
  -o "$WORKDIR/musl.tar.gz"
ACTUAL_MUSL_SHA256="$(sha256sum "$WORKDIR/musl.tar.gz" | awk '{print $1}')"
if [ "$ACTUAL_MUSL_SHA256" != "$MUSL_SHA256" ]; then
  echo "Error: musl source checksum does not match the pinned digest." >&2
  exit 1
fi
tar -xzf "$WORKDIR/musl.tar.gz" -C "$WORKDIR"
MUSL_SOURCE="$WORKDIR/musl-${MUSL_VERSION}"
sed -i "s|\"/etc/resolv.conf\"|\"${TERMUX_RESOLV_CONF}\"|" "$MUSL_SOURCE/src/network/resolvconf.c"
grep -Fq "${TERMUX_RESOLV_CONF}" "$MUSL_SOURCE/src/network/resolvconf.c" || {
  echo "Error: failed to apply the Termux resolver patch." >&2
  exit 1
}
(
  cd "$MUSL_SOURCE"
  CC=aarch64-linux-gnu-gcc ./configure
)
make -C "$MUSL_SOURCE" CC=aarch64-linux-gnu-gcc -j2

LOADER="$MUSL_SOURCE/lib/libc.so"
LIBGCC="$WORKDIR/root/usr/lib/libgcc_s.so.1"
LIBSTDCXX="$(find "$WORKDIR/root/usr/lib" -type f -name 'libstdc++.so.6.*' -print | sort -V | tail -n 1)"

for required in "$LOADER" "$LIBGCC" "$LIBSTDCXX"; do
  if [ ! -f "$required" ]; then
    echo "Error: missing runtime library $required." >&2
    exit 1
  fi
done

install -m 0755 "$WORKDIR/upstream/opencode" "$WORKDIR/stage/opencode"
install -m 0755 "$LOADER" "$WORKDIR/stage/ld-musl-aarch64.so.1"
install -m 0755 "$LOADER" "$WORKDIR/stage/libc.musl-aarch64.so.1"
install -m 0644 "$LIBGCC" "$WORKDIR/stage/libgcc_s.so.1"
install -m 0755 "$LIBSTDCXX" "$WORKDIR/stage/libstdc++.so.6.0.33"
ln -s libstdc++.so.6.0.33 "$WORKDIR/stage/libstdc++.so.6"

for library in libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6; do
  patchelf --print-needed "$WORKDIR/stage/opencode" | grep -Fxq "$library" || {
    echo "Error: official binary does not declare required library $library." >&2
    exit 1
  }
done

tar -C "$WORKDIR/stage" -czf "$OUTPUT" \
  opencode ld-musl-aarch64.so.1 libc.musl-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libstdc++.so.6.0.33
