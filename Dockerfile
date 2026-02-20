FROM ubuntu:24.04

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG MC_VERSION=1.21.11
ARG FABRIC_LOADER_VERSION=auto
ARG FABRIC_INSTALLER_VERSION=auto
ARG FORGE_VERSION=auto
ARG NEOFORGE_VERSION=auto

ENV MC_VERSION=${MC_VERSION}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openjdk-21-jre-headless \
        tini \
        unzip \
    && if ! apt-get install -y --no-install-recommends mcrcon; then \
         apt-get install -y --no-install-recommends build-essential git; \
         git clone --depth 1 https://github.com/Tiiffi/mcrcon.git /tmp/mcrcon-src; \
         make -C /tmp/mcrcon-src; \
         install -m 0755 /tmp/mcrcon-src/mcrcon /usr/local/bin/mcrcon; \
         rm -rf /tmp/mcrcon-src; \
         apt-get purge -y --auto-remove build-essential git; \
       fi \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/minecraft/dist /opt/minecraft/runtimes /data/config /data/world /data/mods /data/resourcepacks /data/logs

# Download and cache vanilla, fabric, forge and neoforge server artifacts.
RUN curl_common=(--fail --location --silent --show-error --retry 3 --connect-timeout 10 --max-time 300 --proto '=https' --tlsv1.2); \
    MC_MAJOR_MINOR="$(awk -F. '{print $1 "." $2}' <<<"$MC_VERSION")"; \
    MC_MAJOR_MINOR_ESC="${MC_MAJOR_MINOR//./\\.}"; \
    NEOFORGE_LINE="$(awk -F. '{print $2 "." $3}' <<<"$MC_VERSION")"; \
    NEOFORGE_MAJOR="$(awk -F. '{print $2}' <<<"$MC_VERSION")"; \
    assert_nonempty_file() { \
      local file_path="$1"; \
      if [[ ! -s "$file_path" ]]; then \
        echo "Download validation failed: '$file_path' is missing or empty." >&2; \
        exit 1; \
      fi; \
    }; \
    assert_archive_readable() { \
      local file_path="$1"; \
      if ! unzip -tqq "$file_path" >/dev/null; then \
        echo "Download validation failed: '$file_path' is not a readable archive (jar/zip)." >&2; \
        exit 1; \
      fi; \
    }; \
    download_with_optional_sha() { \
      local url="$1" out="$2"; \
      local sha_url="${url}.sha1"; \
      curl "${curl_common[@]}" "$url" -o "$out"; \
      assert_nonempty_file "$out"; \
      local expected_sha=""; \
      expected_sha="$(curl "${curl_common[@]}" "$sha_url" 2>/dev/null | tr -d '\\r\\n' || true)"; \
      if [[ "$expected_sha" =~ ^[a-fA-F0-9]{40}$ ]]; then \
        echo "$expected_sha  $out" | sha1sum -c -; \
      else \
        assert_archive_readable "$out"; \
      fi; \
    }; \
    VANILLA_MANIFEST_URL="$(curl "${curl_common[@]}" https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url')"; \
    [[ -n "$VANILLA_MANIFEST_URL" ]]; \
    VANILLA_MANIFEST="$(curl "${curl_common[@]}" "$VANILLA_MANIFEST_URL")"; \
    VANILLA_SERVER_URL="$(jq -r '.downloads.server.url' <<<"$VANILLA_MANIFEST")"; \
    VANILLA_SERVER_SHA1="$(jq -r '.downloads.server.sha1' <<<"$VANILLA_MANIFEST")"; \
    [[ -n "$VANILLA_SERVER_URL" ]]; \
    curl "${curl_common[@]}" "$VANILLA_SERVER_URL" -o /opt/minecraft/dist/vanilla-server.jar; \
    assert_nonempty_file /opt/minecraft/dist/vanilla-server.jar; \
    echo "$VANILLA_SERVER_SHA1  /opt/minecraft/dist/vanilla-server.jar" | sha1sum -c -; \
    if [[ "$FABRIC_LOADER_VERSION" == "auto" ]]; then \
      FABRIC_LOADER_VERSION="$(curl "${curl_common[@]}" https://meta.fabricmc.net/v2/versions/loader | jq -r '[.[] | select(.stable == true) | .version] | first // empty')"; \
    fi; \
    if [[ "$FABRIC_INSTALLER_VERSION" == "auto" ]]; then \
      FABRIC_INSTALLER_VERSION="$(curl "${curl_common[@]}" https://meta.fabricmc.net/v2/versions/installer | jq -r '[.[] | select(.stable == true) | .version] | first // empty')"; \
    fi; \
    [[ -n "$FABRIC_LOADER_VERSION" ]]; \
    [[ -n "$FABRIC_INSTALLER_VERSION" ]]; \
    FABRIC_GAME_VERSION="$MC_VERSION"; \
    FABRIC_GAME_VERSIONS="$(curl "${curl_common[@]}" https://meta.fabricmc.net/v2/versions/game | jq -r '.[].version')"; \
    if ! grep -Fxq "$FABRIC_GAME_VERSION" <<<"$FABRIC_GAME_VERSIONS"; then \
      FABRIC_GAME_VERSION="$(grep -E "^${MC_MAJOR_MINOR_ESC}\\.[0-9]+$" <<<"$FABRIC_GAME_VERSIONS" | sort -V | tail -n1 || true)"; \
    fi; \
    [[ -n "$FABRIC_GAME_VERSION" ]]; \
    FABRIC_URL="https://meta.fabricmc.net/v2/versions/loader/${FABRIC_GAME_VERSION}/${FABRIC_LOADER_VERSION}/${FABRIC_INSTALLER_VERSION}/server/jar"; \
    curl "${curl_common[@]}" "$FABRIC_URL" -o /opt/minecraft/dist/fabric-server.jar; \
    assert_nonempty_file /opt/minecraft/dist/fabric-server.jar; \
    assert_archive_readable /opt/minecraft/dist/fabric-server.jar; \
    FORGE_VERSIONS="$(curl "${curl_common[@]}" https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml | tr -d '\r' | sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p')"; \
    if [[ "$FORGE_VERSION" == "auto" ]]; then \
      FORGE_FULL_VERSION="$(grep -E "^${MC_VERSION//./\\.}-" <<<"$FORGE_VERSIONS" | tail -n1 || true)"; \
      if [[ -z "$FORGE_FULL_VERSION" ]]; then \
        FORGE_FULL_VERSION="$(grep -E "^${MC_MAJOR_MINOR_ESC}\\.[0-9]+-" <<<"$FORGE_VERSIONS" | sort -V | tail -n1 || true)"; \
      fi; \
    else \
      case "$FORGE_VERSION" in \
        "$MC_VERSION"-*) FORGE_FULL_VERSION="$FORGE_VERSION" ;; \
        *) FORGE_FULL_VERSION="$MC_VERSION-$FORGE_VERSION" ;; \
      esac; \
    fi; \
    [[ -n "$FORGE_FULL_VERSION" ]]; \
    download_with_optional_sha "https://maven.minecraftforge.net/net/minecraftforge/forge/${FORGE_FULL_VERSION}/forge-${FORGE_FULL_VERSION}-installer.jar" "/opt/minecraft/dist/forge-installer.jar"; \
    mkdir -p /opt/minecraft/runtimes/forge; \
    (cd /opt/minecraft/runtimes/forge && java -jar /opt/minecraft/dist/forge-installer.jar --installServer); \
    NEOFORGE_VERSIONS="$(curl "${curl_common[@]}" https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml | tr -d '\r' | sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p')"; \
    if [[ "$NEOFORGE_VERSION" == "auto" ]]; then \
      NEOFORGE_VERSION="$(grep -E "^${NEOFORGE_LINE//./\\.}\\." <<<"$NEOFORGE_VERSIONS" | sort -V | tail -n1 || true)"; \
      if [[ -z "$NEOFORGE_VERSION" ]]; then \
        NEOFORGE_VERSION="$(grep -E "^${NEOFORGE_MAJOR//./\\.}\\." <<<"$NEOFORGE_VERSIONS" | sort -V | tail -n1 || true)"; \
      fi; \
    fi; \
    [[ -n "$NEOFORGE_VERSION" ]]; \
    download_with_optional_sha "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar" "/opt/minecraft/dist/neoforge-installer.jar"; \
    mkdir -p /opt/minecraft/runtimes/neoforge; \
    (cd /opt/minecraft/runtimes/neoforge && java -jar /opt/minecraft/dist/neoforge-installer.jar --installServer); \
    printf '%s\n' \
      "MC_VERSION=${MC_VERSION}" \
      "FABRIC_LOADER_VERSION=${FABRIC_LOADER_VERSION}" \
      "FABRIC_INSTALLER_VERSION=${FABRIC_INSTALLER_VERSION}" \
      "FORGE_FULL_VERSION=${FORGE_FULL_VERSION}" \
      "NEOFORGE_VERSION=${NEOFORGE_VERSION}" > /opt/minecraft/versions.env

RUN useradd -r -m -d /data -s /usr/sbin/nologin minecraft \
    && chown -R minecraft:minecraft /opt/minecraft /data

COPY start-minecraft.sh /usr/local/bin/start-minecraft.sh
COPY mc-cmd.sh /usr/local/bin/mc-cmd
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/start-minecraft.sh /usr/local/bin/mc-cmd /usr/local/bin/healthcheck.sh
RUN for c in \
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

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-minecraft.sh"]
