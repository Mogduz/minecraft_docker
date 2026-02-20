#!/usr/bin/env bash
set -euo pipefail

binary_name="$(basename "$0")"

if [[ "$binary_name" == "mc-cmd" ]]; then
  if [[ $# -eq 0 ]]; then
    echo "Usage: mc-cmd <minecraft command...>" >&2
    exit 2
  fi
  cmd="$*"
else
  if [[ $# -gt 0 ]]; then
    cmd="${binary_name} $*"
  else
    cmd="${binary_name}"
  fi
fi

RCON_ENABLED="$(echo "${RCON_ENABLED:-FALSE}" | tr '[:lower:]' '[:upper:]')"
RCON_PORT="${RCON_PORT:-25575}"

if [[ "$RCON_ENABLED" == "TRUE" ]] && command -v mcrcon >/dev/null 2>&1 && [[ -n "${RCON_PASSWORD:-}" ]]; then
  exec mcrcon -H 127.0.0.1 -P "$RCON_PORT" -p "$RCON_PASSWORD" "$cmd"
fi

pid_file="/run/minecraft.pid"
if [[ ! -r "$pid_file" ]]; then
  echo "Kein PID-File unter ${pid_file} gefunden. Nutze RCON oder aktiviere stdin_open/tty in Compose." >&2
  exit 1
fi

server_pid="$(tr -d '[:space:]' < "$pid_file")"
if ! [[ "$server_pid" =~ ^[0-9]+$ ]]; then
  echo "Ungueltige PID in ${pid_file}: '${server_pid}'" >&2
  exit 1
fi

if ! kill -0 "$server_pid" 2>/dev/null; then
  echo "Minecraft-Prozess mit PID ${server_pid} existiert nicht mehr. Nutze RCON oder pruefe den Containerstatus." >&2
  exit 1
fi

stdin_path="/proc/${server_pid}/fd/0"
if [[ ! -w "$stdin_path" ]]; then
  echo "STDIN nicht beschreibbar (${stdin_path}). Nutze RCON oder aktiviere stdin_open/tty in Compose." >&2
  exit 1
fi

if ! printf '%s\n' "$cmd" > "$stdin_path"; then
  echo "Befehl konnte nicht an Minecraft-STDIN gesendet werden (${stdin_path}). Nutze RCON als Fallback." >&2
  exit 1
fi
