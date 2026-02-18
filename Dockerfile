FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG MC_VERSION=1.21.11
ARG FABRIC_LOADER_VERSION=auto
ARG FABRIC_INSTALLER_VERSION=auto
ARG FORGE_VERSION=auto
ARG NEOFORGE_VERSION=auto

ENV MC_VERSION=${MC_VERSION}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openjdk-21-jre-headless \
        tini; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /opt/minecraft/dist /opt/minecraft/runtimes /data/config /data/world /data/mods /data/resourcepacks /data/logs

# Download and cache vanilla, fabric, forge and neoforge server artifacts.
RUN set -eux; \
    VANILLA_MANIFEST_URL="$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url')"; \
    test -n "$VANILLA_MANIFEST_URL"; \
    VANILLA_SERVER_URL="$(curl -fsSL "$VANILLA_MANIFEST_URL" | jq -r '.downloads.server.url')"; \
    VANILLA_SERVER_SHA1="$(curl -fsSL "$VANILLA_MANIFEST_URL" | jq -r '.downloads.server.sha1')"; \
    test -n "$VANILLA_SERVER_URL"; \
    curl -fsSL "$VANILLA_SERVER_URL" -o /opt/minecraft/dist/vanilla-server.jar; \
    echo "$VANILLA_SERVER_SHA1  /opt/minecraft/dist/vanilla-server.jar" | sha1sum -c -; \
    if [ "$FABRIC_LOADER_VERSION" = "auto" ]; then \
      FABRIC_LOADER_VERSION="$(curl -fsSL https://meta.fabricmc.net/v2/versions/loader | jq -r '.[] | select(.stable == true) | .version' | head -n1)"; \
    fi; \
    if [ "$FABRIC_INSTALLER_VERSION" = "auto" ]; then \
      FABRIC_INSTALLER_VERSION="$(curl -fsSL https://meta.fabricmc.net/v2/versions/installer | jq -r '.[] | select(.stable == true) | .version' | head -n1)"; \
    fi; \
    test -n "$FABRIC_LOADER_VERSION"; \
    test -n "$FABRIC_INSTALLER_VERSION"; \
    curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER_VERSION}/${FABRIC_INSTALLER_VERSION}/server/jar" -o /opt/minecraft/dist/fabric-server.jar; \
    if [ "$FORGE_VERSION" = "auto" ]; then \
      FORGE_FULL_VERSION="$(curl -fsSL https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml | tr -d '\r' | sed -n 's|.*<version>\('"$MC_VERSION"'-[^<]*\)</version>.*|\1|p' | tail -n1)"; \
    else \
      case "$FORGE_VERSION" in \
        "$MC_VERSION"-*) FORGE_FULL_VERSION="$FORGE_VERSION" ;; \
        *) FORGE_FULL_VERSION="$MC_VERSION-$FORGE_VERSION" ;; \
      esac; \
    fi; \
    test -n "$FORGE_FULL_VERSION"; \
    curl -fsSL "https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_FULL_VERSION}/forge-${FORGE_FULL_VERSION}-installer.jar" -o /opt/minecraft/dist/forge-installer.jar; \
    mkdir -p /opt/minecraft/runtimes/forge; \
    cd /opt/minecraft/runtimes/forge; \
    java -jar /opt/minecraft/dist/forge-installer.jar --installServer; \
    if [ "$NEOFORGE_VERSION" = "auto" ]; then \
      NEOFORGE_LINE="$(echo "$MC_VERSION" | awk -F. '{print $2 "." $3}')"; \
      NEOFORGE_VERSION="$(curl -fsSL https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml | tr -d '\r' | sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' | grep -E "^${NEOFORGE_LINE}\\." | tail -n1)"; \
    fi; \
    test -n "$NEOFORGE_VERSION"; \
    curl -fsSL "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar" -o /opt/minecraft/dist/neoforge-installer.jar; \
    mkdir -p /opt/minecraft/runtimes/neoforge; \
    cd /opt/minecraft/runtimes/neoforge; \
    java -jar /opt/minecraft/dist/neoforge-installer.jar --installServer; \
    printf '%s\n' \
      "MC_VERSION=${MC_VERSION}" \
      "FABRIC_LOADER_VERSION=${FABRIC_LOADER_VERSION}" \
      "FABRIC_INSTALLER_VERSION=${FABRIC_INSTALLER_VERSION}" \
      "FORGE_FULL_VERSION=${FORGE_FULL_VERSION}" \
      "NEOFORGE_VERSION=${NEOFORGE_VERSION}" > /opt/minecraft/versions.env

RUN set -eux; \
    useradd -r -m -d /data -s /usr/sbin/nologin minecraft; \
    chown -R minecraft:minecraft /opt/minecraft /data

COPY start-minecraft.sh /usr/local/bin/start-minecraft.sh
COPY mc-cmd.sh /usr/local/bin/mc-cmd
RUN chmod +x /usr/local/bin/start-minecraft.sh
RUN chmod +x /usr/local/bin/mc-cmd
RUN set -eux; \
    for c in \
      help stop reload list say seed me msg teammsg tm tell w \
      ban ban-ip banlist pardon pardon-ip kick op deop \
      whitelist save-all save-on save-off \
      time weather difficulty defaultgamemode gamemode gamerule \
      effect enchant experience xp give clear item \
      teleport tp spreadplayers summon kill \
      setworldspawn spawnpoint setblock fill clone placeblock \
      setidletimeout setmaxplayers publish \
      function schedule trigger recipe advancement loot \
      scoreboard team bossbar title tellraw tm \
      datapack debug forceload jfr perf \
      locate locatebiome locatepoi playsound stopsound \
      particle damage ride tag attribute data \
      worldborder; do \
      ln -sfn /usr/local/bin/mc-cmd "/usr/local/bin/$c"; \
    done

USER minecraft
WORKDIR /data

EXPOSE 25565
VOLUME ["/data/config", "/data/world", "/data/mods", "/data/resourcepacks", "/data/logs"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-minecraft.sh"]
