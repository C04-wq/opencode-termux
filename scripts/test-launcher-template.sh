#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/install.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start_marker = 'cat > "$STAGE/opencode-launcher" <<\'LAUNCHER\'\n'
end_marker = '\nLAUNCHER\n'
start = source.find(start_marker)
if start < 0:
    raise SystemExit("installed launcher heredoc start marker is missing")
start += len(start_marker)
end = source.find(end_marker, start)
if end < 0:
    raise SystemExit("installed launcher heredoc end marker is missing")
Path(sys.argv[2]).write_text(source[start:end] + "\n", encoding="utf-8")
PY

bash -n "$TMP"
shellcheck -S error "$TMP"
echo "Installed launcher template syntax and ShellCheck passed."
