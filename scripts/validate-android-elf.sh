#!/usr/bin/env bash
set -euo pipefail

BINARY="${1:?Usage: validate-android-elf.sh BINARY EXPECTED_INTERPRETER}"
EXPECTED_INTERPRETER="${2:?Usage: validate-android-elf.sh BINARY EXPECTED_INTERPRETER}"

[[ -f "$BINARY" ]] || { echo "Error: Android ELF validation target is missing: $BINARY" >&2; exit 1; }
READELF="${READELF:-}"
if [[ -z "$READELF" ]]; then
  if command -v aarch64-linux-gnu-readelf >/dev/null 2>&1; then
    READELF=aarch64-linux-gnu-readelf
  elif command -v readelf >/dev/null 2>&1; then
    READELF=readelf
  else
    echo "Error: readelf is required to validate the Android executable." >&2
    exit 1
  fi
fi

HEADER="$("$READELF" -h "$BINARY")"
ELF_TYPE="$(printf '%s\n' "$HEADER" | awk '/Type:/{print $2; exit}')"
ENTRY_POINT="$(printf '%s\n' "$HEADER" | awk '/Entry point address:/{print $4; exit}')"
if [[ -z "$ENTRY_POINT" || "$ENTRY_POINT" =~ ^0x0+$ ]]; then
  echo "Error: ET_DYN executable has no entry point; it is not an executable PIE." >&2
  exit 1
fi
if [[ "$ELF_TYPE" != "DYN" ]]; then
  echo "Error: OpenCode must be an ELF PIE (ET_DYN) executable for Termux; found '$ELF_TYPE'." >&2
  echo "The Linux release binary is not Android-compatible. Changing PT_INTERP with patchelf does not convert ET_EXEC to PIE." >&2
  exit 1
fi

PROGRAM_HEADERS="$("$READELF" -l "$BINARY")"
if ! printf '%s\n' "$PROGRAM_HEADERS" | grep -Fq "[Requesting program interpreter: $EXPECTED_INTERPRETER]"; then
  echo "Error: executable does not request the expected Termux musl interpreter: $EXPECTED_INTERPRETER" >&2
  exit 1
fi

if ! "$READELF" -d "$BINARY" 2>/dev/null | grep -Fq '(DYNAMIC)'; then
  echo "Error: ET_DYN executable has no dynamic section; it is not a runnable dynamic PIE." >&2
  exit 1
fi

echo "Android ELF validation... OK (ET_DYN with Termux musl interpreter)"
