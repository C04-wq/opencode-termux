#!/data/data/com.termux/files/usr/bin/bash
# Resolve the owning dpkg package without failing when no package owns a path.
get_dpkg_package_owner() {
  local query_output
  query_output="$(dpkg-query -S "$1" 2>/dev/null || true)"
  [[ -n "$query_output" ]] || return 0
  printf '%s' "${query_output%%:*}"
}
