#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

PROJECT_NAME="codex_e2e"
TEST_ENV_FILE="1.21.11/.env.test"
TEST_CONTAINER_NAME="minecraft-java-e2e"
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.test.yml)
COMPOSE_BASE=(docker compose "${COMPOSE_FILES[@]}" --env-file "$TEST_ENV_FILE" -p "$PROJECT_NAME")
KEEP_TMP_ON_FAILURE=1
CURRENT_SERVER_TYPE="vanilla"
CURRENT_RCON_ENABLED="FALSE"
CURRENT_RCON_PASSWORD="codex"
CURRENT_RCON_PORT="25575"
LOADERS=(vanilla fabric forge neoforge)
ALIASES=(
  help stop reload list say seed me msg teammsg tm tell w
  ban ban-ip banlist pardon pardon-ip kick op deop
  whitelist save-all save-on save-off
  time weather difficulty defaultgamemode gamemode gamerule
  effect enchant experience xp give clear item
  teleport tp spreadplayers summon kill
  setworldspawn spawnpoint setblock fill clone placeblock
  setidletimeout setmaxplayers publish
  function schedule trigger recipe advancement loot
  scoreboard team bossbar title tellraw
  datapack debug forceload jfr perf
  locate locatebiome locatepoi playsound stopsound
  particle damage ride tag attribute data
  worldborder
)

compose() {
  SERVER_TYPE="$CURRENT_SERVER_TYPE" \
  CONTAINER_NAME="$TEST_CONTAINER_NAME" \
  RCON_ENABLED="$CURRENT_RCON_ENABLED" \
  RCON_PASSWORD="$CURRENT_RCON_PASSWORD" \
  RCON_PORT="$CURRENT_RCON_PORT" \
  "${COMPOSE_BASE[@]}" "$@"
}

print_failure_diagnostics() {
  compose ps || true
  docker logs "$TEST_CONTAINER_NAME" --tail 200 || true
  docker inspect --format '{{json .State.Health}}' "$TEST_CONTAINER_NAME" || true
}

cleanup() {
  compose down --remove-orphans || true
  if [[ "${KEEP_TMP_ON_FAILURE}" -eq 0 ]]; then
    rm -rf .tmp
  fi
}

trap cleanup EXIT

wait_for_healthy() {
  local timeout_seconds="$1"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local status
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$TEST_CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi

    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "Timeout: Container wurde nicht healthy (Status: ${status:-unbekannt})." >&2
      print_failure_diagnostics
      return 1
    fi

    sleep 3
  done
}

wait_for_log_message() {
  local message="$1"
  local timeout_seconds="$2"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if docker exec "$TEST_CONTAINER_NAME" sh -lc "grep -F '$message' /data/logs/latest.log" >/dev/null 2>&1; then
      return 0
    fi

    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "Timeout: Log-Meldung nicht gefunden: $message" >&2
      print_failure_diagnostics
      return 1
    fi

    sleep 2
  done
}

prepare_tmp() {
  mkdir -p .tmp/minecraft/config .tmp/minecraft/world .tmp/minecraft/mods .tmp/minecraft/resourcepacks .tmp/minecraft/logs
}

reset_loader_state() {
  rm -rf .tmp/minecraft/config .tmp/minecraft/world .tmp/minecraft/mods .tmp/minecraft/resourcepacks .tmp/minecraft/logs
  prepare_tmp
}

require_test_env_file() {
  if [[ ! -f "$TEST_ENV_FILE" ]]; then
    echo "Fehler: Test-Env-Datei fehlt: $TEST_ENV_FILE" >&2
    echo "Lege die Datei an oder passe TEST_ENV_FILE im Script an." >&2
    exit 1
  fi
}

run_loader_test() {
  local loader="$1"
  local rcon_enabled="$2"
  local label="ohne RCON"
  local log_marker="codex-${loader}-smoke-test"

  if [[ "$rcon_enabled" == "true" ]]; then
    label="mit RCON"
    log_marker="codex-${loader}-rcon-test"
  fi

  echo "== Test: ${loader} (${label}) =="
  reset_loader_state
  CURRENT_SERVER_TYPE="$loader"
  if [[ "$rcon_enabled" == "true" ]]; then
    CURRENT_RCON_ENABLED="TRUE"
    CURRENT_RCON_PASSWORD="codex"
    CURRENT_RCON_PORT="25575"
  else
    CURRENT_RCON_ENABLED="FALSE"
    CURRENT_RCON_PASSWORD="codex"
    CURRENT_RCON_PORT="25575"
  fi
  compose up -d
  wait_for_healthy 600
  test_aliases
  set +e
  timeout 30 docker exec "$TEST_CONTAINER_NAME" mc-cmd "say $log_marker"
  cmd_rc=$?
  set -e
  if [[ "$cmd_rc" -ne 0 && "$cmd_rc" -ne 124 ]]; then
    echo "Senden des Testbefehls fehlgeschlagen (Exit $cmd_rc): $log_marker" >&2
    print_failure_diagnostics
    return 1
  fi
  if [[ "$cmd_rc" -eq 124 ]]; then
    echo "Hinweis: mc-cmd Timeout bei '$log_marker', pruefe Log-Nachweis weiter."
  fi
  wait_for_log_message "$log_marker" 120
  compose down --remove-orphans
}

test_aliases() {
  local aliases_joined
  aliases_joined="${ALIASES[*]}"

  if ! docker exec -e CODEX_ALIASES="$aliases_joined" "$TEST_CONTAINER_NAME" sh -lc '
    set -e
    for alias_name in $CODEX_ALIASES; do
      alias_path="/usr/local/bin/${alias_name}"
      [ -x "$alias_path" ] || { echo "Alias fehlt oder ist nicht ausfuehrbar: $alias_path" >&2; exit 1; }
      resolved_path="$(readlink -f "$alias_path" 2>/dev/null || true)"
      [ "$resolved_path" = "/usr/local/bin/mc-cmd" ] || { echo "Alias zeigt nicht auf mc-cmd: $alias_path -> $resolved_path" >&2; exit 1; }
    done
  '; then
    print_failure_diagnostics
    return 1
  fi
}

require_test_env_file
prepare_tmp
compose build
compose down --remove-orphans || true

for loader in "${LOADERS[@]}"; do
  run_loader_test "$loader" "false"
done

for loader in "${LOADERS[@]}"; do
  run_loader_test "$loader" "true"
done

KEEP_TMP_ON_FAILURE=0
echo "E2E-Tests erfolgreich."
