#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="codex_e2e"
TEST_ENV_FILE=".tmp/.env.test"
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.test.yml)
COMPOSE_BASE=(docker compose "${COMPOSE_FILES[@]}" --env-file "$TEST_ENV_FILE" -p "$PROJECT_NAME")
KEEP_TMP_ON_FAILURE=1

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

write_env_base() {
  cat > "$TEST_ENV_FILE" <<'ENV'
EULA=TRUE
SERVER_TYPE=vanilla
JVM_OPTS=-Xms512M -Xmx1024M
ENV
}

write_env_with_rcon() {
  cat > "$TEST_ENV_FILE" <<'ENV'
EULA=TRUE
SERVER_TYPE=vanilla
JVM_OPTS=-Xms512M -Xmx1024M
RCON_ENABLED=TRUE
RCON_PASSWORD=codex
RCON_PORT=25575
ENV
}

run_test_without_rcon() {
  echo "== Testlauf 1: ohne RCON =="
  write_env_base
  compose up -d --build
  wait_for_healthy 300
  docker exec minecraft-java say codex-smoke-test
  wait_for_log_message "codex-smoke-test" 90
  compose down --remove-orphans
}

run_test_with_rcon() {
  echo "== Testlauf 2: mit RCON =="
  write_env_with_rcon
  compose up -d --build
  wait_for_healthy 300
  docker exec minecraft-java say codex-rcon-test
  wait_for_log_message "codex-rcon-test" 90
  compose down --remove-orphans
}

prepare_tmp
run_test_without_rcon
run_test_with_rcon
KEEP_TMP_ON_FAILURE=0
echo "E2E-Tests erfolgreich."
