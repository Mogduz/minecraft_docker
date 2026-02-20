#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

PROJECT_NAME="codex_e2e"
TEST_ENV_FILE=".tmp/.env.test"
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.test.yml)
COMPOSE_BASE=(docker compose "${COMPOSE_FILES[@]}" --env-file "$TEST_ENV_FILE" -p "$PROJECT_NAME")
KEEP_TMP_ON_FAILURE=1
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
  "${COMPOSE_BASE[@]}" "$@"
}

print_failure_diagnostics() {
  compose ps || true
  docker logs minecraft-java --tail 200 || true
  docker inspect --format '{{json .State.Health}}' minecraft-java || true
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
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' minecraft-java 2>/dev/null || true)"
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
    if docker exec minecraft-java sh -lc "grep -F '$message' /data/logs/latest.log" >/dev/null 2>&1; then
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

write_env() {
  local loader="$1"
  local rcon_enabled="$2"
  cat > "$TEST_ENV_FILE" <<'ENV'
EULA=TRUE
SERVER_TYPE=__SERVER_TYPE__
JVM_OPTS=-Xms512M -Xmx1024M
ENV
  sed -i "s/__SERVER_TYPE__/${loader}/" "$TEST_ENV_FILE"
  if [[ "$rcon_enabled" == "true" ]]; then
    cat >> "$TEST_ENV_FILE" <<'ENV'
RCON_ENABLED=TRUE
RCON_PASSWORD=codex
RCON_PORT=25575
ENV
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
  write_env "$loader" "$rcon_enabled"
  compose up -d --build
  wait_for_healthy 600
  test_aliases
  docker exec minecraft-java say "$log_marker"
  wait_for_log_message "$log_marker" 120
  compose down --remove-orphans
}

test_aliases() {
  local alias_name
  local alias_path
  local resolved_path

  for alias_name in "${ALIASES[@]}"; do
    alias_path="/usr/local/bin/${alias_name}"
    if ! docker exec minecraft-java sh -lc "[ -x '${alias_path}' ]"; then
      echo "Alias fehlt oder ist nicht ausfuehrbar: ${alias_path}" >&2
      print_failure_diagnostics
      return 1
    fi

    resolved_path="$(docker exec minecraft-java sh -lc "readlink -f '${alias_path}'" 2>/dev/null || true)"
    if [[ "$resolved_path" != "/usr/local/bin/mc-cmd" ]]; then
      echo "Alias zeigt nicht auf mc-cmd: ${alias_path} -> ${resolved_path}" >&2
      print_failure_diagnostics
      return 1
    fi
  done
}

prepare_tmp
for loader in "${LOADERS[@]}"; do
  run_loader_test "$loader" "false"
done

for loader in "${LOADERS[@]}"; do
  run_loader_test "$loader" "true"
done

KEEP_TMP_ON_FAILURE=0
echo "E2E-Tests erfolgreich."
