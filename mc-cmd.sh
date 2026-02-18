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

# Send command to the main server process stdin.
printf '%s\n' "$cmd" > /proc/1/fd/0
