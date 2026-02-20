#!/usr/bin/env bash
set -euo pipefail

if [[ "${EULA:-FALSE}" != "TRUE" ]]; then
  echo "Setze EULA=TRUE, um den Server zu starten."
  exit 1
fi

source /opt/minecraft/versions.env

SERVER_TYPE="$(echo "${SERVER_TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')"
RCON_ENABLED="$(echo "${RCON_ENABLED:-FALSE}" | tr '[:lower:]' '[:upper:]')"
RCON_PORT="${RCON_PORT:-25575}"

mkdir -p /data/config /data/world /data/mods /data/resourcepacks /data/logs

# Migration from old flat /data layout.
for cfg in eula.txt server.properties whitelist.json ops.json banned-ips.json banned-players.json usercache.json; do
  if [[ -e "/data/${cfg}" && ! -L "/data/${cfg}" ]]; then
    mv "/data/${cfg}" "/data/config/${cfg}"
  fi
done

if [[ ! -f /data/config/server.properties ]]; then
  cat > /data/config/server.properties <<'PROPS'
level-name=world
enable-query=false
enable-rcon=false
motd=Minecraft Server
PROPS
fi

echo "eula=true" > /data/config/eula.txt

for cfg in eula.txt server.properties whitelist.json ops.json banned-ips.json banned-players.json usercache.json; do
  if [[ ! -f "/data/config/${cfg}" ]]; then
    touch "/data/config/${cfg}"
  fi
  ln -sfn "/data/config/${cfg}" "/data/${cfg}"
done

upsert_property() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -F= -v k="$key" -v v="$value" '
    BEGIN { updated = 0 }
    $1 == k {
      if (updated == 0) {
        print k "=" v
        updated = 1
      }
      next
    }
    { print }
    END {
      if (updated == 0) {
        print k "=" v
      }
    }
  ' "$file" > "$tmp_file"

  mv "$tmp_file" "$file"
}

if [[ "$RCON_ENABLED" == "TRUE" ]]; then
  if [[ -z "${RCON_PASSWORD:-}" ]]; then
    echo "RCON_ENABLED=TRUE, aber RCON_PASSWORD ist nicht gesetzt."
    exit 1
  fi

  if ! [[ "$RCON_PORT" =~ ^[0-9]+$ ]] || (( RCON_PORT < 1 || RCON_PORT > 65535 )); then
    echo "Ungueltiger RCON_PORT: ${RCON_PORT}. Erwartet: 1-65535"
    exit 1
  fi

  upsert_property "enable-rcon" "true" /data/config/server.properties
  upsert_property "rcon.password" "${RCON_PASSWORD}" /data/config/server.properties
  upsert_property "rcon.port" "${RCON_PORT}" /data/config/server.properties
fi

link_runtime_paths() {
  local runtime_dir="$1"
  mkdir -p "$runtime_dir"
  ln -sfn /data/config "$runtime_dir/config"
  ln -sfn /data/world "$runtime_dir/world"
  ln -sfn /data/mods "$runtime_dir/mods"
  ln -sfn /data/resourcepacks "$runtime_dir/resourcepacks"
  ln -sfn /data/logs "$runtime_dir/logs"
  for cfg in eula.txt server.properties whitelist.json ops.json banned-ips.json banned-players.json usercache.json; do
    ln -sfn "/data/config/${cfg}" "$runtime_dir/${cfg}"
  done
}

JAVA_ARGS="${JVM_OPTS:-"-Xms1G -Xmx2G"}"
read -r -a JAVA_ARGS_ARR <<< "$JAVA_ARGS"

SERVER_PID=""
STDIN_PIPE="/tmp/minecraft.stdin"

start_server() {
  rm -f "$STDIN_PIPE"
  mkfifo "$STDIN_PIPE"
  exec 3<>"$STDIN_PIPE"

  case "$SERVER_TYPE" in
    vanilla)
      cd /data
      java "${JAVA_ARGS_ARR[@]}" -jar /opt/minecraft/dist/vanilla-server.jar nogui <&3 &
      ;;
    fabric)
      cd /data
      java "${JAVA_ARGS_ARR[@]}" -jar /opt/minecraft/dist/fabric-server.jar nogui <&3 &
      ;;
    forge)
      link_runtime_paths /opt/minecraft/runtimes/forge
      cd /opt/minecraft/runtimes/forge
      printf '%s\n' "$JAVA_ARGS" > user_jvm_args.txt
      ./run.sh nogui <&3 &
      ;;
    neoforge)
      link_runtime_paths /opt/minecraft/runtimes/neoforge
      cd /opt/minecraft/runtimes/neoforge
      printf '%s\n' "$JAVA_ARGS" > user_jvm_args.txt
      ./run.sh nogui <&3 &
      ;;
    *)
      echo "Unbekannter SERVER_TYPE: ${SERVER_TYPE}. Erlaubt: vanilla, fabric, forge, neoforge"
      exit 1
      ;;
  esac

  SERVER_PID="$!"
  mkdir -p /run
  printf '%s\n' "$SERVER_PID" > /run/minecraft.pid
}

forward_and_wait() {
  local signal_name="$1"

  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "-${signal_name}" "$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID"
    rm -f /run/minecraft.pid "$STDIN_PIPE"
    exit $?
  fi

  rm -f /run/minecraft.pid "$STDIN_PIPE"
  exit 1
}

trap 'forward_and_wait TERM' TERM
trap 'forward_and_wait INT' INT
trap 'forward_and_wait HUP' HUP

start_server
wait "$SERVER_PID"
exit_code=$?
rm -f /run/minecraft.pid "$STDIN_PIPE"
exit "$exit_code"
