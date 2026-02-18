#!/usr/bin/env bash
set -euo pipefail

if [[ "${EULA:-FALSE}" != "TRUE" ]]; then
  echo "Setze EULA=TRUE, um den Server zu starten."
  exit 1
fi

source /opt/minecraft/versions.env

SERVER_TYPE="$(echo "${SERVER_TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')"

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

case "$SERVER_TYPE" in
  vanilla)
    cd /data
    exec java "${JAVA_ARGS_ARR[@]}" -jar /opt/minecraft/dist/vanilla-server.jar nogui
    ;;
  fabric)
    cd /data
    exec java "${JAVA_ARGS_ARR[@]}" -jar /opt/minecraft/dist/fabric-server.jar nogui
    ;;
  forge)
    link_runtime_paths /opt/minecraft/runtimes/forge
    cd /opt/minecraft/runtimes/forge
    printf '%s\n' "$JAVA_ARGS" > user_jvm_args.txt
    exec ./run.sh nogui
    ;;
  neoforge)
    link_runtime_paths /opt/minecraft/runtimes/neoforge
    cd /opt/minecraft/runtimes/neoforge
    printf '%s\n' "$JAVA_ARGS" > user_jvm_args.txt
    exec ./run.sh nogui
    ;;
  *)
    echo "Unbekannter SERVER_TYPE: ${SERVER_TYPE}. Erlaubt: vanilla, fabric, forge, neoforge"
    exit 1
    ;;
esac
