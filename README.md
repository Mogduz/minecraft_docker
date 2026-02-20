# minecraft_docker

Minecraft Java Server (`ubuntu:24.04`) mit persistenter Auslagerung von Config, World, Mods, Resourcepacks und Logs.
Beim Build werden Artefakte fuer `vanilla`, `fabric`, `forge` und `neoforge` heruntergeladen und vorgehalten.

## Quickstart

`.env` zuerst aus Vorlage anlegen:

```bash
cp .env.example .env
```

Dann `EULA=TRUE` in `.env` setzen. Ohne diese Einstellung startet der Container nicht.

Starten:

```bash
docker compose up -d --build
```

Health-Status pruefen:

```bash
docker ps
```

Beim Start steht der Container zunaechst auf `health: starting`, im Normalbetrieb auf `Up ... (healthy)` bei laufendem (`running`) Container.

## Konfiguration ueber `.env`

`.env` ist absichtlich nicht versioniert. Vorlage ist `.env.example`.

Wichtige Runtime-Variablen:

- `SERVER_TYPE` (`vanilla`, `fabric`, `forge`, `neoforge`)
- `JVM_OPTS`
- `EULA`
- `MC_PORT`
- `CONTAINER_NAME`
- `RCON_ENABLED` (Default `FALSE`)
- `RCON_PASSWORD` (nur noetig bei aktiviertem RCON)
- `RCON_PORT` (Default `25575`)

Image/Container:

- `IMAGE_NAME`
- `IMAGE_TAG`
- `RESTART_POLICY`

Build-Argumente (werden via Compose in den Build durchgereicht):

- `MC_VERSION`
- `FABRIC_LOADER_VERSION`
- `FABRIC_INSTALLER_VERSION`
- `FORGE_VERSION`
- `NEOFORGE_VERSION`

## RCON (optional, per Profil)

Standardmaessig ist kein zusaetzlicher RCON-Port nach aussen offen.

RCON mit Port-Freigabe aktivieren:

```bash
docker compose --profile rcon up -d --build
```

Dafuer in `.env` mindestens setzen:

- `RCON_ENABLED=TRUE`
- `RCON_PASSWORD=<dein-passwort>`
- optional `RCON_PORT=25575`

`mc-cmd` nutzt automatisch RCON, wenn `RCON_ENABLED=TRUE`, `RCON_PASSWORD` gesetzt ist und `mcrcon` im Container verfuegbar ist. Sonst faellt es auf den bisherigen STDIN-Mechanismus zurueck.

## Persistente Daten

Bind-Mounts:

- `./minecraft/config:/data/config`
- `./minecraft/world:/data/world`
- `./minecraft/mods:/data/mods`
- `./minecraft/resourcepacks:/data/resourcepacks`
- `./minecraft/logs:/data/logs`

Empfohlene Repo-Hygiene:

- Persistente Laufzeitdaten unter `minecraft/` sind in `.gitignore` ausgenommen.
- Auch `minecraft/config` ist ignoriert (enthaelt benutzerspezifische Daten wie `server.properties`, `ops.json`, Whitelist, usw.).
- Nur `.gitkeep`-Dateien bleiben versioniert, damit die Ordnerstruktur erhalten bleibt.
- `.env` bleibt lokal und wird nicht eingecheckt.
- `.env.example` ist die versionierte Vorlage.

## Befehle in die Server-Konsole senden

Direkt als Alias-Befehl im Container:

```bash
docker exec -it minecraft-java help
docker exec -it minecraft-java list
docker exec -it minecraft-java reload
docker exec -it minecraft-java stop
```

Fuer beliebige (auch modded) Commands:

```bash
docker exec -it minecraft-java mc-cmd "say Hello from mc-cmd"
```

`mc-cmd` nutzt RCON wenn aktiviert, sonst den STDIN-Fallback.

## Stoppen

```bash
docker compose down
```

## Tests

E2E-Tests laufen in WSL mit lokalem Docker:

```bash
./scripts/test_e2e.sh
```
