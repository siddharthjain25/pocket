#!/usr/bin/env bash
set -Eeuo pipefail

BASE="https://raw.githubusercontent.com/siddharthjain25/pocket/main"
CLIENT="$HOME/.local/bin/tcp-connect.sh"

if [[ ! -x "$HOME/.local/bin/nc" ]]; then
    curl -fsSL "$BASE/scripts/install-nc.sh" | bash
fi

curl -fsSL "$BASE/scripts/tcp-connect.sh" -o "$CLIENT"
chmod 700 "$CLIENT"

HOST="${1:?Usage: run.sh <server-host> [port]}"
PORT="${2:-5000}"

exec "$CLIENT" "$HOST" "$PORT"
