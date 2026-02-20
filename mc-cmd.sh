#!/usr/bin/env bash
set -euo pipefail

# Generic mode:
#   mc-cmd <minecraft command...>
# Alias mode via symlink name:
#   help
#   stop
#   ...
if [[ $# -eq 0 && "$(basename "$0")" == "mc-cmd" ]]; then
  echo "Usage: mc-cmd <minecraft command...>"
  exit 1
fi

if [[ "$(basename "$0")" == "mc-cmd" ]]; then
  cmd="$*"
else
  if [[ $# -gt 0 ]]; then
    cmd="$(basename "$0") $*"
  else
    cmd="$(basename "$0")"
  fi
fi

RCON_ENABLED="$(echo "${RCON_ENABLED:-FALSE}" | tr '[:lower:]' '[:upper:]')"
RCON_PORT="${RCON_PORT:-25575}"

if [[ "$RCON_ENABLED" == "TRUE" ]] && command -v mcrcon >/dev/null 2>&1 && [[ -n "${RCON_PASSWORD:-}" ]]; then
  exec mcrcon -H 127.0.0.1 -P "$RCON_PORT" -p "$RCON_PASSWORD" "$cmd"
fi

# Fallback: send command to the main server process stdin.
printf '%s\n' "$cmd" > /proc/1/fd/0