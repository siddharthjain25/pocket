#!/usr/bin/env bash
set -Eeuo pipefail

NC="$HOME/.local/bin/nc"
HOST="${1:?Usage: tcp-connect.sh <server-host> [port]}"
PORT="${2:-5000}"

if [[ ! -x "$NC" ]]; then
    echo "Ncat not installed. Run scripts/run.sh first." >&2
    exit 1
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
    echo "Invalid port: $PORT" >&2
    exit 1
fi

exec "$NC" -v "$HOST" "$PORT"
