#!/usr/bin/env bash
set -euo pipefail

# Java process must be alive.
if ! pgrep -f 'java' >/dev/null; then
  exit 1
fi

# Server port must accept TCP connections.
if ! timeout 3 bash -c '>/dev/tcp/127.0.0.1/25565' 2>/dev/null; then
  exit 1
fi

# Server must have reached "Done (...)" at least once.
if [[ ! -f /data/logs/latest.log ]]; then
  exit 1
fi
if ! grep -q 'Done (' /data/logs/latest.log; then
  exit 1
fi

exit 0
